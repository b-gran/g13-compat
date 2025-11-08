import Foundation
import IOKit.hid

// IOHIDUserDevice type alias
private typealias VirtualHIDDevice = IOHIDUserDevice

// Declare IOHIDUserDevice C functions that aren't exposed to Swift
@_silgen_name("IOHIDUserDeviceCreate")
private func IOHIDUserDeviceCreate(
    _ allocator: CFAllocator?,
    _ properties: CFDictionary
) -> IOHIDUserDevice?

@_silgen_name("IOHIDUserDeviceHandleReport")
private func IOHIDUserDeviceHandleReport(
    _ device: IOHIDUserDevice,
    _ report: UnsafePointer<UInt8>,
    _ reportLength: CFIndex
) -> IOReturn

// Create a virtual HID device
// NOTE: Requires com.apple.developer.hid.virtual.device entitlement on modern macOS
// Without this entitlement, IOHIDUserDeviceCreate will fail
private func createVirtualDevice(properties: CFDictionary) -> VirtualHIDDevice? {
    guard let device = IOHIDUserDeviceCreate(kCFAllocatorDefault, properties) else {
        log("Error: IOHIDUserDeviceCreate failed")
        log("Ensure you have the com.apple.developer.hid.virtual.device entitlement")
        log("Add this to your entitlements file:")
        log("  <key>com.apple.developer.hid.virtual.device</key>")
        log("  <true/>")
        return nil
    }
    return device
}

// Send a HID report to the virtual device
private func sendReport(_ device: VirtualHIDDevice?, _ data: Data) -> IOReturn {
    guard let device = device else {
        return kIOReturnNotOpen
    }

    return data.withUnsafeBytes { bytes in
        guard let baseAddress = bytes.bindMemory(to: UInt8.self).baseAddress else {
            return kIOReturnError
        }
        return IOHIDUserDeviceHandleReport(device, baseAddress, data.count)
    }
}

/// Represents a virtual HID keyboard device using IOHIDUserDevice
public class VirtualKeyboard: KeyboardOutput {
    private var device: VirtualHIDDevice?
    private var pressedKeys: Set<UInt8> = []

    public enum KeyboardError: Error, LocalizedError, Equatable {
        case failedToCreateDevice
        case deviceNotActive
        case reportSendFailed(code: IOReturn)
        case entitlementMissing
        case unknownFailure(String)

        public var errorDescription: String? {
            switch self {
            case .failedToCreateDevice:
                return "Failed to create virtual HID device (IOHIDUserDeviceCreate returned nil)"
            case .deviceNotActive:
                return "Virtual device not active"
            case .reportSendFailed(let code):
                return "Failed to send HID report (IOReturn=0x\(String(code, radix: 16)))"
            case .entitlementMissing:
                return "Missing com.apple.developer.hid.virtual.device entitlement"
            case .unknownFailure(let msg):
                return "Unknown virtual keyboard failure: \(msg)"
            }
        }
    }

    // HID Keyboard Usage IDs (USB HID Usage Tables)
    public enum KeyCode: UInt8 {
        case a = 0x04
        case b = 0x05
        case c = 0x06
        case d = 0x07
        case e = 0x08
        case f = 0x09
        case g = 0x0A
        case h = 0x0B
        case i = 0x0C
        case j = 0x0D
        case k = 0x0E
        case l = 0x0F
        case m = 0x10
        case n = 0x11
        case o = 0x12
        case p = 0x13
        case q = 0x14
        case r = 0x15
        case s = 0x16
        case t = 0x17
        case u = 0x18
        case v = 0x19
        case w = 0x1A
        case x = 0x1B
        case y = 0x1C
        case z = 0x1D

        case num1 = 0x1E
        case num2 = 0x1F
        case num3 = 0x20
        case num4 = 0x21
        case num5 = 0x22
        case num6 = 0x23
        case num7 = 0x24
        case num8 = 0x25
        case num9 = 0x26
        case num0 = 0x27

        case enter = 0x28
        case escape = 0x29
        case backspace = 0x2A
        case tab = 0x2B
        case space = 0x2C
        case minus = 0x2D
        case equals = 0x2E
        case leftBracket = 0x2F
        case rightBracket = 0x30
        case backslash = 0x31
        case semicolon = 0x33
        case quote = 0x34
        case grave = 0x35
        case comma = 0x36
        case period = 0x37
        case slash = 0x38
        case capsLock = 0x39

        case f1 = 0x3A
        case f2 = 0x3B
        case f3 = 0x3C
        case f4 = 0x3D
        case f5 = 0x3E
        case f6 = 0x3F
        case f7 = 0x40
        case f8 = 0x41
        case f9 = 0x42
        case f10 = 0x43
        case f11 = 0x44
        case f12 = 0x45

