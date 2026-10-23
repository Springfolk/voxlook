/// Triangle mesh of a model's visible surface, flat-shaded with per-vertex colours.
public struct VoxMesh: Sendable {
    /// A run of `indices` drawn with one surface.
    public struct Part: Sendable {
        public var surface: VoxSurface
        public var indices: Range<Int>
        public var triangleCount: Int { indices.count / 3 }
    }

    /// xyz per vertex, centred on the model box (see `VoxInstance`).
    public var positions: [Float] = []
    /// xyz per vertex.
    public var normals: [Float] = []
    /// rgba per vertex, ambient occlusion baked in.
    public var colors: [UInt8] = []
    public var indices: [UInt32] = []
    /// Non-empty runs of `indices` by surface, in `VoxSurface` order.
    public var parts: [Part] = []

    public var vertexCount: Int { positions.count / 3 }
    public var triangleCount: Int { indices.count / 3 }
}

extension VoxModel {
    /// Brightness of a vertex by how many of its three neighbours on the open
    /// side are solid (index 0: both sides solid).
    static let occlusionShade: [Float] = [0.56, 0.72, 0.86, 1]

    /// Builds the visible surface with greedy meshing: faces between two filled
    /// voxels are dropped, and coplanar faces of one colour and shading merge
    /// into one quad.
    ///
    /// - Parameters:
    ///   - surfaces: per palette index; transparent ones keep the faces behind
    ///     them and don't occlude. Nil draws everything diffuse.
    ///   - ambientOcclusion: darken creases and corners (baked into the colours;
    ///     costs only meshing time).
    public func mesh(palette: [VoxColor], surfaces: [VoxSurface]? = nil, ambientOcclusion: Bool = true) -> VoxMesh {
        var mesh = VoxMesh()
        guard voxelCount > 0 else { return mesh }
        // Per palette index: 0 empty, 1 opaque, 2 transparent; and whether its faces get AO.
        var kind = [UInt8](repeating: 1, count: 256), shaded = [Bool](repeating: ambientOcclusion, count: 256)
        kind[0] = 0
        if let surfaces {
            for i in 1..<min(256, surfaces.count) {
                if surfaces[i].isTransparent { kind[i] = 2 }
                if surfaces[i] == .glass || surfaces[i] == .emissive { shaded[i] = false }  // glows / lets light through
            }
        }
        let surfaceOf = (0..<256).map { i in surfaces.map { i < $0.count ? $0[i] : .diffuse } ?? .diffuse }
        var partIndices = [[UInt32]](repeating: [], count: VoxSurface.allCases.count)

        // Walk the stored grid only; `offset` maps grid coordinates to box-centred ones.
        let size = [extent.x, extent.y, extent.z]
        let stride = [1, extent.x, extent.x * extent.y]
        let box = [sizeX, sizeY, sizeZ]
        let offset = (0..<3).map { Float(origin[$0]) - Float(box[$0]) / 2 }

        cells.withUnsafeBufferPointer { cells in kind.withUnsafeBufferPointer { kind in
            for d in 0..<3 {
                let u = (d + 1) % 3, v = (d + 2) % 3
                let su = size[u], sv = size[v]
                let sd = stride[d], ku = stride[u], kv = stride[v], depth = size[d]
                // Low byte: palette index; high byte: the four corners' AO, 2 bits each.
                var mask = [UInt16](repeating: 0, count: su * sv)
                for positive in [false, true] {
                    var normal = SIMD3<Float>(repeating: 0)
                    normal[d] = positive ? 1 : -1
                    let step = positive ? 1 : -1
                    for slice in 0..<depth {
                        let neighbour = slice + step
                        let neighbourInside = neighbour >= 0 && neighbour < depth
                        // Mask of exposed faces in this slice.
                        for j in 0..<sv {
                            for i in 0..<su {
                                let k = slice * sd + i * ku + j * kv
                                let c = cells[k]
                                mask[i + j * su] = 0
                                guard c != 0 else { continue }
                                let air = k + step * sd
                                if neighbourInside {
                                    // Covered by an opaque neighbour, or glass inside glass.
                                    let n = kind[Int(cells[air])]
                                    if n == 1 || (n == 2 && kind[Int(c)] == 2) { continue }
                                }
                                var ao: UInt16 = 0xFF  // all corners open
                                if shaded[Int(c)] && neighbourInside {
                                    // The 8 cells around the face on its open side; outside the grid is empty.
                                    let hasW = i > 0, hasE = i + 1 < su, hasS = j > 0, hasN = j + 1 < sv
                                    let w = hasW && kind[Int(cells[air - ku])] == 1
                                    let e = hasE && kind[Int(cells[air + ku])] == 1
                                    let s = hasS && kind[Int(cells[air - kv])] == 1
                                    let n = hasN && kind[Int(cells[air + kv])] == 1
                                    let sw = hasS && hasW && kind[Int(cells[air - ku - kv])] == 1
                                    let se = hasS && hasE && kind[Int(cells[air + ku - kv])] == 1
                                    let ne = hasN && hasE && kind[Int(cells[air + ku + kv])] == 1
                                    let nw = hasN && hasW && kind[Int(cells[air - ku + kv])] == 1
                                    func level(_ a: Bool, _ b: Bool, _ corner: Bool) -> UInt16 {
                                        a && b ? 0 : 3 - (a ? 1 : 0) - (b ? 1 : 0) - (corner ? 1 : 0)
                                    }
                                    // Corners in quad order: (−u −v), (+u −v), (+u +v), (−u +v).
                                    ao = level(w, s, sw) | level(e, s, se) << 2 | level(e, n, ne) << 4 | level(w, n, nw) << 6
                                }
                                mask[i + j * su] = UInt16(c) | ao << 8
                            }
                        }
                        // Greedily merge into rectangles. A run may only stretch along an
                        // axis its shading doesn't vary on, so the interpolated AO stays exact.
                        let plane = Float(slice + (positive ? 1 : 0))
                        for j in 0..<sv {
                            var i = 0
                            while i < su {
                                let key = mask[i + j * su]
                                if key == 0 { i += 1; continue }
                                let ao = SIMD4<Int>(Int(key >> 8 & 3), Int(key >> 10 & 3), Int(key >> 12 & 3), Int(key >> 14 & 3))
                                var w = 1
                                if ao[0] == ao[1] && ao[3] == ao[2] {
                                    while i + w < su && mask[i + w + j * su] == key { w += 1 }
                                }
                                var h = 1
                                if ao[0] == ao[3] && ao[1] == ao[2] {
                                    grow: while j + h < sv {
                                        for x in i..<i + w where mask[x + (j + h) * su] != key { break grow }
                                        h += 1
                                    }
                                }
                                for y in j..<j + h { for x in i..<i + w { mask[x + y * su] = 0 } }

                                var corner = SIMD3<Float>(repeating: 0)
                                corner[d] = plane + offset[d]
                                corner[u] = Float(i) + offset[u]
                                corner[v] = Float(j) + offset[v]
                                var du = SIMD3<Float>(repeating: 0), dv = SIMD3<Float>(repeating: 0)
                                du[u] = Float(w)
                                dv[v] = Float(h)
                                let c = Int(key & 0xFF)
                                mesh.addQuad(corner: corner, du: du, dv: dv, normal: normal, flip: !positive,
                                             color: palette[c], ao: ao, into: &partIndices[surfaceOf[c].rawValue])
                                i += w
                            }
                        }
                    }
                }
            }
        }}
        for s in partIndices.indices where !partIndices[s].isEmpty {
            let range = mesh.indices.count..<mesh.indices.count + partIndices[s].count
            mesh.parts.append(VoxMesh.Part(surface: VoxSurface(rawValue: s)!, indices: range))
            // The usual single surface moves over without a copy.
            if mesh.indices.isEmpty { swap(&mesh.indices, &partIndices[s]) } else { mesh.indices += partIndices[s] }
            partIndices[s] = []
        }
        return mesh
    }
}

