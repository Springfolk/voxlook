import Metal
import XCTest
import simd
@testable import VoxKit
import VoxRender

final class ParserTests: XCTestCase {
    func testSingleModelWithDefaultPalette() throws {
        var w = VoxWriter()
        w.model(size: (2, 3, 4), voxels: [(0, 0, 0, 1), (1, 2, 3, 79), (9, 9, 9, 5)])  // last is out of bounds
        let file = try VoxFile(data: w.data)
        XCTAssertEqual(file.version, 200)
        XCTAssertEqual(file.models.count, 1)
        let m = file.models[0]
        XCTAssertEqual([m.sizeX, m.sizeY, m.sizeZ], [2, 3, 4])
        XCTAssertEqual(m.voxelCount, 2)
        XCTAssertEqual(m[1, 2, 3], 79)
        XCTAssertEqual(file.palette.count, 256)
        XCTAssertEqual(file.palette[1], VoxColor(r: 255, g: 255, b: 255))
        XCTAssertEqual(file.palette[255], VoxColor(r: 0x11, g: 0x11, b: 0x11))
    }

    func testRGBAEntryKColoursIndexKPlusOne() throws {
        var w = VoxWriter()
        w.model(size: (1, 1, 1), voxels: [(0, 0, 0, 1)])
        var rgba = Data(count: 1024)
        rgba[0] = 10; rgba[1] = 20; rgba[2] = 30; rgba[3] = 255
        w.chunk("RGBA", rgba)
        XCTAssertEqual(try VoxFile(data: w.data).palette[1], VoxColor(r: 10, g: 20, b: 30))
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try VoxFile(data: Data("hello world".utf8))) {
            XCTAssertEqual($0 as? VoxError, .notAVoxFile)
        }
        XCTAssertThrowsError(try VoxFile(data: Data()))
    }

    func testEveryTruncationThrowsInsteadOfCrashing() throws {
        var w = VoxWriter()
        w.model(size: (3, 3, 3), voxels: [(1, 1, 1, 3)])
        w.transform(id: 0, child: 1, frame: ["_t": "1 2 3", "_r": "4"])
        w.group(id: 1, children: [2])
        w.transform(id: 2, child: 3)
        w.shape(id: 3, model: 0)
        let full = w.data
        XCTAssertNoThrow(try VoxFile(data: full))
        for n in 0..<full.count {
            _ = try? VoxFile(data: full.prefix(n))
        }
    }

    func testRejectsHugeModelSize() {
        var w = VoxWriter()
        w.chunk("SIZE", VoxWriter.int32(100_000) + VoxWriter.int32(100_000) + VoxWriter.int32(100_000))
        XCTAssertThrowsError(try VoxFile(data: w.data))
    }
}

final class RotationTests: XCTestCase {
    func testIdentityByte() {
        XCTAssertEqual(VoxRotation(packed: 4), .identity)
    }

    func testInvalidPermutationIsRejected() {
        XCTAssertNil(VoxRotation(packed: 0))  // both rows in column 0
    }

    func testApplyAndConcatenate() throws {
        // Row 0 takes y, row 1 takes −x: a quarter turn about Z.
        let r = try XCTUnwrap(VoxRotation(packed: 0b0010_0001))
        XCTAssertEqual(r.apply(SIMD3(1, 0, 0)), SIMD3(0, -1, 0))
        XCTAssertEqual(r.apply(SIMD3(0, 1, 0)), SIMD3(1, 0, 0))
        XCTAssertEqual(r.concatenating(r).concatenating(r).concatenating(r), .identity)
        XCTAssertEqual(r.applyToSize(SIMD3(1, 2, 3)), SIMD3(2, 1, 3))
    }
}

final class SceneTests: XCTestCase {
    func testWithoutSceneGraphEveryModelIsAnInstance() throws {
        var w = VoxWriter()
        w.model(size: (1, 1, 1), voxels: [(0, 0, 0, 1)])
        w.model(size: (1, 1, 1), voxels: [(0, 0, 0, 2)])
        XCTAssertEqual(try VoxFile(data: w.data).instances().count, 2)
    }

