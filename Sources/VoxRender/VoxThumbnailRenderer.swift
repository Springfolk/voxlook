import CoreGraphics
import Foundation
import Metal
import SceneKit
import VoxKit

/// Renders `.vox` files to images offscreen, on a transparent background.
///
/// Thread-safe. Finder asks for each file at several sizes in a row, so the
/// last few parsed scenes are kept and the renderer is reused.
public enum VoxThumbnailRenderer {
    private static let lock = NSLock()
    // The integrated GPU on dual-GPU Macs: thumbnails never need the discrete one.
    private static let device = MTLCopyAllDevices().first(where: \.isLowPower) ?? MTLCreateSystemDefaultDevice()
    private static var renderer: SCNRenderer?
    private static var recent: [(key: String, scene: VoxScene)] = []
    private static let recentLimit = 4

    /// - Parameter pixelSize: output size in pixels.
    public static func render(_ voxScene: VoxScene, pixelSize: CGSize) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        let renderer = renderer ?? SCNRenderer(device: device, options: nil)
        Self.renderer = renderer
        defer { renderer.scene = nil }  // don't pin the scene once it leaves the cache

        voxScene.scene.background.contents = NSColor.clear
        renderer.scene = voxScene.scene
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera!.usesOrthographicProjection = true  // isometric look reads best at icon sizes
        voxScene.scene.rootNode.addChildNode(cameraNode)
        defer { cameraNode.removeFromParentNode() }
        voxScene.frame(cameraNode, aspect: Float(pixelSize.width / pixelSize.height), margin: 1.02)
        renderer.pointOfView = cameraNode

        let image = renderer.snapshot(atTime: 0, with: pixelSize, antialiasingMode: .multisampling4X)
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    public static func render(contentsOf url: URL, pixelSize: CGSize) throws -> CGImage? {
        render(try scene(contentsOf: url), pixelSize: pixelSize)
    }

    /// Parses and meshes `url`, or returns the cached scene if the file is unchanged.
    public static func scene(contentsOf url: URL) throws -> VoxScene {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let key = "\(url.path)|\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(values?.fileSize ?? 0)"
        lock.lock()
        if let hit = recent.firstIndex(where: { $0.key == key }) {
            let entry = recent.remove(at: hit)
            recent.append(entry)
            lock.unlock()
            return entry.scene
        }
        lock.unlock()

        let scene = VoxScene(file: try VoxFile(contentsOf: url))
        lock.lock()
        recent.append((key, scene))
        if recent.count > recentLimit { recent.removeFirst() }
        lock.unlock()
        return scene
    }
}
