import Foundation

/// stores a small, credential-free diagnostic history that users can export for support.
public final class ClientLogStore: @unchecked Sendable {
    public static let shared = ClientLogStore()
    private static let knownTRPCCodes: Set<String> = [
        "AUDIO_FORMAT",
        "BAD_GATEWAY",
        "BAD_REQUEST",
        "CLIENT_CLOSED_REQUEST",
        "CONFLICT",
        "DISCONNECTED",
        "ENCODING",
        "FORBIDDEN",
        "GATEWAY_TIMEOUT",
        "INTERNAL_SERVER_ERROR",
        "METHOD_NOT_SUPPORTED",
        "NOT_FOUND",
        "NOT_IMPLEMENTED",
        "PAYLOAD_TOO_LARGE",
        "PRECONDITION_FAILED",
        "PROTOCOL",
        "RECONNECT",
        "SERVICE_UNAVAILABLE",
        "TIMEOUT",
        "TOO_MANY_REQUESTS",
        "UNAUTHORIZED",
        "UNPROCESSABLE_CONTENT",
        "UNPROCESSABLE_ENTITY"
    ]

    private let directoryURL: URL
    private let maximumFileSize: Int
    private let retainedArchives: Int
    private let fileManager: FileManager
    private let lock = NSLock()

    public init(
        directoryURL: URL? = nil,
        maximumFileSize: Int = 1_048_576,
        retainedArchives: Int = 3,
        fileManager: FileManager = .default
    ) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.directoryURL = supportURL
                .appendingPathComponent("Cove", isDirectory: true)
                .appendingPathComponent("Logs", isDirectory: true)
        }

        self.maximumFileSize = max(1, maximumFileSize)
        self.retainedArchives = max(0, retainedArchives)
        self.fileManager = fileManager
    }

    public func recordInfo(_ event: String, code: String? = nil) {
        append(level: "INFO", event: event, errorType: nil, code: code)
    }

    public func recordFailure(_ event: String, code: String? = nil) {
        append(level: "ERROR", event: event, errorType: nil, code: code)
    }

    public func recordError(_ event: String, error: Error) {
        if error is CancellationError {
            return
        }

        let nsError = error as NSError
        let code: String
        if let error = error as? TRPCClientError {
            let normalizedCode = error.code.uppercased()
            if Self.knownTRPCCodes.contains(normalizedCode) || Int(normalizedCode) != nil {
                code = "trpc.\(normalizedCode)"
            } else {
                code = "trpc.unknown"
            }
        } else if let error = error as? SharkordHTTPError {
            code = "http.\(error.status)"
        } else {
            code = "system.\(nsError.code)"
        }

        append(
            level: "ERROR",
            event: event,
            errorType: String(describing: type(of: error)),
            code: code
        )
    }

    public func exportLogs(to destinationURL: URL) throws {
        lock.lock()
        defer { lock.unlock() }

        let contents = try logFileURLs()
            .filter { fileManager.fileExists(atPath: $0.path) }
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")

        try Data(contents.utf8).write(to: destinationURL, options: .atomic)
    }

    private var currentLogURL: URL {
        directoryURL.appendingPathComponent("cove.log")
    }

    private func append(level: String, event: String, errorType: String?, code: String?) {
        lock.lock()
        defer { lock.unlock() }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        var fields = [
            timestamp,
            "level=\(safeField(level))",
            "event=\(safeField(event))"
        ]
        if let errorType {
            fields.append("error=\(safeField(errorType))")
        }
        if let code {
            fields.append("code=\(safeField(code))")
        }

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let line = Data((fields.joined(separator: " ") + "\n").utf8)
            try rotateIfNeeded(for: line.count)

            if !fileManager.fileExists(atPath: currentLogURL.path) {
                fileManager.createFile(atPath: currentLogURL.path, contents: nil)
            }

            let handle = try FileHandle(forWritingTo: currentLogURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } catch {
            NSLog("Cove could not write a diagnostic log entry (%@)", safeField(String(describing: type(of: error))))
        }
    }

    private func rotateIfNeeded(for incomingSize: Int) throws {
        guard fileManager.fileExists(atPath: currentLogURL.path),
              let attributes = try? fileManager.attributesOfItem(atPath: currentLogURL.path)
        else {
            return
        }

        let currentSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard currentSize > 0, currentSize + incomingSize > maximumFileSize else {
            return
        }

        guard retainedArchives > 0 else {
            try fileManager.removeItem(at: currentLogURL)
            return
        }

        let oldestURL = archiveURL(retainedArchives)
        if fileManager.fileExists(atPath: oldestURL.path) {
            try fileManager.removeItem(at: oldestURL)
        }

        if retainedArchives > 1 {
            for index in stride(from: retainedArchives - 1, through: 1, by: -1) {
                let sourceURL = archiveURL(index)
                guard fileManager.fileExists(atPath: sourceURL.path) else {
                    continue
                }
                try fileManager.moveItem(at: sourceURL, to: archiveURL(index + 1))
            }
        }

        try fileManager.moveItem(at: currentLogURL, to: archiveURL(1))
    }

    private func logFileURLs() -> [URL] {
        let archives = retainedArchives > 0
            ? (1...retainedArchives).reversed().map(archiveURL)
            : []
        return archives + [currentLogURL]
    }

    private func archiveURL(_ index: Int) -> URL {
        directoryURL.appendingPathComponent("cove.\(index).log")
    }

    private func safeField(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        let sanitized = Array(value.unicodeScalars.filter { allowed.contains($0) }.prefix(96))
        return sanitized.isEmpty ? "unknown" : String(String.UnicodeScalarView(sanitized))
    }
}
