import Foundation
import IOKit.hid
import SwiftUI

public struct HIDInputData {
    public let timestamp: UInt64
    public let length: Int
    public let usagePage: UInt32
    public let usage: UInt32
    public let intValue: Int64
    public let rawData: [UInt8]
    
    public init(timestamp: UInt64, length: CFIndex, usagePage: UInt32, usage: UInt32, intValue: Int64, rawData: [UInt8]) {
        self.timestamp = timestamp
        self.length = length
        self.usagePage = usagePage
        self.usage = usage
        self.intValue = intValue
        self.rawData = rawData
    }
}

public protocol HIDDeviceDelegate: AnyObject {
    func hidDevice(_ device: HIDDevice, didReceiveInput data: HIDInputData)
    func hidDeviceDidConnect(_ device: HIDDevice)
    func hidDeviceDidDisconnect(_ device: HIDDevice)
}

public enum HIDDeviceError: Error {
    case failedToOpenManager
    case permissionDenied
    case deviceNotFound
}

public class HIDDevice {
    private var device: IOHIDDevice?
    private var deviceManager: IOHIDManager
    private var isManagerOpen: Bool = false
    public weak var delegate: HIDDeviceDelegate?
    public var joystickSettings: JoystickSettings?

    // Virtual keyboard components
    private var keyboardOutput: KeyboardOutput?
    private var macroEngine: MacroEngine?
    private var keyMapper: KeyMapper?
    private var joystickController: JoystickController?
    private var configManager: ConfigManager?

    // Constants for the G13
    private let vendorID: Int = 0x046D
    private let productID: Int = 0xC21C

    // Joystick constants
    private let joystickUsagePage: UInt32 = 0x01  // Generic Desktop Controls
    private let joystickXUsage: UInt32 = 0x30     // X axis
    private let joystickYUsage: UInt32 = 0x31     // Y axis

    // Track joystick state
    private var joystickX: Int64 = 128
    private var joystickY: Int64 = 128

    public init(configPath: URL? = nil) throws {
        deviceManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        // Initialize virtual keyboard and related components
        do {
            let config = try ConfigManager(configPath: configPath)
            self.configManager = config

            // Create keyboard output based on config
            let outputMode = config.getConfig().keyboardOutputMode
            log("Keyboard output mode: \(outputMode.description)")

            let keyboard: KeyboardOutput
            if let kb = KeyboardOutputFactory.create(mode: outputMode) {
                keyboard = kb
                self.keyboardOutput = kb
            } else {
                log("Failed to create keyboard with mode \(outputMode), falling back to CGEvent")
                keyboard = CGEventKeyboard()
                self.keyboardOutput = keyboard
            }

            let macro = MacroEngine(keyboard: keyboard)
            self.macroEngine = macro

            // Register macros from config
            for (key, macroObj) in config.getConfig().macros {
                macro.registerMacro(key: key, macro: macroObj)
            }

            let mapper = KeyMapper(keyboard: keyboard, macroEngine: macro, config: config.getConfig())
            self.keyMapper = mapper

            let joystick = JoystickController(keyboard: keyboard)
            joystick.deadzone = config.getConfig().joystick.deadzone
            joystick.dutyCycleFrequency = config.getConfig().joystick.dutyCycleFrequency
            joystick.dutyCycleRatio = config.getConfig().joystick.dutyCycleRatio
            self.joystickController = joystick

            log("Keyboard output initialized successfully")
            log("Config loaded from: \(config.getConfigPath().path)")
        } catch {
            log("Warning: Failed to initialize keyboard output: \(error)")
            log("Device will run in monitor-only mode")
        }

        try setupDeviceManager()
    }
    
