import XCTest
@testable import G13HID

final class JoystickContinuousRotationTests: XCTestCase {
    func makeController(percent: Double = 0.15) -> JoystickController {
        let kb = MockKeyboardOutput()
        let ctrl = JoystickController(keyboard: kb)
        let cfg = JoystickConfig(
            enabled: true,
            deadzone: 0.05,
            events: .hold(diagonalAnglePercent: percent, holdEnabled: true, diagonalAssist: nil),
            upKey: "w", downKey: "s", leftKey: "a", rightKey: "d"
        )
        ctrl.configure(from: cfg)
        return ctrl
    }

    private func angleVector(_ deg: Double) -> (Double, Double) {
        let rad = deg * .pi / 180.0
        return (cos(rad), sin(rad))
    }

    func testFullTwoRotationsNoStall() {
        let ctrl = makeController(percent: 0.15)
        // Rotate 0 -> 720 degrees in small steps.
        var gaps = 0
        for deg in stride(from: 0.0, through: 720.0, by: 3.0) { // 3° increments
            let (x, y) = angleVector(deg.truncatingRemainder(dividingBy: 360.0))
            ctrl.updateJoystick(x: x, y: y)
            let hasPrimary = ctrl.primaryKey != nil
            if !hasPrimary { gaps += 1 }
        }
        // Expect very few (ideally zero) gaps where no primary key is held.
        XCTAssertLessThanOrEqual(gaps, 2, "Too many stalls detected: gaps=\(gaps)")
        ctrl.stop()
    }

#if !canImport(ObjectiveC)
    static var allTests = [
        ("testFullTwoRotationsNoStall", testFullTwoRotationsNoStall)
    ]
#endif
}
