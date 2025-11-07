import XCTest
@testable import G13HID
import ApplicationServices

final class CGEventKeyboardTests: XCTestCase {
    func testAccessibilityCheckDoesNotCrash() {
        // This should always construct (it will log if accessibility missing)
        let cg = CGEventKeyboard()
        // Can't assert AXIsProcessTrusted in CI reliably, just ensure instance exists
        XCTAssertNotNil(cg)
    }

    func testTapKeyWhenAccessibilityMissing() throws {
        let cg = CGEventKeyboard()
        // If accessibility is denied, tapping should throw accessibilityDenied.
        // If granted, it should succeed. We'll accept either but ensure no crash.
        do {
            try cg.tapKey(.a)
        } catch CGEventKeyboard.KeyboardError.accessibilityDenied {
            // acceptable in test environment
        } catch {
            // Other errors are not expected
            XCTFail("Unexpected error: \(error)")
        }
    }
}
