import Foundation
import IOKit.hid

public enum HIDDeviceError: Error {
    case failedToOpenManager
    case permissionDenied
    case deviceNotFound
}

public class HIDDevice {
    private var device: IOHIDDevice?
    private var deviceManager: IOHIDManager
    private var isManagerOpen: Bool = false
    
    // Constants for the G13
    private let vendorID: Int = 0x046D
    private let productID: Int = 0xC21C
    
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
    }
    
    private func handleDeviceRemoval(device: IOHIDDevice) {
        if device == self.device {
            print("G13 device disconnected")
            self.device = nil
        }
    }
    
    private func handleInput(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let timestamp = IOHIDValueGetTimeStamp(value)
        let length = IOHIDValueGetLength(value)
        let data = IOHIDValueGetBytePtr(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)
        
        print("Input received:")
        print("Timestamp: \(timestamp)")
        print("Length: \(length)")
        print("Usage Page: 0x\(String(format: "%04X", usagePage))")
        print("Usage: 0x\(String(format: "%04X", usage))")
        print("Integer Value: \(intValue)")
        print("Raw Data: ", terminator: "")
        for i in 0..<min(length, 8) {  // Print first 8 bytes
            print(String(format: "%02X ", data[Int(i)]), terminator: "")
        }
        print()
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