        case printScreen = 0x46
        case scrollLock = 0x47
        case pause = 0x48
        case insert = 0x49
        case home = 0x4A
        case pageUp = 0x4B
        case delete = 0x4C
        case end = 0x4D
        case pageDown = 0x4E
        case rightArrow = 0x4F
        case leftArrow = 0x50
        case downArrow = 0x51
        case upArrow = 0x52
    }

    // Modifier flags
    public enum ModifierKey: UInt8 {
        case leftControl = 0x01
        case leftShift = 0x02
        case leftAlt = 0x04
        case leftCommand = 0x08
        case rightControl = 0x10
        case rightShift = 0x20
        case rightAlt = 0x40
        case rightCommand = 0x80
    }

    public init() throws {
        try createDevice()
    }

    private func createDevice() throws {
        // HID descriptor for a standard keyboard
        // This is a boot keyboard descriptor (6-key rollover)
        let descriptor: [UInt8] = [
            0x05, 0x01,        // Usage Page (Generic Desktop)
            0x09, 0x06,        // Usage (Keyboard)
            0xA1, 0x01,        // Collection (Application)

            // Modifier byte
            0x05, 0x07,        //   Usage Page (Keyboard/Keypad)
            0x19, 0xE0,        //   Usage Minimum (Keyboard Left Control)
            0x29, 0xE7,        //   Usage Maximum (Keyboard Right GUI)
            0x15, 0x00,        //   Logical Minimum (0)
            0x25, 0x01,        //   Logical Maximum (1)
            0x75, 0x01,        //   Report Size (1)
            0x95, 0x08,        //   Report Count (8)
            0x81, 0x02,        //   Input (Data, Variable, Absolute) - Modifier byte

            // Reserved byte
            0x95, 0x01,        //   Report Count (1)
            0x75, 0x08,        //   Report Size (8)
            0x81, 0x01,        //   Input (Constant) - Reserved byte

            // LED output report
            0x95, 0x05,        //   Report Count (5)
            0x75, 0x01,        //   Report Size (1)
            0x05, 0x08,        //   Usage Page (LEDs)
            0x19, 0x01,        //   Usage Minimum (Num Lock)
            0x29, 0x05,        //   Usage Maximum (Kana)
            0x91, 0x02,        //   Output (Data, Variable, Absolute) - LED report

            // LED padding
            0x95, 0x01,        //   Report Count (1)
            0x75, 0x03,        //   Report Size (3)
            0x91, 0x01,        //   Output (Constant) - LED padding

            // Key arrays (6 keys)
            0x95, 0x06,        //   Report Count (6)
            0x75, 0x08,        //   Report Size (8)
            0x15, 0x00,        //   Logical Minimum (0)
            0x25, 0x65,        //   Logical Maximum (101)
            0x05, 0x07,        //   Usage Page (Keyboard/Keypad)
            0x19, 0x00,        //   Usage Minimum (0)
            0x29, 0x65,        //   Usage Maximum (101)
            0x81, 0x00,        //   Input (Data, Array) - Key array

            0xC0               // End Collection
        ]

        // Device properties - DO NOT use Apple's VID/PID in production
        // Use your own or get proper IDs from USB-IF
        let properties: [CFString: Any] = [
            kIOHIDReportDescriptorKey: Data(descriptor) as CFData,
            kIOHIDVendorIDKey: 0x1234,                    // Placeholder - change this
            kIOHIDProductIDKey: 0x5678,                   // Placeholder - change this
            kIOHIDProductKey: "G13 Virtual Keyboard",
            kIOHIDManufacturerKey: "G13Compat",
            kIOHIDTransportKey: "Virtual",
            kIOHIDVersionNumberKey: 0x0100,
            kIOHIDPrimaryUsagePageKey: 0x01,              // Generic Desktop
            kIOHIDPrimaryUsageKey: 0x06,                  // Keyboard
            kIOHIDMaxInputReportSizeKey: 8,               // 8-byte input reports
            kIOHIDMaxOutputReportSizeKey: 1,              // 1-byte LED output
            kIOHIDMaxFeatureReportSizeKey: 0              // No feature reports
        ] as [CFString: Any]

        guard let userDevice = createVirtualDevice(properties: properties as CFDictionary) else {
            // Distinguish entitlement absence via heuristic: if running without entitlement typical failure occurs
            // (We logged guidance in createVirtualDevice). Surface specific error for caller.
            throw KeyboardError.failedToCreateDevice
        }

        self.device = userDevice
    }

