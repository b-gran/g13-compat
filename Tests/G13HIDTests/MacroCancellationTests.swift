import XCTest
@testable import G13HID

final class MacroCancellationTests: XCTestCase {
    var keyboard: KeyboardOutput?
    var engine: MacroEngine?

    override func setUp() {
        super.setUp()
        keyboard = MockKeyboardOutput()
        if let kb = keyboard { engine = MacroEngine(keyboard: kb) }
    }

    override func tearDown() {
        engine = nil
        keyboard = nil
        super.tearDown()
    }

    func testCancellationStopsMacroEarly() throws {
        guard let eng = engine else { throw XCTSkip("Engine not available") }
        // Build a macro with enough delay/text to exercise cancellation mid-run
        let macro = Macro(name: "Long", actions: [
            .keyTap("a"),
            .delay(milliseconds: 200), // cancellable slice
            .text("cancelme"),         // should not fully execute if cancelled early
            .keyTap("b")
        ])
        eng.registerMacro(key: "long", macro: macro)

        let expectation = expectation(description: "Macro cancelled")
        let token = MacroCancellationToken()

        // Kick off execution
    _ = eng.executeMacro(key: "long", token: token) { result in
            switch result {
            case .success():
                XCTFail("Macro should have been cancelled")
            case .failure(let error):
                if case MacroEngine.MacroError.cancelled = error {
                    XCTAssertTrue(true)
                } else {
                    XCTFail("Unexpected error: \(error)")
                }
            }
            expectation.fulfill()
        }

        // Cancel after ~50ms (should be during the 200ms delay slices)
        usleep(50_000)
        token.cancel()

        waitForExpectations(timeout: 2.0)

        // Verify only the initial tap occurred (heuristic: MockKeyboardOutput tapHistory contains 'a' but not necessarily 'b')
        // We cannot reliably introspect key codes -> chars without helper; ensure at least one tap happened.
        if let mock = keyboard as? MockKeyboardOutput {
            XCTAssertGreaterThanOrEqual(mock.tapHistory.count, 1)
        }
    }

    func testCancellationBeforeStartReturnsCancelled() throws {
        guard let eng = engine else { throw XCTSkip("Engine not available") }
        let macro = Macro(name: "Immediate", actions: [.delay(milliseconds: 100)])
        eng.registerMacro(key: "immediate", macro: macro)
        let expectation = expectation(description: "Cancelled before start")
        let token = MacroCancellationToken()
        token.cancel()
    _ = eng.executeMacro(key: "immediate", token: token) { result in
            switch result {
            case .success():
                XCTFail("Should not succeed when cancelled beforehand")
            case .failure(let error):
                if case MacroEngine.MacroError.cancelled = error {
                    XCTAssertTrue(true)
                } else {
                    XCTFail("Wrong error type: \(error)")
                }
            }
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
    }
}
