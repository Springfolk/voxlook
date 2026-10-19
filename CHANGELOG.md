# Changelog

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
