import XCTest
import Foundation
@testable import G13HID

final class HIDDeviceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Add any setup code here
    }
    
    override func tearDown() {
        // Add any cleanup code here
        super.tearDown()
    }
    
    func testDeviceInitialization() {
        do {
            let device = try HIDDevice()
            XCTAssertNotNil(device, "HIDDevice should be successfully initialized")
        } catch HIDDeviceError.permissionDenied {
            // This is expected when running without proper permissions
            log("Test skipped: HID access permission denied (this is normal when running without sudo)")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testErrorHandling() {
        do {
            let device = try HIDDevice()
            XCTAssertNotNil(device)
        } catch HIDDeviceError.permissionDenied {
            // Expected case - test passes
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}

#if swift(>=5.5)
extension HIDDeviceTests {
    // This allows the test to be discovered in Swift Package Manager
    static var allTests = [
        ("testDeviceInitialization", testDeviceInitialization),
        ("testErrorHandling", testErrorHandling),
    ]
}
#endif 