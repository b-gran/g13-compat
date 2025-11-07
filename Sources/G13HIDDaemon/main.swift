import Foundation
import G13HID

log("G13 Daemon starting...")
log("Press Ctrl+C to quit")
log("")

// Create HID device
let device: HIDDevice
do {
    device = try HIDDevice()
} catch {
    log("Failed to initialize HID device: \(error)")
    exit(1)
}

// Keep running
RunLoop.main.run()
