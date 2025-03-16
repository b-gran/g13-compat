import Foundation

print("Starting G13 HID Monitor...")

do {
    let device = try HIDDevice()
    print("HID Manager initialized successfully")
    print("Waiting for G13 device events (press Ctrl+C to exit)...")
    
    // Keep the run loop running
    RunLoop.main.run()
} catch HIDDeviceError.permissionDenied {
    print("Error: Permission denied. Try running with sudo.")
} catch {
    print("Error: \(error)")
} 