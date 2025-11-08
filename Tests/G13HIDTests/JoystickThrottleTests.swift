import XCTest
@testable import G13HID

final class JoystickThrottleTests: XCTestCase {
    func testSecondaryThrottleMaxEventsPerSecond() throws {
        let kb = MockKeyboardOutput()
        let controller = JoystickController(keyboard: kb)
        controller.dutyCycleFrequency = 60.0 // High base frequency
        controller.maxEventsPerSecond = 5    // Cap transitions to <=5 events/sec (press/release cycles cause 2 transitions)
        // Choose angle at 22.5° from Up toward Left -> ratio ~0.5 for secondary.
        let angleRad = 112.5 * Double.pi / 180.0
        let x = cos(angleRad)
        let y = sin(angleRad)
        controller.updateJoystick(x: x, y: y)
        // Wait 1 second to accumulate events
        Thread.sleep(forTimeInterval: 1.05)
        controller.stop()
        // Count secondary transitions (should be capped). We expect roughly <=5 press + release combined.
        let totalTransitions = kb.pressEvents + kb.releaseEvents
        XCTAssertLessThanOrEqual(totalTransitions, 6, "Expected throttled transitions (allow small slack)")
    }
}

#if !canImport(ObjectiveC)
extension JoystickThrottleTests {
    static var allTests = [
        ("testSecondaryThrottleMaxEventsPerSecond", testSecondaryThrottleMaxEventsPerSecond)
    ]
}
#endif