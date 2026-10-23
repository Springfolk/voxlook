// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoxLook",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VoxKit", targets: ["VoxKit"]),
        .library(name: "VoxRender", targets: ["VoxRender"]),
        .executable(name: "voxthumb", targets: ["voxthumb"]),
    ],
    targets: [
        // Pure Foundation: .vox parsing, scene flattening, meshing.
        .target(name: "VoxKit"),
        // SceneKit scene building and offscreen rendering.
        .target(name: "VoxRender", dependencies: ["VoxKit"]),
        // CLI: render a .vox to PNG (same code path as Finder thumbnails).
        .executableTarget(name: "voxthumb", dependencies: ["VoxKit", "VoxRender"]),
        .testTarget(name: "VoxKitTests", dependencies: ["VoxKit", "VoxRender"]),
    ]
)
