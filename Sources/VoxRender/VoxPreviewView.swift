import AppKit
import SceneKit
import VoxKit

/// Interactive orbit view of a `VoxScene` with a stats caption, the palette in
/// use, and — when the file has them — a play button and a layer menu.
/// Double-click resets the view.
///
/// Draws only when something changes: no continuous render loop, no shadows,
/// no post-processing, so an idle preview costs nothing. Playback ticks a
/// timer only while playing and only while the view is on screen.
public final class VoxPreviewView: NSView {
    public let sceneView: SCNView
    private let voxScene: VoxScene
    private let camera = SCNNode()
    private let caption = NSTextField(labelWithString: "")
    private var playButton: NSButton?
    private var timer: Timer?
    private var currentFrame = 0
    /// MagicaVoxel's default playback speed.
    private static let framesPerSecond = 10.0

    public init(scene voxScene: VoxScene) {
        self.voxScene = voxScene
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

        camera.camera = SCNCamera()
        camera.camera!.fieldOfView = 30
        voxScene.scene.rootNode.addChildNode(camera)
        resetCamera()

        let reset = NSClickGestureRecognizer(target: self, action: #selector(resetView))
        reset.numberOfClicksRequired = 2
        reset.delaysPrimaryMouseButtonEvents = false
        sceneView.addGestureRecognizer(reset)

        let d = voxScene.voxelDimensions
        var parts = ["\(d.x) × \(d.y) × \(d.z)", "\(voxScene.voxelCount.formatted()) voxels"]
        if voxScene.instanceCount != 1 { parts.append("\(voxScene.instanceCount) models") }
        if voxScene.frameCount > 1 { parts.append("\(voxScene.frameCount) frames") }
        caption.stringValue = parts.joined(separator: " · ")
        caption.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        caption.textColor = .secondaryLabelColor

        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 10
        bar.alignment = .centerY
        if voxScene.frameCount > 1 {
            let play = NSButton(image: Self.symbol("play.fill"), target: self, action: #selector(togglePlay))
            play.isBordered = false
            play.toolTip = "Play animation"
            playButton = play
            bar.addArrangedSubview(play)
        }
        bar.addArrangedSubview(caption)
        if !voxScene.usedColors.isEmpty { bar.addArrangedSubview(PaletteStrip(colors: voxScene.usedColors)) }
        if !voxScene.layers.isEmpty { bar.addArrangedSubview(layerMenu()) }

        for v in [sceneView, bar] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            sceneView.leadingAnchor.constraint(equalTo: leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: trailingAnchor),
            sceneView.topAnchor.constraint(equalTo: topAnchor),
            sceneView.bottomAnchor.constraint(equalTo: bottomAnchor),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            bar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() }
    }

    // MARK: - Camera

    private func resetCamera() {
        let size = sceneView.bounds.size
        let aspect = size.width > 0 && size.height > 0 ? Float(size.width / size.height) : 4 / 3
        voxScene.frame(camera, aspect: aspect)
        sceneView.pointOfView = camera
    }

    @objc private func resetView() {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.25
        resetCamera()
        SCNTransaction.commit()
    }

    // MARK: - Animation

    @objc private func togglePlay() {
        if timer == nil { play() } else { stop() }
    }

    private func play() {
        let t = Timer(timeInterval: 1 / Self.framesPerSecond, repeats: true) { [weak self] _ in
            guard let self else { return }
            currentFrame = (currentFrame + 1) % voxScene.frameCount
            voxScene.showFrame(currentFrame)
        }
        t.tolerance = 0.2 / Self.framesPerSecond  // lets the system coalesce wake-ups
        RunLoop.main.add(t, forMode: .common)
        timer = t
        playButton?.image = Self.symbol("pause.fill")
        playButton?.toolTip = "Pause animation"
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        playButton?.image = Self.symbol("play.fill")
        playButton?.toolTip = "Play animation"
    }

    // MARK: - Layers

    private func layerMenu() -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.isBordered = false
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.addItem(withTitle: "Layers")
        for layer in voxScene.layers {
            let item = NSMenuItem(title: layer.name, action: #selector(toggleLayer(_:)), keyEquivalent: "")
            item.target = self
            item.tag = layer.id
            item.state = layer.initiallyVisible ? .on : .off
            button.menu?.addItem(item)
        }
        return button
    }

    @objc private func toggleLayer(_ item: NSMenuItem) {
        item.state = item.state == .on ? .off : .on
        voxScene.setLayer(item.tag, visible: item.state == .on)
    }

    private static func symbol(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
    }
}

/// The most-used colours as a row of small swatches.
private final class PaletteStrip: NSView {
    private let colors: [NSColor]
    private static let swatch: CGFloat = 8, gap: CGFloat = 2, limit = 24

    init(colors: [VoxColor]) {
        self.colors = colors.prefix(Self.limit).map {
            NSColor(srgbRed: CGFloat($0.r) / 255, green: CGFloat($0.g) / 255, blue: CGFloat($0.b) / 255, alpha: 1)
        }
        super.init(frame: .zero)
        toolTip = colors.count == 1 ? "1 colour" : "\(colors.count) colours"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: CGFloat(colors.count) * (Self.swatch + Self.gap) - Self.gap, height: Self.swatch)
    }

    override func draw(_ dirtyRect: NSRect) {
        let y = (bounds.height - Self.swatch) / 2
        for (i, color) in colors.enumerated() {
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: CGFloat(i) * (Self.swatch + Self.gap), y: y,
                                             width: Self.swatch, height: Self.swatch), xRadius: 2, yRadius: 2).fill()
        }
    }
}
