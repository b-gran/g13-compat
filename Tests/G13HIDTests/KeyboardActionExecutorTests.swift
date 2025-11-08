import XCTest
@testable import G13HID

final class KeyboardActionExecutorTests: XCTestCase {
    private var mockKeyboard: MockKeyboardOutput! = nil
    private var macroEngine: MacroEngine! = nil
    private var executor: KeyboardActionExecutor! = nil

    override func setUp() {
        super.setUp()
        mockKeyboard = MockKeyboardOutput()
        macroEngine = MacroEngine(keyboard: mockKeyboard)
        executor = KeyboardActionExecutor(keyboard: mockKeyboard, macroEngine: macroEngine)
    }

    override func tearDown() {
        executor = nil
        macroEngine = nil
        mockKeyboard = nil
        super.tearDown()
    }

    func testKeyTapSuccess() throws {
        let result = executor.perform(.keyTap("a"))
        switch result {
        case .success: XCTAssertEqual(mockKeyboard.tapHistory.count, 1)
        case .failure(let error): XCTFail("Unexpected failure: \(error)")
        }
    }

    func testInvalidKeyTapFails() throws {
        let result = executor.perform(.keyTap("invalidKey"))
        switch result {
        case .success: XCTFail("Expected failure for invalid key")
        case .failure(let error):
            guard case KeyboardActionError.invalidKey("invalidKey") = error else {
                XCTFail("Wrong error: \(error)"); return
            }
        }
    }

    func testMacroSuccessCallbackInvoked() throws {
        let exp = expectation(description: "Macro completion")
        macroEngine.registerMacro(key: "hello", macro: Macro(name: "hello", actions: [.keyTap("a"), .keyTap("b")]))
        let dispatchResult = executor.perform(.macro("hello")) { result in
            switch result {
            case .success:
                XCTAssertEqual(self.mockKeyboard.tapHistory.count, 2)
            case .failure(let error):
                XCTFail("Macro failed: \(error)")
            }
            exp.fulfill()
        }
        // Dispatch should be success even though async
        if case .failure(let error) = dispatchResult { XCTFail("Dispatch unexpectedly failed: \(error)") }
        waitForExpectations(timeout: 1.0)
    }

    func testMacroNotFoundFailsImmediately() throws {
        let exp = expectation(description: "Macro completion fails")
        let dispatchResult = executor.perform(.macro("missing")) { result in
            switch result {
            case .success: XCTFail("Should not succeed")
            case .failure(let error):
                guard case KeyboardActionError.macroNotFound("missing") = error else {
                    XCTFail("Wrong error: \(error)"); return
                }
            }
            exp.fulfill()
        }
        // Dispatch should be failure for missing macro
        if case .success = dispatchResult { XCTFail("Dispatch should fail for missing macro") }
        waitForExpectations(timeout: 0.2)
    }

    func testKeyDownAndUpMaintainPressedState() throws {
        // Press down 'a'
        let downResult = executor.perform(.keyDown("a"))
        if case .failure(let error) = downResult { XCTFail("keyDown failed: \(error)") }
        XCTAssertEqual(mockKeyboard.pressed.count, 1)

        // Redundant press should still keep one entry
        _ = executor.perform(.keyDown("a"))
        XCTAssertEqual(mockKeyboard.pressed.count, 1)

        // Release
        let upResult = executor.perform(.keyUp("a"))
        if case .failure(let error) = upResult { XCTFail("keyUp failed: \(error)") }
        XCTAssertEqual(mockKeyboard.pressed.count, 0)
    }
}
