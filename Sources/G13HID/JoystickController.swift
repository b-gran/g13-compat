import Foundation

/// Controls joystick input and converts it to keyboard output with duty cycle
public class JoystickController {
    private let keyboard: KeyboardOutput

    // Public configuration
    public var deadzone: Double = 0.15            // Threshold magnitude below which no output
    public var dutyCycleFrequency: Double = 60.0  // Base cycles per second
    public var maxEventsPerSecond: Int? = nil      // Optional cap limiting press/release transitions for secondary key

    // Internal state exposed for tests via @testable import
    var primaryKey: VirtualKeyboard.KeyCode? { currentPrimary }
    var secondaryKey: VirtualKeyboard.KeyCode? { currentSecondary }
    var secondaryRatio: Double { currentSecondaryRatio }

    // Current keys & ratio
    private var currentPrimary: VirtualKeyboard.KeyCode? = nil
    private var currentSecondary: VirtualKeyboard.KeyCode? = nil
    private var currentSecondaryRatio: Double = 0.0 // 0..1 (fraction of cycle pressed)

    // Timers for secondary duty cycle (variable interval)
    private var secondaryTimer: Timer?
    private var secondaryPhaseIsOn: Bool = false

    public init(keyboard: KeyboardOutput) {
        self.keyboard = keyboard
    }

    /// Update joystick position (normalized -1.0 to 1.0)
    public func updateJoystick(x: Double, y: Double) {
        let magnitude = sqrt(x * x + y * y)
        if magnitude < deadzone {
            // Centered: release everything
            releasePrimary()
            stopSecondaryCycle()
            return
        }

        let angleDeg = normalizeAngleDegrees(atan2(y, x) * 180.0 / .pi) // 0° = right
        let (primary, secondary, ratio) = computeKeys(angle: angleDeg)
        apply(primary: primary, secondary: secondary, ratio: ratio)
    }

    /// Compute primary key, secondary key, and duty cycle ratio based on angle.
    /// - Parameter angle: normalized 0..360 degrees (0 = right, 90 = up)
    /// - Returns: (primary, secondary, ratio) where ratio \in [0,1]
    func computeKeys(angle: Double) -> (VirtualKeyboard.KeyCode?, VirtualKeyboard.KeyCode?, Double) {
        // Cardinal anchors: Right(0), Up(90), Left(180), Down(270)
        let anchors: [(deg: Double, key: VirtualKeyboard.KeyCode)] = [
            (0, .d), (90, .w), (180, .a), (270, .s)
        ]
        // Find nearest cardinal anchor (min angular distance <= 45)
        var best = anchors[0]
        var bestDiff = angularDifference(angle, anchors[0].deg)
        for candidate in anchors.dropFirst() {
            let diff = angularDifference(angle, candidate.deg)
            if abs(diff) < abs(bestDiff) {
                best = candidate
                bestDiff = diff
            }
        }
        let primary = best.key
        let diffAbs = abs(bestDiff)
        let clamped = min(diffAbs, 45.0)
        let ratio = clamped / 45.0 // 0 at anchor, 1 at diagonal
        if ratio == 0 { return (primary, nil, 0) }

        // Determine secondary based on direction of deviation from anchor
        let secondary: VirtualKeyboard.KeyCode
        switch best.key {
        case .w: secondary = bestDiff > 0 ? .a : .d   // Up -> toward + diff (clockwise) is left (NW), negative diff is right (NE)
        case .d: secondary = bestDiff > 0 ? .w : .s   // Right -> toward NE (positive) up, toward SE (negative) down
        case .a: secondary = bestDiff > 0 ? .s : .w   // Left -> toward SW (positive) down, toward NW (negative) up
        case .s: secondary = bestDiff > 0 ? .d : .a   // Down -> toward SE (positive) right, toward SW (negative) left
        default: secondary = .w // Fallback should never occur
        }
        return (primary, secondary, ratio)
    }

    private func apply(primary: VirtualKeyboard.KeyCode?, secondary: VirtualKeyboard.KeyCode?, ratio: Double) {
        // Primary key changes
        if currentPrimary != primary {
            releasePrimary()
            if let pk = primary { try? keyboard.pressKey(pk) }
            currentPrimary = primary
        }

        // Secondary key or ratio changes
        let secondaryChanged = currentSecondary != secondary
        let ratioChanged = abs(currentSecondaryRatio - ratio) > 0.0001
        if secondaryChanged || ratioChanged {
            stopSecondaryCycle()
            currentSecondary = secondary
            currentSecondaryRatio = ratio
            if let sk = secondary {
                if ratio >= 0.999 { // Hold continuously
                    try? keyboard.pressKey(sk)
                } else if ratio <= 0.0001 { // No secondary
                    // nothing
                } else {
                    // Start duty cycle
                    startSecondaryCycle(key: sk, ratio: ratio)
                }
            }
        }
    }

