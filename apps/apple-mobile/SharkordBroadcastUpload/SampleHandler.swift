import CoreImage
import CoreMedia
import Foundation
import ReplayKit

private enum BroadcastConfiguration {
    static let appGroupIdentifier = "group.com.timmysheep.sharkord.ios"
    static let socketFileName = "screen-broadcast.sock"
    static let stopNotification = "com.timmysheep.sharkord.ios.stop-screen-broadcast"
    static let maximumDimension = 1280
    static let frameInterval: TimeInterval = 1.0 / 12.0
}

final class SampleHandler: RPBroadcastSampleHandler {
    private let encodingQueue = DispatchQueue(label: "cove.broadcast.frame-encoder", qos: .userInteractive)
    private let imageContext = CIContext(options: [.cacheIntermediates: false])
    private let stateLock = NSLock()
    private var socketFD: Int32 = -1
    private var isEncodingFrame = false
    private var lastFrameTime = 0.0
    private var stopObserver: UnsafeMutableRawPointer?

    override init() {
        super.init()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        stopObserver = observer
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let handler = Unmanaged<SampleHandler>.fromOpaque(observer).takeUnretainedValue()
                handler.finishBroadcastWithError(SampleHandler.broadcastStoppedError)
            },
            BroadcastConfiguration.stopNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        if let stopObserver {
            CFNotificationCenterRemoveObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                stopObserver,
                CFNotificationName(rawValue: BroadcastConfiguration.stopNotification as CFString),
                nil
            )
        }
        closeSocket()
    }

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        guard connectToHost() else {
            finishBroadcastWithError(Self.hostUnavailableError)
            return
        }
    }

    override func broadcastPaused() {}

    override func broadcastResumed() {}

    override func broadcastFinished() {
        closeSocket()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else {
            return
        }

        stateLock.lock()
        let now = ProcessInfo.processInfo.systemUptime
        guard !isEncodingFrame, now - lastFrameTime >= BroadcastConfiguration.frameInterval else {
            stateLock.unlock()
            return
        }
        isEncodingFrame = true
        lastFrameTime = now
        stateLock.unlock()

        encodingQueue.async { [weak self] in
            guard let self else { return }
            defer {
                self.stateLock.lock()
                self.isEncodingFrame = false
                self.stateLock.unlock()
            }
            self.encodeAndSend(sampleBuffer)
        }
    }

    private func connectToHost() -> Bool {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: BroadcastConfiguration.appGroupIdentifier
        ) else {
            return false
        }

        let path = containerURL.appendingPathComponent(BroadcastConfiguration.socketFileName).path
        guard path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
            return false
        }

        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            return false
        }

        var noSignal: Int32 = 1
        _ = setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let socketPathLength = MemoryLayout.size(ofValue: address.sun_path)
        _ = path.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path.0) { destination in
                strncpy(destination, source, socketPathLength - 1)
            }
        }

        let result = withUnsafePointer(to: &address) { addressPointer in
            addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            Darwin.close(descriptor)
            return false
        }

        stateLock.lock()
        socketFD = descriptor
        stateLock.unlock()
        return true
    }

    private func encodeAndSend(_ sampleBuffer: CMSampleBuffer) {
        guard let source = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let sourceImage = CIImage(cvPixelBuffer: source)
        let sourceSize = sourceImage.extent.size
        let scale = min(
            1,
            CGFloat(BroadcastConfiguration.maximumDimension) / max(sourceSize.width, sourceSize.height)
        )
        let scaledImage = sourceImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let colorSpace = scaledImage.colorSpace,
              let jpegData = imageContext.jpegRepresentation(
                of: scaledImage,
                colorSpace: colorSpace,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.72]
              )
        else {
            return
        }

        let width = UInt32(scaledImage.extent.width.rounded())
        let height = UInt32(scaledImage.extent.height.rounded())
        let rotation = UInt32(screenRotation(sampleBuffer))
        var packet = Data()
        packet.reserveCapacity(16 + jpegData.count)
        packet.appendBigEndian(UInt32(jpegData.count))
        packet.appendBigEndian(width)
        packet.appendBigEndian(height)
        packet.appendBigEndian(rotation)
        packet.append(jpegData)

        stateLock.lock()
        let descriptor = socketFD
        stateLock.unlock()
        guard descriptor >= 0 else {
            finishBroadcastWithError(Self.hostUnavailableError)
            return
        }

        guard sendAll(packet, to: descriptor) else {
            closeSocket()
            finishBroadcastWithError(Self.hostUnavailableError)
            return
        }
    }

    private func sendAll(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return false }
            var offset = 0
            while offset < bytes.count {
                let sent = Darwin.send(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    bytes.count - offset,
                    0
                )
                if sent > 0 {
                    offset += sent
                } else if sent < 0 && errno == EINTR {
                    continue
                } else {
                    return false
                }
            }
            return true
        }
    }

    private func screenRotation(_ sampleBuffer: CMSampleBuffer) -> Int {
        guard let orientation = CMGetAttachment(
            sampleBuffer,
            key: RPVideoSampleOrientationKey as CFString,
            attachmentModeOut: nil
        )?.uintValue,
        let imageOrientation = CGImagePropertyOrientation(rawValue: UInt32(orientation))
        else {
            return 0
        }

        return switch imageOrientation {
        case .right, .rightMirrored:
            90
        case .down, .downMirrored:
            180
        case .left, .leftMirrored:
            270
        default:
            0
        }
    }

    private func closeSocket() {
        stateLock.lock()
        let descriptor = socketFD
        socketFD = -1
        stateLock.unlock()
        if descriptor >= 0 {
            Darwin.shutdown(descriptor, SHUT_RDWR)
            Darwin.close(descriptor)
        }
    }

    private static var broadcastStoppedError: NSError {
        NSError(
            domain: RPRecordingErrorDomain,
            code: 10001,
            userInfo: [NSLocalizedDescriptionKey: "Screen sharing stopped"]
        )
    }

    private static var hostUnavailableError: NSError {
        NSError(
            domain: RPRecordingErrorDomain,
            code: 10002,
            userInfo: [NSLocalizedDescriptionKey: "The Cove call is no longer available"]
        )
    }
}

private extension Data {
    mutating func appendBigEndian(_ value: UInt32) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { append(contentsOf: $0) }
    }
}
