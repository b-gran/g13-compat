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
    // Use shared mapping so tests can validate coverage.
    private let mapping = G13BitToGKeyMapping

    func process(report: [UInt8]) -> [GKeyStateChange] {
        guard report.count >= 5 else { // Need at least up to byte index 4
            lastReport = report
            return []
        }
        var changes: [GKeyStateChange] = []

        if let previous = lastReport, previous.count == report.count {
            // Diff with previous report
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
                            let beforeHex = String(format: "%02X", before)
                            let afterHex = String(format: "%02X", after)
                            let stateStr = down ? "DOWN" : "UP"
                            logDebug("RawReportParser: byte=\(byteIndex) bit=\(bit) -> G\(gKey) \(stateStr) before=\(beforeHex) after=\(afterHex)")
                        } else {
                            logDebug("RawReportParser: unmapped bit change byte=\(byteIndex) bit=\(bit)")
                        }
                    }
                }
            }
        } else {
            // First report: emit DOWN events for any currently pressed bits.
            for byteIndex in [2,3,4] {
                let value = report[byteIndex]
                let maxBit = (byteIndex == 4) ? 6 : 8
                if value == 0 { continue }
                for bit in 0..<maxBit {
                    let mask: UInt8 = 1 << bit
                    if (value & mask) != 0 {
                        let coord = BitCoordinate(byte: byteIndex, bit: bit)
                        if let gKey = mapping[coord] {
                            changes.append(GKeyStateChange(gKey: gKey, down: true))
                            let valueHex = String(format: "%02X", value)
                            logDebug("RawReportParser initial: byte=\(byteIndex) bit=\(bit) -> G\(gKey) DOWN initialValue=\(valueHex)")
                        }
                    }
                }
            }
        }
        lastReport = report
        return changes
    }
}