    private func releasePrimary() {
        if let pk = currentPrimary { try? keyboard.releaseKey(pk) }
        currentPrimary = nil
    }

    private func stopSecondaryCycle() {
        secondaryTimer?.invalidate()
        secondaryTimer = nil
        if let sk = currentSecondary { try? keyboard.releaseKey(sk) }
        secondaryPhaseIsOn = false
    }

    private func startSecondaryCycle(key: VirtualKeyboard.KeyCode, ratio: Double) {
        // Begin with ON phase
        secondaryPhaseIsOn = true
        try? keyboard.pressKey(key)
        scheduleSecondaryPhase(key: key, ratio: ratio, onPhase: true)
    }

    private func scheduleSecondaryPhase(key: VirtualKeyboard.KeyCode, ratio: Double, onPhase: Bool) {
        let basePeriod = 1.0 / max(dutyCycleFrequency, 1.0)
        // If a maxEventsPerSecond is set, enlarge period so total transitions do not exceed cap.
        if let cap = maxEventsPerSecond, cap > 0 {
            // Each full ON+OFF cycle produces 2 transitions; ensure 2 * cyclesPerSecond <= cap.
            let allowedCyclesPerSecond = Double(cap) / 2.0
            if allowedCyclesPerSecond < dutyCycleFrequency {
                // Scale basePeriod up to respect cap
                let scaledPeriod = 1.0 / allowedCyclesPerSecond
                // Choose the larger (slower) of existing basePeriod and scaledPeriod
                // to avoid accidentally speeding up.
                // This keeps the ratio timing proportions while reducing transition frequency.
                // The dutyCycleFrequency remains as configured for ratio semantics but period used for scheduling is adjusted.
                // (We don't mutate dutyCycleFrequency to preserve original ratio computation semantics elsewhere.)
                let effectivePeriod = max(basePeriod, scaledPeriod)
                // Override basePeriod via local variable
                // Recompute basePeriod components using effectivePeriod
                let minInterval = 0.005
                let interval: Double = {
                    if onPhase {
                        return max(effectivePeriod * ratio, minInterval)
                    } else {
                        return max(effectivePeriod * (1.0 - ratio), minInterval)
                    }
                }()
                secondaryTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                    guard let self = self else { return }
                    if onPhase {
                        try? self.keyboard.releaseKey(key)
                        self.secondaryPhaseIsOn = false
                        self.scheduleSecondaryPhase(key: key, ratio: ratio, onPhase: false)
                    } else {
                        try? self.keyboard.pressKey(key)
                        self.secondaryPhaseIsOn = true
                        self.scheduleSecondaryPhase(key: key, ratio: ratio, onPhase: true)
                    }
                }
                return
            }
        }
        // Enforce minimal interval to avoid extremely short timers (<5ms)
        let minInterval = 0.005
        let interval: Double
        if onPhase {
            interval = max(basePeriod * ratio, minInterval)
        } else {
            interval = max(basePeriod * (1.0 - ratio), minInterval)
        }
        secondaryTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if onPhase {
                // Transition to OFF
                try? self.keyboard.releaseKey(key)
                self.secondaryPhaseIsOn = false
                self.scheduleSecondaryPhase(key: key, ratio: ratio, onPhase: false)
            } else {
                // Transition to ON
                try? self.keyboard.pressKey(key)
                self.secondaryPhaseIsOn = true
                self.scheduleSecondaryPhase(key: key, ratio: ratio, onPhase: true)
            }
        }
    }

    /// Stop all joystick output
    public func stop() {
        releasePrimary()
        stopSecondaryCycle()
    }

    deinit { stop() }
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

// MARK: - Angle helpers
private func normalizeAngleDegrees(_ angle: Double) -> Double {
    var a = angle
    while a < 0 { a += 360 }
    while a >= 360 { a -= 360 }
    return a
}

/// Returns signed smallest difference (angle - anchor) in degrees in range [-180,180]
private func angularDifference(_ angle: Double, _ anchor: Double) -> Double {
    var diff = angle - anchor
    while diff < -180 { diff += 360 }
    while diff > 180 { diff -= 360 }
    return diff
}
