import XCTest
@testable import G13HID

final class KeyMapperTests: XCTestCase {
    var keyboard: VirtualKeyboard?
    var macroEngine: MacroEngine?
    var keyMapper: KeyMapper?
    var config: G13Config?

    override func setUp() {
        super.setUp()

        keyboard = try? VirtualKeyboard()
        if let kb = keyboard {
            macroEngine = MacroEngine(keyboard: kb)

            config = G13Config.defaultConfig()
            if let cfg = config, let macro = macroEngine {
                keyMapper = KeyMapper(keyboard: kb, macroEngine: macro, config: cfg)
            }
        }
    }

    override func tearDown() {
        keyMapper = nil
        macroEngine = nil
        keyboard = nil
        config = nil
        super.tearDown()
    }

    func testKeyMapperInitialization() throws {
        let kb = try VirtualKeyboard()
        let macro = MacroEngine(keyboard: kb)
        let cfg = G13Config.defaultConfig()
        let mapper = KeyMapper(keyboard: kb, macroEngine: macro, config: cfg)

        XCTAssertNotNil(mapper)
    }

    func testProcessButtonPress() throws {
        guard let mapper = keyMapper else {
            throw XCTSkip("KeyMapper not available")
        }

        // Simulate G1 button press (usage page 0x09, usage 0x01, value 1)
        let inputData = HIDInputData(
            timestamp: 0,
            length: 1,
            usagePage: 0x09,  // Button usage page
            usage: 0x01,      // G1
            intValue: 1,      // Pressed
            rawData: [1]
        )

        XCTAssertNoThrow(mapper.processInput(inputData))

        // Check that G1 is tracked as pressed
        XCTAssertTrue(mapper.getPressedGKeys().contains(1))
    }

    func testProcessButtonRelease() throws {
        guard let mapper = keyMapper else {
            throw XCTSkip("KeyMapper not available")
        }

        // Press G1
        let pressData = HIDInputData(
            timestamp: 0,
            length: 1,
            usagePage: 0x09,
            usage: 0x01,
            intValue: 1,
            rawData: [1]
        )
        mapper.processInput(pressData)

        // Release G1
        let releaseData = HIDInputData(
            timestamp: 1,
            length: 1,
            usagePage: 0x09,
            usage: 0x01,
            intValue: 0,
            rawData: [0]
        )
        mapper.processInput(releaseData)

        // Check that G1 is no longer pressed
        XCTAssertFalse(mapper.getPressedGKeys().contains(1))
    }

    func testMultipleButtonPress() throws {
        guard let mapper = keyMapper else {
            throw XCTSkip("KeyMapper not available")
        }

        // Press G1
        let g1Data = HIDInputData(timestamp: 0, length: 1, usagePage: 0x09, usage: 0x01, intValue: 1, rawData: [1])
        mapper.processInput(g1Data)

        // Press G2
        let g2Data = HIDInputData(timestamp: 1, length: 1, usagePage: 0x09, usage: 0x02, intValue: 1, rawData: [1])
        mapper.processInput(g2Data)

        // Press G3
        let g3Data = HIDInputData(timestamp: 2, length: 1, usagePage: 0x09, usage: 0x03, intValue: 1, rawData: [1])
        mapper.processInput(g3Data)

        // Check all are pressed
        let pressed = mapper.getPressedGKeys()
        XCTAssertTrue(pressed.contains(1))
        XCTAssertTrue(pressed.contains(2))
        XCTAssertTrue(pressed.contains(3))
    }

    func testReleaseAllGKeys() throws {
        guard let mapper = keyMapper else {
            throw XCTSkip("KeyMapper not available")
        }

        // Press multiple keys
        for i in 1...5 {
            let data = HIDInputData(timestamp: UInt64(i), length: 1, usagePage: 0x09, usage: UInt32(i), intValue: 1, rawData: [1])
            mapper.processInput(data)
        }

        XCTAssertEqual(mapper.getPressedGKeys().count, 5)

        // Release all
        mapper.releaseAllGKeys()
        XCTAssertEqual(mapper.getPressedGKeys().count, 0)
    }

    func testUpdateConfig() throws {
        guard let mapper = keyMapper else {
            throw XCTSkip("KeyMapper not available")
        }

        // Create new config
        var newConfig = G13Config()
        newConfig.gKeys = [
            GKeyConfig(keyNumber: 1, action: .keyTap("z"))
        ]

        // Update config
        mapper.updateConfig(newConfig)

        // Process G1 press
        let data = HIDInputData(timestamp: 0, length: 1, usagePage: 0x09, usage: 0x01, intValue: 1, rawData: [1])
        XCTAssertNoThrow(mapper.processInput(data))
    }

