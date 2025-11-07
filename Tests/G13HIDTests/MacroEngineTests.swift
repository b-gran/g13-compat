import XCTest
@testable import G13HID

final class MacroEngineTests: XCTestCase {
    var keyboard: KeyboardOutput?
    var engine: MacroEngine?

    override func setUp() {
        super.setUp()
        keyboard = MockKeyboardOutput()
        if let kb = keyboard {
            engine = MacroEngine(keyboard: kb)
        }
    }

    override func tearDown() {
        engine = nil
        keyboard = nil
        super.tearDown()
    }

    func testEngineInitialization() throws {
    let kb = MockKeyboardOutput()
    let eng = MacroEngine(keyboard: kb)
        XCTAssertNotNil(eng)
    }

    func testRegisterMacro() throws {
        guard let eng = engine else {
            throw XCTSkip("Engine not available")
        }

        let macro = Macro(name: "Test", actions: [.keyTap("a")])
        eng.registerMacro(key: "test1", macro: macro)

        let retrieved = eng.getMacro(key: "test1")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.name, "Test")
    }

    func testUnregisterMacro() throws {
        guard let eng = engine else {
            throw XCTSkip("Engine not available")
        }

        let macro = Macro(name: "Test", actions: [.keyTap("a")])
        eng.registerMacro(key: "test1", macro: macro)

        XCTAssertNotNil(eng.getMacro(key: "test1"))

        eng.unregisterMacro(key: "test1")
        XCTAssertNil(eng.getMacro(key: "test1"))
    }

    func testGetAllMacros() throws {
        guard let eng = engine else {
            throw XCTSkip("Engine not available")
        }

        let macro1 = Macro(name: "Test1", actions: [.keyTap("a")])
        let macro2 = Macro(name: "Test2", actions: [.keyTap("b")])

        eng.registerMacro(key: "test1", macro: macro1)
        eng.registerMacro(key: "test2", macro: macro2)

        let allMacros = eng.getAllMacros()
        XCTAssertEqual(allMacros.count, 2)
        XCTAssertNotNil(allMacros["test1"])
        XCTAssertNotNil(allMacros["test2"])
    }

    func testExecuteSimpleMacro() throws {
        guard let eng = engine else {
            throw XCTSkip("Engine not available")
        }

        let macro = Macro(name: "Simple", actions: [
            .keyTap("a"),
            .delay(milliseconds: 10),
            .keyTap("b")
        ])

        eng.registerMacro(key: "simple", macro: macro)

        let expectation = self.expectation(description: "Macro execution")

        eng.executeMacro(key: "simple") { result in
            switch result {
            case .success():
                XCTAssertTrue(true)
            case .failure(let error):
                XCTFail("Macro execution failed: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    func testExecuteNonexistentMacro() throws {
        guard let eng = engine else {
            throw XCTSkip("Engine not available")
        }

        let expectation = self.expectation(description: "Macro not found")

        eng.executeMacro(key: "nonexistent") { result in
            switch result {
            case .success():
                XCTFail("Should not succeed")
            case .failure(let error):
                if case MacroEngine.MacroError.macroNotFound = error {
                    XCTAssertTrue(true)
                } else {
                    XCTFail("Wrong error type: \(error)")
                }
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    func testMacroWithInvalidKey() throws {
        guard let eng = engine else {
            throw XCTSkip("Engine not available")
        }

        let macro = Macro(name: "Invalid", actions: [
            .keyTap("invalidkey")
        ])

        eng.registerMacro(key: "invalid", macro: macro)

        let expectation = self.expectation(description: "Invalid key")

        eng.executeMacro(key: "invalid") { result in
            switch result {
            case .success():
                XCTFail("Should not succeed with invalid key")
            case .failure(let error):
                if case MacroEngine.MacroError.invalidKey = error {
                    XCTAssertTrue(true)
                } else {
                    XCTFail("Wrong error type: \(error)")
                }
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    func testMacroWithPressRelease() throws {
        guard let eng = engine else {
            throw XCTSkip("Engine not available")
        }

        let macro = Macro(name: "PressRelease", actions: [
            .keyPress("w"),
            .delay(milliseconds: 50),
            .keyRelease("w")
        ])

        eng.registerMacro(key: "pressrelease", macro: macro)

        let expectation = self.expectation(description: "Press/Release")

        eng.executeMacro(key: "pressrelease") { result in
            switch result {
            case .success():
                XCTAssertTrue(true)
            case .failure(let error):
                XCTFail("Failed: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 1.0)
    }

    func testMacroWithText() throws {
        guard let eng = engine else {
            throw XCTSkip("Engine not available")
        }

        let macro = Macro(name: "Text", actions: [
            .text("hello")
        ])

        eng.registerMacro(key: "text", macro: macro)

        let expectation = self.expectation(description: "Text typing")

        eng.executeMacro(key: "text") { result in
            switch result {
            case .success():
                XCTAssertTrue(true)
            case .failure(let error):
                XCTFail("Failed: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2.0)
    }

    func testMacroHelpers() {
        // Test simple tap helper
        let tapMacro = Macro.simpleTap("a")
        XCTAssertEqual(tapMacro.actions.count, 1)

        // Test text helper
        let textMacro = Macro.typeText("test")
        XCTAssertEqual(textMacro.actions.count, 1)

        // Test key combo helper
        let comboMacro = Macro.keyCombo(keys: ["a", "b"])
        XCTAssertTrue(comboMacro.actions.count > 2)
    }

    func testMacroActionCodable() throws {
        // Test encoding and decoding of macro actions
        let actions: [MacroAction] = [
            .keyPress("a"),
            .keyRelease("b"),
            .keyTap("c"),
            .delay(milliseconds: 100),
            .text("hello")
        ]

        let macro = Macro(name: "Codable", actions: actions)

        let encoder = JSONEncoder()
        let data = try encoder.encode(macro)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Macro.self, from: data)

        XCTAssertEqual(decoded.name, macro.name)
        XCTAssertEqual(decoded.actions.count, macro.actions.count)
    }

    func testComplexMacro() throws {
        guard let eng = engine else {
            throw XCTSkip("Engine not available")
        }

        let macro = Macro(name: "Complex", actions: [
            .keyPress("w"),
            .delay(milliseconds: 10),
            .keyPress("a"),
            .delay(milliseconds: 50),
            .keyRelease("w"),
            .delay(milliseconds: 10),
            .keyRelease("a"),
            .delay(milliseconds: 10),
            .keyTap("space"),
            .delay(milliseconds: 10),
            .text("hi")
        ])

        eng.registerMacro(key: "complex", macro: macro)

        let expectation = self.expectation(description: "Complex macro")

        eng.executeMacro(key: "complex") { result in
            switch result {
            case .success():
                XCTAssertTrue(true)
            case .failure(let error):
                XCTFail("Failed: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2.0)
    }
}
