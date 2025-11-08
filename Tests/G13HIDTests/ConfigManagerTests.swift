import XCTest
@testable import G13HID
import Foundation

final class ConfigManagerTests: XCTestCase {
    var tempConfigPath: URL?
    var configManager: ConfigManager?

    override func setUp() {
        super.setUp()
        // Create a temporary config file path
        let tempDir = FileManager.default.temporaryDirectory
        tempConfigPath = tempDir.appendingPathComponent("test-g13-config-\(UUID().uuidString).json")
    }

    override func tearDown() {
        // Clean up temp config file
        if let path = tempConfigPath {
            try? FileManager.default.removeItem(at: path)
        }
        configManager = nil
        tempConfigPath = nil
        super.tearDown()
    }

    func testDefaultConfig() throws {
        let config = G13Config.defaultConfig()

        // Check that default config has G keys mapped
        XCTAssertEqual(config.gKeys.count, 22)

        // Check joystick defaults
        XCTAssertTrue(config.joystick.enabled)
        XCTAssertEqual(config.joystick.deadzone, 0.15)
        // Default events mode should be duty cycle
        if case .dutyCycle(let freq, let ratio, _) = config.joystick.events {
            XCTAssertEqual(freq, 60.0)
            XCTAssertEqual(ratio, 0.5)
        } else { XCTFail("Expected dutyCycle events mode") }
        XCTAssertEqual(config.joystick.upKey, "w")
        XCTAssertEqual(config.joystick.downKey, "s")
        XCTAssertEqual(config.joystick.leftKey, "a")
        XCTAssertEqual(config.joystick.rightKey, "d")

        // Check that macros is empty
        XCTAssertEqual(config.macros.count, 0)
    }

    func testConfigManagerInitialization() throws {
        guard let path = tempConfigPath else {
            XCTFail("No temp path")
            return
        }

        // Create config manager with custom path
        let manager = try ConfigManager(configPath: path)
        XCTAssertNotNil(manager)

        // Check that config file was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))

        // Get config and verify it's the default
        let config = manager.getConfig()
        XCTAssertEqual(config.gKeys.count, 22)
    }

    func testGetConfig() throws {
        guard let path = tempConfigPath else {
            XCTFail("No temp path")
            return
        }

        let manager = try ConfigManager(configPath: path)
        let config = manager.getConfig()

        XCTAssertNotNil(config)
        XCTAssertEqual(config.gKeys.count, 22)
    }

    func testUpdateConfig() throws {
        guard let path = tempConfigPath else {
            XCTFail("No temp path")
            return
        }

        let manager = try ConfigManager(configPath: path)

        // Create a new config
        var newConfig = G13Config()
        newConfig.gKeys = [
            GKeyConfig(keyNumber: 1, action: .keyTap("f1")),
            GKeyConfig(keyNumber: 2, action: .keyTap("f2"))
        ]

        // Update
        try manager.updateConfig(newConfig)

        // Verify
        let retrieved = manager.getConfig()
        XCTAssertEqual(retrieved.gKeys.count, 2)
    }

    func testUpdateMacros() throws {
        guard let path = tempConfigPath else {
            XCTFail("No temp path")
            return
        }

        let manager = try ConfigManager(configPath: path)

        // Create some macros
        let macros: [String: Macro] = [
            "macro1": Macro(name: "Macro 1", actions: [.keyTap("a")]),
            "macro2": Macro(name: "Macro 2", actions: [.keyTap("b")])
        ]

        // Update
        try manager.updateMacros(macros)

        // Verify
        let config = manager.getConfig()
        XCTAssertEqual(config.macros.count, 2)
        XCTAssertNotNil(config.macros["macro1"])
        XCTAssertNotNil(config.macros["macro2"])
    }

    func testUpdateGKeys() throws {
        guard let path = tempConfigPath else {
            XCTFail("No temp path")
            return
        }

        let manager = try ConfigManager(configPath: path)

        let gKeys = [
            GKeyConfig(keyNumber: 1, action: .keyTap("a")),
            GKeyConfig(keyNumber: 2, action: .keyTap("b")),
            GKeyConfig(keyNumber: 3, action: .disabled)
        ]

        try manager.updateGKeys(gKeys)

        let config = manager.getConfig()
        XCTAssertEqual(config.gKeys.count, 3)
    }

    func testUpdateJoystick() throws {
        guard let path = tempConfigPath else {
            XCTFail("No temp path")
            return
        }

        let manager = try ConfigManager(configPath: path)

    var joystick = JoystickConfig()
    joystick.deadzone = 0.25
    joystick.enabled = false
    joystick.events = .dutyCycle(frequency: 30.0, ratio: 0.5, maxEventsPerSecond: nil)

        try manager.updateJoystick(joystick)

        let config = manager.getConfig()
        XCTAssertEqual(config.joystick.deadzone, 0.25)
        if case .dutyCycle(let freq, _, _) = config.joystick.events {
            XCTAssertEqual(freq, 30.0)
        } else { XCTFail("Expected duty cycle mode") }
        XCTAssertFalse(config.joystick.enabled)
    }

