import AppKit
import SceneKit

/// Interactive orbit view of a `VoxScene` with a one-line stats caption.
///
/// Draws only when something changes: no continuous render loop, no shadows,
/// no post-processing, so an idle preview costs nothing.
public final class VoxPreviewView: NSView {
    public let sceneView: SCNView
    private let caption = NSTextField(labelWithString: "")

    public init(scene voxScene: VoxScene) {
        // Prefer the efficiency GPU on dual-GPU Macs.
        sceneView = SCNView(frame: .zero, options: [
            SCNView.Option.preferLowPowerDevice.rawValue: true,
            SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue,
        ])
        super.init(frame: .zero)

        voxScene.scene.background.contents = NSColor.clear
        sceneView.scene = voxScene.scene
        sceneView.backgroundColor = .clear
        sceneView.antialiasingMode = .multisampling4X
        sceneView.rendersContinuously = false
        sceneView.isPlaying = false
        sceneView.allowsCameraControl = true
        sceneView.defaultCameraController.interactionMode = .orbitTurntable
        sceneView.defaultCameraController.inertiaEnabled = true

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera!.fieldOfView = 30
        voxScene.scene.rootNode.addChildNode(camera)
        voxScene.frame(camera, aspect: 4 / 3)
        sceneView.pointOfView = camera

        let d = voxScene.voxelDimensions
        let models = voxScene.instanceCount == 1 ? "" : " · \(voxScene.instanceCount) models"
        caption.stringValue = "\(d.x) × \(d.y) × \(d.z) · \(voxScene.voxelCount.formatted()) voxels\(models)"
        caption.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        caption.textColor = .secondaryLabelColor

        for v in [sceneView, caption] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            sceneView.leadingAnchor.constraint(equalTo: leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: trailingAnchor),
            sceneView.topAnchor.constraint(equalTo: topAnchor),
            sceneView.bottomAnchor.constraint(equalTo: bottomAnchor),
            caption.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            caption.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}