    /// Presses a key (or multiple keys simultaneously)
    public func pressKey(_ keyCode: KeyCode, modifiers: [ModifierKey]) throws {
        guard device != nil else {
            throw KeyboardError.deviceNotActive
        }

        pressedKeys.insert(keyCode.rawValue)
        try sendKeyReport(modifiers: modifiers)
    }

    /// Releases a key
    public func releaseKey(_ keyCode: KeyCode, modifiers: [ModifierKey]) throws {
        guard device != nil else {
            throw KeyboardError.deviceNotActive
        }

        pressedKeys.remove(keyCode.rawValue)
        try sendKeyReport(modifiers: modifiers)
    }

    /// Taps a key (press and release) asynchronously; invokes completion after release attempt.
    public func tapKey(_ keyCode: KeyCode, modifiers: [ModifierKey], completion: (() -> Void)?) throws {
        try pressKey(keyCode, modifiers: modifiers)
        let delayMs = VirtualKeyboard.tapDelayMilliseconds
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .milliseconds(delayMs)) { [weak self] in
            guard let self = self else { completion?(); return }
            do {
                try self.releaseKey(keyCode, modifiers: modifiers)
            } catch {
                log("VirtualKeyboard async tap release failed for key=\(keyCode) error=\(error)")
            }
            completion?()
        }
    }

    // Environment configurable tap delay (default 10ms, bounds 5-250ms)
    private static let tapDelayMilliseconds: Int = {
        let env = ProcessInfo.processInfo.environment["G13_TAP_DELAY_MS"]
        if let raw = env, let val = Int(raw), val >= 5, val <= 250 { return val }
        return 10
    }()

    /// Releases all currently pressed keys
    public func releaseAllKeys() throws {
        guard device != nil else {
            throw KeyboardError.deviceNotActive
        }

        pressedKeys.removeAll()
        try sendKeyReport(modifiers: [])
    }

    /// Sends a keyboard report to the virtual device
    private func sendKeyReport(modifiers: [ModifierKey]) throws {
        guard let device = device else {
            throw KeyboardError.deviceNotActive
        }

        // Build the 8-byte keyboard report
        var report = [UInt8](repeating: 0, count: 8)

        // Byte 0: Modifier keys
        for modifier in modifiers {
            report[0] |= modifier.rawValue
        }

        // Byte 1: Reserved (always 0)
        // Bytes 2-7: Pressed keys (up to 6)
        // Sort keys to maintain stable ordering and prevent flickering
        let keysArray = Array(pressedKeys).sorted().prefix(6)
        for (index, key) in keysArray.enumerated() {
            report[2 + index] = key
        }

        let data = Data(report)
        let result = sendReport(device, data)

        if result != kIOReturnSuccess {
            throw KeyboardError.reportSendFailed(code: result)
        }
    }

    /// Convert string key name to KeyCode
    public static func keyCodeFromString(_ string: String) -> KeyCode? {
        let lowercased = string.lowercased()
        switch lowercased {
        case "a": return .a
        case "b": return .b
        case "c": return .c
        case "d": return .d
        case "e": return .e
        case "f": return .f
        case "g": return .g
        case "h": return .h
        case "i": return .i
        case "j": return .j
        case "k": return .k
        case "l": return .l
        case "m": return .m
        case "n": return .n
        case "o": return .o
        case "p": return .p
        case "q": return .q
        case "r": return .r
        case "s": return .s
        case "t": return .t
        case "u": return .u
        case "v": return .v
        case "w": return .w
        case "x": return .x
        case "y": return .y
        case "z": return .z
        case "1": return .num1
        case "2": return .num2
        case "3": return .num3
        case "4": return .num4
        case "5": return .num5
        case "6": return .num6
        case "7": return .num7
        case "8": return .num8
        case "9": return .num9
        case "0": return .num0
        case "space": return .space
        case "enter", "return": return .enter
        case "escape", "esc": return .escape
        case "backspace": return .backspace
        case "tab": return .tab
        case "up": return .upArrow
        case "down": return .downArrow
        case "left": return .leftArrow
        case "right": return .rightArrow
        case "f1": return .f1
        case "f2": return .f2
        case "f3": return .f3
        case "f4": return .f4
        case "f5": return .f5
        case "f6": return .f6
        case "f7": return .f7
        case "f8": return .f8
        case "f9": return .f9
        case "f10": return .f10
        case "f11": return .f11
        case "f12": return .f12
        default: return nil
        }
    }

    deinit {
        // Release all keys before destroying the device
        try? releaseAllKeys()
    }
}
