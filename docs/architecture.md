# Architecture

| Target | Path | Role |
|---|---|---|
| `VoxKit` | `Sources/VoxKit` | Parse `.vox` → `VoxFile` (zero-copy over mapped bytes); sample the scene graph at a frame → `[VoxInstance]`; greedy mesh with baked AO, split by `VoxSurface` → `VoxMesh`; `VoxSummary`. Foundation + simd only. |
| `VoxRender` | `Sources/VoxRender` | `VoxScene` (SceneKit scene, one material per surface, bounds, framing; `interactive:` adds every frame, hidden layers, colour use), `VoxThumbnailRenderer` (offscreen `SCNRenderer`), `VoxPreviewView` (AppKit: play, layers, palette, double-click reset). |
| `voxthumb` | `Sources/voxthumb` | CLI: `.vox` → PNG via `VoxThumbnailRenderer`; `--bench` prints CPU, triangles, peak RSS. |
| `VoxLook` app | `App/` | Host for the extensions; welcome screen, drop/open viewer. Declares the `com.ephtracy.vox` UTI. |
| Preview ext. | `PreviewExtension/` | `QLPreviewingController`; parses off-main, shows `VoxPreviewView`. |
| Thumbnail ext. | `ThumbnailExtension/` | `QLThumbnailProvider`; orthographic render, transparent background. |
| Spotlight importer | `SpotlightImporter/` | Classic `.mdimporter` in `Contents/Library/Spotlight` (C CFPlugIn shim → Swift `VoxSummary`): description, version, object/layer names. Parses only. |

Flow: `VoxFile(data:)` → `instances(frame:)` → per used model `mesh(palette:surfaces:)` (cached per model index) → one `SCNGeometry` per model, one element per surface, shared by every instance (mirrored instances get a double-sided copy) → nodes under a frame container under a root rotated −90° about X (Z-up → Y-up).

Performance choices: dense `UInt8` grid cropped to each model's occupied box; greedy meshing by colour + AO pattern, stretching only along axes the AO doesn't vary on (exact, no streaks); half-float vertex data; 16-bit indices when ≤ 65 535 vertices; bounds from occupied boxes, not vertices; thumbnails build frame 0 only; one low-power Metal device and one `SCNRenderer` per process, scenes of the last 4 files cached (Finder asks for several sizes per file); `SCNView` with `rendersContinuously = false`, low-power GPU, no shadows; playback timer runs only while playing and on screen.

Surfaces (`VoxMaterial.surface`): diffuse → Lambert; metal → Blinn + specular; emissive → unlit; glass → Blinn, alpha from `_trans`, no depth write, keeps faces behind it, gets no AO and casts none.