    func testTranslationAndHiddenLayer() throws {
        var w = VoxWriter()
        w.model(size: (2, 2, 3), voxels: [(0, 0, 0, 1)])
        w.transform(id: 0, child: 1)
        w.group(id: 1, children: [2, 4])
        w.transform(id: 2, child: 3, frame: ["_t": "10 0 -5"])
        w.shape(id: 3, model: 0)
        w.transform(id: 4, child: 5, layer: 1)
        w.shape(id: 5, model: 0)
        w.chunk("LAYR", VoxWriter.int32(1) + VoxWriter.dict(["_hidden": "1"]) + VoxWriter.int32(-1))
        let instances = try VoxFile(data: w.data).instances()
        XCTAssertEqual(instances.count, 1)
        // Odd Z extent shifts half a voxel: floor(size/2) sits at the translation.
        XCTAssertEqual(instances[0].translation, SIMD3(10, 0, -4.5))
    }

    func testCyclicGraphTerminates() throws {
        var w = VoxWriter()
        w.model(size: (1, 1, 1), voxels: [(0, 0, 0, 1)])
        w.transform(id: 0, child: 1)
        w.group(id: 1, children: [0])
        XCTAssertEqual(try VoxFile(data: w.data).instances().count, 0)
    }
}

final class MesherTests: XCTestCase {
    func testSingleVoxelIsACube() {
        var m = VoxModel(sizeX: 1, sizeY: 1, sizeZ: 1)
        m[0, 0, 0] = 1
        let mesh = m.mesh(palette: VoxPalette.default)
        XCTAssertEqual(mesh.triangleCount, 12)
        XCTAssertEqual(mesh.vertexCount, 24)
        XCTAssertEqual(mesh.positions.min(), -0.5)
        XCTAssertEqual(mesh.positions.max(), 0.5)
    }

    func testSparseModelStoresOnlyItsBoundingBox() throws {
        var w = VoxWriter()
        w.model(size: (256, 256, 256), voxels: [(10, 20, 30, 1), (11, 20, 30, 1)])
        let m = try VoxFile(data: w.data).models[0]
        XCTAssertEqual(m.extent, SIMD3(2, 1, 1))
        XCTAssertEqual(m.cells.count, 2)
        XCTAssertEqual(m[11, 20, 30], 1)
        XCTAssertEqual(m[0, 0, 0], 0)
        // Geometry still sits where the voxels are in the centred box.
        let mesh = m.mesh(palette: VoxPalette.default)
        let xs = stride(from: 0, to: mesh.positions.count, by: 3).map { mesh.positions[$0] }
        let zs = stride(from: 2, to: mesh.positions.count, by: 3).map { mesh.positions[$0] }
        XCTAssertEqual(xs.min(), 10 - 128)
        XCTAssertEqual(xs.max(), 12 - 128)
        XCTAssertEqual(zs.min(), 30 - 128)
        XCTAssertEqual(mesh.triangleCount, 12)
    }

    func testSameColourFacesMerge() {
        var m = VoxModel(sizeX: 4, sizeY: 4, sizeZ: 4)
        for x in 0..<4 { for y in 0..<4 { for z in 0..<4 { m[x, y, z] = 7 } } }
        XCTAssertEqual(m.mesh(palette: VoxPalette.default).triangleCount, 12)
    }

    func testDifferentColoursDoNotMerge() {
        var m = VoxModel(sizeX: 2, sizeY: 1, sizeZ: 1)
        m[0, 0, 0] = 1
        m[1, 0, 0] = 2
        // Shared face culled; the four sides can't merge across colours → 10 quads.
        XCTAssertEqual(m.mesh(palette: VoxPalette.default).triangleCount, 20)
    }

