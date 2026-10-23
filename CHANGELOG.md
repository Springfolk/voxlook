# Changelog

## 1.2.0 — 2026-10-23

- Ambient occlusion: corners and creases are shaded, baked in at mesh time so drawing costs nothing extra.
- Materials: emissive voxels glow, metal gets a highlight, glass is see-through and keeps what's behind it visible.
- Preview: play button for animated files, a layer menu (hidden layers can be shown), the palette in use, double-click to reset the view.
- Spotlight importer: object and layer names become searchable; size and voxel count become the file's description.
- Lighter: the parser reads the memory-mapped file without copying it, vertex data is half-precision, and bounds come from the occupied voxels instead of a scan of every vertex.
- `voxthumb --bench` reports CPU time, triangles and peak memory for a set of files.

## 1.1.0 — 2026-10-19

- One-line installer (`install.sh`) that downloads a universal, prebuilt app from the latest release, plus `--uninstall`.
- The installer relaunches Finder, so files that cached a plain icon before VoxLook was installed show their thumbnails.
- A VoxLook document icon for `.vox`, used when VoxLook is the app that opens them.
- Lighter: models store only their occupied voxels, thumbnails reuse parsed scenes across Finder's size requests, and rendering prefers the low-power GPU.

## 1.0.0 — 2026-10-19

First release.

- Quick Look thumbnail and preview extensions for MagicaVoxel `.vox`.
- Scene graph support: multiple models, groups, rotations, mirroring, hidden layers and objects.
- `VoxKit` and `VoxRender` Swift packages; `voxthumb` CLI.
