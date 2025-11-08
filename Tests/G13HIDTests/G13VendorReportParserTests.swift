import XCTest
@testable import G13HID

final class G13VendorReportParserTests: XCTestCase {
    func testInitialPressEmitsDown() {
        let parser = G13VendorReportParser()
        // First report already has G1 pressed (byte2 bit0)
        let changes = parser.process(report: [0,0,0b00000001,0,0,0,0])
        XCTAssertEqual(changes, [GKeyStateChange(gKey: 1, down: true)], "Initial pressed bit should emit DOWN event on first report")
    }

    func testNoPreviousReportYieldsNoChanges() {
        let parser = G13VendorReportParser()
        let changes = parser.process(report: [0,0,0,0,0,0,0])
        XCTAssertTrue(changes.isEmpty)
    }

    func testSingleBitPressAndRelease() {
        let parser = G13VendorReportParser()
        // First baseline (no prior diff)
        _ = parser.process(report: [0,0,0b00000000,0,0,0,0])
        // Press G1 (byte 2 bit0)
        let pressChanges = parser.process(report: [0,0,0b00000001,0,0,0,0])
        XCTAssertEqual(pressChanges, [GKeyStateChange(gKey: 1, down: true)])
        // Release G1
        let releaseChanges = parser.process(report: [0,0,0b00000000,0,0,0,0])
        XCTAssertEqual(releaseChanges, [GKeyStateChange(gKey: 1, down: false)])
    }

    func testMultipleBitsInDifferentBytes() {
        let parser = G13VendorReportParser()
        _ = parser.process(report: [0,0,0,0,0,0,0])
        // Press G8 (byte2 bit7) and G9 (byte3 bit0) and G22 (byte4 bit5)
        let changes = parser.process(report: [0,0,0b10000000,0b00000001,0b00100000,0,0])
        // Order is deterministic by iteration order (byte 2 then 3 then 4, lower bits ascending)
        XCTAssertEqual(changes, [
            GKeyStateChange(gKey: 8, down: true),
            GKeyStateChange(gKey: 9, down: true),
            GKeyStateChange(gKey: 22, down: true)
        ])
    }

    func testNoChangesReturnsEmpty() {
        let parser = G13VendorReportParser()
        _ = parser.process(report: [0,0,0xFF,0xAA,0x3F,0,0])
        let changes = parser.process(report: [0,0,0xFF,0xAA,0x3F,0,0])
        XCTAssertTrue(changes.isEmpty)
    }
}
