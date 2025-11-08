import XCTest
@testable import G13HID

final class TapKeyCompletionTests: XCTestCase {
    func testTapKeyCompletionInvoked() throws {
        let mock = MockKeyboardOutput()
        let engine = MacroEngine(keyboard: mock)
        let exp = expectation(description: "tap completion")
        var completionFired = false
        if let keyCode = VirtualKeyboard.keyCodeFromString("a") {
            try mock.tapKey(keyCode) {
                completionFired = true
                exp.fulfill()
            }
        } else {
            XCTFail("Failed to resolve key code for 'a'")
        }
        waitForExpectations(timeout: 0.2)
        XCTAssertTrue(completionFired, "Completion should have fired for tapKey")
        XCTAssertEqual(mock.tapHistory.first, VirtualKeyboard.keyCodeFromString("a"), "Tap history should record tapped key")
    }

    func testTapKeyCompletionInvokedThroughExecutor() throws {
        let mock = MockKeyboardOutput()
        let engine = MacroEngine(keyboard: mock)
        let executor = KeyboardActionExecutor(keyboard: mock, macroEngine: engine)
        let exp = expectation(description: "executor tap completion")
        var completionFired = false
        let result = executor.perform(.keyTap("b")) { r in
            switch r {
            case .success: completionFired = true
            case .failure(let e): XCTFail("Tap failed: \(e)")
            }
            exp.fulfill()
        }
        if case .failure(let e) = result { XCTFail("Immediate failure: \(e)") }
        waitForExpectations(timeout: 0.2)
        XCTAssertTrue(completionFired, "Completion should have fired via executor")
        XCTAssertEqual(mock.tapHistory.last, VirtualKeyboard.keyCodeFromString("b"))
    }
}
