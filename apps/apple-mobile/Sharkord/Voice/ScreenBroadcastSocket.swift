import CoreImage
import CoreVideo
import Darwin
import Foundation
import WebRTC

enum ScreenBroadcastConfiguration {
    static let appGroupIdentifier = "group.com.timmysheep.sharkord.ios"
    static let extensionIdentifier = "com.timmysheep.sharkord.ios.BroadcastUpload"
    static let stopNotification = "com.timmysheep.sharkord.ios.stop-screen-broadcast"
    static let socketFileName = "screen-broadcast.sock"
}

/// Receives compressed ReplayKit frames from the upload extension over the shared app-group
/// Unix socket. Frames are never written to disk.
final class ScreenBroadcastSocketServer {
    private static let headerLength = 16
    private static let maximumFrameLength = 8 * 1024 * 1024

    private let path: String
    private let queue = DispatchQueue(label: "cove.screen-broadcast.socket", qos: .userInitiated)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let onConnect: () -> Void
    private let onFrame: (CVPixelBuffer, RTCVideoRotation) -> Void
    private let onDisconnect: () -> Void

    private var listenerFD: Int32 = -1
    private var clientFD: Int32 = -1
    private var listenerSource: DispatchSourceRead?
    private var clientSource: DispatchSourceRead?
    private var pendingBytes = Data()
    private var isStopping = false

    init(
        containerURL: URL,
        onConnect: @escaping () -> Void,
        onFrame: @escaping (CVPixelBuffer, RTCVideoRotation) -> Void,
        onDisconnect: @escaping () -> Void
    ) {
        path = containerURL.appendingPathComponent(ScreenBroadcastConfiguration.socketFileName).path
        self.onConnect = onConnect
        self.onFrame = onFrame
        self.onDisconnect = onDisconnect
    }

    func start() throws {
        guard path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
            throw SocketError.invalidPath
        }

        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw SocketError.system(errno)
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let socketPathLength = MemoryLayout.size(ofValue: address.sun_path)
        _ = path.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path.0) { destination in
                strncpy(destination, source, socketPathLength - 1)
            }
        }

        _ = Darwin.unlink(path)
        let bindResult = withUnsafePointer(to: &address) { addressPointer in
            addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0, Darwin.listen(descriptor, 1) == 0 else {
            let error = errno
            Darwin.close(descriptor)
            _ = Darwin.unlink(path)
            throw SocketError.system(error)
        }

        listenerFD = descriptor
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptClient()
        }
        source.setCancelHandler {
            Darwin.close(descriptor)
        }
        listenerSource = source
        source.resume()
    }

    func requestStop() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(rawValue: ScreenBroadcastConfiguration.stopNotification as CFString),
            nil,
            nil,
            true
        )
    }

    func stop() {
        queue.sync {
            isStopping = true
            closeClient(notify: false)
            listenerFD = -1
            listenerSource?.cancel()
            listenerSource = nil
            _ = Darwin.unlink(path)
            pendingBytes.removeAll(keepingCapacity: false)
        }
    }

    private func acceptClient() {
        guard listenerFD >= 0, clientFD < 0 else {
            return
        }

        let descriptor = Darwin.accept(listenerFD, nil, nil)
        guard descriptor >= 0 else {
            return
        }

        let flags = fcntl(descriptor, F_GETFL, 0)
        _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
        clientFD = descriptor
        isStopping = false

        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in
            self?.readAvailableBytes()
        }
        source.setCancelHandler {
            Darwin.close(descriptor)
        }
        clientSource = source
        source.resume()
        onConnect()
    }

    private func readAvailableBytes() {
        guard clientFD >= 0 else {
            return
        }

        var scratch = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = scratch.withUnsafeMutableBytes { bytes in
                Darwin.recv(clientFD, bytes.baseAddress, bytes.count, 0)
            }

            if count > 0 {
                pendingBytes.append(contentsOf: scratch.prefix(count))
                guard consumeFrames() else {
                    closeClient(notify: true)
                    return
                }
                continue
            }

            if count == 0 {
                closeClient(notify: true)
                return
            }

            if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR {
                return
            }

            closeClient(notify: true)
            return
        }
    }

    private func consumeFrames() -> Bool {
        while pendingBytes.count >= Self.headerLength {
            let frameLength = Int(readUInt32(at: 0))
            let width = Int(readUInt32(at: 4))
            let height = Int(readUInt32(at: 8))
            let rotation = readUInt32(at: 12)

            guard frameLength > 0,
                  frameLength <= Self.maximumFrameLength,
                  (1...4096).contains(width),
                  (1...4096).contains(height)
            else {
                return false
            }

            let packetLength = Self.headerLength + frameLength
            guard pendingBytes.count >= packetLength else {
                return true
            }

            let imageData = pendingBytes.subdata(in: Self.headerLength..<packetLength)
            pendingBytes.removeSubrange(0..<packetLength)
            guard let pixelBuffer = pixelBuffer(from: imageData, width: width, height: height) else {
                continue
            }

            onFrame(pixelBuffer, videoRotation(rotation))
        }

        return true
    }

    private func readUInt32(at offset: Int) -> UInt32 {
        pendingBytes[offset..<(offset + 4)].reduce(UInt32.zero) { ($0 << 8) | UInt32($1) }
    }

    private func pixelBuffer(from data: Data, width: Int, height: Int) -> CVPixelBuffer? {
        guard let image = CIImage(data: data),
              abs(Int(image.extent.width) - width) <= 2,
              abs(Int(image.extent.height) - height) <= 2
        else {
            return nil
        }

        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            return nil
        }

        context.render(image, to: pixelBuffer)
        return pixelBuffer
    }

    private func videoRotation(_ degrees: UInt32) -> RTCVideoRotation {
        switch degrees {
        case 90:
            ._90
        case 180:
            ._180
        case 270:
            ._270
        default:
            ._0
        }
    }

    private func closeClient(notify: Bool) {
        guard clientFD >= 0 else {
            return
        }

        clientFD = -1
        pendingBytes.removeAll(keepingCapacity: false)
        clientSource?.cancel()
        clientSource = nil

        if notify, !isStopping {
            onDisconnect()
        }
    }

    private enum SocketError: LocalizedError {
        case invalidPath
        case system(Int32)

        var errorDescription: String? {
            switch self {
            case .invalidPath:
                return "The screen broadcast socket path is too long."
            case .system(let code):
                return String(cString: strerror(code))
            }
        }
    }
}
