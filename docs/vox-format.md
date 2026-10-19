# .vox format notes

Spec: <https://github.com/ephtracy/voxel-model>. What we rely on:

- Chunks: `SIZE`/`XYZI` pairs (models, in order), `RGBA`, `nTRN`, `nGRP`, `nSHP`, `LAYR`. Everything else is skipped (`MATL`, `rOBJ`, `rCAM`, `NOTE`, `IMAP`).
- `RGBA` entry *k* colours palette index *k + 1*. No `RGBA` → `VoxPalette.default` (generated, not a table).
- `nTRN` frame `_r`: packed row-major signed permutation (`VoxRotation`); `4` = identity. `_t`: `"x y z"`.
- Placement: a model's `floor(size/2)` voxel sits at the translation, so odd rotated extents shift +0.5 (`VoxScene.swift`, shape level only).
- Hidden: `nTRN` `_hidden = 1`, or `LAYR` `_hidden = 1` on its layer.
- Animation: only the first frame / first model of an `nSHP`.
- Limits: model edge capped at 2048 (format max 256); out-of-bounds voxels dropped; cyclic graphs terminate.
- Coordinates: MagicaVoxel is Z up; `VoxScene` maps (x, y, z) → (x, z, −y).
