import Foundation

/// Controls joystick input and converts it to keyboard output with duty cycle
public class JoystickController {
    private let keyboard: VirtualKeyboard
    private var dutyCycleTimer: Timer?
    private var currentDirection: Direction = .none
    private var dutyCyclePhase: DutyCyclePhase = .off

    // Joystick state
    private var joystickX: Double = 0.0
    private var joystickY: Double = 0.0

    // Configuration
    public var deadzone: Double = 0.15  // Deadzone threshold (0.0 to 1.0)
    public var dutyCycleFrequency: Double = 60.0  // Hz
    public var dutyCycleRatio: Double = 0.5  // 50% duty cycle

    private enum Direction {
        case none
        case up
        case down
        case left
        case right
        case upLeft
        case upRight
        case downLeft
        case downRight

        var keys: [VirtualKeyboard.KeyCode] {
            switch self {
            case .none: return []
            case .up: return [.w]
            case .down: return [.s]
            case .left: return [.a]
            case .right: return [.d]
            case .upLeft: return [.w, .a]
            case .upRight: return [.w, .d]
            case .downLeft: return [.s, .a]
            case .downRight: return [.s, .d]
            }
        }
    }

    private enum DutyCyclePhase {
        case on
        case off
    }

    public init(keyboard: VirtualKeyboard) {
        self.keyboard = keyboard
    }

    /// Update joystick position (normalized -1.0 to 1.0)
    public func updateJoystick(x: Double, y: Double) {
        joystickX = x
        joystickY = y

        let newDirection = calculateDirection(x: x, y: y)

        if newDirection != currentDirection {
            // Direction changed, release old keys and start new direction
            stopDutyCycle()
            currentDirection = newDirection

            if newDirection != .none {
                startDutyCycle()
            }
        }
    }

    private func calculateDirection(x: Double, y: Double) -> Direction {
        // Check if within deadzone
        let magnitude = sqrt(x * x + y * y)
        if magnitude < deadzone {
            return .none
        }

        // Calculate angle (0° is right, 90° is up, etc.)
        let angle = atan2(y, x) * 180.0 / .pi

        // Normalize angle to 0-360
        let normalizedAngle = angle < 0 ? angle + 360 : angle

        // Determine direction based on angle
        // Using 45-degree segments
        switch normalizedAngle {
        case 22.5..<67.5:
            return .upRight
        case 67.5..<112.5:
            return .up
        case 112.5..<157.5:
            return .upLeft
        case 157.5..<202.5:
            return .left
        case 202.5..<247.5:
            return .downLeft
        case 247.5..<292.5:
            return .down
        case 292.5..<337.5:
            return .downRight
        default:
            return .right
        }
    }

    private func startDutyCycle() {
        dutyCyclePhase = .on
        pressCurrentKeys()

        let interval = 1.0 / dutyCycleFrequency
        dutyCycleTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.dutyCycleTick()
        }
    }

    private func stopDutyCycle() {
        dutyCycleTimer?.invalidate()
        dutyCycleTimer = nil
        releaseCurrentKeys()
        dutyCyclePhase = .off
    }

    private func dutyCycleTick() {
        switch dutyCyclePhase {
        case .on:
            releaseCurrentKeys()
            dutyCyclePhase = .off
        case .off:
            pressCurrentKeys()
            dutyCyclePhase = .on
        }
    }

    private func pressCurrentKeys() {
        for key in currentDirection.keys {
            try? keyboard.pressKey(key)
        }
    }

    private func releaseCurrentKeys() {
        for key in currentDirection.keys {
            try? keyboard.releaseKey(key)
        }
    }

    /// Stop all joystick output
    public func stop() {
        stopDutyCycle()
        currentDirection = .none
    }

    deinit {
        stop()
    }
}

/// Extension to convert raw joystick values to normalized coordinates
extension JoystickController {
    /// Convert raw joystick values (typically 0-255) to normalized -1.0 to 1.0
    public func updateJoystickRaw(x: Int64, y: Int64, centerX: Int64 = 128, centerY: Int64 = 128, range: Int64 = 128) {
        let normalizedX = Double(x - centerX) / Double(range)
        let normalizedY = Double(y - centerY) / Double(range)

        // Invert Y axis (typically joystick Y is inverted)
        updateJoystick(x: normalizedX, y: -normalizedY)
    }
}
