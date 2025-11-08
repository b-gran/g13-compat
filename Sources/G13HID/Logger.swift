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

    private var logFile: URL
    private var fileHandle: FileHandle?
    private let minLevel: LogLevel
    private let appendMode: Bool
    private let maxBytes: Int? // rotation threshold

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
        if let rawMax = ProcessInfo.processInfo.environment["G13_LOG_MAX_BYTES"], let v = Int(rawMax), v > 1024 { // require >1KB
            maxBytes = v
        } else {
            maxBytes = nil
        }

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
        if let data = logMessage.data(using: .utf8) {
            rotateIfNeeded(adding: data.count)
            fileHandle?.write(data)
        }
    }

    /// Check size and rotate if threshold exceeded.
    private func rotateIfNeeded(adding pendingBytes: Int) {
        guard let max = maxBytes else { return }
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: logFile.path)
            let currentSize = (attrs[.size] as? NSNumber)?.intValue ?? 0
            if currentSize + pendingBytes > max {
                // Close current handle
                try fileHandle?.close()
                // Rotate: move existing file to .1 (single backup)
                let rotated = logFile.appendingPathExtension("1")
                // Remove previous rotated if exists
                if FileManager.default.fileExists(atPath: rotated.path) {
                    try? FileManager.default.removeItem(at: rotated)
                }
                try FileManager.default.moveItem(at: logFile, to: rotated)
                // Create new empty file
                FileManager.default.createFile(atPath: logFile.path, contents: nil)
                fileHandle = try FileHandle(forWritingTo: logFile)
                fileHandle?.seekToEndOfFile()
                internalLog(.info, "🔄 Log rotated (size exceeded \(max) bytes). Previous saved as \(rotated.lastPathComponent)")
            }
        } catch {
            // If rotation fails, log once and disable further rotation attempts by clearing maxBytes (could also keep trying)
            print("[WARN] Logger rotation failed: \(error)")
        }
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
