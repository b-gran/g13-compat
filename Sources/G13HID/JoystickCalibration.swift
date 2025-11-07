import Foundation
import SwiftUI

@available(macOS 12.0, *)
public struct JoystickCalibration: Codable {
    public var leftKey: String
    public var rightKey: String
    public var upKey: String
    public var downKey: String
    
    public init(leftKey: String = "a", rightKey: String = "d", upKey: String = "w", downKey: String = "s") {
        self.leftKey = leftKey
        self.rightKey = rightKey
        self.upKey = upKey
        self.downKey = downKey
    }
}

@available(macOS 12.0, *)
public final class JoystickSettings: ObservableObject {
    @Published public var calibration: JoystickCalibration {
        didSet {
            saveCalibration()
        }
    }
    
    private let defaults = UserDefaults.standard
    private let calibrationKey = "g13.joystick.calibration"
    
    public init() {
        if let data = defaults.data(forKey: calibrationKey),
           let savedCalibration = try? JSONDecoder().decode(JoystickCalibration.self, from: data) {
            self.calibration = savedCalibration
        } else {
            self.calibration = JoystickCalibration()
        }
    }
    
    private func saveCalibration() {
        if let data = try? JSONEncoder().encode(calibration) {
            defaults.set(data, forKey: calibrationKey)
        }
    }
} 