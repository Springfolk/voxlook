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
}