    private func setupDeviceManager() throws {
        // Create matching dictionary for the G13
        let matching = IOHIDDeviceCreateMatchingDictionary(vendorID, productID)
        IOHIDManagerSetDeviceMatching(deviceManager, matching)
        
        let deviceCallback: IOHIDDeviceCallback = { context, result, sender, device in
            let this = Unmanaged<HIDDevice>.fromOpaque(context!).takeUnretainedValue()
            this.handleDeviceConnection(device: device)
        }
        
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(deviceManager, deviceCallback, context)
        
        // Register for device removal
        let deviceRemovalCallback: IOHIDDeviceCallback = { context, result, sender, device in
            let this = Unmanaged<HIDDevice>.fromOpaque(context!).takeUnretainedValue()
            this.handleDeviceRemoval(device: device)
        }
        IOHIDManagerRegisterDeviceRemovalCallback(deviceManager, deviceRemovalCallback, context)
        
        IOHIDManagerScheduleWithRunLoop(deviceManager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        
        let result = IOHIDManagerOpen(deviceManager, IOOptionBits(kIOHIDOptionsTypeNone))
        switch result {
        case kIOReturnSuccess:
            isManagerOpen = true
            // Try to find the device immediately
            if let devices = IOHIDManagerCopyDevices(deviceManager) as? Set<IOHIDDevice> {
                for device in devices {
                    if isTargetDevice(device) {
                        self.device = device
                        handleDeviceConnection(device: device)
                        break
                    }
                }
            }
        case kIOReturnNotPermitted:
            throw HIDDeviceError.permissionDenied
        default:
            throw HIDDeviceError.failedToOpenManager
        }
    }
    
    private func isTargetDevice(_ device: IOHIDDevice) -> Bool {
        let deviceVendorID = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
        let deviceProductID = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
        return deviceVendorID == vendorID && deviceProductID == productID
    }
    
    private func handleDeviceConnection(device: IOHIDDevice) {
        if !isTargetDevice(device) {
            return
        }
        
        self.device = device
        let context = Unmanaged.passUnretained(self).toOpaque()
        
        let manufacturer = IOHIDDeviceGetProperty(device, kIOHIDManufacturerKey as CFString) as? String ?? "Unknown"
        let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Unknown"

        log("G13 device connected:")
        log("Manufacturer: \(manufacturer)")
        log("Product: \(product)")
        log("Vendor ID: \(String(format: "0x%04X", vendorID))")
        log("Product ID: \(String(format: "0x%04X", productID))")
        log("Enumerating elements (usagePage:usage -> type,length,reportID)...")

        if let elements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] {
            for element in elements {
                let usagePage = IOHIDElementGetUsagePage(element)
                let usage = IOHIDElementGetUsage(element)
                let type = IOHIDElementGetType(element)
                let reportSize = IOHIDElementGetReportSize(element)
                let reportCount = IOHIDElementGetReportCount(element)
                let reportID = IOHIDElementGetReportID(element)
                // Filter out collections to reduce noise
                if type != kIOHIDElementTypeCollection {
                    log(String(format: "  • usagePage=0x%02X usage=0x%02X type=%d reportSize=%d bits reportCount=%d id=0x%02X",
                                usagePage, usage, type.rawValue, reportSize, reportCount, reportID))
                }
            }
        } else {
            log("(No elements enumerated)")
        }
        
        // Register for input reports
        let inputCallback: IOHIDValueCallback = { context, result, sender, value in
            let this = Unmanaged<HIDDevice>.fromOpaque(context!).takeUnretainedValue()
            this.handleInput(value)
        }
        
        IOHIDDeviceRegisterInputValueCallback(
            device,
            inputCallback,
            context
        )
        
        delegate?.hidDeviceDidConnect(self)
    }
    
    private func handleDeviceRemoval(device: IOHIDDevice) {
        if device == self.device {
            log("G13 device disconnected")
            self.device = nil
            delegate?.hidDeviceDidDisconnect(self)
        }
    }
    
