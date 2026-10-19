import Cocoa
import QuickLookUI
import VoxKit
import VoxRender

/// Space-bar preview in Finder: an orbitable 3D view of the model.
final class PreviewViewController: NSViewController, QLPreviewingController {
    override func loadView() {
        view = NSView()
        preferredContentSize = NSSize(width: 800, height: 600)
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let voxScene = try await Task.detached(priority: .userInitiated) {
            VoxScene(file: try VoxFile(contentsOf: url))
        }.value
        let preview = VoxPreviewView(scene: voxScene)
        preview.frame = view.bounds
        preview.autoresizingMask = [.width, .height]
        view.addSubview(preview)
    }
}
