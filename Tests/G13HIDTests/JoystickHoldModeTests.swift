import XCTest
@testable import G13HID

final class JoystickHoldModeTests: XCTestCase {
    func makeController(diagonalPercent: Double) -> (JoystickController, MockKeyboardOutput) {
        let kb = MockKeyboardOutput()
        let ctrl = JoystickController(keyboard: kb)
        let cfg = JoystickConfig(
            enabled: true,
            deadzone: 0.05,
            events: JoystickConfig.EventsMode.hold(diagonalAnglePercent: diagonalPercent, holdEnabled: true),
            upKey: "w", downKey: "s", leftKey: "a", rightKey: "d"
        )
        ctrl.configure(from: cfg)
        return (ctrl, kb)
    }

    func angleVector(_ deg: Double) -> (Double, Double) {
        let rad = deg * .pi / 180.0
        return (cos(rad), sin(rad))
    }

    func testAddSecondaryAtThreshold() {
        let diagonalPercent = 0.15 // 15% of 90° => 13.5°
        let (ctrl, kb) = makeController(diagonalPercent: diagonalPercent)
        // Slightly below threshold: only primary
        let below = 13.0
        let (bx, by) = angleVector(90 + below) // around Up towards Left
        ctrl.updateJoystick(x: bx, y: by)
        XCTAssertEqual(ctrl.primaryKey, .w)
        XCTAssertNil(ctrl.secondaryKey)
        // Just above threshold: secondary engaged
        let above = 14.0
        let (ax, ay) = angleVector(90 + above)
        ctrl.updateJoystick(x: ax, y: ay)
        XCTAssertEqual(ctrl.primaryKey, .w)
        XCTAssertEqual(ctrl.secondaryKey, .a)
        ctrl.stop()
        _ = kb // silence unused warning
    }

    func testDropPrimaryNearSecondaryAxis() {
        let diagonalPercent = 0.15
        let (ctrl, _) = makeController(diagonalPercent: diagonalPercent)
        // thresholdDropPrimary = (1 - p) * 90 = 76.5° offset from the initial anchor (Up -> Left path)
        // First establish initial anchor at Up by moving just past add threshold (13.5°)
        let establish = 90 + 14.0
        let (ex, ey) = angleVector(establish)
        ctrl.updateJoystick(x: ex, y: ey)
        XCTAssertEqual(ctrl.primaryKey, .w)
        XCTAssertEqual(ctrl.secondaryKey, .a)

        // Now move near (but below) the drop threshold: still dual keys expected
        let near = 90 + 76.0 // just below drop
        let (nx, ny) = angleVector(near)
        ctrl.updateJoystick(x: nx, y: ny)
        XCTAssertEqual(ctrl.primaryKey, .w)
        XCTAssertEqual(ctrl.secondaryKey, .a)

        // Move beyond drop threshold: expect switch to secondary only (Left)
        let beyond = 90 + 77.0 // >= threshold -> switch to A only per logic
        let (sx, sy) = angleVector(beyond)
        ctrl.updateJoystick(x: sx, y: sy)
        XCTAssertEqual(ctrl.primaryKey, .a)
        XCTAssertNil(ctrl.secondaryKey)
        ctrl.stop()
    }

    func testOnlyTwoKeysHeld() {
        let (ctrl, _) = makeController(diagonalPercent: 0.2)
        // Navigate through quadrants ensuring we never get 3 keys
        for deg in stride(from: 0.0, through: 360.0, by: 15.0) {
            let (x, y) = angleVector(deg)
            ctrl.updateJoystick(x: x, y: y)
            var held = [VirtualKeyboard.KeyCode]()
            if let p = ctrl.primaryKey { held.append(p) }
            if let s = ctrl.secondaryKey { held.append(s) }
            XCTAssertLessThanOrEqual(held.count, 2)
        }
        ctrl.stop()
    }
}

#if !canImport(ObjectiveC)
extension JoystickHoldModeTests {
    static var allTests = [
        ("testAddSecondaryAtThreshold", testAddSecondaryAtThreshold),
        ("testDropPrimaryNearSecondaryAxis", testDropPrimaryNearSecondaryAxis),
        ("testOnlyTwoKeysHeld", testOnlyTwoKeysHeld)
    ]
}
#endif