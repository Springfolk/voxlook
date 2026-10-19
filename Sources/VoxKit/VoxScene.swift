/// A model placed in the world (MagicaVoxel coordinates, Z up).
///
/// The model's geometry is expected centred on its own box — voxel `v`
/// spanning `v - size/2 … v + 1 - size/2` — so that `world = rotation · p + translation`.
public struct VoxInstance: Sendable {
    public var modelIndex: Int
    public var rotation: VoxRotation
    public var translation: SIMD3<Float>
}

extension VoxFile {
    /// Every visible model instance, in world space. Hidden nodes and layers
    /// are skipped. Files without a scene graph place each model at the origin.
    public func instances() -> [VoxInstance] {
        guard let root = nodes[0] else {
            return models.indices.map { VoxInstance(modelIndex: $0, rotation: .identity, translation: .zero) }
        }
        var out: [VoxInstance] = []
        var visited = Set<Int>()
        walk(root, id: 0, rotation: .identity, translation: .zero, visited: &visited, into: &out)
        return out
    }

    private func walk(_ node: VoxNode, id: Int, rotation: VoxRotation, translation: SIMD3<Float>,
                      visited: inout Set<Int>, into out: inout [VoxInstance]) {
        // Guards against cycles in corrupt files; a node may still be reached twice.
        guard visited.insert(id).inserted else { return }
        defer { visited.remove(id) }
        switch node {
        case .transform(let t):
            if t.hidden || layers[t.layer]?.hidden == true { return }
            guard let child = nodes[t.child] else { return }
            let r = rotation.concatenating(t.rotation)
            var local = SIMD3<Float>(t.translation)
            // MagicaVoxel puts a box's floor(size/2) voxel at the translation,
            // so odd extents sit half a voxel off the centre.
            if case .shape(let ids) = child, let first = ids.first, models.indices.contains(first) {
                let m = models[first]
                let size = t.rotation.applyToSize(SIMD3(Int32(m.sizeX), Int32(m.sizeY), Int32(m.sizeZ)))
                local += SIMD3<Float>(size & 1) * 0.5
            }
            walk(child, id: t.child, rotation: r, translation: rotation.apply(local) + translation,
                 visited: &visited, into: &out)
        case .group(let children):
            for c in children {
                if let n = nodes[c] { walk(n, id: c, rotation: rotation, translation: translation, visited: &visited, into: &out) }
            }
        case .shape(let ids):
            // Several ids means animation frames; show the first.
            if let m = ids.first, models.indices.contains(m) {
                out.append(VoxInstance(modelIndex: m, rotation: rotation, translation: translation))
            }
        }
    }
}
