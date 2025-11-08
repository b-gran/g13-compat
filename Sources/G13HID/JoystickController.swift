import Foundation

/// Controls joystick input and converts it to keyboard output with duty cycle
public class JoystickController {
    private let keyboard: KeyboardOutput

    // Public configuration
    public var deadzone: Double = 0.15            // Threshold magnitude below which no output
    public var dutyCycleFrequency: Double = 60.0  // Base cycles per second (for duty cycle mode)
    public var maxEventsPerSecond: Int? = nil      // Optional cap limiting press/release transitions for secondary key (duty cycle mode)
    public enum Mode {
        case dutyCycle(ratioProvider: (Double) -> Double) // ratio based on angular offset function returns 0..1
        case hold(diagonalAnglePercent: Double) // dual-key hold with progressive travel from initial anchor
    }
    public var mode: Mode = .dutyCycle(ratioProvider: { $0 / 45.0 }) // default (ratio = offset/45)
    // Debug instrumentation (set true during troubleshooting to emit hold-mode state transitions)
    public var debugHoldLogging: Bool = true

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

    // Hold mode state
    private var holdInitialAnchorKey: VirtualKeyboard.KeyCode? = nil
    private var holdInitialAnchorAngle: Double? = nil // cardinal angle (0,90,180,270)
    private var holdDirectionClockwise: Bool = true // direction of travel from initial anchor
    private var holdDroppedPrimary: Bool = false

    public init(keyboard: KeyboardOutput) {
        self.keyboard = keyboard
    }

    /// Apply joystick events configuration (parsed from JoystickConfig)
    public func configure(from config: JoystickConfig) {
        self.deadzone = config.deadzone
        switch config.events {
        case .dutyCycle(let frequency, let ratio, let maxEvents):
            self.dutyCycleFrequency = frequency
            self.maxEventsPerSecond = maxEvents
            // ratio parameter from config represents maximum ratio at 45°, we scale actual offset proportionally
            self.mode = .dutyCycle(ratioProvider: { offsetDeg in
                let clamped = min(offsetDeg, 45.0)
                let base = clamped / 45.0
                return base * ratio // allow tuning vs default 1.0
            })
        case .hold(let diagonalAnglePercent, _):
            // In hold mode we ignore dutyCycleFrequency/maxEvents
            self.maxEventsPerSecond = nil
            self.mode = .hold(diagonalAnglePercent: diagonalAnglePercent)
        }
    }

