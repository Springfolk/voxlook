/// Triangle mesh of a model's visible surface, flat-shaded with per-vertex colours.
public struct VoxMesh: Sendable {
    /// xyz per vertex, centred on the model box (see `VoxInstance`).
    public var positions: [Float] = []
    /// xyz per vertex.
    public var normals: [Float] = []
    /// rgba per vertex.
    public var colors: [UInt8] = []
    public var indices: [UInt32] = []

    public var vertexCount: Int { positions.count / 3 }
    public var triangleCount: Int { indices.count / 3 }
}

extension VoxModel {
    /// Builds the visible surface with greedy meshing: faces between two filled
    /// voxels are dropped, and coplanar same-colour faces merge into one quad.
    public func mesh(palette: [VoxColor]) -> VoxMesh {
        var mesh = VoxMesh()
        guard voxelCount > 0 else { return mesh }
        // Walk the stored grid only; `offset` maps grid coordinates to box-centred ones.
        let size = [extent.x, extent.y, extent.z]
        let stride = [1, extent.x, extent.x * extent.y]
        let box = [sizeX, sizeY, sizeZ]
        let offset = (0..<3).map { Float(origin[$0]) - Float(box[$0]) / 2 }

        cells.withUnsafeBufferPointer { cells in
            for d in 0..<3 {
                let u = (d + 1) % 3, v = (d + 2) % 3
                let su = size[u], sv = size[v]
                var mask = [UInt8](repeating: 0, count: su * sv)
                for positive in [false, true] {
                    var normal = SIMD3<Float>(repeating: 0)
                    normal[d] = positive ? 1 : -1
                    for slice in 0..<size[d] {
                        let neighbour = slice + (positive ? 1 : -1)
                        let neighbourInside = neighbour >= 0 && neighbour < size[d]
                        // Mask of exposed faces in this slice.
                        for j in 0..<sv {
                            for i in 0..<su {
                                let k = slice * stride[d] + i * stride[u] + j * stride[v]
                                let c = cells[k]
                                let covered = neighbourInside && cells[k + (positive ? stride[d] : -stride[d])] != 0
                                mask[i + j * su] = covered ? 0 : c
                            }
                        }
                        // Greedily merge into rectangles.
                        let plane = Float(slice + (positive ? 1 : 0))
                        for j in 0..<sv {
                            var i = 0
                            while i < su {
                                let c = mask[i + j * su]
                                if c == 0 { i += 1; continue }
                                var w = 1
                                while i + w < su && mask[i + w + j * su] == c { w += 1 }
                                var h = 1
                                grow: while j + h < sv {
                                    for x in i..<i + w where mask[x + (j + h) * su] != c { break grow }
                                    h += 1
                                }
                                for y in j..<j + h { for x in i..<i + w { mask[x + y * su] = 0 } }

                                var corner = SIMD3<Float>(repeating: 0)
                                corner[d] = plane + offset[d]
                                corner[u] = Float(i) + offset[u]
                                corner[v] = Float(j) + offset[v]
                                var du = SIMD3<Float>(repeating: 0), dv = SIMD3<Float>(repeating: 0)
                                du[u] = Float(w)
                                dv[v] = Float(h)
                                mesh.addQuad(corner: corner, du: du, dv: dv, normal: normal,
                                             flip: !positive, color: palette[Int(c)])
                                i += w
                            }
                        }
                    }
                }
            }
        }
        return mesh
    }
}

extension VoxMesh {
    fileprivate mutating func addQuad(corner p: SIMD3<Float>, du: SIMD3<Float>, dv: SIMD3<Float>,
                                      normal n: SIMD3<Float>, flip: Bool, color: VoxColor) {
        let base = UInt32(vertexCount)
        for q in [p, p + du, p + du + dv, p + dv] {
            positions.append(q.x); positions.append(q.y); positions.append(q.z)
            normals.append(n.x); normals.append(n.y); normals.append(n.z)
            colors.append(color.r); colors.append(color.g); colors.append(color.b); colors.append(color.a)
        }
        // u × v points along +d, so counter-clockwise for positive faces.
        let (b1, b3) = flip ? (base + 3, base + 1) : (base + 1, base + 3)
        indices.append(base); indices.append(b1); indices.append(base + 2)
        indices.append(base); indices.append(base + 2); indices.append(b3)
    }
}
