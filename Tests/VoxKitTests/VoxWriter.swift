import Foundation

/// Builds `.vox` bytes for tests, chunk by chunk.
struct VoxWriter {
    private(set) var chunks = Data()

    static func int32(_ v: Int) -> Data { withUnsafeBytes(of: Int32(v).littleEndian) { Data($0) } }

    static func string(_ s: String) -> Data { int32(s.utf8.count) + Data(s.utf8) }

    static func dict(_ d: [String: String]) -> Data {
        d.sorted { $0.key < $1.key }.reduce(int32(d.count)) { $0 + string($1.key) + string($1.value) }
    }

    mutating func chunk(_ id: String, _ content: Data) {
        chunks += Data(id.utf8) + Self.int32(content.count) + Self.int32(0) + content
    }

    mutating func model(size: (Int, Int, Int), voxels: [(Int, Int, Int, UInt8)]) {
        chunk("SIZE", Self.int32(size.0) + Self.int32(size.1) + Self.int32(size.2))
        chunk("XYZI", voxels.reduce(Self.int32(voxels.count)) {
            $0 + Data([UInt8($1.0), UInt8($1.1), UInt8($1.2), $1.3])
        })
    }

    mutating func transform(id: Int, child: Int, layer: Int = 0, frame: [String: String] = [:]) {
        chunk("nTRN", Self.int32(id) + Self.dict([:]) + Self.int32(child) + Self.int32(-1)
            + Self.int32(layer) + Self.int32(1) + Self.dict(frame))
    }

    mutating func group(id: Int, children: [Int]) {
        chunk("nGRP", children.reduce(Self.int32(id) + Self.dict([:]) + Self.int32(children.count)) { $0 + Self.int32($1) })
    }

    mutating func shape(id: Int, model: Int) {
        chunk("nSHP", Self.int32(id) + Self.dict([:]) + Self.int32(1) + Self.int32(model) + Self.dict([:]))
    }

    var data: Data {
        Data("VOX ".utf8) + Self.int32(200) + Data("MAIN".utf8) + Self.int32(0) + Self.int32(chunks.count) + chunks
    }
}
