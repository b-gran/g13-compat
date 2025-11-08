import XCTest
@testable import G13HID

final class ModifierStandaloneEventsTests: XCTestCase {
    func testModifierStandalonePressReleaseGeneratesEvents() throws {
        let mock = MockKeyboardOutput()
        let macroEngine = MacroEngine(keyboard: mock)
        let config = G13Config(
            macros: [:],
            gKeys: [
                GKeyConfig(keyNumber: 3, action: .modifier(.control))
            ],
            joystick: JoystickConfig(),
            keyboardOutputMode: .cgEvent
        )
        let mapper = KeyMapper(keyboard: mock, macroEngine: macroEngine, config: config)

        // Press control modifier on G3
        let press = HIDInputData(timestamp: 0, length: 1, usagePage: 0x09, usage: 0x03, intValue: 1, rawData: [1])
        mapper.processInput(press)
        XCTAssertTrue(mock.activeModifiers.contains(.leftControl), "Control modifier should be active after G3 press")
        XCTAssertEqual(mock.modifierPressEvents, 1, "Expected one modifier press event")
        XCTAssertEqual(mock.modifierReleaseEvents, 0)

        // Release control modifier on G3
        let release = HIDInputData(timestamp: 1, length: 1, usagePage: 0x09, usage: 0x03, intValue: 0, rawData: [0])
        mapper.processInput(release)
        XCTAssertFalse(mock.activeModifiers.contains(.leftControl), "Control modifier should be inactive after G3 release")
        XCTAssertEqual(mock.modifierPressEvents, 1)
        XCTAssertEqual(mock.modifierReleaseEvents, 1, "Expected one modifier release event")
    }
}