    private func handleInput(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let timestamp = IOHIDValueGetTimeStamp(value)
        let length = IOHIDValueGetLength(value)
        let data = IOHIDValueGetBytePtr(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = Int64(IOHIDValueGetIntegerValue(value))

        let rawData = Array(UnsafeBufferPointer(start: data, count: Int(length)))

        // Enhanced debug logging
        log("📥 HID: len=\(rawData.count) usagePage=0x\(String(format: "%02X", usagePage)) usage=0x\(String(format: "%02X", usage)) int=\(intValue) bytes=\(rawData.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " "))")

        // If we are not getting per-button elements (expected usagePage 0x09), attempt raw report parsing
        if usagePage != 0x09 && length == 7 {
            parseRawG13Report(rawData)
        }

        let inputData = HIDInputData(
            timestamp: timestamp,
            length: length,
            usagePage: usagePage,
            usage: usage,
            intValue: intValue,
            rawData: rawData
        )

        // Handle joystick input with virtual keyboard
        if usagePage == joystickUsagePage {
            if usage == joystickXUsage {
                joystickX = intValue
                updateJoystickController()
            } else if usage == joystickYUsage {
                joystickY = intValue
                updateJoystickController()
            }
        }

        // Handle button/key input with key mapper
        keyMapper?.processInput(inputData)

        delegate?.hidDevice(self, didReceiveInput: inputData)
    }

    private func updateJoystickController() {
        guard let controller = joystickController else { return }
        guard let config = configManager?.getConfig() else { return }

        if config.joystick.enabled {
            controller.updateJoystickRaw(x: joystickX, y: joystickY)
        }
    }

    // MARK: - Raw Report Parsing (Fallback / Heuristic)

    private var lastRawReport: [UInt8]? = nil
    // Dynamic (auto-learn) mapping: (byteIndex<<8 | bitIndex) -> G key number (1-22)
    private var bitToGKey: [Int: Int] = [:]
    private var nextAssignableGKey: Int = 1
    private let maxGKeys = 22

    /// Heuristic parser for the 7-byte G13 input report when the system does not expose individual button elements.
    /// This is an exploratory implementation: it logs bit transitions so we can map them to G key numbers empirically.
    /// Strategy:
    ///  - Compare with previous report (if any)
    ///  - XOR to find changed bits across the first N bytes (we start with first 3 bytes assuming they contain G key bitmap)
    ///  - For each changed bit, log press/release with a provisional key index
    /// After collecting logs by pressing each G key individually, we can build a definitive bit->G# map.
    private func parseRawG13Report(_ report: [UInt8]) {
        let interestingBytes = min(report.count, 3) // assume first 3 bytes carry up to 24 button bits
        if let previous = lastRawReport, previous.count >= interestingBytes {
            for byteIndex in 0..<interestingBytes {
                let before = previous[byteIndex]
                let after = report[byteIndex]
                let delta = before ^ after
                if delta != 0 {
                    for bit in 0..<8 { // low bit = bit0
                        let mask: UInt8 = 1 << bit
                        if (delta & mask) != 0 {
                            let pressed = (after & mask) != 0
                            let provisionalKeyNumber = byteIndex * 8 + bit + 1 // 1-based
                            log("🧩 Heuristic bit change: byte=\(byteIndex) bit=\(bit) -> G? (provisional #\(provisionalKeyNumber)) \(pressed ? "DOWN" : "UP") rawByteBefore=\(String(format: "%02X", before)) rawByteAfter=\(String(format: "%02X", after)))")
                            handleDynamicBit(byteIndex: byteIndex, bitIndex: bit, pressed: pressed, originalReport: report)
                        }
                    }
                }
            }
        }
        lastRawReport = report
    }

    // Auto-learn mapping: assign first unseen bit to next G key (prompt user to press G1..G22 in order)
    private func handleDynamicBit(byteIndex: Int, bitIndex: Int, pressed: Bool, originalReport: [UInt8]) {
        let key = (byteIndex << 8) | bitIndex
        var gKeyNumber: Int
        if let existing = bitToGKey[key] {
            gKeyNumber = existing
        } else {
            guard nextAssignableGKey <= maxGKeys else { return }
            gKeyNumber = nextAssignableGKey
            bitToGKey[key] = gKeyNumber
            nextAssignableGKey += 1
            log("🆕 Learned mapping: byte=\(byteIndex) bit=\(bitIndex) -> G\(gKeyNumber)")
            if nextAssignableGKey <= maxGKeys {
                log("➡️  Press G\(nextAssignableGKey) to learn next mapping (or keep using out-of-order; assignment will proceed sequentially)")
            } else {
                log("✅ Learned all G key mappings (22).")
            }
        }

        // Synthesize HIDInputData to reuse KeyMapper logic
        let timestamp = mach_absolute_time()
        let usagePage: UInt32 = 0x09 // button page
        let usage: UInt32 = UInt32(gKeyNumber) // G key number
        let intValue: Int64 = pressed ? 1 : 0

        let inputData = HIDInputData(
            timestamp: timestamp,
            length: originalReport.count,
            usagePage: usagePage,
            usage: usage,
            intValue: intValue,
            rawData: originalReport
        )
        keyMapper?.processInput(inputData)
    }
    
    private func IOHIDDeviceCreateMatchingDictionary(_ vendorID: Int, _ productID: Int) -> CFDictionary {
        var dict: [String: Any] = [:]
        dict[kIOHIDVendorIDKey as String] = NSNumber(value: vendorID)
        dict[kIOHIDProductIDKey as String] = NSNumber(value: productID)
        return dict as CFDictionary
    }
    
    // Public accessors for configuration
    public func getConfigManager() -> ConfigManager? {
        return configManager
    }

    public func getKeyboardOutput() -> KeyboardOutput? {
        return keyboardOutput
    }

    public func getMacroEngine() -> MacroEngine? {
        return macroEngine
    }

    public func getJoystickController() -> JoystickController? {
        return joystickController
    }

    /// Reload configuration from file
    public func reloadConfig() throws {
        guard let config = configManager else { return }

        let newConfig = config.getConfig()

        // Update macro engine
        if let macro = macroEngine {
            // Clear old macros and register new ones
            for (key, macroObj) in newConfig.macros {
                macro.registerMacro(key: key, macro: macroObj)
            }
        }

        // Update key mapper
        keyMapper?.updateConfig(newConfig)

        // Update joystick controller settings
        if let joystick = joystickController {
            joystick.deadzone = newConfig.joystick.deadzone
            joystick.dutyCycleFrequency = newConfig.joystick.dutyCycleFrequency
            joystick.dutyCycleRatio = newConfig.joystick.dutyCycleRatio
        }
    }

    deinit {
        // Stop joystick controller
        joystickController?.stop()

        // Release all keys
        try? keyboardOutput?.releaseAllKeys()

        if let device = device {
            IOHIDDeviceRegisterInputValueCallback(device, nil, nil)
        }
        if isManagerOpen {
            IOHIDManagerClose(deviceManager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }
} 