    func testFacesWindCounterClockwise() {
        var m = VoxModel(sizeX: 1, sizeY: 1, sizeZ: 1)
        m[0, 0, 0] = 1
        let mesh = m.mesh(palette: VoxPalette.default)
        func vec(_ a: [Float], _ vertex: UInt32) -> SIMD3<Float> {
            let i = Int(vertex) * 3
            return SIMD3(a[i], a[i + 1], a[i + 2])
        }
        for t in 0..<mesh.triangleCount {
            let ids = mesh.indices[t * 3..<t * 3 + 3].map { $0 }
            let p = ids.map { vec(mesh.positions, $0) }
            let winding = simd_cross(p[1] - p[0], p[2] - p[0])
            XCTAssertGreaterThan(simd_dot(winding, vec(mesh.normals, ids[0])), 0, "triangle \(t)")
        }
    }
}

final class MaterialTests: XCTestCase {
    func testMaterialsMapToSurfaces() throws {
        var w = VoxWriter()
        w.model(size: (1, 1, 1), voxels: [(0, 0, 0, 1)])
        w.material(1, ["_type": "_diffuse"])  // default: not stored
        w.material(2, ["_type": "_glass", "_trans": "0.6"])
        w.material(3, ["_type": "_emit", "_emit": "2"])
        w.material(4, ["_type": "_metal", "_metal": "1", "_rough": "0.3"])
        w.material(5, ["_type": "_glass", "_trans": "0"])  // opaque glass reads as diffuse
        let file = try VoxFile(data: w.data)
        XCTAssertNil(file.materials[1])
        XCTAssertEqual(file.materials[2]?.transparency, 0.6)
        XCTAssertEqual(file.materials[4]?.roughness, 0.3)
        XCTAssertEqual(file.surfaces[1...5].map { $0 }, [.diffuse, .glass, .emissive, .metal, .diffuse])
    }

    func testMeshSplitsIntoSurfaceParts() {
        var m = VoxModel(sizeX: 3, sizeY: 1, sizeZ: 1)
        m[0, 0, 0] = 1; m[1, 0, 0] = 2; m[2, 0, 0] = 3
        var surfaces = [VoxSurface](repeating: .diffuse, count: 256)
        surfaces[2] = .emissive; surfaces[3] = .metal
        let mesh = m.mesh(palette: VoxPalette.default, surfaces: surfaces)
        XCTAssertEqual(mesh.parts.map(\.surface), [.diffuse, .metal, .emissive])
        XCTAssertEqual(mesh.parts.reduce(0) { $0 + $1.indices.count }, mesh.indices.count)
        XCTAssertEqual(mesh.parts.first?.indices.lowerBound, 0)
    }

    func testFacesBehindGlassStay() {
        // Opaque voxel next to glass keeps its face; glass next to opaque drops its own.
        var m = VoxModel(sizeX: 2, sizeY: 1, sizeZ: 1)
        m[0, 0, 0] = 1; m[1, 0, 0] = 2
        var surfaces = [VoxSurface](repeating: .diffuse, count: 256)
        surfaces[2] = .glass
        let mesh = m.mesh(palette: VoxPalette.default, surfaces: surfaces)
        XCTAssertEqual(mesh.parts.first { $0.surface == .diffuse }?.triangleCount, 12)
        XCTAssertEqual(mesh.parts.first { $0.surface == .glass }?.triangleCount, 10)
        // Two glass voxels merge into one blob with no inner faces.
        m[0, 0, 0] = 2
        XCTAssertEqual(m.mesh(palette: VoxPalette.default, surfaces: surfaces).triangleCount, 12)
    }
}

final class AmbientOcclusionTests: XCTestCase {
    /// Vertex brightness (red channel; the palette entry is white).
    private func shades(_ mesh: VoxMesh) -> [UInt8] { stride(from: 0, to: mesh.colors.count, by: 4).map { mesh.colors[$0] } }

