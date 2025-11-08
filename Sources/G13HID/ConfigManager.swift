import Foundation

/// Configuration for a single G key
public struct GKeyConfig: Codable {
    public let keyNumber: Int
    public let action: GKeyAction

    public init(keyNumber: Int, action: GKeyAction) {
        self.keyNumber = keyNumber
        self.action = action
    }
}

/// Actions that can be assigned to G keys
public enum GKeyAction: Codable {
    case macro(String)  // Reference to a macro name
    case keyTap(String)  // Single key tap
    case disabled

    enum CodingKeys: String, CodingKey {
        case type
        case macroName
        case key
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "macro":
            let macroName = try container.decode(String.self, forKey: .macroName)
            self = .macro(macroName)
        case "keyTap":
            let key = try container.decode(String.self, forKey: .key)
            self = .keyTap(key)
        case "disabled":
            self = .disabled
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown action type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .macro(let name):
            try container.encode("macro", forKey: .type)
            try container.encode(name, forKey: .macroName)
        case .keyTap(let key):
            try container.encode("keyTap", forKey: .type)
            try container.encode(key, forKey: .key)
        case .disabled:
            try container.encode("disabled", forKey: .type)
        }
    }
}

/// Joystick configuration
public struct JoystickConfig: Codable {
    public var enabled: Bool
    public var deadzone: Double
    public var dutyCycleFrequency: Double
    public var dutyCycleRatio: Double
    public var upKey: String
    public var downKey: String
    public var leftKey: String
    public var rightKey: String
    public var maxEventsPerSecond: Int? // Optional cap on key press/release events (secondary duty cycle throttle)

    public init(
        enabled: Bool = true,
        deadzone: Double = 0.15,
        dutyCycleFrequency: Double = 60.0,
        dutyCycleRatio: Double = 0.5,
        upKey: String = "w",
        downKey: String = "s",
        leftKey: String = "a",
        rightKey: String = "d",
        maxEventsPerSecond: Int? = nil
    ) {
        self.enabled = enabled
        self.deadzone = deadzone
        self.dutyCycleFrequency = dutyCycleFrequency
        self.dutyCycleRatio = dutyCycleRatio
        self.upKey = upKey
        self.downKey = downKey
        self.leftKey = leftKey
        self.rightKey = rightKey
        self.maxEventsPerSecond = maxEventsPerSecond
    }
}

/// Complete G13 configuration
public struct G13Config: Codable {
    public var macros: [String: Macro]
    public var gKeys: [GKeyConfig]
    public var joystick: JoystickConfig
    public var keyboardOutputMode: KeyboardOutputMode

    public init(
        macros: [String: Macro] = [:],
        gKeys: [GKeyConfig] = [],
        joystick: JoystickConfig = JoystickConfig(),
        keyboardOutputMode: KeyboardOutputMode = .cgEvent
    ) {
        self.macros = macros
        self.gKeys = gKeys
        self.joystick = joystick
        self.keyboardOutputMode = keyboardOutputMode
    }

    /// Create a default configuration with all G keys mapped
    public static func defaultConfig() -> G13Config {
        var gKeys: [GKeyConfig] = []

        // Map G1-G22 to F1-F12 and other keys
        let defaultMappings: [(Int, String)] = [
            (1, "f1"), (2, "f2"), (3, "f3"), (4, "f4"),
            (5, "f5"), (6, "f6"), (7, "f7"), (8, "f8"),
            (9, "f9"), (10, "f10"), (11, "f11"), (12, "f12"),
            (13, "1"), (14, "2"), (15, "3"), (16, "4"),
            (17, "5"), (18, "6"), (19, "7"), (20, "8"),
            (21, "9"), (22, "0")
        ]

        for (number, key) in defaultMappings {
            gKeys.append(GKeyConfig(keyNumber: number, action: .keyTap(key)))
        }

        return G13Config(
            macros: [:],
            gKeys: gKeys,
            joystick: JoystickConfig()
        )
    }
}

/// Manages configuration loading and saving
public class ConfigManager {
    private let fileManager = FileManager.default
    private var configPath: URL
    private var config: G13Config

    public enum ConfigError: Error, LocalizedError {
        case fileNotFound
        case invalidJSON
        case saveFailed(String)
        case loadFailed(String)

        public var errorDescription: String? {
            switch self {
            case .fileNotFound:
                return "Configuration file not found"
            case .invalidJSON:
                return "Invalid JSON in configuration file"
            case .saveFailed(let message):
                return "Failed to save configuration: \(message)"
            case .loadFailed(let message):
                return "Failed to load configuration: \(message)"
            }
        }
    }

    public init(configPath: URL? = nil) throws {
        // Default config path in user's home directory
        if let customPath = configPath {
            self.configPath = customPath
        } else {
            let homeDir = fileManager.homeDirectoryForCurrentUser
            self.configPath = homeDir.appendingPathComponent(".g13-config.json")
        }

        // Initialize with default config first
        self.config = G13Config.defaultConfig()

        // Try to load existing config, or save default
        if fileManager.fileExists(atPath: self.configPath.path) {
            self.config = try loadConfig()
        } else {
            try saveConfig()
        }
    }

    /// Get the current configuration
    public func getConfig() -> G13Config {
        return config
    }

    /// Update the configuration
    public func updateConfig(_ newConfig: G13Config) throws {
        self.config = newConfig
        try saveConfig()
    }

    /// Update just the macros
    public func updateMacros(_ macros: [String: Macro]) throws {
        config.macros = macros
        try saveConfig()
    }

    /// Update just the G key mappings
    public func updateGKeys(_ gKeys: [GKeyConfig]) throws {
        config.gKeys = gKeys
        try saveConfig()
    }

    /// Update just the joystick config
    public func updateJoystick(_ joystick: JoystickConfig) throws {
        config.joystick = joystick
        try saveConfig()
    }

    /// Load configuration from file
    private func loadConfig() throws -> G13Config {
        do {
            let data = try Data(contentsOf: configPath)
            let decoder = JSONDecoder()
            return try decoder.decode(G13Config.self, from: data)
        } catch {
            throw ConfigError.loadFailed(error.localizedDescription)
        }
    }

    /// Save configuration to file
    private func saveConfig() throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: configPath, options: .atomic)
        } catch {
            throw ConfigError.saveFailed(error.localizedDescription)
        }
    }

    /// Get the configuration file path
    public func getConfigPath() -> URL {
        return configPath
    }

    /// Export configuration to a different path
    public func exportConfig(to path: URL) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: path, options: .atomic)
        } catch {
            throw ConfigError.saveFailed(error.localizedDescription)
        }
    }

    /// Import configuration from a file
    public func importConfig(from path: URL) throws {
        do {
            let data = try Data(contentsOf: path)
            let decoder = JSONDecoder()
            let newConfig = try decoder.decode(G13Config.self, from: data)
            self.config = newConfig
            try saveConfig()
        } catch {
            throw ConfigError.loadFailed(error.localizedDescription)
        }
    }
}
