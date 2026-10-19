import Foundation

extension VoxFile {
    /// Largest model edge we accept. The format caps models at 256; anything
    /// bigger is a corrupt or hostile file and would allocate gigabytes.
    static let maxModelEdge = 2048

    public init(contentsOf url: URL) throws {
        try self.init(data: try Data(contentsOf: url, options: .mappedIfSafe))
    }

    /// Parses a `.vox` file. Unknown chunks are skipped.
    ///
    /// Format reference: https://github.com/ephtracy/voxel-model/tree/master
    public init(data: Data) throws {
        var r = ByteReader(data)
        guard r.remaining >= 8, try r.fourCC() == "VOX " else { throw VoxError.notAVoxFile }
        self.init(version: Int(try r.int32()))

        guard try r.fourCC() == "MAIN" else { throw VoxError.malformed("missing MAIN chunk") }
        let mainContent = Int(try r.int32()), mainChildren = Int(try r.int32())
        try r.skip(mainContent)
        var children = try r.sub(min(mainChildren, r.remaining))

        var pendingSize: (Int, Int, Int)?
        while children.remaining >= 12 {
            let id = try children.fourCC()
            let contentSize = Int(try children.int32()), childSize = Int(try children.int32())
            guard contentSize >= 0, childSize >= 0 else { throw VoxError.malformed("negative chunk size") }
            var c = try children.sub(contentSize)
            try children.skip(childSize)

            switch id {
            case "SIZE":
                let x = Int(try c.int32()), y = Int(try c.int32()), z = Int(try c.int32())
                let edge = 1...Self.maxModelEdge
                guard edge ~= x, edge ~= y, edge ~= z else { throw VoxError.malformed("model size \(x)×\(y)×\(z)") }
                pendingSize = (x, y, z)
            case "XYZI":
                guard let (sx, sy, sz) = pendingSize else { throw VoxError.malformed("XYZI without SIZE") }
                pendingSize = nil
                let count = Int(try c.int32())
                guard count >= 0, count <= c.remaining / 4 else { throw VoxError.truncated }
                models.append(try c.withBytes(count * 4) { VoxModel(sizeX: sx, sizeY: sy, sizeZ: sz, xyzi: $0) })
            case "RGBA":
                // Entry k colours palette index k + 1; the 256th entry is unused.
                var colors = [VoxColor(r: 0, g: 0, b: 0, a: 0)]
                for _ in 0..<255 {
                    colors.append(VoxColor(r: try c.byte(), g: try c.byte(), b: try c.byte(), a: try c.byte()))
                }
                palette = colors
            case "nTRN":
                let nodeID = Int(try c.int32())
                let attrs = try c.dict()
                let child = Int(try c.int32())
                _ = try c.int32()  // reserved
                let layer = Int(try c.int32())
                let frames = Int(try c.int32())
                var rotation = VoxRotation.identity, translation = SIMD3<Int32>(0, 0, 0)
                if frames > 0 {
                    let f = try c.dict()  // first frame only; animation isn't previewed
                    if let s = f["_r"], let b = UInt8(s), let rot = VoxRotation(packed: b) { rotation = rot }
                    if let s = f["_t"] {
                        let parts = s.split(separator: " ").compactMap { Int32($0) }
                        if parts.count == 3 { translation = SIMD3(parts[0], parts[1], parts[2]) }
                    }
                }
                nodes[nodeID] = .transform(VoxTransformNode(
                    name: attrs["_name"], hidden: attrs["_hidden"] == "1",
                    child: child, layer: layer, rotation: rotation, translation: translation))
            case "nGRP":
                let nodeID = Int(try c.int32())
                _ = try c.dict()
                let n = Int(try c.int32())
                guard n >= 0, n <= c.remaining / 4 else { throw VoxError.truncated }
                nodes[nodeID] = .group(children: try (0..<n).map { _ in Int(try c.int32()) })
            case "nSHP":
                let nodeID = Int(try c.int32())
                _ = try c.dict()
                let n = Int(try c.int32())
                guard n >= 0, n <= c.remaining / 8 else { throw VoxError.truncated }
                var ids: [Int] = []
                for _ in 0..<n {
                    ids.append(Int(try c.int32()))
                    _ = try c.dict()
                }
                nodes[nodeID] = .shape(modelIDs: ids)
            case "LAYR":
                let layerID = Int(try c.int32())
                let attrs = try c.dict()
                layers[layerID] = VoxLayer(name: attrs["_name"], hidden: attrs["_hidden"] == "1")
            default:
                break
            }
        }
        if models.isEmpty { throw VoxError.malformed("no models") }
    }
}

/// Bounds-checked little-endian reader. Every read throws on overrun.
struct ByteReader {
    private let bytes: [UInt8]
    private var offset: Int
    private let end: Int

    init(_ data: Data) {
        bytes = [UInt8](data)
        offset = 0
        end = bytes.count
    }

    private init(_ bytes: [UInt8], range: Range<Int>) {
        self.bytes = bytes  // copy-on-write: shares storage, no copy
        offset = range.lowerBound
        end = range.upperBound
    }

    var remaining: Int { end - offset }

    mutating func byte() throws -> UInt8 {
        guard offset < end else { throw VoxError.truncated }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func int32() throws -> Int32 {
        guard remaining >= 4 else { throw VoxError.truncated }
        let v = UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
        offset += 4
        return Int32(bitPattern: v)
    }

    mutating func fourCC() throws -> String {
        guard remaining >= 4 else { throw VoxError.truncated }
        defer { offset += 4 }
        return String(decoding: bytes[offset..<offset + 4], as: UTF8.self)
    }

    mutating func skip(_ n: Int) throws {
        guard n >= 0, n <= remaining else { throw VoxError.truncated }
        offset += n
    }

    /// A reader over the next `n` bytes; advances past them.
    mutating func sub(_ n: Int) throws -> ByteReader {
        guard n >= 0, n <= remaining else { throw VoxError.truncated }
        defer { offset += n }
        return ByteReader(bytes, range: offset..<offset + n)
    }

    /// Calls `body` with the next `n` bytes; advances past them.
    mutating func withBytes<T>(_ n: Int, _ body: (UnsafeBufferPointer<UInt8>) -> T) throws -> T {
        guard n >= 0, n <= remaining else { throw VoxError.truncated }
        defer { offset += n }
        return bytes.withUnsafeBufferPointer { body(UnsafeBufferPointer(rebasing: $0[offset..<offset + n])) }
    }

    mutating func string() throws -> String {
        let n = Int(try int32())
        guard n >= 0, n <= remaining else { throw VoxError.truncated }
        defer { offset += n }
        return String(decoding: bytes[offset..<offset + n], as: UTF8.self)
    }

    mutating func dict() throws -> [String: String] {
        let n = Int(try int32())
        guard n >= 0, n <= remaining / 8 else { throw VoxError.truncated }
        var d: [String: String] = [:]
        for _ in 0..<n {
            let k = try string()
            d[k] = try string()
        }
        return d
    }
}
