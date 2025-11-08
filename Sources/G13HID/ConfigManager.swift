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
    case modifier(ModifierKind) // Acts as held modifier while pressed

    enum CodingKeys: String, CodingKey {
        case type
        case macroName
        case key
        case modifier
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
        case "modifier":
            let mod = try container.decode(ModifierKind.self, forKey: .modifier)
            self = .modifier(mod)
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
        case .modifier(let kind):
            try container.encode("modifier", forKey: .type)
            try container.encode(kind, forKey: .modifier)
        }
    }
}

/// Supported logical modifier kinds user can assign to a G-key.
public enum ModifierKind: String, Codable, CaseIterable {
    case shift
    case control
    case alt
    case command

    public var displayName: String { rawValue.capitalized }
}

/// Joystick configuration
public struct JoystickDiagonalAssist: Codable {
    public let axisThresholdMultiplier: Double
    public let minAngleDegrees: Double
    public let maxAngleDegrees: Double
    public let minSecondaryRatio: Double

    public init(axisThresholdMultiplier: Double = 0.85,
                minAngleDegrees: Double = 8.0,
                maxAngleDegrees: Double = 40.0,
                minSecondaryRatio: Double = 0.35) {
        self.axisThresholdMultiplier = axisThresholdMultiplier
        self.minAngleDegrees = minAngleDegrees
        self.maxAngleDegrees = maxAngleDegrees
        self.minSecondaryRatio = minSecondaryRatio
    }
}

public struct JoystickConfig: Codable {
    /// Nested events configuration describing behavior mode
    public enum EventsMode: Codable {
    case dutyCycle(frequency: Double, ratio: Double, maxEventsPerSecond: Int?, diagonalAssist: JoystickDiagonalAssist?)
        case hold(diagonalAnglePercent: Double, holdEnabled: Bool, diagonalAssist: JoystickDiagonalAssist?)

