import Foundation
import CoreGraphics
import ApplicationServices

/// Keyboard output using CGEvent API
/// This implementation doesn't require entitlements but may not work in all apps
public class CGEventKeyboard: KeyboardOutput {
    private var pressedKeys: Set<VirtualKeyboard.KeyCode> = []
    private var activeModifiers: Set<VirtualKeyboard.ModifierKey> = []

    public init() {
        log("CGEventKeyboard initialized")
        log("Note: Requires Accessibility permissions in System Preferences > Privacy & Security > Accessibility")

        // Check if we have accessibility permission
        diagnoseAccessibility()
    }

    public func tapKey(_ keyCode: VirtualKeyboard.KeyCode, modifiers: [VirtualKeyboard.ModifierKey], completion: (() -> Void)?) throws {
        log("🟢 CGEventKeyboard.tapKey called: \(keyCode)")
        try pressKey(keyCode, modifiers: modifiers)
        let start = Date()
        let delayMs = CGEventKeyboard.tapDelayMilliseconds
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(delayMs)) { [weak self] in
            guard let self = self else { completion?(); return }
            do {
                try self.releaseKey(keyCode, modifiers: modifiers)
                let elapsed = Int(Date().timeIntervalSince(start) * 1000)
                log("⏱ CGEventKeyboard async tap release (\(elapsed)ms, cfg=\(delayMs)) for key: \(keyCode)")
            } catch {
                log("❌ CGEventKeyboard async tap release failed for key: \(keyCode) error=\(error)")
            }
            completion?()
        }
    }

    // Read configurable tap delay (default 10ms) from environment once.
    private static let tapDelayMilliseconds: Int = {
        let env = ProcessInfo.processInfo.environment["G13_TAP_DELAY_MS"]
        if let raw = env, let val = Int(raw), val >= 5, val <= 250 { return val }
        return 10
    }()
    
    public func pressKey(_ keyCode: VirtualKeyboard.KeyCode, modifiers: [VirtualKeyboard.ModifierKey]) throws {
        log("🔵 CGEventKeyboard.pressKey called: \(keyCode)")

        guard let cgKeyCode = mapToCGKeyCode(keyCode) else {
            log("❌ Failed to map key code: \(keyCode)")
            throw KeyboardError.unsupportedKey(keyCode)
        }

        guard AXIsProcessTrusted() else {
            log("🚫 Cannot post keyDown (AXIsProcessTrusted == false). Open Accessibility prefs and enable this app.")
            throw KeyboardError.accessibilityDenied
        }

        // Track pressed state
        pressedKeys.insert(keyCode)

        let effectiveMods = combinedModifiers(transient: modifiers)
        var flags: CGEventFlags = []
        for modifier in effectiveMods { flags.insert(mapModifierFlags(modifier)) }

        // Send key down event
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: cgKeyCode, keyDown: true) else {
            log("❌ Failed to create CGEvent")
            throw KeyboardError.eventCreationFailed
        }

        event.flags = flags
        event.post(tap: .cghidEventTap)
        log("✅ Posted key down event for CGKeyCode: 0x\(String(format: "%02X", cgKeyCode))")
    }

    public func releaseKey(_ keyCode: VirtualKeyboard.KeyCode, modifiers: [VirtualKeyboard.ModifierKey]) throws {
        log("🔵 CGEventKeyboard.releaseKey called: \(keyCode)")

        guard let cgKeyCode = mapToCGKeyCode(keyCode) else {
            log("❌ Failed to map key code: \(keyCode)")
            throw KeyboardError.unsupportedKey(keyCode)
        }

        guard AXIsProcessTrusted() else {
            log("🚫 Cannot post keyUp (AXIsProcessTrusted == false).")
            throw KeyboardError.accessibilityDenied
        }

        // Remove from pressed state
        pressedKeys.remove(keyCode)

        let effectiveMods = combinedModifiers(transient: modifiers)
        var flags: CGEventFlags = []
        for modifier in effectiveMods { flags.insert(mapModifierFlags(modifier)) }

        // Send key up event
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: cgKeyCode, keyDown: false) else {
            log("❌ Failed to create CGEvent")
            throw KeyboardError.eventCreationFailed
        }

        event.flags = flags
        event.post(tap: .cghidEventTap)
        log("✅ Posted key up event for CGKeyCode: 0x\(String(format: "%02X", cgKeyCode))")
    }


    public func releaseAllKeys() throws {
        // Release all currently pressed keys
        for keyCode in pressedKeys {
            try? releaseKey(keyCode, modifiers: [])
        }
        pressedKeys.removeAll()
        activeModifiers.removeAll()
    }

    // MARK: Modifier standalone handling
    public func pressModifier(_ modifier: VirtualKeyboard.ModifierKey) throws {
        activeModifiers.insert(modifier)
        // Emit a standalone keyDown event for the physical modifier to reflect held state to the system.
        try postModifierEvent(modifier: modifier, keyDown: true)
    }

    public func releaseModifier(_ modifier: VirtualKeyboard.ModifierKey) throws {
        activeModifiers.remove(modifier)
        // Emit a standalone keyUp event for the physical modifier.
        try postModifierEvent(modifier: modifier, keyDown: false)
    }

    private func combinedModifiers(transient: [VirtualKeyboard.ModifierKey]) -> [VirtualKeyboard.ModifierKey] {
        if transient.isEmpty { return Array(activeModifiers) }
        return Array(activeModifiers.union(transient))
    }

    // MARK: - Key Code Mapping

    /// Map HID usage codes to CGKeyCode
    /// Note: These are US QWERTY layout mappings
    private func mapToCGKeyCode(_ keyCode: VirtualKeyboard.KeyCode) -> CGKeyCode? {
        switch keyCode {
        // Letters
        case .a: return 0x00
        case .s: return 0x01
        case .d: return 0x02
        case .f: return 0x03
        case .h: return 0x04
        case .g: return 0x05
        case .z: return 0x06
        case .x: return 0x07
        case .c: return 0x08
        case .v: return 0x09
        case .b: return 0x0B
        case .q: return 0x0C
        case .w: return 0x0D
        case .e: return 0x0E
        case .r: return 0x0F
        case .y: return 0x10
        case .t: return 0x11
        case .num1: return 0x12
        case .num2: return 0x13
        case .num3: return 0x14
        case .num4: return 0x15
        case .num6: return 0x16
        case .num5: return 0x17
        case .equals: return 0x18
        case .num9: return 0x19
        case .num7: return 0x1A
        case .minus: return 0x1B
        case .num8: return 0x1C
        case .num0: return 0x1D
        case .rightBracket: return 0x1E
        case .o: return 0x1F
        case .u: return 0x20
        case .leftBracket: return 0x21
        case .i: return 0x22
        case .p: return 0x23
        case .l: return 0x25
        case .j: return 0x26
        case .quote: return 0x27
        case .k: return 0x28
        case .semicolon: return 0x29
        case .backslash: return 0x2A
        case .comma: return 0x2B
        case .slash: return 0x2C
        case .n: return 0x2D
        case .m: return 0x2E
        case .period: return 0x2F
        case .grave: return 0x32

        // Special keys
        case .enter: return 0x24
        case .tab: return 0x30
        case .space: return 0x31
        case .backspace: return 0x33
        case .escape: return 0x35
        case .capsLock: return 0x39

        // Function keys
        case .f1: return 0x7A
        case .f2: return 0x78
        case .f3: return 0x63
        case .f4: return 0x76
        case .f5: return 0x60
        case .f6: return 0x61
        case .f7: return 0x62
        case .f8: return 0x64
        case .f9: return 0x65
        case .f10: return 0x6D
        case .f11: return 0x67
        case .f12: return 0x6F

        // Arrow keys
        case .leftArrow: return 0x7B
        case .rightArrow: return 0x7C
        case .downArrow: return 0x7D
        case .upArrow: return 0x7E

        // Navigation keys
        case .home: return 0x73
        case .end: return 0x77
        case .pageUp: return 0x74
        case .pageDown: return 0x79
        case .delete: return 0x75

        default:
            return nil
        }
    }

    private func mapModifierFlags(_ modifier: VirtualKeyboard.ModifierKey) -> CGEventFlags {
        switch modifier {
        case .leftControl, .rightControl:
            return .maskControl
        case .leftShift, .rightShift:
            return .maskShift
        case .leftAlt, .rightAlt:
            return .maskAlternate
        case .leftCommand, .rightCommand:
            return .maskCommand
        }
    }

    /// Map modifier to a representative CGKeyCode (left side variants preferred).
    /// Using actual key codes ensures applications registering separate modifier down/up without an accompanying non-modifier key will observe state transitions.
    private func mapModifierToCGKeyCode(_ modifier: VirtualKeyboard.ModifierKey) -> CGKeyCode? {
        switch modifier {
        case .leftShift, .rightShift:
            return 0x38 // Shift (left)
        case .leftControl, .rightControl:
            return 0x3B // Control (left)
        case .leftAlt, .rightAlt:
            return 0x3A // Option (left)
        case .leftCommand, .rightCommand:
            return 0x37 // Command (left)
        }
    }

    /// Post a standalone modifier event (keyDown/keyUp) so the system updates modifier state.
    private func postModifierEvent(modifier: VirtualKeyboard.ModifierKey, keyDown: Bool) throws {
        guard AXIsProcessTrusted() else {
            throw KeyboardError.accessibilityDenied
        }
        guard let cgKeyCode = mapModifierToCGKeyCode(modifier) else { return }
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: cgKeyCode, keyDown: keyDown) else {
            throw KeyboardError.eventCreationFailed
        }
        // Ensure flags reflect all currently active modifiers (including this one if keyDown).
        var flags: CGEventFlags = []
        for m in activeModifiers { flags.insert(mapModifierFlags(m)) }
        event.flags = flags
        event.post(tap: .cghidEventTap)
        log("🔑 Posted modifier \(keyDown ? "DOWN" : "UP") event for \(modifier) CGKeyCode=0x\(String(format: "%02X", cgKeyCode)) activeFlags=\(flags)")
    }

    // MARK: - Error Types

    public enum KeyboardError: Error, LocalizedError, Equatable {
        case unsupportedKey(VirtualKeyboard.KeyCode)
        case eventCreationFailed
        case accessibilityDenied
        case postFailed(String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedKey(let key):
                return "Unsupported key: \(key)"
            case .eventCreationFailed:
                return "Failed to create CGEvent"
            case .accessibilityDenied:
                return "Accessibility permission denied (AXIsProcessTrusted == false)"
            case .postFailed(let msg):
                return "Failed to post CGEvent: \(msg)"
            }
        }
    }

    // MARK: - Diagnostics

    private func diagnoseAccessibility() {
        let trusted = AXIsProcessTrusted()
        if trusted {
            log("✅ Accessibility permission: GRANTED")
        } else {
            log("⚠️  Accessibility permission: NOT GRANTED - keyboard output will not work!")
            log("   Go to System Settings > Privacy & Security > Accessibility and enable: \(ProcessInfo.processInfo.processName)")
            let bundleID = Bundle.main.bundleIdentifier ?? "(unknown bundle id)"
            log("   Bundle ID: \(bundleID)")
        }
    }

    deinit {
        try? releaseAllKeys()
    }
}
