import XCTest
@testable import G13HID

final class VirtualKeyboardTests: XCTestCase {
    // All tests that instantiate VirtualKeyboard are skipped to avoid entitlement requirement.

    override func setUp() { super.setUp() }

    func testKeyboardInitializationSkipped() throws {
        throw XCTSkip("VirtualKeyboard requires HID entitlement; skipped.")
    }

    func testKeyCodeFromString() {
        // Test key code conversion
        XCTAssertEqual(VirtualKeyboard.keyCodeFromString("a"), .a)
        XCTAssertEqual(VirtualKeyboard.keyCodeFromString("A"), .a)
        XCTAssertEqual(VirtualKeyboard.keyCodeFromString("w"), .w)
        XCTAssertEqual(VirtualKeyboard.keyCodeFromString("s"), .s)
        XCTAssertEqual(VirtualKeyboard.keyCodeFromString("d"), .d)
        XCTAssertEqual(VirtualKeyboard.keyCodeFromString("space"), .space)
        XCTAssertEqual(VirtualKeyboard.keyCodeFromString("enter"), .enter)
        XCTAssertEqual(VirtualKeyboard.keyCodeFromString("return"), .enter)
        XCTAssertEqual(VirtualKeyboard.keyCodeFromString("escape"), .escape)
        XCTAssertEqual(VirtualKeyboard.keyCodeFromString("esc"), .escape)
        XCTAssertEqual(VirtualKeyboard.keyCodeFromString("f1"), .f1)
        XCTAssertEqual(VirtualKeyboard.keyCodeFromString("1"), .num1)
        XCTAssertEqual(VirtualKeyboard.keyCodeFromString("up"), .upArrow)
        XCTAssertEqual(VirtualKeyboard.keyCodeFromString("down"), .downArrow)
        XCTAssertEqual(VirtualKeyboard.keyCodeFromString("left"), .leftArrow)
        XCTAssertEqual(VirtualKeyboard.keyCodeFromString("right"), .rightArrow)

        // Test invalid key
        XCTAssertNil(VirtualKeyboard.keyCodeFromString("invalid"))
    }

    func testPressAndReleaseKeySkipped() throws { throw XCTSkip("Skipped VirtualKeyboard press/release") }

    func testTapKeySkipped() throws { throw XCTSkip("Skipped VirtualKeyboard tap") }

    func testMultipleKeyPressSkipped() throws { throw XCTSkip("Skipped VirtualKeyboard multi-press") }

    func testReleaseAllKeysSkipped() throws { throw XCTSkip("Skipped VirtualKeyboard releaseAll") }

    func testModifierKeysSkipped() throws { throw XCTSkip("Skipped VirtualKeyboard modifiers") }

    func testAllKeyCodes() {
        // Test that all key codes have valid raw values
        XCTAssertEqual(VirtualKeyboard.KeyCode.a.rawValue, 0x04)
        XCTAssertEqual(VirtualKeyboard.KeyCode.w.rawValue, 0x1A)
        XCTAssertEqual(VirtualKeyboard.KeyCode.space.rawValue, 0x2C)
        XCTAssertEqual(VirtualKeyboard.KeyCode.enter.rawValue, 0x28)
    }

    func testModifierValues() {
        // Test modifier key values
        XCTAssertEqual(VirtualKeyboard.ModifierKey.leftControl.rawValue, 0x01)
        XCTAssertEqual(VirtualKeyboard.ModifierKey.leftShift.rawValue, 0x02)
        XCTAssertEqual(VirtualKeyboard.ModifierKey.leftAlt.rawValue, 0x04)
        XCTAssertEqual(VirtualKeyboard.ModifierKey.leftCommand.rawValue, 0x08)
    }
}