        // Extend coding keys for hold-mode assist; keep existing keys for backward compatibility.
        private enum CodingKeys: String, CodingKey {
            case dutyCycleFrequency, dutyCycleRatio, maxEventsPerSecond, hold, diagonalAnglePercent
            case diagonalAssistAxisMultiplier, diagonalAssistMinAngle, diagonalAssistMaxAngle, diagonalAssistMinSecondaryRatio
            // Hold mode assist uses same key names (additive only) so legacy configs without them still decode.
            case holdDiagonalAssistAxisMultiplier, holdDiagonalAssistMinAngle, holdDiagonalAssistMaxAngle, holdDiagonalAssistMinSecondaryRatio
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            // Distinguish hold vs duty cycle by presence of hold keys
            if container.contains(.hold) || container.contains(.diagonalAnglePercent) {
                let holdFlag = try container.decodeIfPresent(Bool.self, forKey: .hold) ?? true
                let diagonal = try container.decodeIfPresent(Double.self, forKey: .diagonalAnglePercent) ?? 0.15
                // Optional assist for hold mode (uses dedicated hold* keys first, falls back to shared if user manually edited file)
                let axisMul = try container.decodeIfPresent(Double.self, forKey: .holdDiagonalAssistAxisMultiplier) ?? container.decodeIfPresent(Double.self, forKey: .diagonalAssistAxisMultiplier)
                let minAng = try container.decodeIfPresent(Double.self, forKey: .holdDiagonalAssistMinAngle) ?? container.decodeIfPresent(Double.self, forKey: .diagonalAssistMinAngle)
                let maxAng = try container.decodeIfPresent(Double.self, forKey: .holdDiagonalAssistMaxAngle) ?? container.decodeIfPresent(Double.self, forKey: .diagonalAssistMaxAngle)
                let minRatio = try container.decodeIfPresent(Double.self, forKey: .holdDiagonalAssistMinSecondaryRatio) ?? container.decodeIfPresent(Double.self, forKey: .diagonalAssistMinSecondaryRatio)
                var assist: JoystickDiagonalAssist? = nil
                if let axisMul = axisMul, let minAng = minAng, let maxAng = maxAng, let minRatio = minRatio {
                    assist = JoystickDiagonalAssist(axisThresholdMultiplier: axisMul,
                                                    minAngleDegrees: minAng,
                                                    maxAngleDegrees: maxAng,
                                                    minSecondaryRatio: minRatio)
                }
                self = .hold(diagonalAnglePercent: diagonal, holdEnabled: holdFlag, diagonalAssist: assist)
                return
            }
            // Duty cycle path
            let freq = try container.decodeIfPresent(Double.self, forKey: .dutyCycleFrequency) ?? 60.0
            let ratio = try container.decodeIfPresent(Double.self, forKey: .dutyCycleRatio) ?? 0.5
            let maxEvents = try container.decodeIfPresent(Int.self, forKey: .maxEventsPerSecond)
            // Diagonal assist (optional additive keys)
            let axisMul = try container.decodeIfPresent(Double.self, forKey: .diagonalAssistAxisMultiplier)
            let minAng = try container.decodeIfPresent(Double.self, forKey: .diagonalAssistMinAngle)
            let maxAng = try container.decodeIfPresent(Double.self, forKey: .diagonalAssistMaxAngle)
            let minRatio = try container.decodeIfPresent(Double.self, forKey: .diagonalAssistMinSecondaryRatio)
            var assist: JoystickDiagonalAssist? = nil
            if let axisMul = axisMul, let minAng = minAng, let maxAng = maxAng, let minRatio = minRatio {
                assist = JoystickDiagonalAssist(axisThresholdMultiplier: axisMul,
                                                minAngleDegrees: minAng,
                                                maxAngleDegrees: maxAng,
                                                minSecondaryRatio: minRatio)
            }
            self = .dutyCycle(frequency: freq, ratio: ratio, maxEventsPerSecond: maxEvents, diagonalAssist: assist)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .dutyCycle(let frequency, let ratio, let maxEvents, let assist):
                try container.encode(frequency, forKey: .dutyCycleFrequency)
                try container.encode(ratio, forKey: .dutyCycleRatio)
                if let m = maxEvents { try container.encode(m, forKey: .maxEventsPerSecond) }
                if let a = assist {
                    try container.encode(a.axisThresholdMultiplier, forKey: .diagonalAssistAxisMultiplier)
                    try container.encode(a.minAngleDegrees, forKey: .diagonalAssistMinAngle)
                    try container.encode(a.maxAngleDegrees, forKey: .diagonalAssistMaxAngle)
                    try container.encode(a.minSecondaryRatio, forKey: .diagonalAssistMinSecondaryRatio)
                }
            case .hold(let diagonalAnglePercent, let holdEnabled, let assist):
                try container.encode(holdEnabled, forKey: .hold)
                try container.encode(diagonalAnglePercent, forKey: .diagonalAnglePercent)
                if let a = assist { // write using hold-specific assist keys for clarity
                    try container.encode(a.axisThresholdMultiplier, forKey: .holdDiagonalAssistAxisMultiplier)
                    try container.encode(a.minAngleDegrees, forKey: .holdDiagonalAssistMinAngle)
                    try container.encode(a.maxAngleDegrees, forKey: .holdDiagonalAssistMaxAngle)
                    try container.encode(a.minSecondaryRatio, forKey: .holdDiagonalAssistMinSecondaryRatio)
                }
            }
        }
    }

    public var enabled: Bool
    public var deadzone: Double
    public var events: EventsMode
    public var upKey: String
    public var downKey: String
    public var leftKey: String
    public var rightKey: String

    public init(
        enabled: Bool = true,
        deadzone: Double = 0.15,
    events: EventsMode = .dutyCycle(frequency: 60.0, ratio: 0.5, maxEventsPerSecond: nil, diagonalAssist: nil),
        upKey: String = "w",
        downKey: String = "s",
        leftKey: String = "a",
        rightKey: String = "d"
    ) {
        self.enabled = enabled
        self.deadzone = deadzone
        self.events = events
        self.upKey = upKey
        self.downKey = downKey
        self.leftKey = leftKey
        self.rightKey = rightKey
    }

    // Backward compatibility: decode legacy flat fields if present
    private enum CodingKeys: String, CodingKey { case enabled, deadzone, dutyCycleFrequency, dutyCycleRatio, upKey, downKey, leftKey, rightKey, maxEventsPerSecond, events }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        self.deadzone = try container.decodeIfPresent(Double.self, forKey: .deadzone) ?? 0.15
        self.upKey = try container.decodeIfPresent(String.self, forKey: .upKey) ?? "w"
        self.downKey = try container.decodeIfPresent(String.self, forKey: .downKey) ?? "s"
        self.leftKey = try container.decodeIfPresent(String.self, forKey: .leftKey) ?? "a"
        self.rightKey = try container.decodeIfPresent(String.self, forKey: .rightKey) ?? "d"

        // Prefer nested events object if present
        if container.contains(.events) {
            self.events = try container.decode(EventsMode.self, forKey: .events)
        } else {
            // Legacy flat fields
            let freq = try container.decodeIfPresent(Double.self, forKey: .dutyCycleFrequency) ?? 60.0
            let ratio = try container.decodeIfPresent(Double.self, forKey: .dutyCycleRatio) ?? 0.5
            let maxEvents = try container.decodeIfPresent(Int.self, forKey: .maxEventsPerSecond)
            self.events = .dutyCycle(frequency: freq, ratio: ratio, maxEventsPerSecond: maxEvents, diagonalAssist: nil)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(deadzone, forKey: .deadzone)
        try container.encode(upKey, forKey: .upKey)
        try container.encode(downKey, forKey: .downKey)
        try container.encode(leftKey, forKey: .leftKey)
        try container.encode(rightKey, forKey: .rightKey)
        try container.encode(events, forKey: .events)
    }
}

