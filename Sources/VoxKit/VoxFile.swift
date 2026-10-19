import Foundation

/// An RGBA color, 8 bits per channel.
public struct VoxColor: Hashable, Sendable {
    public var r, g, b, a: UInt8
    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
}

/// One model: a dense grid of palette indices (0 = empty).
public struct VoxModel: Sendable {
    public let sizeX, sizeY, sizeZ: Int
    /// Indexed `x + y * sizeX + z * sizeX * sizeY`.
    public var cells: [UInt8]
    public private(set) var voxelCount = 0

    public init(sizeX: Int, sizeY: Int, sizeZ: Int) {
        self.sizeX = sizeX; self.sizeY = sizeY; self.sizeZ = sizeZ
        cells = [UInt8](repeating: 0, count: sizeX * sizeY * sizeZ)
    }

    /// Fills from packed `XYZI` records, dropping out-of-bounds voxels.
    init(sizeX: Int, sizeY: Int, sizeZ: Int, xyzi: UnsafeBufferPointer<UInt8>) {
        self.init(sizeX: sizeX, sizeY: sizeY, sizeZ: sizeZ)
        let sxy = sizeX * sizeY
        var count = 0
        cells.withUnsafeMutableBufferPointer { cells in
            var i = 0
            while i + 3 < xyzi.count {
                let x = Int(xyzi[i]), y = Int(xyzi[i + 1]), z = Int(xyzi[i + 2]), c = xyzi[i + 3]
                i += 4
                guard x < sizeX, y < sizeY, z < sizeZ, c != 0 else { continue }
                let k = x + y * sizeX + z * sxy
                if cells[k] == 0 { count += 1 }
                cells[k] = c
            }
        }
        voxelCount = count
    }

    public subscript(x: Int, y: Int, z: Int) -> UInt8 {
        get { cells[x + y * sizeX + z * sizeX * sizeY] }
        set {
            let i = x + y * sizeX + z * sizeX * sizeY
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
