import Accelerate
import Foundation
import SceneKit
import VoxKit

/// A ready-to-render SceneKit scene for a `.vox` file.
public struct VoxScene {
    /// A MagicaVoxel layer that has models in it.
    public struct Layer: Sendable {
        public let id: Int
        public let name: String
        /// Shown when the scene opens (MagicaVoxel's own visibility).
        public let initiallyVisible: Bool
    }

    public let scene: SCNScene
    /// World bounds in SceneKit coordinates (Y up), of what shows when the scene opens.
    public let boundsMin: SIMD3<Float>
    public let boundsMax: SIMD3<Float>
    public let voxelCount: Int
    public let triangleCount: Int
    public let instanceCount: Int
    /// Animation frames built into the scene; 1 unless `interactive`.
    public let frameCount: Int
    /// Layers with models, for toggling; empty unless `interactive` and there are two or more.
    public let layers: [Layer]
    /// Colours in use, most voxels first; empty unless `interactive`.
    public let usedColors: [VoxColor]

    private let frameNodes: [SCNNode]
    private let layerNodes: [Int: [SCNNode]]

    public var size: SIMD3<Float> { boundsMax - boundsMin }
    public var center: SIMD3<Float> { (boundsMin + boundsMax) / 2 }

    /// Size in voxels as MagicaVoxel shows it (X × Y × Z, Z up).
    public var voxelDimensions: (x: Int, y: Int, z: Int) {
        (Int(size.x.rounded()), Int(size.z.rounded()), Int(size.y.rounded()))
    }

    /// - Parameter interactive: also build every animation frame and hidden
    ///   layer (hidden for now) and count colours, for the preview. Thumbnails
    ///   leave it off and mesh only what frame 0 shows.
    public init(file: VoxFile, interactive: Bool = false) {
        let scene = SCNScene()
        // MagicaVoxel is Z up; SceneKit is Y up.
        let world = SCNNode()
        world.eulerAngles.x = -.pi / 2
        scene.rootNode.addChildNode(world)

        let surfaces = file.surfaces
        var palette = file.palette
        for i in palette.indices {
            // Glass shows through; everything else is drawn opaque.
            let glass = surfaces[i] == .glass ? file.materials[i]?.transparency ?? 0 : 0
            palette[i].a = UInt8(255 * max(0.2, 1 - 0.8 * glass))
        }
        let materials = Self.materials(), mirrored = materials.map { m -> SCNMaterial in
            let copy = m.copy() as! SCNMaterial
            copy.isDoubleSided = true  // reflections flip winding
            return copy
        }

        var geometries: [Int: (plain: SCNGeometry, mirrored: SCNGeometry?)] = [:]
        func geometry(_ modelIndex: Int, mirror: Bool) -> SCNGeometry {
            var entry = geometries[modelIndex] ?? {
                let mesh = file.models[modelIndex].mesh(palette: palette, surfaces: surfaces)
                let g = Self.geometry(from: mesh)
                g.materials = mesh.parts.map { materials[$0.surface.rawValue] }
                return (g, nil)
            }()
            if mirror && entry.mirrored == nil {
                let g = entry.plain.copy() as! SCNGeometry  // shares vertex buffers
                g.materials = entry.plain.materials.map { mirrored[materials.firstIndex(of: $0)!] }
                entry.mirrored = g
            }
            geometries[modelIndex] = entry
            return mirror ? entry.mirrored! : entry.plain
        }

        let frameCount = interactive ? file.frameCount : 1
        var frameNodes: [SCNNode] = [], layerNodes: [Int: [SCNNode]] = [:]
        var firstFrame: [VoxInstance] = []
        for f in 0..<frameCount {
            let container = SCNNode()
            container.isHidden = f != 0
            world.addChildNode(container)
            frameNodes.append(container)
            for inst in file.instances(frame: f, includeHiddenLayers: interactive) {
                guard file.models[inst.modelIndex].voxelCount > 0 else { continue }
                let hidden = file.layers[inst.layer]?.hidden == true
                if f == 0 && !hidden { firstFrame.append(inst) }
                let node = SCNNode(geometry: geometry(inst.modelIndex, mirror: Self.determinant(inst.rotation) < 0))
                node.simdTransform = Self.matrix(inst.rotation, inst.translation)
                node.isHidden = hidden
                container.addChildNode(node)
                layerNodes[inst.layer, default: []].append(node)
            }
        }

        // Bounds of the occupied voxels, Z-up → Y-up: (x, y, z) → (x, z, −y).
        let (lo, hi) = file.bounds(of: firstFrame).map {
            (SIMD3($0.min.x, $0.min.z, -$0.max.y), SIMD3($0.max.x, $0.max.z, -$0.min.y))
        } ?? (.zero, .zero)

        Self.addLights(to: scene)
        self.scene = scene
        boundsMin = lo; boundsMax = hi
        voxelCount = firstFrame.reduce(0) { $0 + file.models[$1.modelIndex].voxelCount }
        triangleCount = firstFrame.reduce(0) { $0 + (geometries[$1.modelIndex]?.plain.elements.reduce(0) { $0 + $1.primitiveCount } ?? 0) }
        instanceCount = firstFrame.count
        self.frameCount = frameCount
        self.frameNodes = frameNodes
        self.layerNodes = layerNodes
        let layerIDs = layerNodes.keys.filter { $0 >= 0 }.sorted()
        layers = interactive && layerIDs.count > 1 ? layerIDs.map {
            // MagicaVoxel names untouched layers "0", "1", …
            let name = file.layers[$0]?.name.flatMap { Int($0) == nil ? $0 : nil } ?? "Layer \($0)"
            return Layer(id: $0, name: name, initiallyVisible: file.layers[$0]?.hidden != true)
        } : []
        usedColors = interactive ? Self.colorsByUse(file, firstFrame) : []
    }

