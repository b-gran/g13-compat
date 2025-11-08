import XCTest
@testable import G13HID

final class JoystickHoldAssistTests: XCTestCase {
    /// Mock keyboard output capturing presses/releases
    private final class MockKeyboard: KeyboardOutput {
        var pressed: Set<VirtualKeyboard.KeyCode> = []

        func pressKey(_ keyCode: VirtualKeyboard.KeyCode, modifiers: [VirtualKeyboard.ModifierKey]) throws {
            pressed.insert(keyCode)
        }

        func releaseKey(_ keyCode: VirtualKeyboard.KeyCode, modifiers: [VirtualKeyboard.ModifierKey]) throws {
            pressed.remove(keyCode)
        }

        func tapKey(_ keyCode: VirtualKeyboard.KeyCode, modifiers: [VirtualKeyboard.ModifierKey], completion: (() -> Void)?) throws {
            pressed.insert(keyCode)
            pressed.remove(keyCode)
            completion?()
        }

        func releaseAllKeys() throws { pressed.removeAll() }
        func pressModifier(_ modifier: VirtualKeyboard.ModifierKey) throws {}
        func releaseModifier(_ modifier: VirtualKeyboard.ModifierKey) throws {}
    }

    func testAssistStartsDualKeysEarlyWithinAngleWindow() {
        let kb = MockKeyboard()
        let controller = JoystickController(keyboard: kb)
        // Configure hold mode with assist requiring small angle to trigger
        let assist = JoystickDiagonalAssist(axisThresholdMultiplier: 0.7, minAngleDegrees: 5.0, maxAngleDegrees: 25.0, minSecondaryRatio: 0.30)
        var cfg = JoystickConfig()
    cfg.events = .hold(diagonalAnglePercent: 0.30, holdEnabled: true, diagonalAssist: assist)
        controller.configure(from: cfg)
        controller.debugHoldLogging = false

        // Provide an angle just above minAngleDegrees but below diagonalAnglePercent*90 (thresholdAdd)
        // thresholdAdd = 0.30 * 90 = 27 degrees. We'll use ~15 degrees which is inside assist window.
        // Vector near 15 degrees from right (d + w)
        let angleRad = 15.0 * Double.pi / 180.0
        let x = cos(angleRad)
        let y = sin(angleRad)
        controller.updateJoystick(x: x, y: y)

        // Expect both d and w pressed due to assist early start
        XCTAssertTrue(kb.pressed.contains(.d), "Primary key d should be pressed")
        XCTAssertTrue(kb.pressed.contains(.w), "Secondary key w should be pressed early via assist")
    }

    func testAssistStartsDualKeysViaAxisThresholdEvenIfAngleBelowMin() {
        let kb = MockKeyboard()
        let controller = JoystickController(keyboard: kb)
        // Use a multiplier low enough that both axis components exceed threshold even at a very small angle (< minAngleDegrees)
        // deadzone = 0.15, axisThresholdMultiplier = 0.55 -> componentThreshold = 0.0825; sin(5°) ≈ 0.0872 > threshold
        // This validates axis-based early dual key start independent of angle window.
        let assist = JoystickDiagonalAssist(axisThresholdMultiplier: 0.55, minAngleDegrees: 10.0, maxAngleDegrees: 30.0, minSecondaryRatio: 0.25)
        var cfg = JoystickConfig()
        cfg.deadzone = 0.15
    cfg.events = .hold(diagonalAnglePercent: 0.35, holdEnabled: true, diagonalAssist: assist)
        controller.configure(from: cfg)
        controller.debugHoldLogging = false

        // Angle small (< minAngleDegrees) but strong axis components both exceed axisThresholdMultiplier * deadzone
        // componentThreshold = 0.6 * 0.15 = 0.09; choose x,y large enough but angle ~5 degrees.
        let angleDeg = 5.0
        let angleRad = angleDeg * Double.pi / 180.0
        let magnitude = 1.0
        let x = magnitude * cos(angleRad)
        let y = magnitude * sin(angleRad)
        controller.updateJoystick(x: x, y: y)

        XCTAssertTrue(kb.pressed.contains(.d), "Primary key d should be pressed")
        XCTAssertTrue(kb.pressed.contains(.w), "Secondary key w should be pressed due to axis threshold assist")
    }

    func testNoAssistSingleKeyBeforeThresholdWithoutAssist() {
        let kb = MockKeyboard()
        let controller = JoystickController(keyboard: kb)
        var cfg = JoystickConfig()
    cfg.events = .hold(diagonalAnglePercent: 0.30, holdEnabled: true, diagonalAssist: nil)
        controller.configure(from: cfg)
        controller.debugHoldLogging = false

        // Angle 15 degrees (< thresholdAdd 27) but no assist configured; expect only primary
        let angleRad = 15.0 * Double.pi / 180.0
        let x = cos(angleRad)
        let y = sin(angleRad)
        controller.updateJoystick(x: x, y: y)

        XCTAssertTrue(kb.pressed.contains(.d))
        XCTAssertFalse(kb.pressed.contains(.w), "Secondary key should not start early without assist")
    }
}
