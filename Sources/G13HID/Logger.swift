import Foundation

public enum LogLevel: Int, Comparable, CustomStringConvertible {
    case debug = 0
    case info
    case warn
    case error

    public var description: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warn: return "WARN"
        case .error: return "ERROR"
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Structured file logger with level filtering & optional append mode
public class Logger {
    public static let shared = Logger()

    private let logFile: URL
    private let fileHandle: FileHandle?
    private let minLevel: LogLevel
    private let appendMode: Bool

    private init() {
        // Resolve min level from environment
        if let levelString = ProcessInfo.processInfo.environment["G13_LOG_LEVEL"]?.lowercased() {
            switch levelString {
            case "debug": minLevel = .debug
            case "info": minLevel = .info
            case "warn", "warning": minLevel = .warn
            case "error": minLevel = .error
            default: minLevel = .info
            }
        } else {
            minLevel = .info
        }

        appendMode = ProcessInfo.processInfo.environment["G13_LOG_APPEND"].map { $0 == "1" || $0.lowercased() == "true" } ?? false

        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        logFile = homeDir.appendingPathComponent("g13-debug.log")

        // Create file if missing; truncate only if not in append mode
        if !FileManager.default.fileExists(atPath: logFile.path) {
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
        } else if !appendMode {
            // Truncate
            try? Data().write(to: logFile, options: .atomic)
        }

        fileHandle = try? FileHandle(forWritingTo: logFile)
        fileHandle?.seekToEndOfFile()

        internalLog(.info, "=== G13 Debug Log Started (level=\(minLevel), append=\(appendMode)) ===")
        internalLog(.info, "Log file: \(logFile.path)")
    }

    /// Main logging entry point
    public func log(_ level: LogLevel = .info, _ message: String) {
        guard level >= minLevel else { return }
        internalLog(level, message)
    }

    private func internalLog(_ level: LogLevel, _ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logMessage = "[\(timestamp)] [\(level)] \(message)\n"
        // Console
        print(logMessage, terminator: "")
        // File
        if let data = logMessage.data(using: .utf8) { fileHandle?.write(data) }
    }

    deinit {
        internalLog(.info, "=== G13 Debug Log Ended ===")
        try? fileHandle?.close()
    }
}

// Convenience global functions
public func log(_ message: String) { Logger.shared.log(.info, message) }
public func logDebug(_ message: String) { Logger.shared.log(.debug, message) }
public func logInfo(_ message: String) { Logger.shared.log(.info, message) }
public func logWarn(_ message: String) { Logger.shared.log(.warn, message) }
public func logError(_ message: String) { Logger.shared.log(.error, message) }
