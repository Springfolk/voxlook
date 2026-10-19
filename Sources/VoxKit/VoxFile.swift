import Foundation

/// An RGBA color, 8 bits per channel.
public struct VoxColor: Hashable, Sendable {
    public var r, g, b, a: UInt8
    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
}

/// One model: palette indices (0 = empty) on a `sizeX × sizeY × sizeZ` box.
///
/// Only the occupied part of the box is stored, as a dense grid starting at
/// `origin` — models are often 256³ boxes with a small object inside.
public struct VoxModel: Sendable {
    public let sizeX, sizeY, sizeZ: Int
    /// Corner of the stored grid within the model box.
    public private(set) var origin: SIMD3<Int>
    /// Extent of the stored grid.
    public private(set) var extent: SIMD3<Int>
    /// Indexed `x + y * extent.x + z * extent.x * extent.y`, relative to `origin`.
    public private(set) var cells: [UInt8]
    public private(set) var voxelCount = 0

    /// An empty model storing its whole box.
    public init(sizeX: Int, sizeY: Int, sizeZ: Int) {
        self.sizeX = sizeX; self.sizeY = sizeY; self.sizeZ = sizeZ
        origin = .zero
        extent = SIMD3(sizeX, sizeY, sizeZ)
        cells = [UInt8](repeating: 0, count: sizeX * sizeY * sizeZ)
    }

    /// Fills from packed `XYZI` records, dropping out-of-bounds voxels and
    /// storing only their bounding box.
    init(sizeX: Int, sizeY: Int, sizeZ: Int, xyzi: UnsafeBufferPointer<UInt8>) {
        self.sizeX = sizeX; self.sizeY = sizeY; self.sizeZ = sizeZ
        var lo = SIMD3(sizeX, sizeY, sizeZ), hi = SIMD3<Int>(repeating: -1)
        var i = 0
        while i + 3 < xyzi.count {
            let p = SIMD3(Int(xyzi[i]), Int(xyzi[i + 1]), Int(xyzi[i + 2]))
            if xyzi[i + 3] != 0, p.x < sizeX, p.y < sizeY, p.z < sizeZ {
                lo = pointwiseMin(lo, p); hi = pointwiseMax(hi, p)
            }
            i += 4
        }
        guard hi.x >= 0 else {
            origin = .zero; extent = .zero; cells = []
            return
        }
        origin = lo
        extent = hi &- lo &+ 1
        cells = [UInt8](repeating: 0, count: extent.x * extent.y * extent.z)
        let (ex, exy) = (extent.x, extent.x * extent.y)
        var count = 0
        cells.withUnsafeMutableBufferPointer { cells in
            var i = 0
            while i + 3 < xyzi.count {
                let x = Int(xyzi[i]), y = Int(xyzi[i + 1]), z = Int(xyzi[i + 2]), c = xyzi[i + 3]
                i += 4
                guard x < sizeX, y < sizeY, z < sizeZ, c != 0 else { continue }
                let k = (x - lo.x) + (y - lo.y) * ex + (z - lo.z) * exy
                if cells[k] == 0 { count += 1 }
                cells[k] = c
            }
        }
        voxelCount = count
    }

    /// In model-box coordinates. Writes must fall inside the stored grid.
    public subscript(x: Int, y: Int, z: Int) -> UInt8 {
        get {
            let p = SIMD3(x, y, z) &- origin
            guard all(p .>= 0), all(p .< extent) else { return 0 }
            return cells[p.x + p.y * extent.x + p.z * extent.x * extent.y]
        }
        set {
            let p = SIMD3(x, y, z) &- origin
            precondition(all(p .>= 0) && all(p .< extent), "write outside the stored grid")
            let i = p.x + p.y * extent.x + p.z * extent.x * extent.y
            voxelCount += (cells[i] == 0 ? 1 : 0) - (newValue == 0 ? 1 : 0)
            cells[i] = newValue
        }
    }
}

/// A node of the scene graph introduced in MagicaVoxel 0.99.
public enum VoxNode: Sendable {
    case transform(VoxTransformNode)
    case group(children: [Int])
    case shape(modelIDs: [Int])
}

public struct VoxTransformNode: Sendable {
    public var name: String?
    public var hidden: Bool
    public var child: Int
    public var layer: Int
    public var rotation: VoxRotation
    public var translation: SIMD3<Int32>
}

public struct VoxLayer: Sendable {
    public var name: String?
    public var hidden: Bool
}

/// A parsed `.vox` file.
public struct VoxFile: Sendable {
    public var version: Int
    public var models: [VoxModel] = []
    /// 256 entries; index 0 is unused (empty).
    public var palette: [VoxColor] = VoxPalette.default
    public var nodes: [Int: VoxNode] = [:]
    public var layers: [Int: VoxLayer] = [:]

    public init(version: Int) { self.version = version }
}

public enum VoxError: Error, Equatable, CustomStringConvertible {
    case notAVoxFile
    case truncated
    case malformed(String)

    public var description: String {
        switch self {
        case .notAVoxFile: return "not a MagicaVoxel .vox file"
        case .truncated: return "file is truncated"
        case .malformed(let why): return "malformed file: \(why)"
        }
    }
}
