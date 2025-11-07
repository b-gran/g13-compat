import Foundation

/// Maps G13 HID input to keyboard output
public class KeyMapper {
    private let keyboard: VirtualKeyboard
    private let macroEngine: MacroEngine
    private var config: G13Config
    private var pressedGKeys: Set<Int> = []

    // G13 HID constants
    private let buttonUsagePage: UInt32 = 0x09  // Button usage page
    private let gKeyBaseUsage: UInt32 = 0x01    // G1 starts at usage 0x01

    public init(keyboard: VirtualKeyboard, macroEngine: MacroEngine, config: G13Config) {
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
            handleGKey(usage: data.usage, pressed: data.intValue != 0)
        }

        // Note: Joystick input is handled separately by JoystickController
    }

    private func handleGKey(usage: UInt32, pressed: Bool) {
        // Calculate G key number (G1 = usage 1, G2 = usage 2, etc.)
        let gKeyNumber = Int(usage)

        if pressed && !pressedGKeys.contains(gKeyNumber) {
            // Key press
            pressedGKeys.insert(gKeyNumber)
            executeGKeyAction(gKeyNumber)
        } else if !pressed && pressedGKeys.contains(gKeyNumber) {
            // Key release
            pressedGKeys.remove(gKeyNumber)
        }
    }

    private func executeGKeyAction(_ gKeyNumber: Int) {
        // Find the configuration for this G key
        guard let keyConfig = config.gKeys.first(where: { $0.keyNumber == gKeyNumber }) else {
            print("No configuration found for G\(gKeyNumber)")
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
                print("Executed macro: \(macroName)")
            case .failure(let error):
                print("Failed to execute macro \(macroName): \(error)")
            }
        }
    }

    private func executeKeyTap(_ keyString: String) {
        guard let keyCode = VirtualKeyboard.keyCodeFromString(keyString) else {
            print("Invalid key: \(keyString)")
            return
        }

        do {
            try keyboard.tapKey(keyCode)
            print("Tapped key: \(keyString)")
        } catch {
            print("Failed to tap key \(keyString): \(error)")
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
