import CoreGraphics
import Foundation
import Metal
import SceneKit
import VoxKit

/// Renders `.vox` files to images offscreen, on a transparent background.
public enum VoxThumbnailRenderer {
    // One Metal device per process; creating it is the expensive part.
    private static let device = MTLCreateSystemDefaultDevice()

    /// - Parameter pixelSize: output size in pixels.
    public static func render(_ voxScene: VoxScene, pixelSize: CGSize) -> CGImage? {
        let renderer = SCNRenderer(device: device, options: nil)
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
        render(VoxScene(file: try VoxFile(contentsOf: url)), pixelSize: pixelSize)
    }
}
