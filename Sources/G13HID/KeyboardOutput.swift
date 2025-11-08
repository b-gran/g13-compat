import Foundation

/// Protocol for keyboard output implementations
public protocol KeyboardOutput {
    /// Press a key with optional modifiers
    func pressKey(_ keyCode: VirtualKeyboard.KeyCode, modifiers: [VirtualKeyboard.ModifierKey]) throws

    /// Release a key with optional modifiers
    func releaseKey(_ keyCode: VirtualKeyboard.KeyCode, modifiers: [VirtualKeyboard.ModifierKey]) throws

    /// Tap a key (press and release)
    /// - Parameters:
    ///   - keyCode: Key to tap
    ///   - modifiers: Modifiers applied during press/release
    ///   - completion: Optional callback invoked after release attempt completes (success or failure)
    func tapKey(_ keyCode: VirtualKeyboard.KeyCode, modifiers: [VirtualKeyboard.ModifierKey], completion: (() -> Void)?) throws

    /// Release all currently pressed keys
    func releaseAllKeys() throws
}

// Extension to provide convenience methods with default parameters
extension KeyboardOutput {
    public func pressKey(_ keyCode: VirtualKeyboard.KeyCode) throws {
        try pressKey(keyCode, modifiers: [])
    }

    public func releaseKey(_ keyCode: VirtualKeyboard.KeyCode) throws {
        try releaseKey(keyCode, modifiers: [])
    }

    public func tapKey(_ keyCode: VirtualKeyboard.KeyCode, completion: (() -> Void)? = nil) throws {
        try tapKey(keyCode, modifiers: [], completion: completion)
    }
}

/// Keyboard output mode
public enum KeyboardOutputMode: String, Codable {
    case hidDevice      // Real IOHIDUserDevice (requires entitlement)
    case cgEvent        // CGEvent API (works immediately, no entitlement)

    public var description: String {
        switch self {
        case .hidDevice:
            return "HID Device (requires entitlement)"
        case .cgEvent:
            return "CGEvent (no entitlement required)"
        }
    }
}

/// Factory for creating keyboard output implementations
public class KeyboardOutputFactory {
    /// Create a keyboard output implementation
    /// - Parameter mode: The output mode to use
    /// - Returns: A keyboard output implementation, or nil if creation failed
    public static func create(mode: KeyboardOutputMode) -> KeyboardOutput? {
        switch mode {
        case .hidDevice:
            do {
                return try VirtualKeyboard()
            } catch {
                log("Failed to create HID keyboard: \(error)")
                return nil
            }

        case .cgEvent:
            return CGEventKeyboard()
        }
    }

    /// Create a keyboard output implementation with automatic fallback
    /// Tries HID device first, falls back to CGEvent if that fails
    /// - Returns: A keyboard output implementation
    public static func createWithFallback() -> KeyboardOutput {
        log("Attempting to create HID virtual keyboard...")
        if let hidKeyboard = create(mode: .hidDevice) {
            log("✅ Using HID virtual keyboard")
            return hidKeyboard
        }

        log("⚠️  HID keyboard creation failed, falling back to CGEvent")
        log("   (This is expected if you don't have the entitlement)")
        return CGEventKeyboard()
    }
}