    /// Shows animation frame `frame` (wrapping) and hides the rest.
    public func showFrame(_ frame: Int) {
        guard frameNodes.count > 1 else { return }
        let f = (frame % frameNodes.count + frameNodes.count) % frameNodes.count
        for (i, node) in frameNodes.enumerated() where node.isHidden != (i != f) { node.isHidden = i != f }
    }

    /// Shows or hides every model on `layer`, in every frame.
    public func setLayer(_ layer: Int, visible: Bool) {
        for node in layerNodes[layer] ?? [] { node.isHidden = !visible }
    }

    private static func colorsByUse(_ file: VoxFile, _ instances: [VoxInstance]) -> [VoxColor] {
        var counts = [Int](repeating: 0, count: 256)
        for m in Set(instances.map(\.modelIndex)) {
            for c in file.models[m].cells where c != 0 { counts[Int(c)] += 1 }
        }
        return (1..<256).filter { counts[$0] > 0 }.sorted { counts[$0] > counts[$1] }.map { file.palette[$0] }
    }

    /// Positions an orbit camera so the whole model fits.
    /// - Parameters:
    ///   - yaw/pitch: view direction in radians (pitch > 0 looks down).
    ///   - aspect: viewport width / height.
    public func frame(_ cameraNode: SCNNode, yaw: Float = .pi / 4, pitch: Float = 0.52,
                      aspect: Float = 1, margin: Float = 1.08) {
        guard let camera = cameraNode.camera else { return }
        let dir = SIMD3<Float>(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))  // towards camera
        let forward = -dir
        let right = simd_normalize(simd_cross(forward, SIMD3(0, 1, 0)))
        let up = simd_cross(right, forward)

        // Extents of the bounding box corners in camera space.
        var maxX: Float = 0, maxY: Float = 0, maxZ: Float = 0
        let h = size / 2
        for sx in [-1, 1] as [Float] { for sy in [-1, 1] as [Float] { for sz in [-1, 1] as [Float] {
            let c = h * SIMD3(sx, sy, sz)
            maxX = max(maxX, abs(simd_dot(c, right)))
            maxY = max(maxY, abs(simd_dot(c, up)))
            maxZ = max(maxZ, abs(simd_dot(c, forward)))
        }}}
        let radius = max(simd_length(h), 0.5)
        maxX = max(maxX, 0.5); maxY = max(maxY, 0.5)

        let distance: Float
        if camera.usesOrthographicProjection {
            camera.orthographicScale = Double(max(maxY, maxX / aspect) * margin)
            distance = radius * 3
        } else {
            let tanHalf = tan(Float(camera.fieldOfView) * .pi / 360)  // vertical FOV
            distance = max(maxY / tanHalf, maxX / (tanHalf * aspect)) * margin + maxZ
        }
        camera.zNear = Double(max(distance - radius * 1.5, 0.1))
        camera.zFar = Double(distance + radius * 2)
        cameraNode.simdPosition = center + dir * distance
        cameraNode.simdLook(at: center, up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
    }

    // MARK: - Building blocks

