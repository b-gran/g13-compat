import SwiftUI
import G13HID

@available(macOS 13.0, *)
struct JoystickCalibrationView: View {
    @ObservedObject var settings: JoystickSettings
    @ObservedObject var monitor: HIDMonitor
    
    private func formatJoystickValue(_ value: UInt8) -> String {
        return String(format: "0x%02X (%d)", value, value)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Joystick Calibration")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Left Key:")
                    TextField("Key", text: $settings.calibration.leftKey)
                        .frame(width: 60)
                }
                
                HStack {
                    Text("Right Key:")
                    TextField("Key", text: $settings.calibration.rightKey)
                        .frame(width: 60)
                }
                
                HStack {
                    Text("Up Key:")
                    TextField("Key", text: $settings.calibration.upKey)
                        .frame(width: 60)
                }
                
                HStack {
                    Text("Down Key:")
                    TextField("Key", text: $settings.calibration.downKey)
                        .frame(width: 60)
                }
            }
            .textFieldStyle(RoundedBorderTextFieldStyle())
            
            if let input = monitor.lastInput,
               input.rawData.count >= 7 {  // G13 reports are 7 bytes long
                VStack(alignment: .leading, spacing: 8) {
                    Text("Joystick Position:")
                        .font(.headline)
                    
                    Text("X-Axis: \(formatJoystickValue(input.rawData[0]))")
                        .font(.system(.body, design: .monospaced))
                        .help("00 = Full Left, FF = Full Right")
                    
                    Text("Y-Axis: \(formatJoystickValue(input.rawData[1]))")
                        .font(.system(.body, design: .monospaced))
                        .help("00 = Full Up, FF = Full Down")
                }
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 300)
    }
} 