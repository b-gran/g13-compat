import SwiftUI
import G13HID
import Foundation

@available(macOS 12.0, *)
typealias JS = G13HID.JoystickSettings

@available(macOS 12.0, *)
class HIDMonitor: ObservableObject, HIDDeviceDelegate {
    @Published var isConnected = false
    @Published var lastInput: HIDInputData?
    @Published var errorMessage: String?
    private var hidDevice: HIDDevice?
    
    init() {
        do {
            hidDevice = try HIDDevice()
            hidDevice?.delegate = self
        } catch HIDDeviceError.permissionDenied {
            errorMessage = "Permission denied. Try running with sudo."
        } catch {
            errorMessage = "Error: \(error)"
        }
    }
    
    func setJoystickSettings(_ settings: JS) {
        hidDevice?.joystickSettings = settings
    }
    
    func hidDevice(_ device: HIDDevice, didReceiveInput data: HIDInputData) {
        DispatchQueue.main.async {
            self.lastInput = data
        }
    }
    
    func hidDeviceDidConnect(_ device: HIDDevice) {
        DispatchQueue.main.async {
            self.isConnected = true
            self.errorMessage = nil
        }
    }
    
    func hidDeviceDidDisconnect(_ device: HIDDevice) {
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }
}

@available(macOS 12.0, *)
struct ContentView: View {
    @StateObject private var monitor = HIDMonitor()
    @StateObject private var joystickSettings = JS()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("G13 HID Monitor")
                .font(.title)
            
            if let error = monitor.errorMessage {
                Text(error)
                    .foregroundColor(.red)
            } else {
                Text("Device Status: \(monitor.isConnected ? "Connected" : "Disconnected")")
                    .foregroundColor(monitor.isConnected ? .green : .red)
                
                if monitor.isConnected {
                    JoystickCalibrationView(settings: joystickSettings, monitor: monitor)
                        .padding(Edge.Set.top)
                }
                
                if let input = monitor.lastInput {
                    Group {
                        Text("Last Input:")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Timestamp: \(input.timestamp)")
                            Text("Length: \(input.length)")
                            Text("Usage Page: 0x\(String(format: "%04X", input.usagePage))")
                            Text("Usage: 0x\(String(format: "%04X", input.usage))")
                            Text("Integer Value: \(input.intValue)")
                            Text("Raw Data: \(input.rawData.prefix(8).map { String(format: "%02X ", $0) }.joined())")
                        }
                        .font(.system(.body, design: .monospaced))
                    }
                }
            }
            
            Spacer()
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
        .onAppear {
            monitor.setJoystickSettings(joystickSettings)
        }
    }
} 