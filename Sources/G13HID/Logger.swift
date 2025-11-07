import Foundation

/// Simple file logger
public class Logger {
    public static let shared = Logger()

    private let logFile: URL
    private let fileHandle: FileHandle?

    private init() {
        // Log to ~/g13-debug.log
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        logFile = homeDir.appendingPathComponent("g13-debug.log")

        // Create or truncate the log file
        FileManager.default.createFile(atPath: logFile.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: logFile)

        log("=== G13 Debug Log Started ===")
        log("Log file: \(logFile.path)")
    }

    public func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logMessage = "[\(timestamp)] \(message)\n"

        // Print to console
        print(logMessage, terminator: "")

        // Write to file
        if let data = logMessage.data(using: .utf8) {
            fileHandle?.write(data)
        }
    }

    deinit {
        log("=== G13 Debug Log Ended ===")
        try? fileHandle?.close()
    }
}

// Convenience function
public func log(_ message: String) {
    Logger.shared.log(message)
}
