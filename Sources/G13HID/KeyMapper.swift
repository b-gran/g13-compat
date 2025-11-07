import Foundation

/// Maps G13 HID input to keyboard output
public class KeyMapper {
    private let keyboard: KeyboardOutput
    private let macroEngine: MacroEngine
    private var config: G13Config
    private var pressedGKeys: Set<Int> = []

    // G13 HID constants
    private let buttonUsagePage: UInt32 = 0x09  // Button usage page
    private let gKeyBaseUsage: UInt32 = 0x01    // G1 starts at usage 0x01

    public init(keyboard: KeyboardOutput, macroEngine: MacroEngine, config: G13Config) {
        self.keyboard = keyboard
        self.macroEngine = macroEngine
        self.config = config
    }

    /// Update the configuration
    public func updateConfig(_ newConfig: G13Config) {
        self.config = newConfig
    }

    /// Process HID input and map to keyboard output
    public func processInput(_ data: HIDInputData) {
        // Handle button presses (G keys)
        if data.usagePage == buttonUsagePage {
            log("⚡️ KeyMapper detected button input: usagePage=0x\(String(format: "%02X", data.usagePage)), usage=0x\(String(format: "%02X", data.usage)), value=\(data.intValue)")
            handleGKey(usage: data.usage, pressed: data.intValue != 0)
        }

        // Note: Joystick input is handled separately by JoystickController
    }

    private func handleGKey(usage: UInt32, pressed: Bool) {
        // Calculate G key number (G1 = usage 1, G2 = usage 2, etc.)
        let gKeyNumber = Int(usage)

        log("🎮 KeyMapper.handleGKey: G\(gKeyNumber) \(pressed ? "pressed" : "released")")

        if pressed && !pressedGKeys.contains(gKeyNumber) {
            // Key press
            pressedGKeys.insert(gKeyNumber)
            log("➡️  Executing action for G\(gKeyNumber)")
            executeGKeyAction(gKeyNumber)
        } else if !pressed && pressedGKeys.contains(gKeyNumber) {
            // Key release
            pressedGKeys.remove(gKeyNumber)
        }
    }

    private func executeGKeyAction(_ gKeyNumber: Int) {
        // Find the configuration for this G key
        guard let keyConfig = config.gKeys.first(where: { $0.keyNumber == gKeyNumber }) else {
            log("No configuration found for G\(gKeyNumber)")
            return
        }

        switch keyConfig.action {
        case .macro(let macroName):
            executeMacro(macroName)

        case .keyTap(let keyString):
            executeKeyTap(keyString)

        case .disabled:
            // Do nothing
            break
        }
    }

    private func executeMacro(_ macroName: String) {
        macroEngine.executeMacro(key: macroName) { result in
            switch result {
            case .success():
                log("Executed macro: \(macroName)")
            case .failure(let error):
                log("Failed to execute macro \(macroName): \(error)")
            }
        }
    }

    private func executeKeyTap(_ keyString: String) {
        log("⌨️  KeyMapper.executeKeyTap: \(keyString)")

        guard let keyCode = VirtualKeyboard.keyCodeFromString(keyString) else {
            log("❌ Invalid key: \(keyString)")
            return
        }

        do {
            try keyboard.tapKey(keyCode)
            log("✅ Tapped key: \(keyString)")
        } catch {
            log("❌ Failed to tap key \(keyString): \(error)")
        }
    }

    /// Get currently pressed G keys
    public func getPressedGKeys() -> Set<Int> {
        return pressedGKeys
    }

    /// Release all currently pressed G keys
    public func releaseAllGKeys() {
        pressedGKeys.removeAll()
    }
}
