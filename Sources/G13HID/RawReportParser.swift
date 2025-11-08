import Foundation

/// Represents a change in state for a single G key.
public struct GKeyStateChange: Equatable {
    public let gKey: Int
    public let down: Bool
}

/// Protocol for parsing raw vendor reports into G key state changes.
public protocol RawReportParser {
    /// Processes a raw report and returns any detected G key press/release changes.
    /// Implementations may keep internal state (e.g. previous report) to diff transitions.
    func process(report: [UInt8]) -> [GKeyStateChange]
}

/// Parser for 7-byte Logitech G13 input reports on macOS when the system does not expose per-button elements.
/// Mapping logic based on heuristic analysis:
///  Byte index 2 bits 0..7 => G1..G8
///  Byte index 3 bits 0..7 => G9..G16
///  Byte index 4 bits 0..5 => G17..G22 (bits 6 unused, 7 constant axis base)
final class G13VendorReportParser: RawReportParser {
    private var lastReport: [UInt8]? = nil

    private struct BitCoordinate: Hashable { let byte: Int; let bit: Int }
    private let mapping: [BitCoordinate: Int] = {
        var dict: [BitCoordinate: Int] = [:]
        for bit in 0..<8 { dict[BitCoordinate(byte: 2, bit: bit)] = bit + 1 }      // G1..G8
        for bit in 0..<8 { dict[BitCoordinate(byte: 3, bit: bit)] = bit + 9 }      // G9..G16
        for bit in 0..<6 { dict[BitCoordinate(byte: 4, bit: bit)] = bit + 17 }     // G17..G22
        return dict
    }()

    func process(report: [UInt8]) -> [GKeyStateChange] {
        guard report.count >= 5 else { // Need at least up to byte index 4
            lastReport = report
            return []
        }
        var changes: [GKeyStateChange] = []
        if let previous = lastReport, previous.count == report.count {
            for byteIndex in [2,3,4] { // Relevant bytes
                let before = previous[byteIndex]
                let after = report[byteIndex]
                let delta = before ^ after
                if delta == 0 { continue }
                let maxBit = (byteIndex == 4) ? 6 : 8
                for bit in 0..<maxBit {
                    let mask: UInt8 = 1 << bit
                    if (delta & mask) != 0 {
                        let down = (after & mask) != 0
                        let coord = BitCoordinate(byte: byteIndex, bit: bit)
                        if let gKey = mapping[coord] {
                            changes.append(GKeyStateChange(gKey: gKey, down: down))
                            logDebug("RawReportParser: byte=\(byteIndex) bit=\(bit) -> G\(gKey) \(down ? "DOWN" : "UP") before=\(String(format: "%02X", before)) after=\(String(format: "%02X", after))")
                        } else {
                            logDebug("RawReportParser: unmapped bit change byte=\(byteIndex) bit=\(bit)")
                        }
                    }
                }
            }
        }
        lastReport = report
        return changes
    }
}