    /// Update joystick position (normalized -1.0 to 1.0)
    public func updateJoystick(x: Double, y: Double) {
        let magnitude = sqrt(x * x + y * y)
        if magnitude < deadzone {
            // Centered: release everything
            releasePrimary()
            stopSecondaryCycle()
            resetHoldState()
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
        switch mode {
        case .dutyCycle(let ratioProvider):
            let ratio = ratioProvider(diffAbs)
            if ratio <= 0.0001 { return (primary, nil, 0) }
            // Determine secondary based on direction of deviation from anchor
            let secondary: VirtualKeyboard.KeyCode
            switch best.key {
            case .w: secondary = bestDiff > 0 ? .a : .d
            case .d: secondary = bestDiff > 0 ? .w : .s
            case .a: secondary = bestDiff > 0 ? .s : .w
            case .s: secondary = bestDiff > 0 ? .d : .a
            default: secondary = .w
            }
            return (primary, secondary, ratio)
        case .hold(let diagonalAnglePercent):
            // Travel thresholds relative to initial anchor's 90° span toward adjacent cardinal.
            let thresholdAdd = diagonalAnglePercent * 90.0
            let thresholdDrop = (1.0 - diagonalAnglePercent) * 90.0
            if debugHoldLogging {
                logInfo("[HOLD] angle=\(String(format: "%.2f", angle)) nearest=\(best.key) diffAbs=\(String(format: "%.2f", diffAbs)) add=\(String(format: "%.2f", thresholdAdd)) drop=\(String(format: "%.2f", thresholdDrop)) initial=\(holdInitialAnchorKey.map { String(describing: $0) } ?? "nil")")
            }

            // If no hold session active, evaluate possibility to start one using current nearest anchor.
            if holdInitialAnchorKey == nil || holdInitialAnchorAngle == nil {
                if diffAbs < thresholdAdd { // Not far enough: single primary
                    return (primary, nil, 0)
                }
                // Start hold session.
                holdInitialAnchorKey = primary
                holdInitialAnchorAngle = best.deg
                holdDirectionClockwise = bestDiff > 0 // sign of deviation from anchor determines direction of travel
                holdDroppedPrimary = false
                if debugHoldLogging { logInfo("[HOLD] START segment anchor=\(primary) angle=\(best.deg) clockwise=\(holdDirectionClockwise)") }
            }

            // Compute progress from initial anchor along chosen direction even if nearest anchor changed.
            guard let initialAngle = holdInitialAnchorAngle, let initialKey = holdInitialAnchorKey else {
                return (primary, nil, 0)
            }
            let progress = angularProgress(from: initialAngle, to: angle, clockwise: holdDirectionClockwise)
            // If user reversed direction substantially (progress decreases below add threshold), reset state.
            if progress < thresholdAdd * 0.5 { // hysteresis factor to avoid flicker
                if debugHoldLogging { logInfo("[HOLD] RESET due to reverse progress=\(String(format: "%.2f", progress)) < hysteresis=\(String(format: "%.2f", thresholdAdd * 0.5))") }
                resetHoldState()
                return (primary, nil, 0)
            }
            // Determine secondary (target cardinal) based on initial key + direction
            let secondaryTarget = adjacentCardinal(from: initialKey, clockwise: holdDirectionClockwise)

            if progress >= thresholdDrop {
                // Drop initial primary; keep only target.
                holdDroppedPrimary = true
                if debugHoldLogging { logInfo("[HOLD] DROP primary=\(initialKey) progress=\(String(format: "%.2f", progress)) >= drop=\(String(format: "%.2f", thresholdDrop)) -> newPrimary=\(secondaryTarget)") }

                // Only consider starting a new segment AFTER we fully complete the 90° span (progress ~90) AND
                // we have moved sufficiently away from the secondary target toward its adjacent (nextDiff >= thresholdAdd).
                let nearEndOfSpan = progress >= 90.0
                if nearEndOfSpan {
                    let nextAnchor = secondaryTarget
                    let nextAnchorAngle: Double
                    switch nextAnchor {
                    case .d: nextAnchorAngle = 0
                    case .w: nextAnchorAngle = 90
                    case .a: nextAnchorAngle = 180
                    case .s: nextAnchorAngle = 270
                    default: nextAnchorAngle = 0
                    }
                    let nextDiff = abs(angularDifference(angle, nextAnchorAngle))
                    if nextDiff >= thresholdAdd { // moved far enough from new anchor to begin dual-key of next segment
                        holdInitialAnchorKey = nextAnchor
                        holdInitialAnchorAngle = nextAnchorAngle
                        holdDroppedPrimary = false
                        // Continue same rotation direction.
                        let newProgress = angularProgress(from: nextAnchorAngle, to: angle, clockwise: holdDirectionClockwise)
                        if debugHoldLogging { logInfo("[HOLD] RE-ANCHOR nextAnchor=\(nextAnchor) angle=\(nextAnchorAngle) newProgress=\(String(format: "%.2f", newProgress)) nextDiff=\(String(format: "%.2f", nextDiff))") }
                        if newProgress >= thresholdDrop {
                            // Large jump: immediately in drop zone of new segment
                            let newSecondary = adjacentCardinal(from: nextAnchor, clockwise: holdDirectionClockwise)
                            holdDroppedPrimary = true
                            if debugHoldLogging { logInfo("[HOLD] Immediate drop in new segment newPrimary=\(newSecondary)") }
                            return (newSecondary, nil, 0)
                        } else if newProgress >= thresholdAdd {
                            let newSecondary = adjacentCardinal(from: nextAnchor, clockwise: holdDirectionClockwise)
                            if debugHoldLogging { logInfo("[HOLD] New segment dual keys \(nextAnchor)+\(newSecondary) progress=\(String(format: "%.2f", newProgress))") }
                            return (nextAnchor, newSecondary, 1.0)
                        } else {
                            if debugHoldLogging { logInfo("[HOLD] New segment single key \(nextAnchor) progress=\(String(format: "%.2f", newProgress)) < add=\(String(format: "%.2f", thresholdAdd))") }
                            return (nextAnchor, nil, 0)
                        }
                    }
                }
                return (secondaryTarget, nil, 0)
            }
            // Both keys held until primary drop threshold is reached regardless of nearest cardinal switching.
            if debugHoldLogging { logInfo("[HOLD] Dual keys \(initialKey)+\(secondaryTarget) progress=\(String(format: "%.2f", progress)) < drop=\(String(format: "%.2f", thresholdDrop))") }
            return (initialKey, secondaryTarget, 1.0)
        }
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
                if case .hold = mode { // In hold mode we simply press secondary continuously
                    try? keyboard.pressKey(sk)
                } else if ratio >= 0.999 { // Hold continuously
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
        if let sk = currentSecondary {
            // If the secondary key just became the primary due to a DROP event, avoid releasing it.
            // This prevents the press-then-immediate-release flicker seen when promoting the secondary to primary.
            if sk != currentPrimary {
                try? keyboard.releaseKey(sk)
            }
        }
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
        resetHoldState()
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

// Returns positive progress (0..90) representing travel from startAngle toward direction (clockwise or counter-clockwise) limited to 90.
private func angularProgress(from startAngle: Double, to currentAngle: Double, clockwise: Bool) -> Double {
    var raw = currentAngle - startAngle
    while raw < -180 { raw += 360 }
    while raw > 180 { raw -= 360 }
    let signed = clockwise ? raw : -raw
    let clamped = max(0.0, min(90.0, signed))
    return clamped
}

// Adjacent cardinal in travel direction.
private func adjacentCardinal(from key: VirtualKeyboard.KeyCode, clockwise: Bool) -> VirtualKeyboard.KeyCode {
    switch key {
    case .d: return clockwise ? .w : .s
    case .w: return clockwise ? .a : .d
    case .a: return clockwise ? .s : .w
    case .s: return clockwise ? .d : .a
    default: return .w
    }
}

private extension JoystickController {
    func resetHoldState() {
        holdInitialAnchorKey = nil
        holdInitialAnchorAngle = nil
        holdDroppedPrimary = false
    }
}
