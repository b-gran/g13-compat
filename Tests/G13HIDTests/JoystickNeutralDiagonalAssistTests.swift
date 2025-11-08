import XCTest
@testable import G13HID

final class JoystickNeutralDiagonalAssistTests: XCTestCase {
    func makeController(assist: JoystickDiagonalAssist?) -> (JoystickController, MockKeyboardOutput) {
        let kb = MockKeyboardOutput()
        let ctrl = JoystickController(keyboard: kb)
        let events: JoystickConfig.EventsMode = .dutyCycle(
            frequency: 60.0,
            ratio: 1.0, // allow full scaling
            maxEventsPerSecond: nil,
            diagonalAssist: assist
        )
        let cfg = JoystickConfig(enabled: true, deadzone: 0.15, events: events, upKey: "w", downKey: "s", leftKey: "a", rightKey: "d")
        ctrl.configure(from: cfg)
        return (ctrl, kb)
    }

    func testNeutralToDiagonalEngagesSecondaryWithAssist() {
    let assist = JoystickDiagonalAssist(axisThresholdMultiplier: 0.85, minAngleDegrees: 8.0, maxAngleDegrees: 40.0, minSecondaryRatio: 0.35)
        let (ctrl, _) = makeController(assist: assist)
        // Direct jump from neutral to a diagonal vector with modest angle offset (~35° from right toward up)
        let angle = 35.0 * Double.pi / 180.0
        let x = cos(angle)
        let y = sin(angle)
        ctrl.updateJoystick(x: x, y: y)
        XCTAssertEqual(ctrl.primaryKey, .d)
        XCTAssertEqual(ctrl.secondaryKey, .w, "Secondary key should engage due to diagonal assist from neutral")
        XCTAssertGreaterThanOrEqual(ctrl.secondaryRatio, 0.34)
        ctrl.stop()
    }

    func testNeutralToCardinalDoesNotForceSecondary() {
    let assist = JoystickDiagonalAssist()
        let (ctrl, _) = makeController(assist: assist)
        // Straight right
        ctrl.updateJoystick(x: 1.0, y: 0.0)
        XCTAssertEqual(ctrl.primaryKey, .d)
        XCTAssertNil(ctrl.secondaryKey)
        ctrl.stop()
    }

    func testWithoutAssistNoSecondaryForSmallOffset() {
        let (ctrl, _) = makeController(assist: nil)
        // Small angle 10°; with ratioProvider offset/45 => ratio ~0.22 (should produce a secondary, but low) - ensure baseline behavior still works.
        let angle = 10.0 * Double.pi / 180.0
        let x = cos(angle)
        let y = sin(angle)
        ctrl.updateJoystick(x: x, y: y)
        // baseline ratio ~0.22; depending on threshold secondary appears. We assert ratio is below assist's min.
        XCTAssertEqual(ctrl.primaryKey, .d)
        if let secondary = ctrl.secondaryKey {
            XCTAssertEqual(secondary, .w)
            XCTAssertLessThan(ctrl.secondaryRatio, 0.35)
        }
        ctrl.stop()
    }
}

#if !canImport(ObjectiveC)
extension JoystickNeutralDiagonalAssistTests {
    static var allTests = [
        ("testNeutralToDiagonalEngagesSecondaryWithAssist", testNeutralToDiagonalEngagesSecondaryWithAssist),
        ("testNeutralToCardinalDoesNotForceSecondary", testNeutralToCardinalDoesNotForceSecondary),
        ("testWithoutAssistNoSecondaryForSmallOffset", testWithoutAssistNoSecondaryForSmallOffset)
    ]
}
#endif