extension VoxMesh {
    fileprivate mutating func addQuad(corner p: SIMD3<Float>, du: SIMD3<Float>, dv: SIMD3<Float>,
                                      normal n: SIMD3<Float>, flip: Bool, color: VoxColor, ao: SIMD4<Int>,
                                      into indices: inout [UInt32]) {
        let base = UInt32(vertexCount)
        for corner in 0..<4 {
            let q = p + (corner == 1 || corner == 2 ? du : .zero) + (corner >= 2 ? dv : .zero)
            positions.append(q.x); positions.append(q.y); positions.append(q.z)
            normals.append(n.x); normals.append(n.y); normals.append(n.z)
            let shade = VoxModel.occlusionShade[ao[corner]]
            colors.append(UInt8(Float(color.r) * shade)); colors.append(UInt8(Float(color.g) * shade))
            colors.append(UInt8(Float(color.b) * shade)); colors.append(color.a)
        }
        // Split along the diagonal whose ends are lighter, so shading doesn't streak.
        let (a, b, c, d) = ao[0] + ao[2] >= ao[1] + ao[3] ? (base, base + 1, base + 2, base + 3)
                                                           : (base + 1, base + 2, base + 3, base)
        // u × v points along +d, so counter-clockwise for positive faces.
        let (second, last) = flip ? (d, b) : (b, d)
        indices.append(a); indices.append(second); indices.append(c)
        indices.append(a); indices.append(c); indices.append(last)
    }
}