    func testOpenSurfacesStayFullBrightAndMerged() {
        var m = VoxModel(sizeX: 4, sizeY: 4, sizeZ: 4)
        for x in 0..<4 { for y in 0..<4 { for z in 0..<4 { m[x, y, z] = 1 } } }
        let mesh = m.mesh(palette: VoxPalette.default)
        XCTAssertEqual(mesh.triangleCount, 12)
        XCTAssertTrue(shades(mesh).allSatisfy { $0 == 255 })
    }

    func testCreaseDarkensAndMergesAlongIt() {
        // An L: a 6-long floor row with a wall row on top of its back edge.
        var m = VoxModel(sizeX: 6, sizeY: 2, sizeZ: 2)
        for x in 0..<6 { m[x, 0, 0] = 1; m[x, 1, 0] = 1; m[x, 1, 1] = 1 }
        let mesh = m.mesh(palette: VoxPalette.default)
        XCTAssertTrue(shades(mesh).contains { $0 < 255 }, "the inner corner gets darker")
        // The floor's top in front of the wall: the two ends shade differently (open
        // past the wall's end); the four in between merge into one quad.
        let n = mesh.vertexCount
        let tops = (0..<n).filter { mesh.normals[$0 * 3 + 2] == 1 && mesh.positions[$0 * 3 + 2] == 0 }
        XCTAssertEqual(tops.count, 12)
        XCTAssertEqual(Set(tops.map { mesh.positions[$0 * 3] }), [-3, -2, 2, 3])
    }

    func testCanBeTurnedOff() {
        var m = VoxModel(sizeX: 2, sizeY: 2, sizeZ: 2)
        m[0, 0, 0] = 1; m[1, 0, 0] = 1; m[0, 1, 0] = 1; m[0, 0, 1] = 1
        XCTAssertTrue(shades(m.mesh(palette: VoxPalette.default, ambientOcclusion: false)).allSatisfy { $0 == 255 })
        XCTAssertTrue(shades(m.mesh(palette: VoxPalette.default)).contains { $0 < 255 })
    }
}

final class AnimationTests: XCTestCase {
    private func animated() -> VoxFile? {
        var w = VoxWriter()
        w.model(size: (2, 2, 2), voxels: [(0, 0, 0, 1)])
        w.model(size: (2, 2, 2), voxels: [(1, 1, 1, 2)])
        w.transform(id: 0, child: 1)
        w.group(id: 1, children: [2])
        w.transform(id: 2, child: 3, frames: [["_f": "0", "_t": "0 0 0"], ["_f": "4", "_t": "10 0 0"]])
        w.shape(id: 3, frames: [(0, 0), (1, 2)])
        return try? VoxFile(data: w.data)
    }

    func testFrameCountAndSampling() throws {
        let file = try XCTUnwrap(animated())
        XCTAssertEqual(file.frameCount, 5)
        XCTAssertEqual(file.instances(frame: 0).first?.modelIndex, 0)
        XCTAssertEqual(file.instances(frame: 1).first?.translation.x, 0)
        XCTAssertEqual(file.instances(frame: 2).first?.modelIndex, 1)  // shape key holds from frame 2
        XCTAssertEqual(file.instances(frame: 4).first?.translation.x, 10)
    }

    func testStillFileHasOneFrame() throws {
        var w = VoxWriter()
        w.model(size: (1, 1, 1), voxels: [(0, 0, 0, 1)])
        XCTAssertEqual(try VoxFile(data: w.data).frameCount, 1)
    }
}

