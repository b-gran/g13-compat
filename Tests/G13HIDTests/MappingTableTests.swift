import XCTest
@testable import G13HID

final class MappingTableTests: XCTestCase {
    func testMappingCoverageAndUniqueness() {
        // Expect exactly 22 G keys
        XCTAssertEqual(Set(G13BitToGKeyMapping.values).count, 22, "There should be 22 unique G keys mapped")
        XCTAssertEqual(G13BitToGKeyMapping.count, 22, "Exactly 22 bit coordinates should be mapped")

        // Verify range 1...22
        let expected = Set(1...22)
        XCTAssertEqual(Set(G13BitToGKeyMapping.values), expected, "Mapped G keys should cover 1..22")

        // Ensure no duplicate coordinates map to different keys (dictionary property ensures uniqueness)
        // Additional structural checks: bytes used are only 2,3,4; bits constraints respected.
        for (coord, gKey) in G13BitToGKeyMapping {
            XCTAssertTrue([2,3,4].contains(coord.byte), "Unexpected byte index \(coord.byte)")
            if coord.byte == 4 {
                XCTAssertTrue((0..<6).contains(coord.bit), "Byte 4 should only use bits 0..5 (got bit \(coord.bit))")
            } else {
                XCTAssertTrue((0..<8).contains(coord.bit), "Byte \(coord.byte) should only use bits 0..7")
            }
            XCTAssertTrue((1...22).contains(gKey), "G key out of expected range: G\(gKey)")
        }
    }
}
