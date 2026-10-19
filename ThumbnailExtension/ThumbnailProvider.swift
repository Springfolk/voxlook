import AppKit
import QuickLookThumbnailing
import VoxKit
import VoxRender

/// Finder icons and Quick Look thumbnails. Quick Look caches the result, so
/// each file renders once until it changes.
final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest,
                                   _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        do {
            let side = min(request.maximumSize.width, request.maximumSize.height)
            let pixels = CGSize(width: side * request.scale, height: side * request.scale)
            guard let image = try VoxThumbnailRenderer.render(contentsOf: request.fileURL, pixelSize: pixels) else {
                handler(nil, CocoaError(.fileReadCorruptFile))
                return
            }
            handler(QLThumbnailReply(contextSize: CGSize(width: side, height: side)) { context in
                // The context is backed in pixels with no scale transform applied.
                context.draw(image, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
                return true
            }, nil)
        } catch {
            handler(nil, error)
        }
    }
}