/// Complete G13 configuration
public struct G13Config: Codable {
    public var name: String
    public var macros: [String: Macro]
    public var gKeys: [GKeyConfig]
    public var joystick: JoystickConfig
    public var keyboardOutputMode: KeyboardOutputMode

    public init(
        name: String = "Default",
        macros: [String: Macro] = [:],
        gKeys: [GKeyConfig] = [],
        joystick: JoystickConfig = JoystickConfig(),
        keyboardOutputMode: KeyboardOutputMode = .cgEvent
    ) {
        self.name = name
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
            name: "Default",
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
    private var profiles: [G13Config]
    private var activeProfileIndex: Int = 0

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
    self.profiles = [G13Config.defaultConfig()]

        // Try to load existing config, or save default
        if fileManager.fileExists(atPath: self.configPath.path) {
            // Attempt to load as array first, then fallback to single object
            do {
                try loadProfiles()
            } catch {
                // Fallback: try legacy single-config decoding
                do {
                    let legacy = try loadSingleConfig()
                    self.profiles = [legacy]
                    try saveProfiles() // migrate immediately to array format
                } catch {
                    throw error
                }
            }
        } else {
            try saveProfiles()
        }
    }

    /// Get the current configuration
    public func getConfig() -> G13Config { profiles[activeProfileIndex] }

    /// Get all profiles
    public func getProfiles() -> [G13Config] { profiles }

    /// Switch active profile by index (bounds checked). Returns new active config.
    @discardableResult
    public func activateProfile(index: Int) -> G13Config? {
        guard profiles.indices.contains(index) else { return nil }
        activeProfileIndex = index
        return getConfig()
    }

    /// Update the configuration
    public func updateConfig(_ newConfig: G13Config) throws {
        profiles[activeProfileIndex] = newConfig
        try saveProfiles()
    }

    /// Update just the macros
    public func updateMacros(_ macros: [String: Macro]) throws {
        profiles[activeProfileIndex].macros = macros
        try saveProfiles()
    }

    /// Update just the G key mappings
    public func updateGKeys(_ gKeys: [GKeyConfig]) throws {
        profiles[activeProfileIndex].gKeys = gKeys
        try saveProfiles()
    }

    /// Update just the joystick config
    public func updateJoystick(_ joystick: JoystickConfig) throws {
        profiles[activeProfileIndex].joystick = joystick
        try saveProfiles()
    }

    /// Load configuration from file
    private func loadSingleConfig() throws -> G13Config {
        let data = try Data(contentsOf: configPath)
        let decoder = JSONDecoder()
        return try decoder.decode(G13Config.self, from: data)
    }

    private func loadProfiles() throws {
        do {
            let data = try Data(contentsOf: configPath)
            let decoder = JSONDecoder()
            self.profiles = try decoder.decode([G13Config].self, from: data)
        } catch {
            throw ConfigError.loadFailed(error.localizedDescription)
        }
    }

    /// Save configuration to file
    private func saveProfiles() throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(profiles)
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
            let data = try encoder.encode(profiles)
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
            if let array = try? decoder.decode([G13Config].self, from: data) {
                self.profiles = array
            } else {
                let single = try decoder.decode(G13Config.self, from: data)
                self.profiles = [single]
            }
            try saveProfiles()
        } catch {
            throw ConfigError.loadFailed(error.localizedDescription)
        }
    }
}