final class SummaryTests: XCTestCase {
    func testHiddenLayersAndNames() throws {
        var w = VoxWriter()
        w.model(size: (3, 4, 5), voxels: [(0, 0, 0, 1), (2, 3, 4, 1)])
        w.transform(id: 0, child: 1)
        w.group(id: 1, children: [2, 4])
        w.transform(id: 2, child: 3, layer: 0, name: "tower", frames: [[:]])
        w.shape(id: 3, model: 0)
        w.transform(id: 4, child: 5, layer: 1, frames: [["_t": "20 0 0"]])
        w.shape(id: 5, model: 0)
        w.layer(0, name: "castle")
        w.layer(1, name: "scaffold", hidden: true)
        let file = try VoxFile(data: w.data)
        XCTAssertEqual(file.instances().count, 1)
        XCTAssertEqual(file.instances(includeHiddenLayers: true).map(\.layer), [0, 1])
        let summary = VoxSummary(file)
        XCTAssertEqual(summary.dimensions, SIMD3(3, 4, 5))
        XCTAssertEqual(summary.voxelCount, 2)
        XCTAssertEqual(summary.names, ["tower", "castle", "scaffold"])
        XCTAssertEqual(summary.description, "3 × 4 × 5 voxels, 2 filled")
    }
}

final class RenderTests: XCTestCase {
    func testBoundsAndRender() throws {
        try XCTSkipIf(MTLCreateSystemDefaultDevice() == nil, "no Metal device (CI VM)")
        var w = VoxWriter()
        w.model(size: (4, 2, 6), voxels: [(0, 0, 0, 1), (3, 1, 5, 2)])
        let scene = VoxScene(file: try VoxFile(data: w.data))
        XCTAssertEqual(scene.voxelDimensions.x, 4)
        XCTAssertEqual(scene.voxelDimensions.y, 2)
        XCTAssertEqual(scene.voxelDimensions.z, 6)
        let image = try XCTUnwrap(VoxThumbnailRenderer.render(scene, pixelSize: CGSize(width: 64, height: 64)))
        XCTAssertEqual(image.width, 64)
    }

    func testInteractiveSceneBuildsFramesLayersAndPalette() throws {
        var w = VoxWriter()
        w.model(size: (2, 2, 2), voxels: [(0, 0, 0, 1), (1, 0, 0, 1), (1, 1, 1, 9)])
        w.model(size: (2, 2, 2), voxels: [(1, 1, 1, 2)])
        w.transform(id: 0, child: 1)
        w.group(id: 1, children: [2, 4])
        w.transform(id: 2, child: 3, layer: 0, frames: [[:]])
        w.shape(id: 3, frames: [(0, 0), (1, 3)])
        w.transform(id: 4, child: 5, layer: 1, frames: [["_t": "6 0 0"]])
        w.shape(id: 5, model: 1)
        w.layer(0, name: "0")
        w.layer(1, name: "b", hidden: true)
        let file = try VoxFile(data: w.data)
        let thumb = VoxScene(file: file)
        XCTAssertEqual(thumb.frameCount, 1)
        XCTAssertTrue(thumb.layers.isEmpty && thumb.usedColors.isEmpty)
        let scene = VoxScene(file: file, interactive: true)
        XCTAssertEqual(scene.frameCount, 4)
        XCTAssertEqual(scene.layers.map(\.initiallyVisible), [true, false])
        XCTAssertEqual(scene.layers.map(\.name), ["Layer 0", "b"])
        XCTAssertEqual(scene.usedColors.first, file.palette[1])  // two voxels of colour 1
        XCTAssertEqual(scene.instanceCount, 1)  // the hidden layer isn't counted
        XCTAssertEqual(scene.voxelDimensions.x, 2)

        let frames = scene.scene.rootNode.childNodes[0].childNodes  // world → one container per frame
        XCTAssertEqual(frames.map(\.isHidden), [false, true, true, true])
        scene.showFrame(2)
        XCTAssertEqual(frames.map(\.isHidden), [true, true, false, true])
        let hiddenLayer = frames.flatMap(\.childNodes).filter(\.isHidden)
        XCTAssertEqual(hiddenLayer.count, 4)  // layer "b" in each frame
        scene.setLayer(1, visible: true)
        XCTAssertTrue(frames.flatMap(\.childNodes).allSatisfy { !$0.isHidden })
    }
}
