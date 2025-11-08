import Foundation

/// Maps G13 HID input to keyboard output
public class KeyMapper {
    private let keyboard: KeyboardOutput
    private let macroEngine: MacroEngine
    private let executor: KeyboardActionExecutor
    private var config: G13Config
    private var pressedGKeys: Set<Int> = []
    private var pressedModifiers: Set<ModifierKind> = []

    // G13 HID constants
    private let buttonUsagePage: UInt32 = 0x09  // Button usage page
    private let gKeyBaseUsage: UInt32 = 0x01    // G1 starts at usage 0x01

    /// Designated initializer injecting an executor.
    public init(keyboard: KeyboardOutput, macroEngine: MacroEngine, executor: KeyboardActionExecutor, config: G13Config) {
        self.keyboard = keyboard
        self.macroEngine = macroEngine
        self.executor = executor
        self.config = config
    }

    /// Convenience initializer maintaining backwards compatibility.
    public convenience init(keyboard: KeyboardOutput, macroEngine: MacroEngine, config: G13Config) {
        let exec = KeyboardActionExecutor(keyboard: keyboard, macroEngine: macroEngine)
        self.init(keyboard: keyboard, macroEngine: macroEngine, executor: exec, config: config)
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
            // If this G key mapped to a modifier, release the modifier
            if let keyConfig = config.gKeys.first(where: { $0.keyNumber == gKeyNumber }) {
                if case .modifier(let kind) = keyConfig.action, pressedModifiers.contains(kind) {
                    pressedModifiers.remove(kind)
                    executor.modifierUp(kind)
                    log("🔓 Modifier UP (\(kind.displayName)) via G\(gKeyNumber)")
                }
            }
        }
    }

    private func executeGKeyAction(_ gKeyNumber: Int) {
        // Find the configuration for this G key
        guard let keyConfig = config.gKeys.first(where: { $0.keyNumber == gKeyNumber }) else {
            log("No configuration found for G\(gKeyNumber)")
            return
        }

        let action: KeyboardAction?
        switch keyConfig.action {
        case .macro(let macroName): action = .macro(macroName)
        case .keyTap(let keyString): action = .keyTap(keyString)
        case .disabled: action = nil
        case .modifier(let kind):
            if !pressedModifiers.contains(kind) {
                pressedModifiers.insert(kind)
                executor.modifierDown(kind)
                log("🔒 Modifier DOWN (\(kind.displayName)) via G\(gKeyNumber)")
            }
            return
        }
        guard let actionToRun = action else { return }
        log("➡️  Emitting action for G\(gKeyNumber): \(actionToRun)")
        _ = executor.perform(actionToRun) { result in
            switch result {
            case .success: log("✅ Action executed for G\(gKeyNumber)")
            case .failure(let error): log("❌ Action failed for G\(gKeyNumber): \(error)")
            }
        }
    }

    /// Get currently pressed G keys
    public func getPressedGKeys() -> Set<Int> {
        return pressedGKeys
    }

    /// Release all currently pressed G keys
    public func releaseAllGKeys() {
        pressedGKeys.removeAll()
        for kind in pressedModifiers { executor.modifierUp(kind) }
        pressedModifiers.removeAll()
    }

    /// Expose currently active modifier VirtualKeyboard.ModifierKeys through executor (for macro engine usage).
    public func currentActiveModifierKeys() -> [VirtualKeyboard.ModifierKey] {
        return executor.currentModifiers()
    }
}
