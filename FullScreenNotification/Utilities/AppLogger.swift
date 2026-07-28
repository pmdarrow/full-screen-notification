import Foundation

final class AppLogger: @unchecked Sendable {
    static let shared = AppLogger()

    static var logFileURL: URL {
        shared.logFileURL
    }

    private static let maximumMessageLength = 4_000

    private let lock = NSLock()
    private let fileManager = FileManager.default
    private let logFileURL: URL
    private let previousLogFileURL: URL
    private let maximumFileSize = 2 * 1_024 * 1_024

    private init() {
        let libraryDirectory = fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let logDirectory = libraryDirectory
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Full Screen Notification", isDirectory: true)

        logFileURL = logDirectory.appendingPathComponent("full-screen-notification.log")
        previousLogFileURL = logDirectory.appendingPathComponent("full-screen-notification.previous.log")
    }

    static func info(_ category: String, _ message: String) {
        shared.write(level: "INFO", category: category, message: message)
    }

    static func error(_ category: String, _ message: String) {
        shared.write(level: "ERROR", category: category, message: message)
    }

    static func errorSummary(_ error: Error) -> String {
        let nsError = error as NSError
        return "domain=\(nsError.domain) code=\(nsError.code) description=\(nsError.localizedDescription)"
    }

    private func write(level: String, category: String, message: String) {
        lock.lock()
        defer { lock.unlock() }

        do {
            try prepareLogFile()

            let timestamp = ISO8601DateFormatter().string(from: Date())
            let sanitizedMessage = sanitize(message)
            let line = "\(timestamp) [\(level)] [\(category)] \(sanitizedMessage)\n"

            let handle = try FileHandle(forWritingTo: logFileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            try handle.close()
        } catch {
            NSLog("Full Screen Notification could not write its log: %@", error.localizedDescription)
        }
    }

    private func prepareLogFile() throws {
        let directory = logFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )

        if shouldRotateLog {
            if fileManager.fileExists(atPath: previousLogFileURL.path) {
                try fileManager.removeItem(at: previousLogFileURL)
            }
            try fileManager.moveItem(at: logFileURL, to: previousLogFileURL)
        }

        if !fileManager.fileExists(atPath: logFileURL.path) {
            guard fileManager.createFile(
                atPath: logFileURL.path,
                contents: nil,
                attributes: [.posixPermissions: 0o600]
            ) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }

        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: logFileURL.path
        )
    }

    private var shouldRotateLog: Bool {
        guard let attributes = try? fileManager.attributesOfItem(atPath: logFileURL.path),
              let fileSize = attributes[.size] as? NSNumber else {
            return false
        }

        return fileSize.intValue >= maximumFileSize
    }

    private func sanitize(_ message: String) -> String {
        let singleLine = message
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")

        return String(singleLine.prefix(Self.maximumMessageLength))
    }
}
