import XCTest
@testable import G13HID

final class JoystickControllerTests: XCTestCase {
    var keyboard: VirtualKeyboard?
    var controller: JoystickController?

    override func setUp() {
        super.setUp()
        keyboard = try? VirtualKeyboard()
        if let kb = keyboard {
            controller = JoystickController(keyboard: kb)
        }
    }

    override func tearDown() {
        controller?.stop()
        controller = nil
        keyboard = nil
        super.tearDown()
    }

    func testControllerInitialization() throws {
        let kb = try VirtualKeyboard()
        let ctrl = JoystickController(keyboard: kb)
        XCTAssertNotNil(ctrl)
        XCTAssertEqual(ctrl.deadzone, 0.15)
        XCTAssertEqual(ctrl.dutyCycleFrequency, 60.0)
        XCTAssertEqual(ctrl.dutyCycleRatio, 0.5)
    }

    func testDeadzoneConfiguration() throws {
        guard let ctrl = controller else {
            throw XCTSkip("Controller not available")
        }

        // Test setting deadzone
        ctrl.deadzone = 0.2
        XCTAssertEqual(ctrl.deadzone, 0.2)

        ctrl.deadzone = 0.3
        XCTAssertEqual(ctrl.deadzone, 0.3)
    }

    func testDutyCycleConfiguration() throws {
        guard let ctrl = controller else {
            throw XCTSkip("Controller not available")
        }

        // Test setting duty cycle parameters
        ctrl.dutyCycleFrequency = 30.0
        XCTAssertEqual(ctrl.dutyCycleFrequency, 30.0)

        ctrl.dutyCycleRatio = 0.75
        XCTAssertEqual(ctrl.dutyCycleRatio, 0.75)
    }

    func testJoystickCentered() throws {
        guard let ctrl = controller else {
            throw XCTSkip("Controller not available")
        }

        // Test centered position (within deadzone)
        XCTAssertNoThrow(ctrl.updateJoystick(x: 0.0, y: 0.0))

        // Small movements within deadzone
        XCTAssertNoThrow(ctrl.updateJoystick(x: 0.1, y: 0.1))
        XCTAssertNoThrow(ctrl.updateJoystick(x: -0.1, y: -0.1))
    }

    func testJoystickDirections() throws {
        guard let ctrl = controller else {
            throw XCTSkip("Controller not available")
        }

        // Test cardinal directions
        XCTAssertNoThrow(ctrl.updateJoystick(x: 1.0, y: 0.0))   // Right
        Thread.sleep(forTimeInterval: 0.05)
        ctrl.stop()

        XCTAssertNoThrow(ctrl.updateJoystick(x: -1.0, y: 0.0))  // Left
        Thread.sleep(forTimeInterval: 0.05)
        ctrl.stop()

        XCTAssertNoThrow(ctrl.updateJoystick(x: 0.0, y: 1.0))   // Up
        Thread.sleep(forTimeInterval: 0.05)
        ctrl.stop()

        XCTAssertNoThrow(ctrl.updateJoystick(x: 0.0, y: -1.0))  // Down
        Thread.sleep(forTimeInterval: 0.05)
        ctrl.stop()
    }

    func testJoystickDiagonals() throws {
        guard let ctrl = controller else {
            throw XCTSkip("Controller not available")
        }

        // Test diagonal directions
        XCTAssertNoThrow(ctrl.updateJoystick(x: 0.7, y: 0.7))    // Up-Right
        Thread.sleep(forTimeInterval: 0.05)
        ctrl.stop()

        XCTAssertNoThrow(ctrl.updateJoystick(x: -0.7, y: 0.7))   // Up-Left
        Thread.sleep(forTimeInterval: 0.05)
        ctrl.stop()

        XCTAssertNoThrow(ctrl.updateJoystick(x: 0.7, y: -0.7))   // Down-Right
        Thread.sleep(forTimeInterval: 0.05)
        ctrl.stop()

        XCTAssertNoThrow(ctrl.updateJoystick(x: -0.7, y: -0.7))  // Down-Left
        Thread.sleep(forTimeInterval: 0.05)
        ctrl.stop()
    }

    func testRawJoystickInput() throws {
        guard let ctrl = controller else {
            throw XCTSkip("Controller not available")
        }

        // Test raw value conversion (0-255 range)
        XCTAssertNoThrow(ctrl.updateJoystickRaw(x: 255, y: 128))  // Full right
        Thread.sleep(forTimeInterval: 0.05)
        ctrl.stop()

        XCTAssertNoThrow(ctrl.updateJoystickRaw(x: 0, y: 128))    // Full left
        Thread.sleep(forTimeInterval: 0.05)
        ctrl.stop()

        XCTAssertNoThrow(ctrl.updateJoystickRaw(x: 128, y: 255))  // Full down (Y inverted)
        Thread.sleep(forTimeInterval: 0.05)
        ctrl.stop()

        XCTAssertNoThrow(ctrl.updateJoystickRaw(x: 128, y: 0))    // Full up (Y inverted)
        Thread.sleep(forTimeInterval: 0.05)
        ctrl.stop()

        XCTAssertNoThrow(ctrl.updateJoystickRaw(x: 128, y: 128))  // Center
        Thread.sleep(forTimeInterval: 0.05)
        ctrl.stop()
    }

    func testStop() throws {
        guard let ctrl = controller else {
            throw XCTSkip("Controller not available")
        }

        // Start movement
        ctrl.updateJoystick(x: 1.0, y: 0.0)
        Thread.sleep(forTimeInterval: 0.05)

        // Stop should clean up
        XCTAssertNoThrow(ctrl.stop())
    }

    func testDirectionChange() throws {
        guard let ctrl = controller else {
            throw XCTSkip("Controller not available")
        }

        // Change from one direction to another
        ctrl.updateJoystick(x: 1.0, y: 0.0)  // Right
        Thread.sleep(forTimeInterval: 0.05)

        ctrl.updateJoystick(x: 0.0, y: 1.0)  // Up
        Thread.sleep(forTimeInterval: 0.05)

        ctrl.updateJoystick(x: 0.0, y: 0.0)  // Center
        Thread.sleep(forTimeInterval: 0.05)

        ctrl.stop()
    }

    func testDutyCycleOperation() throws {
        guard let ctrl = controller else {
            throw XCTSkip("Controller not available")
        }

        // Set up for observable duty cycle
        ctrl.dutyCycleFrequency = 10.0  // 10 Hz (100ms period)

        // Start movement
        ctrl.updateJoystick(x: 1.0, y: 0.0)

        // Wait for a few cycles
        Thread.sleep(forTimeInterval: 0.3)  // 3 cycles

        // Stop
        ctrl.stop()
    }
}
