# Architecture

| Target | Path | Role |
|---|---|---|
| `VoxKit` | `Sources/VoxKit` | Parse `.vox` → `VoxFile`; flatten scene graph → `[VoxInstance]`; greedy mesh → `VoxMesh`. Foundation + simd only. |
| `VoxRender` | `Sources/VoxRender` | `VoxScene` (SceneKit scene, bounds, camera framing), `VoxThumbnailRenderer` (offscreen `SCNRenderer`), `VoxPreviewView` (AppKit). |
| `voxthumb` | `Sources/voxthumb` | CLI: `.vox` → PNG via `VoxThumbnailRenderer`. |
| `VoxLook` app | `App/` | Host for the extensions; welcome screen, drop/open viewer. Declares the `com.ephtracy.vox` UTI. |
| Preview ext. | `PreviewExtension/` | `QLPreviewingController`; parses off-main, shows `VoxPreviewView`. |
| Thumbnail ext. | `ThumbnailExtension/` | `QLThumbnailProvider`; orthographic render, transparent background. |

Flow: `VoxFile(data:)` → `instances()` → per used model `mesh()` (cached per model index) → one `SCNGeometry` shared by every instance (mirrored instances get a double-sided copy) → nodes under a root rotated −90° about X (Z-up → Y-up).

Performance choices: dense `UInt8` grid per model; greedy meshing by colour; 16-bit indices when ≤ 65 535 vertices; one Metal device per process; `SCNView` with `rendersContinuously = false`, low-power GPU, no shadows.
