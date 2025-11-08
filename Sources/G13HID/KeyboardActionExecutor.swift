import Foundation

/// High-level keyboard actions emitted by mapping layer.
public enum KeyboardAction: Equatable {
    case keyTap(String)
    case keyDown(String)
    case keyUp(String)
    case macro(String)
}

/// Errors that can occur while performing a keyboard action.
public enum KeyboardActionError: Error, LocalizedError, Equatable {
    case invalidKey(String)
    case macroNotFound(String)
    case executionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidKey(let k): return "Invalid key: \(k)"
        case .macroNotFound(let m): return "Macro not found: \(m)"
        case .executionFailed(let msg): return "Execution failed: \(msg)"
        }
    }
}

/// Executes keyboard actions using a KeyboardOutput + MacroEngine.
/// Surfaces granular errors from underlying implementations (VirtualKeyboard.KeyboardError, CGEventKeyboard.KeyboardError).
public final class KeyboardActionExecutor {
    private let keyboard: KeyboardOutput
    private let macroEngine: MacroEngine

    public init(keyboard: KeyboardOutput, macroEngine: MacroEngine) {
        self.keyboard = keyboard
        self.macroEngine = macroEngine
    }

    /// Perform a single action. Macro actions are asynchronous; others are immediate.
    @discardableResult
    public func perform(_ action: KeyboardAction, completion: ((Result<Void, Error>) -> Void)? = nil) -> Result<Void, Error> {
        switch action {
        case .keyTap(let key):
            return handleImmediate(key: key, op: .tap, completion: completion)
        case .keyDown(let key):
            return handleImmediate(key: key, op: .down, completion: completion)
        case .keyUp(let key):
            return handleImmediate(key: key, op: .up, completion: completion)
        case .macro(let name):
            guard macroEngine.getMacro(key: name) != nil else {
                let err: KeyboardActionError = .macroNotFound(name)
                completion?(.failure(err));
                return .failure(err)
            }
            macroEngine.executeMacro(key: name) { result in
                completion?(result.map { _ in () })
            }
            return .success(()) // Indicate dispatch success
        }
    }

    private enum ImmediateOp { case tap, down, up }

    private func handleImmediate(key: String, op: ImmediateOp, completion: ((Result<Void, Error>) -> Void)?) -> Result<Void, Error> {
        guard let keyCode = VirtualKeyboard.keyCodeFromString(key) else {
            let err: KeyboardActionError = .invalidKey(key)
            completion?(.failure(err))
            return .failure(err)
        }
        do {
            switch op {
            case .tap: try keyboard.tapKey(keyCode)
            case .down: try keyboard.pressKey(keyCode)
            case .up: try keyboard.releaseKey(keyCode)
            }
            completion?(.success(()))
            return .success(())
        } catch {
            completion?(.failure(error))
            return .failure(error)
        }
    }
}
