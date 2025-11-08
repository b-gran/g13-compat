import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(HIDDeviceTests.allTests),
        testCase(VendorJoystickFallbackTests.allTests)
    ]
}
#endif 