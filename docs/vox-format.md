# .vox format notes

Spec: <https://github.com/ephtracy/voxel-model>. What we rely on:

- Chunks: `SIZE`/`XYZI` pairs (models, in order), `RGBA`, `MATL`, `nTRN`, `nGRP`, `nSHP`, `LAYR`. Skipped: `rOBJ`, `rCAM`, `NOTE`, `IMAP`.
- `MATL` id = palette index. Kept: `_type`, `_trans` (or `_alpha`), `_metal`, `_rough`, `_emit`; default diffuse entries aren't stored.
- `RGBA` entry *k* colours palette index *k + 1*. No `RGBA` → `VoxPalette.default` (generated, not a table).
- `nTRN` frame `_r`: packed row-major signed permutation (`VoxRotation`); `4` = identity. `_t`: `"x y z"`.
- Placement: a model's `floor(size/2)` voxel sits at the translation, so odd rotated extents shift +0.5 (`VoxScene.swift`, shape level only).
- Hidden: `nTRN` `_hidden = 1`, or `LAYR` `_hidden = 1` on its layer.
- Animation: `nTRN` frames and `nSHP` models carry `_f`; each key holds until the next (no interpolation). Frame count = last key + 1; preview plays at 10 fps.
- Limits: model edge capped at 2048 (format max 256); `XYZI` coordinates are bytes, so the stored box is ≤ 256³; out-of-bounds voxels dropped; cyclic graphs terminate.
- Layers: an instance takes the layer of its nearest transform with one. MagicaVoxel names untouched layers "0", "1", … (shown as "Layer 0").
- Coordinates: MagicaVoxel is Z up; `VoxScene` maps (x, y, z) → (x, z, −y).
