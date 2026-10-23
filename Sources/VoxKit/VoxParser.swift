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
        // Reads straight from the (usually memory-mapped) bytes: no copy.
        self = try data.withUnsafeBytes { try VoxFile(parsing: ByteReader($0)) }
    }

    private init(parsing reader: ByteReader) throws {
        var r = reader
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
                models.append(VoxModel(sizeX: sx, sizeY: sy, sizeZ: sz, xyzi: try c.bytes(count * 4)))
            case "RGBA":
                // Entry k colours palette index k + 1; the 256th entry is unused.
                var colors = [VoxColor(r: 0, g: 0, b: 0, a: 0)]
                for _ in 0..<255 {
                    colors.append(VoxColor(r: try c.byte(), g: try c.byte(), b: try c.byte(), a: try c.byte()))
                }
                palette = colors
            case "MATL":
                let index = Int(try c.int32())
                let material = VoxMaterial(attributes: try c.dict())
                if (1...255).contains(index), material != VoxMaterial() { materials[index] = material }
            case "nTRN":
                let nodeID = Int(try c.int32())
                let attrs = try c.dict()
                let child = Int(try c.int32())
                _ = try c.int32()  // reserved
                let layer = Int(try c.int32())
                let frameCount = Int(try c.int32())
                guard frameCount >= 0, frameCount <= c.remaining / 4 else { throw VoxError.truncated }
                var keys: [VoxTransformKey] = []
                for i in 0..<frameCount {
                    let f = try c.dict()
                    var key = VoxTransformKey(frame: f["_f"].flatMap(Int.init) ?? i, rotation: .identity,
                                              translation: .zero)
                    if let s = f["_r"], let b = UInt8(s), let rot = VoxRotation(packed: b) { key.rotation = rot }
                    if let s = f["_t"] {
                        let parts = s.split(separator: " ").compactMap { Int32($0) }
                        if parts.count == 3 { key.translation = SIMD3(parts[0], parts[1], parts[2]) }
                    }
                    keys.append(key)
                }
                keys.sort { $0.frame < $1.frame }
                if keys.isEmpty { keys = [VoxTransformKey(frame: 0, rotation: .identity, translation: .zero)] }
                nodes[nodeID] = .transform(VoxTransformNode(
                    name: attrs["_name"], hidden: attrs["_hidden"] == "1", child: child, layer: layer,
                    rotation: keys[0].rotation, translation: keys[0].translation, keys: keys))
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
                var ids: [Int] = [], frames: [Int] = []
                for i in 0..<n {
                    ids.append(Int(try c.int32()))
                    frames.append(try c.dict()["_f"].flatMap(Int.init) ?? i)
                }
                nodes[nodeID] = .shape(modelIDs: ids)
                if n > 1 { shapeFrames[nodeID] = frames }
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

/// Bounds-checked little-endian reader over borrowed bytes. Every read throws
/// on overrun. Valid only inside the `withUnsafeBytes` call that made it.
struct ByteReader {
    private let base: UnsafeRawBufferPointer
    private var offset: Int
    private let end: Int

    init(_ bytes: UnsafeRawBufferPointer) {
        base = bytes
        offset = 0
        end = bytes.count
    }

    private init(_ bytes: UnsafeRawBufferPointer, range: Range<Int>) {
        base = bytes
        offset = range.lowerBound
        end = range.upperBound
    }

    var remaining: Int { end - offset }

    mutating func byte() throws -> UInt8 {
        guard offset < end else { throw VoxError.truncated }
        defer { offset += 1 }
        return base[offset]
    }

    mutating func int32() throws -> Int32 {
        guard remaining >= 4 else { throw VoxError.truncated }
        defer { offset += 4 }
        return Int32(littleEndian: base.loadUnaligned(fromByteOffset: offset, as: Int32.self))
    }

    mutating func fourCC() throws -> String {
        String(decoding: try bytes(4), as: UTF8.self)
    }

    mutating func skip(_ n: Int) throws {
        guard n >= 0, n <= remaining else { throw VoxError.truncated }
        offset += n
    }

    /// A reader over the next `n` bytes; advances past them.
    mutating func sub(_ n: Int) throws -> ByteReader {
        guard n >= 0, n <= remaining else { throw VoxError.truncated }
        defer { offset += n }
        return ByteReader(base, range: offset..<offset + n)
    }

    /// The next `n` bytes; advances past them.
    mutating func bytes(_ n: Int) throws -> UnsafeBufferPointer<UInt8> {
        guard n >= 0, n <= remaining else { throw VoxError.truncated }
        defer { offset += n }
        return UnsafeRawBufferPointer(rebasing: base[offset..<offset + n]).assumingMemoryBound(to: UInt8.self)
    }

    mutating func string() throws -> String {
        let n = Int(try int32())
        return String(decoding: try bytes(n), as: UTF8.self)
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
