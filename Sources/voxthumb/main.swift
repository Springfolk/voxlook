import Foundation
import ImageIO
import UniformTypeIdentifiers
import VoxRender

let usage = "usage: voxthumb <in.vox> <out.png> [size=512]"
let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(64)
}
let size = args.count > 3 ? Int(args[3]) ?? 512 : 512

do {
    let start = Date()
    guard let image = try VoxThumbnailRenderer.render(contentsOf: URL(fileURLWithPath: args[1]),
                                                      pixelSize: CGSize(width: size, height: size)),
          let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL,
                                                      UTType.png.identifier as CFString, 1, nil)
    else {
        FileHandle.standardError.write(Data("voxthumb: rendering failed\n".utf8))
        exit(1)
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { exit(1) }
    print(String(format: "%@ → %@ (%.0f ms)", args[1], args[2], Date().timeIntervalSince(start) * 1000))
} catch {
    FileHandle.standardError.write(Data("voxthumb: \(error)\n".utf8))
    exit(1)
}
