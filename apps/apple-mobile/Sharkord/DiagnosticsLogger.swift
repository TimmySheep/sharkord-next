import Foundation

final class DiagnosticsLogger {
    static let shared = DiagnosticsLogger()

    private let queue = DispatchQueue(label: "cove.diagnostics.log")
    private let maximumFileBytes = 512 * 1024
    private let maximumRetainedCharacters = 12_000
    private let logDirectory: URL?

    private init() {
        logDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("Diagnostics", isDirectory: true)
    }

    func start(app: String) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        record(
            level: "INFO",
            category: "app",
            message: "started app=\(app) version=\(version) build=\(build) os=\(ProcessInfo.processInfo.operatingSystemVersionString)"
        )
        NSSetUncaughtExceptionHandler(Self.exceptionHandler)
    }

    func info(_ category: String, _ message: String) {
        record(level: "INFO", category: category, message: message)
    }

    func warning(_ category: String, _ message: String) {
        record(level: "WARN", category: category, message: message)
    }

    func error(_ category: String, _ message: String, error: Error? = nil) {
        let details = error.map { "\(String(reflecting: type(of: $0))): \($0.localizedDescription)\n\(Thread.callStackSymbols.joined(separator: "\n"))" }
        record(level: "ERROR", category: category, message: message, details: details)
    }

    func recentText() -> String {
        queue.sync {
            let text = readAllLogs()
            return String(text.suffix(maximumRetainedCharacters))
        }
    }

    func exportURL(additionalLogs: String? = nil) throws -> URL {
        try queue.sync {
            guard let logDirectory else {
                throw CocoaError(.fileNoSuchFile)
            }
            let app = Bundle.main.bundleIdentifier?.components(separatedBy: ".").last ?? "mobile"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("cove-\(app)-logs.txt")
            let additionalSection = additionalLogs.map { "\n\nApple Watch logs\n\n\($0)" } ?? ""
            let contents = """
            cove diagnostic log
            app: \(app)
            version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")
            build: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown")
            os: \(ProcessInfo.processInfo.operatingSystemVersionString)
            logs: \(logDirectory.lastPathComponent)

            \(readAllLogs())\(additionalSection)
            """
            try contents.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        }
    }

    private func record(level: String, category: String, message: String, details: String? = nil) {
        queue.async { [weak self] in
            self?.append(level: level, category: category, message: message, details: details)
        }
    }

    private func append(level: String, category: String, message: String, details: String?) {
        guard let logDirectory else {
            return
        }

        let manager = FileManager.default
        let currentURL = logDirectory.appendingPathComponent("current.log")
        let previousURL = logDirectory.appendingPathComponent("previous.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        var entry = "\(timestamp) \(level) [\(Self.sanitize(category))] \(Self.sanitize(message))"
        if let details, !details.isEmpty {
            entry += "\n\(Self.sanitize(details))"
        }
        entry += "\n"
        guard let data = entry.data(using: .utf8) else {
            return
        }

        do {
            try manager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            var directoryValues = URLResourceValues()
            directoryValues.isExcludedFromBackup = true
            var localDirectory = logDirectory
            try? localDirectory.setResourceValues(directoryValues)

            let currentSize = (try? currentURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if currentSize + data.count > maximumFileBytes,
               manager.fileExists(atPath: currentURL.path) {
                try? manager.removeItem(at: previousURL)
                try manager.moveItem(at: currentURL, to: previousURL)
            }

            if !manager.fileExists(atPath: currentURL.path) {
                manager.createFile(atPath: currentURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: currentURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            return
        }
    }

    private func readAllLogs() -> String {
        guard let logDirectory else {
            return ""
        }
        return ["previous.log", "current.log"].compactMap { name in
            try? String(contentsOf: logDirectory.appendingPathComponent(name), encoding: .utf8)
        }.joined(separator: "\n")
    }

    private static func sanitize(_ value: String) -> String {
        let patterns = [
            #"(?i)(Bearer\s+)[A-Za-z0-9._~+/-]+=*"#,
            #"(?i)([\"']?(?:password|serverpassword|token|accesstoken|refreshtoken|authorization|cookie|secret)[\"']?\s*[:=]\s*[\"']?)[^\"'&\s,;}]+"#,
            #"(?i)([?&](?:password|serverpassword|token|accesstoken|refreshtoken|authorization|cookie|secret)=)[^&\s]+"#,
        ]
        return patterns.reduce(value) { text, pattern in
            guard let expression = try? NSRegularExpression(pattern: pattern) else {
                return text
            }
            let range = NSRange(text.startIndex..., in: text)
            return expression.stringByReplacingMatches(
                in: text,
                range: range,
                withTemplate: "$1[REDACTED]"
            )
        }
    }

    private func recordCrash(_ exception: NSException) {
        append(
            level: "FATAL",
            category: "crash",
            message: "uncaught exception \(exception.name.rawValue): \(exception.reason ?? "unknown")",
            details: exception.callStackSymbols.joined(separator: "\n")
        )
    }

    private static let exceptionHandler: @convention(c) (NSException) -> Void = { exception in
        shared.queue.sync {
            shared.recordCrash(exception)
        }
    }
}
