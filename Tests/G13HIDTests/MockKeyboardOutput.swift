import Foundation
@testable import G13HID

/// Simple mock implementing KeyboardOutput without needing HID entitlement.
final class MockKeyboardOutput: KeyboardOutput {
    private(set) var pressed: [VirtualKeyboard.KeyCode] = []
    private(set) var tapHistory: [VirtualKeyboard.KeyCode] = []
    private(set) var pressEvents: Int = 0
    private(set) var releaseEvents: Int = 0
    private(set) var activeModifiers: Set<VirtualKeyboard.ModifierKey> = []
    private(set) var modifierPressEvents: Int = 0
    private(set) var modifierReleaseEvents: Int = 0
    private(set) var modifiersUsedOnPress: [[VirtualKeyboard.ModifierKey]] = []
    private(set) var modifiersUsedOnRelease: [[VirtualKeyboard.ModifierKey]] = []
    private(set) var modifiersUsedOnTap: [[VirtualKeyboard.ModifierKey]] = []

    func pressKey(_ keyCode: VirtualKeyboard.KeyCode, modifiers: [VirtualKeyboard.ModifierKey]) throws {
        if !pressed.contains(keyCode) { pressed.append(keyCode) }
        pressEvents += 1
        modifiersUsedOnPress.append(modifiers)
    }

    func releaseKey(_ keyCode: VirtualKeyboard.KeyCode, modifiers: [VirtualKeyboard.ModifierKey]) throws {
        pressed.removeAll { $0 == keyCode }
        releaseEvents += 1
        modifiersUsedOnRelease.append(modifiers)
    }

    func tapKey(_ keyCode: VirtualKeyboard.KeyCode, modifiers: [VirtualKeyboard.ModifierKey], completion: (() -> Void)?) throws {
        tapHistory.append(keyCode)
        modifiersUsedOnTap.append(modifiers)
        completion?()
    }

    func releaseAllKeys() throws {
        pressed.removeAll()
        activeModifiers.removeAll()
    }

    func pressModifier(_ modifier: VirtualKeyboard.ModifierKey) throws {
        activeModifiers.insert(modifier)
        modifierPressEvents += 1
    }

    func releaseModifier(_ modifier: VirtualKeyboard.ModifierKey) throws {
        activeModifiers.remove(modifier)
        modifierReleaseEvents += 1
    }
}