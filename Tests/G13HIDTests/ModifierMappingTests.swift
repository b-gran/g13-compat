import XCTest
@testable import G13HID

final class ModifierMappingTests: XCTestCase {
    func testHeldModifierAppliesToSubsequentTap() throws {
        let mock = MockKeyboardOutput()
        let macroEngine = MacroEngine(keyboard: mock)
        let config = G13Config(
            macros: [:],
            gKeys: [
                GKeyConfig(keyNumber: 1, action: .modifier(.shift)),
                GKeyConfig(keyNumber: 2, action: .keyTap("a"))
            ],
            joystick: JoystickConfig(),
            keyboardOutputMode: .cgEvent
        )
        let mapper = KeyMapper(keyboard: mock, macroEngine: macroEngine, config: config)

        // Press modifier G1
        let modPress = HIDInputData(timestamp: 0, length: 1, usagePage: 0x09, usage: 0x01, intValue: 1, rawData: [1])
        mapper.processInput(modPress)
        XCTAssertTrue(mock.activeModifiers.contains(.leftShift), "Shift modifier should be active after G1 press")

        // Tap G2 while modifier held
        let tapPress = HIDInputData(timestamp: 1, length: 1, usagePage: 0x09, usage: 0x02, intValue: 1, rawData: [1])
        mapper.processInput(tapPress)
        XCTAssertEqual(mock.tapHistory.count, 1)
        XCTAssertEqual(mock.tapHistory.first, .a)
        XCTAssertEqual(mock.modifiersUsedOnTap.count, 1)
        XCTAssertEqual(Set(mock.modifiersUsedOnTap.first ?? []), Set([.leftShift]))

        // Release modifier G1
        let modRelease = HIDInputData(timestamp: 2, length: 1, usagePage: 0x09, usage: 0x01, intValue: 0, rawData: [0])
        mapper.processInput(modRelease)
        XCTAssertFalse(mock.activeModifiers.contains(.leftShift), "Shift modifier should be released after G1 release")
    }
}
