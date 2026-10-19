/// The packed rotation byte of an `nTRN` frame (`_r`): a row-major 3×3
/// signed permutation matrix.
///
/// Bits 0–1: column of the non-zero entry in row 0; bits 2–3: in row 1
/// (row 2 takes the remaining column). Bits 4–6: sign of rows 0–2 (1 = −1).
public struct VoxRotation: Hashable, Sendable {
    /// For each row, the column holding the non-zero entry.
    public let columns: SIMD3<Int32>
    /// For each row, +1 or −1.
    public let signs: SIMD3<Int32>

    public static let identity = VoxRotation(columns: [0, 1, 2], signs: [1, 1, 1])

    public init(columns: SIMD3<Int32>, signs: SIMD3<Int32>) {
        self.columns = columns
        self.signs = signs
    }

    /// Returns nil for bit patterns that aren't a permutation.
    public init?(packed: UInt8) {
        let c0 = Int32(packed & 3), c1 = Int32((packed >> 2) & 3)
        guard c0 < 3, c1 < 3, c0 != c1 else { return nil }
        columns = [c0, c1, 3 - c0 - c1]
        signs = [
            packed & 0x10 == 0 ? 1 : -1,
            packed & 0x20 == 0 ? 1 : -1,
            packed & 0x40 == 0 ? 1 : -1,
        ]
    }

    public func apply(_ v: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(
            Float(signs.x) * v[Int(columns.x)],
            Float(signs.y) * v[Int(columns.y)],
            Float(signs.z) * v[Int(columns.z)]
        )
    }

    /// `self ∘ other`: applies `other` first.
    public func concatenating(_ other: VoxRotation) -> VoxRotation {
        var cols = SIMD3<Int32>(), sgns = SIMD3<Int32>()
        for row in 0..<3 {
            let mid = Int(columns[row])
            cols[row] = other.columns[mid]
            sgns[row] = signs[row] * other.signs[mid]
        }
        return VoxRotation(columns: cols, signs: sgns)
    }

    /// Size of a box after rotation (absolute extents).
    public func applyToSize(_ s: SIMD3<Int32>) -> SIMD3<Int32> {
        SIMD3(s[Int(columns.x)], s[Int(columns.y)], s[Int(columns.z)])
    }

    /// The matrix as rows, for consumers that want one.
    public var rows: [SIMD3<Float>] {
        (0..<3).map { row in
            var r = SIMD3<Float>(repeating: 0)
            r[Int(columns[row])] = Float(signs[row])
            return r
        }
    }
}