    func testExportConfig() throws {
        guard let path = tempConfigPath else {
            XCTFail("No temp path")
            return
        }

        let manager = try ConfigManager(configPath: path)

        // Create export path
        let exportPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("exported-\(UUID().uuidString).json")

        // Export
        try manager.exportConfig(to: exportPath)

        // Verify file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportPath.path))

        // Clean up
        try? FileManager.default.removeItem(at: exportPath)
    }

    func testImportConfig() throws {
        guard let path = tempConfigPath else {
            XCTFail("No temp path")
            return
        }

        let manager = try ConfigManager(configPath: path)

        // Create a config to import
        var configToImport = G13Config()
        configToImport.gKeys = [
            GKeyConfig(keyNumber: 1, action: .keyTap("z"))
        ]
        configToImport.joystick.deadzone = 0.33

        // Save it to a temp file
        let importPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-\(UUID().uuidString).json")

        let encoder = JSONEncoder()
        let data = try encoder.encode(configToImport)
        try data.write(to: importPath)

        // Import
        try manager.importConfig(from: importPath)

        // Verify
        let config = manager.getConfig()
        XCTAssertEqual(config.gKeys.count, 1)
        XCTAssertEqual(config.joystick.deadzone, 0.33)

        // Clean up
        try? FileManager.default.removeItem(at: importPath)
    }

    func testConfigPersistence() throws {
        guard let path = tempConfigPath else {
            XCTFail("No temp path")
            return
        }

        // Create and update config
        do {
            let manager = try ConfigManager(configPath: path)
            var config = manager.getConfig()
            config.joystick.deadzone = 0.42
            try manager.updateConfig(config)
        }

        // Create new manager with same path
        do {
            let manager = try ConfigManager(configPath: path)
            let config = manager.getConfig()

            // Verify value persisted
            XCTAssertEqual(config.joystick.deadzone, 0.42)
        }
    }

    func testGKeyActionCodable() throws {
        // Test macro action
        let macroAction = GKeyAction.macro("testMacro")
        let macroData = try JSONEncoder().encode(macroAction)
        let decodedMacro = try JSONDecoder().decode(GKeyAction.self, from: macroData)

        if case .macro(let name) = decodedMacro {
            XCTAssertEqual(name, "testMacro")
        } else {
            XCTFail("Wrong action type")
        }

        // Test keyTap action
        let keyAction = GKeyAction.keyTap("a")
        let keyData = try JSONEncoder().encode(keyAction)
        let decodedKey = try JSONDecoder().decode(GKeyAction.self, from: keyData)

        if case .keyTap(let key) = decodedKey {
            XCTAssertEqual(key, "a")
        } else {
            XCTFail("Wrong action type")
        }

        // Test disabled action
        let disabledAction = GKeyAction.disabled
        let disabledData = try JSONEncoder().encode(disabledAction)
        let decodedDisabled = try JSONDecoder().decode(GKeyAction.self, from: disabledData)

        if case .disabled = decodedDisabled {
            XCTAssertTrue(true)
        } else {
            XCTFail("Wrong action type")
        }
    }

    func testJoystickConfigCodable() throws {
        let joystick = JoystickConfig(
            enabled: true,
            deadzone: 0.2,
            events: .dutyCycle(frequency: 50.0, ratio: 0.6, maxEventsPerSecond: nil),
            upKey: "i",
            downKey: "k",
            leftKey: "j",
            rightKey: "l"
        )

        let data = try JSONEncoder().encode(joystick)
        let decoded = try JSONDecoder().decode(JoystickConfig.self, from: data)

        XCTAssertEqual(decoded.enabled, true)
        XCTAssertEqual(decoded.deadzone, 0.2)
        if case .dutyCycle(let freq, let ratio, _) = decoded.events {
            XCTAssertEqual(freq, 50.0)
            XCTAssertEqual(ratio, 0.6)
        } else { XCTFail("Expected dutyCycle mode") }
        XCTAssertEqual(decoded.upKey, "i")
        XCTAssertEqual(decoded.downKey, "k")
        XCTAssertEqual(decoded.leftKey, "j")
        XCTAssertEqual(decoded.rightKey, "l")
    }

    func testCompleteConfigCodable() throws {
        var config = G13Config()

        // Add macros
        config.macros = [
            "test": Macro(name: "Test", actions: [.keyTap("a"), .delay(milliseconds: 10)])
        ]

        // Add G keys
        config.gKeys = [
            GKeyConfig(keyNumber: 1, action: .macro("test")),
            GKeyConfig(keyNumber: 2, action: .keyTap("b"))
        ]

        // Configure joystick
        config.joystick.deadzone = 0.18

        // Encode and decode
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(G13Config.self, from: data)

        XCTAssertEqual(decoded.macros.count, 1)
        XCTAssertEqual(decoded.gKeys.count, 2)
        XCTAssertEqual(decoded.joystick.deadzone, 0.18)
    }
}
