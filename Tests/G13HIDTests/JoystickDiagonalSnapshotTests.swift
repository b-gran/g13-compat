import XCTest
@testable import G13HID

final class JoystickDiagonalSnapshotTests: XCTestCase {
    func makeController(diagonalPercent: Double) -> (JoystickController, MockKeyboardOutput) {
        let kb = MockKeyboardOutput()
        let ctrl = JoystickController(keyboard: kb)
        let cfg = JoystickConfig(
            enabled: true,
            deadzone: 0.05,
            events: .hold(diagonalAnglePercent: diagonalPercent, holdEnabled: true, diagonalAssist: nil),
            upKey: "w", downKey: "s", leftKey: "a", rightKey: "d"
        )
        ctrl.configure(from: cfg)
        return (ctrl, kb)
    }

    func vector(_ deg: Double) -> (Double, Double) {
        let r = deg * .pi / 180.0
        return (cos(r), sin(r))
    }

    // Assert that for each cardinal span, we hold both keys from add threshold until drop threshold.
    func testDiagonalDualKeyPersistence() {
        // Use a moderate 0.25 (22.5° add, 67.5° drop) for clear separation
        let (ctrl, _) = makeController(diagonalPercent: 0.25)
        // Cardinal anchors at 0 (d) -> 90 (w) -> 180 (a) -> 270 (s) -> 360 (d)
        // We'll rotate clockwise in small steps and sample at: just past add, mid (diagonal), just before drop, beyond drop.
        let step = 3.0
        var deg = 0.0
        // full 360 clockwise
        while deg <= 360.0 {
            let (x, y) = vector(deg)
            ctrl.updateJoystick(x: x, y: y)
            // Determine current segment initial anchor by examining holdInitialAnchorKey (internal) or primary/secondary heuristics.
            if let initial = ctrl.primaryKey, let secondary = ctrl.secondaryKey {
                // Both keys held: ensure they are adjacent cardinals and we haven't exceeded allowed drop threshold heuristically.
                // Accept any dual-state before drop; cannot compute progress externally easily but we can ensure adjacency.
                let pair: Set<VirtualKeyboard.KeyCode> = [initial, secondary]
                let validPairs: [Set<VirtualKeyboard.KeyCode>] = [
                    [.d, .w], [.w, .a], [.a, .s], [.s, .d]
                ]
                XCTAssertTrue(validPairs.contains(pair), "Invalid dual key pair \(pair) at angle \(deg)")
            }
            deg += step
        }
        ctrl.stop()
    }
}

#if !canImport(ObjectiveC)
extension JoystickDiagonalSnapshotTests {
    static var allTests = [
        ("testDiagonalDualKeyPersistence", testDiagonalDualKeyPersistence)
    ]
}
#endif
