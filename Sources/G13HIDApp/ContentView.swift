import SwiftUI
import G13HID
import Foundation
import ApplicationServices

@available(macOS 13.0, *)
typealias JS = G13HID.JoystickSettings

@available(macOS 13.0, *)
class HIDMonitor: ObservableObject, HIDDeviceDelegate {
    @Published var isConnected = false
    @Published var lastInput: HIDInputData?
    @Published var errorMessage: String?
    @Published var hasAccessibilityPermission = false
    @Published var keyboardOutputMode: String = "Unknown"
    private var hidDevice: HIDDevice?
    private var permissionCheckTimer: Timer?

    init() {
        do {
            hidDevice = try HIDDevice()
            hidDevice?.delegate = self

            // Get keyboard output mode
            if let config = hidDevice?.getConfigManager()?.getConfig() {
                keyboardOutputMode = config.keyboardOutputMode.description
            }
        } catch HIDDeviceError.permissionDenied {
            errorMessage = "Permission denied. Try running with sudo."
        } catch {
            errorMessage = "Error: \(error)"
        }

        // Check accessibility permission
        checkAccessibilityPermission()

        // Re-check every 2 seconds in case user grants permission
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkAccessibilityPermission()
        }
    }

    func checkAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()
        DispatchQueue.main.async {
            self.hasAccessibilityPermission = trusted
        }
    }

    deinit {
        permissionCheckTimer?.invalidate()
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

@available(macOS 13.0, *)
struct ContentView: View {
    @StateObject private var monitor = HIDMonitor()
    @StateObject private var joystickSettings = JS()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("G13 HID Monitor")
                .font(.title)

            // Keyboard Output Mode
            HStack {
                Text("Output Mode:")
                    .font(.headline)
                Text(monitor.keyboardOutputMode)
                    .foregroundColor(.blue)
            }

            // Accessibility Permission Status
            HStack {
                Text("Accessibility:")
                    .font(.headline)
                if monitor.hasAccessibilityPermission {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Enabled")
                            .foregroundColor(.green)
                    }
                } else {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.orange)
                        Text("Not Enabled")
                            .foregroundColor(.orange)
                    }
                }
            }

            if !monitor.hasAccessibilityPermission && monitor.keyboardOutputMode.contains("CGEvent") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("⚠️ Accessibility permission required for CGEvent mode")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                    Text("Open System Preferences > Privacy & Security > Accessibility")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Add and enable this app (or Terminal.app)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Open System Preferences") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }

            Divider()

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
                            SelectableText(text: """
                            Timestamp: \(input.timestamp)
                            Length: \(input.length)
                            Usage Page: 0x\(String(format: "%04X", input.usagePage))
                            Usage: 0x\(String(format: "%04X", input.usage))
                            Integer Value: \(input.intValue)
                            Raw Data: \(input.rawData.prefix(8).map { String(format: "%02X ", $0) }.joined())
                            """)
                        }
                        .font(.system(.body, design: .monospaced))
                    }
                }
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 400, minHeight: 400)
        .onAppear {
            monitor.setJoystickSettings(joystickSettings)
        }
    }
} 