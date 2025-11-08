import Foundation

/// Represents a single action in a macro
public enum MacroAction: Codable {
    case keyPress(String)
    case keyRelease(String)
    case keyTap(String)
    case delay(milliseconds: Int)
    case text(String)

    enum CodingKeys: String, CodingKey {
        case type
        case key
        case milliseconds
        case text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "keyPress":
            let key = try container.decode(String.self, forKey: .key)
            self = .keyPress(key)
        case "keyRelease":
            let key = try container.decode(String.self, forKey: .key)
            self = .keyRelease(key)
        case "keyTap":
            let key = try container.decode(String.self, forKey: .key)
            self = .keyTap(key)
        case "delay":
            let ms = try container.decode(Int.self, forKey: .milliseconds)
            self = .delay(milliseconds: ms)
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown macro action type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .keyPress(let key):
            try container.encode("keyPress", forKey: .type)
            try container.encode(key, forKey: .key)
        case .keyRelease(let key):
            try container.encode("keyRelease", forKey: .type)
            try container.encode(key, forKey: .key)
        case .keyTap(let key):
            try container.encode("keyTap", forKey: .type)
            try container.encode(key, forKey: .key)
        case .delay(let ms):
            try container.encode("delay", forKey: .type)
            try container.encode(ms, forKey: .milliseconds)
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        }
    }
}

/// Represents a complete macro sequence
public struct Macro: Codable {
    public let name: String
    public let actions: [MacroAction]

    public init(name: String, actions: [MacroAction]) {
        self.name = name
        self.actions = actions
    }
}

/// Manages and executes macros
public class MacroEngine {
    private let keyboard: KeyboardOutput
    private var macros: [String: Macro] = [:]
    private var executionQueue = DispatchQueue(label: "com.g13compat.macroengine", qos: .userInitiated)
    private var isExecuting = false // Reserved for future use (sequential execution semantics)

    public init(keyboard: KeyboardOutput) {
        self.keyboard = keyboard
    }

    /// Register a macro with a given key
    public func registerMacro(key: String, macro: Macro) {
        macros[key] = macro
    }

    /// Remove a macro
    public func unregisterMacro(key: String) {
        macros.removeValue(forKey: key)
    }

    /// Get a registered macro
    public func getMacro(key: String) -> Macro? {
        return macros[key]
    }

    /// Get all registered macros
    public func getAllMacros() -> [String: Macro] {
        return macros
    }

    /// Execute a macro by key. Optional cancellation token allows mid-run abort.
    /// - Parameters:
    ///   - key: Registered macro key
    ///   - token: Optional cancellation token
    ///   - completion: Completion callback invoked on success or failure (including cancellation)
    /// - Returns: Provided or newly created cancellation token (use to cancel execution)
    @discardableResult
    public func executeMacro(key: String,
                             token: MacroCancellationToken? = nil,
                             completion: ((Result<Void, Error>) -> Void)? = nil) -> MacroCancellationToken? {
        guard let macro = macros[key] else {
            completion?(.failure(MacroError.macroNotFound(key)))
            return token
        }

        let runToken = token ?? MacroCancellationToken()

        executionQueue.async { [weak self] in
            guard let self = self else { return }

            do {
                try self.runMacro(macro, token: runToken)
                completion?(.success(()))
            } catch {
                completion?(.failure(error))
            }
        }
        return runToken
    }

    private func runMacro(_ macro: Macro, token: MacroCancellationToken?) throws {
        for action in macro.actions {
            if token?.isCancelled == true { throw MacroError.cancelled }
            try executeAction(action, token: token)
        }
    }

    private func executeAction(_ action: MacroAction, token: MacroCancellationToken?) throws {
        switch action {
        case .keyPress(let keyString):
            guard let keyCode = VirtualKeyboard.keyCodeFromString(keyString) else {
                throw MacroError.invalidKey(keyString)
            }
            try keyboard.pressKey(keyCode)

        case .keyRelease(let keyString):
            guard let keyCode = VirtualKeyboard.keyCodeFromString(keyString) else {
                throw MacroError.invalidKey(keyString)
            }
            try keyboard.releaseKey(keyCode)

        case .keyTap(let keyString):
            guard let keyCode = VirtualKeyboard.keyCodeFromString(keyString) else {
                throw MacroError.invalidKey(keyString)
            }
            try keyboard.tapKey(keyCode)

        case .delay(let milliseconds):
            try performDelay(milliseconds, token: token)

        case .text(let text):
            try typeText(text, token: token)
        }
    }

    private func typeText(_ text: String, token: MacroCancellationToken?) throws {
        for char in text.lowercased() {
            if token?.isCancelled == true { throw MacroError.cancelled }
            if let keyCode = VirtualKeyboard.keyCodeFromString(String(char)) {
                try keyboard.tapKey(keyCode)
                // Small delay between characters with cancellation responsiveness
                try performDelay(10, token: token)
            } else {
                // Skip unknown characters silently; could be extended for error reporting
                continue
            }
        }
    }

    /// Perform a delay in small slices to allow responsive cancellation.
    private func performDelay(_ milliseconds: Int, token: MacroCancellationToken?) throws {
        guard milliseconds > 0 else { return }
        var remaining = milliseconds
        // Slice size (ms). 10ms chosen as balance between responsiveness and overhead.
        let slice = 10
        while remaining > 0 {
            if token?.isCancelled == true { throw MacroError.cancelled }
            let sleepMs = min(slice, remaining)
            usleep(UInt32(sleepMs * 1000))
            remaining -= sleepMs
        }
    }

    public enum MacroError: Error, LocalizedError {
        case macroNotFound(String)
        case invalidKey(String)
        case executionFailed(String)
        case cancelled

        public var errorDescription: String? {
            switch self {
            case .macroNotFound(let key):
                return "Macro not found: \(key)"
            case .invalidKey(let key):
                return "Invalid key: \(key)"
            case .executionFailed(let message):
                return "Macro execution failed: \(message)"
            case .cancelled:
                return "Macro execution cancelled"
            }
        }
    }
}

/// Cancellation token for macro execution. Thread-safe flag checked between actions and delay slices.
public final class MacroCancellationToken {
    private let lock = DispatchQueue(label: "com.g13compat.macro.cancel", qos: .utility)
    private var _cancelled = false

    public init() {}

    public func cancel() {
        lock.sync { _cancelled = true }
    }

    public var isCancelled: Bool {
        lock.sync { _cancelled }
    }
}

/// Helper to create common macro patterns
extension Macro {
    /// Create a simple key tap macro
    public static func simpleTap(_ key: String) -> Macro {
        return Macro(name: "Tap \(key)", actions: [.keyTap(key)])
    }

    /// Create a text typing macro
    public static func typeText(_ text: String) -> Macro {
        return Macro(name: "Type: \(text)", actions: [.text(text)])
    }

    /// Create a key combo macro (e.g., Ctrl+C)
    public static func keyCombo(keys: [String], delay: Int = 50) -> Macro {
        var actions: [MacroAction] = []

        // Press all keys
        for key in keys {
            actions.append(.keyPress(key))
            actions.append(.delay(milliseconds: delay))
        }

        // Release all keys in reverse order
        for key in keys.reversed() {
            actions.append(.keyRelease(key))
        }

        return Macro(name: "Combo: \(keys.joined(separator: "+"))", actions: actions)
    }
}