    /// One per `VoxSurface`, in its order. Lambert/Blinn and unlit: no PBR, no shadows.
    static func materials() -> [SCNMaterial] {
        VoxSurface.allCases.map { surface in
            let m = SCNMaterial()
            m.diffuse.contents = NSColor.white  // multiplied by the vertex colours
            switch surface {
            case .diffuse:
                m.lightingModel = .lambert
            case .metal:
                m.lightingModel = .blinn
                m.specular.contents = NSColor(white: 0.55, alpha: 1)
                m.shininess = 0.35
            case .emissive:
                m.lightingModel = .constant  // full colour regardless of light: it glows
            case .glass:
                m.lightingModel = .blinn
                m.specular.contents = NSColor(white: 0.4, alpha: 1)
                m.blendMode = .alpha
                m.writesToDepthBuffer = false  // what's behind it still draws
            }
            return m
        }
    }

    static func geometry(from mesh: VoxMesh) -> SCNGeometry {
        let n = mesh.vertexCount
        // Half floats: exact for voxel coordinates up to ±1024 in steps of 0.5, and
        // half the memory. SceneKit doesn't normalise byte colours, so those widen too.
        // vImage converts on Intel too (Swift's Float16 is arm64-only on macOS).
        func source<T>(_ values: [T], _ semantic: SCNGeometrySource.Semantic, components: Int,
                       _ convert: (UnsafePointer<vImage_Buffer>, UnsafePointer<vImage_Buffer>) -> vImage_Error)
            -> SCNGeometrySource {
            var data = Data(count: values.count * 2)
            values.withUnsafeBufferPointer { src in
                data.withUnsafeMutableBytes { dst in
                    let s = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: src.baseAddress), height: 1,
                                          width: vImagePixelCount(src.count), rowBytes: src.count * MemoryLayout<T>.size)
                    let d = vImage_Buffer(data: dst.baseAddress, height: 1, width: vImagePixelCount(src.count),
                                          rowBytes: src.count * 2)
                    _ = withUnsafePointer(to: s) { s in withUnsafePointer(to: d) { d in convert(s, d) } }
                }
            }
            return SCNGeometrySource(data: data, semantic: semantic, vectorCount: n, usesFloatComponents: true,
                                     componentsPerVector: components, bytesPerComponent: 2, dataOffset: 0,
                                     dataStride: 2 * components)
        }
        let float = { vImageConvert_PlanarFtoPlanar16F($0, $1, vImage_Flags(kvImageNoFlags)) }
        let sources = [
            source(mesh.positions, .vertex, components: 3, float),
            source(mesh.normals, .normal, components: 3, float),
            // 0…255 → 0…1.
            source(mesh.colors, .color, components: 4) { vImageConvert_Planar8toPlanar16F($0, $1, vImage_Flags(kvImageNoFlags)) },
        ]
        // 16-bit indices halve index memory for the common small model.
        let small = n <= Int(UInt16.max)
        let elements = mesh.parts.map { part -> SCNGeometryElement in
            let data: Data
            if small {
                var d = Data(count: part.indices.count * 2)
                d.withUnsafeMutableBytes { raw in
                    let out = raw.bindMemory(to: UInt16.self)
                    for (o, i) in part.indices.enumerated() { out[o] = UInt16(truncatingIfNeeded: mesh.indices[i]) }
                }
                data = d
            } else {
                data = mesh.indices[part.indices].withUnsafeBytes { Data($0) }
            }
            return SCNGeometryElement(data: data, primitiveType: .triangles, primitiveCount: part.triangleCount,
                                      bytesPerIndex: small ? 2 : 4)
        }
        return SCNGeometry(sources: sources, elements: elements)
    }

    static func matrix(_ r: VoxRotation, _ t: SIMD3<Float>) -> simd_float4x4 {
        let rows = r.rows
        return simd_float4x4(columns: (
            SIMD4(rows[0].x, rows[1].x, rows[2].x, 0),
            SIMD4(rows[0].y, rows[1].y, rows[2].y, 0),
            SIMD4(rows[0].z, rows[1].z, rows[2].z, 0),
            SIMD4(t.x, t.y, t.z, 1)
        ))
    }

    static func determinant(_ r: VoxRotation) -> Int32 {
        // Sign of the permutation times the product of signs.
        let c = r.columns
        let even = (c.x == 0 && c.y == 1) || (c.x == 1 && c.y == 2) || (c.x == 2 && c.y == 0)
        return (even ? 1 : -1) * r.signs.x * r.signs.y * r.signs.z
    }

    /// Flat, shadowless studio lighting: top faces brightest, sides stepped darker.
    static func addLights(to scene: SCNScene) {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 340
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light!.type = .directional
        key.light!.intensity = 560
        key.simdLook(at: SIMD3(-0.35, -1, -0.6), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light!.type = .directional
        fill.light!.intensity = 140
        fill.simdLook(at: SIMD3(0.6, 0.2, 0.5), up: SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
        scene.rootNode.addChildNode(fill)
    }
}
