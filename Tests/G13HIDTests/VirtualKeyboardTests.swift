import XCTest
@testable import G13HID

final class VirtualKeyboardTests: XCTestCase {
    var keyboard: VirtualKeyboard?

    override func setUp() {
        super.setUp()
        // Note: VirtualKeyboard requires IOHIDUserDevice which may fail in test environment
        keyboard = try? VirtualKeyboard()
    }

    override func tearDown() {
        keyboard = nil
        super.tearDown()
    }

    func testKeyboardInitialization() throws {
        // Test that keyboard can be initialized
        let kb = try VirtualKeyboard()
        XCTAssertNotNil(kb)
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

    func testPressAndReleaseKey() throws {
        guard let kb = keyboard else {
            throw XCTSkip("Virtual keyboard not available in test environment")
        }

        // Test pressing and releasing a key
        XCTAssertNoThrow(try kb.pressKey(.a))
        XCTAssertNoThrow(try kb.releaseKey(.a))
    }

    func testTapKey() throws {
        guard let kb = keyboard else {
            throw XCTSkip("Virtual keyboard not available in test environment")
        }

        // Test tapping a key
        XCTAssertNoThrow(try kb.tapKey(.w))
        XCTAssertNoThrow(try kb.tapKey(.a))
        XCTAssertNoThrow(try kb.tapKey(.s))
        XCTAssertNoThrow(try kb.tapKey(.d))
    }

    func testMultipleKeyPress() throws {
        guard let kb = keyboard else {
            throw XCTSkip("Virtual keyboard not available in test environment")
        }

        // Test pressing multiple keys simultaneously
        XCTAssertNoThrow(try kb.pressKey(.w))
        XCTAssertNoThrow(try kb.pressKey(.a))
        XCTAssertNoThrow(try kb.releaseKey(.w))
        XCTAssertNoThrow(try kb.releaseKey(.a))
    }

    func testReleaseAllKeys() throws {
        guard let kb = keyboard else {
            throw XCTSkip("Virtual keyboard not available in test environment")
        }

        // Press multiple keys
        XCTAssertNoThrow(try kb.pressKey(.w))
        XCTAssertNoThrow(try kb.pressKey(.a))
        XCTAssertNoThrow(try kb.pressKey(.s))

        // Release all at once
        XCTAssertNoThrow(try kb.releaseAllKeys())
    }

    func testModifierKeys() throws {
        guard let kb = keyboard else {
            throw XCTSkip("Virtual keyboard not available in test environment")
        }

        // Test with modifiers
        XCTAssertNoThrow(try kb.tapKey(.c, modifiers: [.leftControl]))
        XCTAssertNoThrow(try kb.tapKey(.v, modifiers: [.leftControl]))
        XCTAssertNoThrow(try kb.tapKey(.a, modifiers: [.leftControl, .leftShift]))
    }

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
