import Foundation

/// Public representation of a bit position within a vendor raw report.
public struct BitCoordinate: Hashable, Codable {
    public let byte: Int
    public let bit: Int
    public init(byte: Int, bit: Int) { self.byte = byte; self.bit = bit }
}

/// Mapping of raw report (byte,bit) positions to G key numbers (1-22).
/// Based on heuristic analysis of Logitech G13 7-byte reports.
public let G13BitToGKeyMapping: [BitCoordinate: Int] = {
    var dict: [BitCoordinate: Int] = [:]
    for bit in 0..<8 { dict[BitCoordinate(byte: 2, bit: bit)] = bit + 1 }      // G1..G8
    for bit in 0..<8 { dict[BitCoordinate(byte: 3, bit: bit)] = bit + 9 }      // G9..G16
    for bit in 0..<6 { dict[BitCoordinate(byte: 4, bit: bit)] = bit + 17 }     // G17..G22
    return dict
}()
