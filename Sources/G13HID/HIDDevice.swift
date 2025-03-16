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
    
    // Constants for the G13
    private let vendorID: Int = 0x046D
    private let productID: Int = 0xC21C
    
    // Joystick constants
    private let joystickUsagePage: UInt32 = 0x01  // Generic Desktop Controls
    private let joystickUsage: UInt32 = 0x04      // Joystick
    private let joystickThreshold: Int64 = 50     // Threshold for detecting joystick movement
    
    private var lastJoystickX: Int64 = 0
    private var lastJoystickY: Int64 = 0
    
    public init() throws {
        deviceManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
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
        
        print("G13 device connected:")
        print("Manufacturer: \(manufacturer)")
        print("Product: \(product)")
        print("Vendor ID: \(String(format: "0x%04X", vendorID))")
        print("Product ID: \(String(format: "0x%04X", productID))")
        
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
            print("G13 device disconnected")
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
        
        let inputData = HIDInputData(
            timestamp: timestamp,
            length: length,
            usagePage: usagePage,
            usage: usage,
            intValue: intValue,
            rawData: rawData
        )
        
        // Handle joystick input
        if usagePage == joystickUsagePage && usage == joystickUsage {
            handleJoystickInput(intValue)
        }
        
        delegate?.hidDevice(self, didReceiveInput: inputData)
    }
    
    private func handleJoystickInput(_ value: Int64) {
        guard let settings = joystickSettings else { return }
        
        // Assuming joystick values are in the range -100 to 100
        if value < -joystickThreshold && lastJoystickX >= -joystickThreshold {
            // Left
            print("Joystick Left: \(settings.calibration.leftKey)")
        } else if value > joystickThreshold && lastJoystickX <= joystickThreshold {
            // Right
            print("Joystick Right: \(settings.calibration.rightKey)")
        } else if value < -joystickThreshold && lastJoystickY >= -joystickThreshold {
            // Up
            print("Joystick Up: \(settings.calibration.upKey)")
        } else if value > joystickThreshold && lastJoystickY <= joystickThreshold {
            // Down
            print("Joystick Down: \(settings.calibration.downKey)")
        }
        
        // Update last values
        lastJoystickX = value
        lastJoystickY = value
    }
    
    private func IOHIDDeviceCreateMatchingDictionary(_ vendorID: Int, _ productID: Int) -> CFDictionary {
        var dict: [String: Any] = [:]
        dict[kIOHIDVendorIDKey as String] = NSNumber(value: vendorID)
        dict[kIOHIDProductIDKey as String] = NSNumber(value: productID)
        return dict as CFDictionary
    }
    
    deinit {
        if let device = device {
            IOHIDDeviceRegisterInputValueCallback(device, nil, nil)
        }
        if isManagerOpen {
            IOHIDManagerClose(deviceManager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }
} 