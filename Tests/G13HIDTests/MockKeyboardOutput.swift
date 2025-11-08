import Foundation
@testable import G13HID

/// Simple mock implementing KeyboardOutput without needing HID entitlement.
final class MockKeyboardOutput: KeyboardOutput {
    private(set) var pressed: [VirtualKeyboard.KeyCode] = []
    private(set) var tapHistory: [VirtualKeyboard.KeyCode] = []

    func pressKey(_ keyCode: VirtualKeyboard.KeyCode, modifiers: [VirtualKeyboard.ModifierKey]) throws {
        if !pressed.contains(keyCode) { pressed.append(keyCode) }
    }

    func releaseKey(_ keyCode: VirtualKeyboard.KeyCode, modifiers: [VirtualKeyboard.ModifierKey]) throws {
        pressed.removeAll { $0 == keyCode }
    }

    func tapKey(_ keyCode: VirtualKeyboard.KeyCode, modifiers: [VirtualKeyboard.ModifierKey], completion: (() -> Void)?) throws {
        tapHistory.append(keyCode)
        completion?()
    }

    func releaseAllKeys() throws {
        pressed.removeAll()
    }
}