import Foundation
import ImageIO
import UniformTypeIdentifiers
import VoxKit
import VoxRender

let usage = """
usage: voxthumb <in.vox> <out.png> [size=512]
       voxthumb --bench [size=256] <file.vox>...   parse, mesh and render each file; print totals
"""
let args = CommandLine.arguments

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

/// User + system CPU seconds of this process.
func cpuTime() -> Double {
    var u = rusage()
    getrusage(RUSAGE_SELF, &u)
    return Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1e6
}

if args.count >= 2, args[1] == "--bench" {
    var files = Array(args.dropFirst(2))
    var size = 256
    if let first = files.first, let n = Int(first) { size = n; files.removeFirst() }
    guard !files.isEmpty else { fail(usage, code: 64) }
    var parse = 0.0, build = 0.0, render = 0.0, triangles = 0, failed = 0
    let start = cpuTime()
    for path in files {
        autoreleasepool {
            do {
                var t = cpuTime()
                let file = try VoxFile(contentsOf: URL(fileURLWithPath: path))
                parse += cpuTime() - t; t = cpuTime()
                let scene = VoxScene(file: file)
                build += cpuTime() - t; t = cpuTime()
                _ = VoxThumbnailRenderer.render(scene, pixelSize: CGSize(width: size, height: size))
                render += cpuTime() - t
                triangles += scene.triangleCount
            } catch {
                failed += 1
                FileHandle.standardError.write(Data("\(path): \(error)\n".utf8))
            }
        }
    }
    var u = rusage()
    getrusage(RUSAGE_SELF, &u)
    print(String(format: "%d files (%d failed) · CPU %.2f s: parse %.2f, mesh+scene %.2f, render %.2f · %@ triangles · peak %.0f MB",
                 files.count, failed, cpuTime() - start, parse, build, render,
                 triangles.formatted(), Double(u.ru_maxrss) / 1_048_576))
    exit(0)
}

guard args.count >= 3 else { fail(usage, code: 64) }
let size = args.count > 3 ? Int(args[3]) ?? 512 : 512

do {
    let start = Date()
    guard let image = try VoxThumbnailRenderer.render(contentsOf: URL(fileURLWithPath: args[1]),
                                                      pixelSize: CGSize(width: size, height: size)),
          let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL,
                                                      UTType.png.identifier as CFString, 1, nil)
    else { fail("voxthumb: rendering failed") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { exit(1) }
    print(String(format: "%@ → %@ (%.0f ms)", args[1], args[2], Date().timeIntervalSince(start) * 1000))
} catch {
    fail("voxthumb: \(error)")
}
