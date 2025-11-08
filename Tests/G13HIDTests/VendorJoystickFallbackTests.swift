import XCTest
@testable import G13HID

final class VendorJoystickFallbackTests: XCTestCase {
    /// Minimal stub to invoke internal extraction without real HID stack.
    func testVendorReportAxisExtraction() throws {
        // Create device using test config path (nil -> default) - may throw permission error; skip if so.
        let device: HIDDevice
        do {
            device = try HIDDevice()
        } catch HIDDeviceError.permissionDenied {
            throw XCTSkip("Permission denied opening HID manager – skipping vendor joystick test")
        } catch {
            throw XCTSkip("Unexpected HID init error: \(error)")
        }

        // Synthetic 7-byte vendor report; bytes[0]=0x90 (X right), bytes[1]=0x40 (Y up after inversion)
        let report: [UInt8] = [0x90, 0x40, 0x00, 0x00, 0x80, 0x00, 0x00]
        guard let (x, y) = device.extractVendorJoystickAxes(report: report) else {
            XCTFail("Axis extraction returned nil")
            return
        }
        XCTAssertEqual(x, 0x90)
        XCTAssertEqual(y, 0x40)

        // Normalization expectation
        let normX = Double(x - 128) / 128.0
        let normY = -Double(y - 128) / 128.0
        XCTAssertGreaterThan(normX, 0.0, "Expect positive X for right movement")
        XCTAssertGreaterThan(normY, 0.0, "Expect positive Y (after inversion) for upward movement")
    }
}

#if !canImport(ObjectiveC)
extension VendorJoystickFallbackTests {
    static var allTests = [
        ("testVendorReportAxisExtraction", testVendorReportAxisExtraction)
    ]
}
#endif