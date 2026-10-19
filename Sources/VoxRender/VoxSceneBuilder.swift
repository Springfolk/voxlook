import Foundation
import SceneKit
import VoxKit

/// A ready-to-render SceneKit scene for a `.vox` file.
public struct VoxScene {
    public let scene: SCNScene
    /// World bounds in SceneKit coordinates (Y up).
    public let boundsMin: SIMD3<Float>
    public let boundsMax: SIMD3<Float>
    public let voxelCount: Int
    public let triangleCount: Int
    public let instanceCount: Int

    public var size: SIMD3<Float> { boundsMax - boundsMin }
    public var center: SIMD3<Float> { (boundsMin + boundsMax) / 2 }

    /// Size in voxels as MagicaVoxel shows it (X × Y × Z, Z up).
    public var voxelDimensions: (x: Int, y: Int, z: Int) {
        (Int(size.x.rounded()), Int(size.z.rounded()), Int(size.y.rounded()))
    }

    public init(file: VoxFile) {
        let scene = SCNScene()
        // MagicaVoxel is Z up; SceneKit is Y up.
        let world = SCNNode()
        world.eulerAngles.x = -.pi / 2
        scene.rootNode.addChildNode(world)

        var palette = file.palette
        for i in palette.indices { palette[i].a = 255 }  // glass etc. isn't modelled; keep everything opaque

        let material = SCNMaterial()
        material.lightingModel = .lambert
        material.diffuse.contents = NSColor.white  // multiplied by the vertex colours
        let mirrored = material.copy() as! SCNMaterial
        mirrored.isDoubleSided = true  // reflections flip winding

        var geometries: [Int: (geometry: SCNGeometry, lo: SIMD3<Float>, hi: SIMD3<Float>)] = [:]
        var mirroredGeometries: [Int: SCNGeometry] = [:]
        var lo = SIMD3<Float>(repeating: .infinity), hi = SIMD3<Float>(repeating: -.infinity)
        var voxels = 0, triangles = 0

        let instances = file.instances()
        for inst in instances {
            let model = file.models[inst.modelIndex]
            guard model.voxelCount > 0 else { continue }
            let entry: (geometry: SCNGeometry, lo: SIMD3<Float>, hi: SIMD3<Float>)
            if let e = geometries[inst.modelIndex] {
                entry = e
            } else {
                let mesh = model.mesh(palette: palette)
                let g = Self.geometry(from: mesh)
                g.firstMaterial = material
                // Tight bounds of the voxels, not the model box.
                var mlo = SIMD3<Float>(repeating: .infinity), mhi = -mlo
                mesh.positions.withUnsafeBufferPointer { p in
                    for i in Swift.stride(from: 0, to: p.count, by: 3) {
                        let v = SIMD3(p[i], p[i + 1], p[i + 2])
                        mlo = simd_min(mlo, v); mhi = simd_max(mhi, v)
                    }
                }
                entry = (g, mlo, mhi)
                geometries[inst.modelIndex] = entry
            }
            let geometry = entry.geometry
            let isMirror = Self.determinant(inst.rotation) < 0
            let node = SCNNode(geometry: isMirror ? {
                if let g = mirroredGeometries[inst.modelIndex] { return g }
                let g = geometry.copy() as! SCNGeometry  // shares vertex buffers
                g.firstMaterial = mirrored
                mirroredGeometries[inst.modelIndex] = g
                return g
            }() : geometry)
            node.simdTransform = Self.matrix(inst.rotation, inst.translation)
            world.addChildNode(node)

            voxels += model.voxelCount
            triangles += geometry.elements.first?.primitiveCount ?? 0
            for corner in 0..<8 {
                let local = SIMD3(corner & 1 == 0 ? entry.lo.x : entry.hi.x,
                                  corner & 2 == 0 ? entry.lo.y : entry.hi.y,
                                  corner & 4 == 0 ? entry.lo.z : entry.hi.z)
                let w = inst.rotation.apply(local) + inst.translation
                let p = SIMD3(w.x, w.z, -w.y)  // Z-up → Y-up
                lo = simd_min(lo, p); hi = simd_max(hi, p)
            }
        }
        if voxels == 0 { lo = .zero; hi = .zero }

        Self.addLights(to: scene)
        self.scene = scene
        boundsMin = lo; boundsMax = hi
        voxelCount = voxels; triangleCount = triangles; instanceCount = instances.count
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

    static func geometry(from mesh: VoxMesh) -> SCNGeometry {
        let n = mesh.vertexCount
        let positions = mesh.positions.withUnsafeBytes { Data($0) }
        let normals = mesh.normals.withUnsafeBytes { Data($0) }
        // SceneKit doesn't normalise byte colours, so widen to floats.
        let colors = mesh.colors.map { Float($0) / 255 }.withUnsafeBytes { Data($0) }
        let sources = [
            SCNGeometrySource(data: positions, semantic: .vertex, vectorCount: n, usesFloatComponents: true,
                              componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12),
            SCNGeometrySource(data: normals, semantic: .normal, vectorCount: n, usesFloatComponents: true,
                              componentsPerVector: 3, bytesPerComponent: 4, dataOffset: 0, dataStride: 12),
            SCNGeometrySource(data: colors, semantic: .color, vectorCount: n, usesFloatComponents: true,
                              componentsPerVector: 4, bytesPerComponent: 4, dataOffset: 0, dataStride: 16),
        ]
        // 16-bit indices halve index memory for the common small model.
        let element: SCNGeometryElement
        if n <= Int(UInt16.max) {
            let small = mesh.indices.map { UInt16($0) }
            element = SCNGeometryElement(data: small.withUnsafeBytes { Data($0) }, primitiveType: .triangles,
                                         primitiveCount: mesh.triangleCount, bytesPerIndex: 2)
        } else {
            element = SCNGeometryElement(data: mesh.indices.withUnsafeBytes { Data($0) }, primitiveType: .triangles,
                                         primitiveCount: mesh.triangleCount, bytesPerIndex: 4)
        }
        return SCNGeometry(sources: sources, elements: [element])
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