    func testGKeyWithMacro() throws {
        guard let mapper = keyMapper,
              let macro = macroEngine else {
            throw XCTSkip("Components not available")
        }

        // Register a macro
        let testMacro = Macro(name: "Test Macro", actions: [
            .keyTap("a"),
            .delay(milliseconds: 10),
            .keyTap("b")
        ])
        macro.registerMacro(key: "testmacro", macro: testMacro)

        // Update config to use macro
        var newConfig = G13Config()
        newConfig.gKeys = [
            GKeyConfig(keyNumber: 1, action: .macro("testmacro"))
        ]
        mapper.updateConfig(newConfig)

        // Press G1
        let data = HIDInputData(timestamp: 0, length: 1, usagePage: 0x09, usage: 0x01, intValue: 1, rawData: [1])
        XCTAssertNoThrow(mapper.processInput(data))

        // Give macro time to execute
        Thread.sleep(forTimeInterval: 0.1)
    }

    func testGKeyWithKeyTap() throws {
        guard let mapper = keyMapper else {
            throw XCTSkip("KeyMapper not available")
        }

        // Configure G1 to tap 'z'
        var newConfig = G13Config()
        newConfig.gKeys = [
            GKeyConfig(keyNumber: 1, action: .keyTap("z"))
        ]
        mapper.updateConfig(newConfig)

        // Press G1
        let data = HIDInputData(timestamp: 0, length: 1, usagePage: 0x09, usage: 0x01, intValue: 1, rawData: [1])
        XCTAssertNoThrow(mapper.processInput(data))
    }

    func testGKeyDisabled() throws {
        guard let mapper = keyMapper else {
            throw XCTSkip("KeyMapper not available")
        }

        // Configure G1 as disabled
        var newConfig = G13Config()
        newConfig.gKeys = [
            GKeyConfig(keyNumber: 1, action: .disabled)
        ]
        mapper.updateConfig(newConfig)

        // Press G1 - should do nothing
        let data = HIDInputData(timestamp: 0, length: 1, usagePage: 0x09, usage: 0x01, intValue: 1, rawData: [1])
        XCTAssertNoThrow(mapper.processInput(data))

        // Key should still be tracked as pressed
        XCTAssertTrue(mapper.getPressedGKeys().contains(1))
    }

    func testGKeyNotConfigured() throws {
        guard let mapper = keyMapper else {
            throw XCTSkip("KeyMapper not available")
        }

        // Use empty config
        let emptyConfig = G13Config()
        mapper.updateConfig(emptyConfig)

        // Press G1 (not configured) - should not crash
        let data = HIDInputData(timestamp: 0, length: 1, usagePage: 0x09, usage: 0x01, intValue: 1, rawData: [1])
        XCTAssertNoThrow(mapper.processInput(data))
    }

    func testNonButtonInput() throws {
        guard let mapper = keyMapper else {
            throw XCTSkip("KeyMapper not available")
        }

        // Send non-button input (e.g., joystick)
        let joystickData = HIDInputData(
            timestamp: 0,
            length: 1,
            usagePage: 0x01,  // Generic Desktop
            usage: 0x30,      // X axis
            intValue: 128,
            rawData: [128]
        )

        // Should not crash or add to pressed keys
        XCTAssertNoThrow(mapper.processInput(joystickData))
        XCTAssertEqual(mapper.getPressedGKeys().count, 0)
    }

    func testRapidButtonPresses() throws {
        guard let mapper = keyMapper else {
            throw XCTSkip("KeyMapper not available")
        }

        // Rapidly press and release G1
        for _ in 0..<10 {
            let pressData = HIDInputData(timestamp: 0, length: 1, usagePage: 0x09, usage: 0x01, intValue: 1, rawData: [1])
            mapper.processInput(pressData)

            let releaseData = HIDInputData(timestamp: 1, length: 1, usagePage: 0x09, usage: 0x01, intValue: 0, rawData: [0])
            mapper.processInput(releaseData)
        }

        // Should end with no keys pressed
        XCTAssertEqual(mapper.getPressedGKeys().count, 0)
    }

    func testAllGKeys() throws {
        guard let mapper = keyMapper else {
            throw XCTSkip("KeyMapper not available")
        }

        // Test all 22 G keys
        for gKey in 1...22 {
            let data = HIDInputData(
                timestamp: UInt64(gKey),
                length: 1,
                usagePage: 0x09,
                usage: UInt32(gKey),
                intValue: 1,
                rawData: [1]
            )
            mapper.processInput(data)
        }

        // All should be tracked
        XCTAssertEqual(mapper.getPressedGKeys().count, 22)

        // Release all
        for gKey in 1...22 {
            let data = HIDInputData(
                timestamp: UInt64(gKey + 100),
                length: 1,
                usagePage: 0x09,
                usage: UInt32(gKey),
                intValue: 0,
                rawData: [0]
            )
            mapper.processInput(data)
        }

        XCTAssertEqual(mapper.getPressedGKeys().count, 0)
    }
}
