import simd

/// A model placed in the world (MagicaVoxel coordinates, Z up).
///
/// The model's geometry is expected centred on its own box — voxel `v`
/// spanning `v - size/2 … v + 1 - size/2` — so that `world = rotation · p + translation`.
public struct VoxInstance: Sendable {
    public var modelIndex: Int
    public var rotation: VoxRotation
    public var translation: SIMD3<Float>
    /// Layer of the nearest transform that has one; −1 for none.
    public var layer: Int = -1
}

extension VoxFile {
    /// Every visible model instance at `frame`, in world space. Hidden nodes
    /// are skipped, and so are hidden layers unless `includeHiddenLayers`.
    /// Files without a scene graph place each model at the origin.
    public func instances(frame: Int = 0, includeHiddenLayers: Bool = false) -> [VoxInstance] {
        guard let root = nodes[0] else {
            return models.indices.map { VoxInstance(modelIndex: $0, rotation: .identity, translation: .zero) }
        }
        var walker = Walker(file: self, frame: frame, includeHiddenLayers: includeHiddenLayers)
        walker.walk(root, id: 0, rotation: .identity, translation: .zero, layer: -1)
        return walker.out
    }

    /// World-space box (Z up) around the occupied voxels of `instances`; nil if there are none.
    public func bounds(of instances: [VoxInstance]) -> (min: SIMD3<Float>, max: SIMD3<Float>)? {
        var lo = SIMD3<Float>(repeating: .infinity), hi = -lo
        for inst in instances {
            let m = models[inst.modelIndex]
            guard m.voxelCount > 0 else { continue }
            let half = SIMD3<Float>(Float(m.sizeX), Float(m.sizeY), Float(m.sizeZ)) / 2
            let a = SIMD3<Float>(m.origin) - half, b = SIMD3<Float>(m.origin &+ m.extent) - half
            // A signed permutation maps the box's min/max corners to two opposite corners.
            let p = inst.rotation.apply(a) + inst.translation, q = inst.rotation.apply(b) + inst.translation
            lo = simd_min(lo, simd_min(p, q)); hi = simd_max(hi, simd_max(p, q))
        }
        return lo.x <= hi.x ? (lo, hi) : nil
    }

    private struct Walker {
        let file: VoxFile
        let frame: Int
        let includeHiddenLayers: Bool
        var out: [VoxInstance] = []
        var visited = Set<Int>()

        mutating func walk(_ node: VoxNode, id: Int, rotation: VoxRotation, translation: SIMD3<Float>, layer: Int) {
            // Guards against cycles in corrupt files; a node may still be reached twice.
            guard visited.insert(id).inserted else { return }
            defer { visited.remove(id) }
            switch node {
            case .transform(let t):
                if t.hidden { return }
                if !includeHiddenLayers, file.layers[t.layer]?.hidden == true { return }
                guard let child = file.nodes[t.child] else { return }
                let key = t.keys.last(where: { $0.frame <= frame }) ?? t.keys.first
                    ?? VoxTransformKey(frame: 0, rotation: t.rotation, translation: t.translation)
                let r = rotation.concatenating(key.rotation)
                var local = SIMD3<Float>(key.translation)
                // MagicaVoxel puts a box's floor(size/2) voxel at the translation,
                // so odd extents sit half a voxel off the centre.
                if case .shape = child, let m = file.shapeModel(t.child, frame: frame) {
                    let size = key.rotation.applyToSize(SIMD3(Int32(m.sizeX), Int32(m.sizeY), Int32(m.sizeZ)))
                    local += SIMD3<Float>(size & 1) * 0.5
                }
                walk(child, id: t.child, rotation: r, translation: rotation.apply(local) + translation,
                     layer: t.layer >= 0 ? t.layer : layer)
            case .group(let children):
                for c in children {
                    if let n = file.nodes[c] { walk(n, id: c, rotation: rotation, translation: translation, layer: layer) }
                }
            case .shape:
                if let m = file.shapeModelIndex(id, frame: frame) {
                    out.append(VoxInstance(modelIndex: m, rotation: rotation, translation: translation, layer: layer))
                }
            }
        }
    }

    /// The model an `nSHP` node shows at `frame`: the last one starting at or before it.
    func shapeModelIndex(_ nodeID: Int, frame: Int) -> Int? {
        guard case .shape(let ids) = nodes[nodeID], !ids.isEmpty else { return nil }
        var pick = ids[0]
        if let frames = shapeFrames[nodeID] {
            var best = Int.min
            for (i, f) in frames.enumerated() where f <= frame && f > best && i < ids.count { best = f; pick = ids[i] }
        }
        return models.indices.contains(pick) ? pick : nil
    }

    private func shapeModel(_ nodeID: Int, frame: Int) -> VoxModel? {
        shapeModelIndex(nodeID, frame: frame).map { models[$0] }
    }
}

/// What a file holds, in words: for Spotlight and other listings.
public struct VoxSummary: Sendable, CustomStringConvertible {
    /// Size in voxels, MagicaVoxel's X × Y × Z (Z up).
    public let dimensions: SIMD3<Int>
    public let voxelCount: Int
    public let instanceCount: Int
    public let frameCount: Int
    /// Object and layer names, deduplicated, in file order.
    public let names: [String]

    public init(_ file: VoxFile) {
        let instances = file.instances()
        let box = file.bounds(of: instances)
        dimensions = box.map { SIMD3<Int>(($0.max - $0.min).rounded(.toNearestOrAwayFromZero)) } ?? .zero
        voxelCount = instances.reduce(0) { $0 + file.models[$1.modelIndex].voxelCount }
        instanceCount = instances.count
        frameCount = file.frameCount
        var seen = Set<String>(), names: [String] = []
        let transformNames = file.nodes.sorted { $0.key < $1.key }.compactMap { entry -> String? in
            if case .transform(let t) = entry.value { return t.name } else { return nil }
        }
        for name in transformNames + file.layers.sorted(by: { $0.key < $1.key }).compactMap(\.value.name)
        where !name.isEmpty && seen.insert(name).inserted { names.append(name) }
        self.names = names
    }

    public var description: String {
        var parts = ["\(dimensions.x) × \(dimensions.y) × \(dimensions.z) voxels",
                     "\(voxelCount.formatted()) filled"]
        if instanceCount != 1 { parts.append("\(instanceCount) models") }
        if frameCount > 1 { parts.append("\(frameCount) frames") }
        return parts.joined(separator: ", ")
    }
}
