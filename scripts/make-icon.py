#!/usr/bin/env python3
"""Regenerates the app icon: writes Resources/icon.vox, renders it with
voxthumb, and composes App/Assets.xcassets/AppIcon.appiconset.

Needs Pillow. Run from the repo root: scripts/make-icon.py
"""
import json
import os
import struct
import subprocess
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
N = 6

# One colour per layer, bottom to top.
LAYERS = [(52, 72, 160), (54, 108, 196), (46, 150, 214), (52, 192, 206), (110, 220, 170), (250, 214, 110)]


def chunk(cid, content):
    return cid + struct.pack('<ii', len(content), 0) + content


def write_vox(path):
    voxels = []
    for x in range(N):
        for y in range(N):
            for z in range(N):
                # A cube with a stepped bite taken out of the front-top corner.
                if x + (N - 1 - y) + z >= 2 * N - 2 and z >= N // 2:
                    continue
                voxels.append((x, y, z, z + 1))
    rgba = bytearray(1024)
    for i, (r, g, b) in enumerate(LAYERS):
        rgba[i * 4:i * 4 + 4] = bytes((r, g, b, 255))
    xyzi = struct.pack('<i', len(voxels)) + b''.join(bytes(v) for v in voxels)
    body = chunk(b'SIZE', struct.pack('<iii', N, N, N)) + chunk(b'XYZI', xyzi) + chunk(b'RGBA', bytes(rgba))
    with open(path, 'wb') as f:
        f.write(b'VOX ' + struct.pack('<i', 150) + b'MAIN' + struct.pack('<ii', 0, len(body)) + body)


def squircle(size, inset):
    mask = Image.new('L', (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((inset, inset, size - inset, size - inset), radius=int(size * 0.185), fill=255)
    return mask


def main():
    vox = os.path.join(ROOT, 'Resources', 'icon.vox')
    os.makedirs(os.path.dirname(vox), exist_ok=True)
    write_vox(vox)
    render = os.path.join(ROOT, '.build', 'icon-render.png')
    subprocess.run(['swift', 'run', '-c', 'release', 'voxthumb', vox, render, '1024'], cwd=ROOT, check=True)

    size, inset = 1024, 100  # macOS icon grid: 824pt body on a 1024 canvas
    bg = Image.new('RGBA', (size, size))
    top, bottom = (44, 46, 58), (22, 23, 30)
    for y in range(size):
        t = y / size
        ImageDraw.Draw(bg).line([(0, y), (size, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)) + (255,))
    icon = Image.new('RGBA', (size, size))
    shadow = Image.new('RGBA', (size, size))
    shadow.putalpha(squircle(size, inset).filter(ImageFilter.GaussianBlur(18)).point(lambda v: v * 0.45))
    icon.alpha_composite(shadow, (0, 12))
    icon.paste(bg, (0, 0), squircle(size, inset))
    model = Image.open(render).convert('RGBA').resize((560, 560), Image.LANCZOS)
    icon.alpha_composite(model, ((size - 560) // 2, (size - 560) // 2 + 8))

    out = os.path.join(ROOT, 'App', 'Assets.xcassets', 'AppIcon.appiconset')
    os.makedirs(out, exist_ok=True)
    images = []
    for pt in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = pt * scale
            name = f'icon_{pt}x{pt}{"@2x" if scale == 2 else ""}.png'
            icon.resize((px, px), Image.LANCZOS).save(os.path.join(out, name))
            images.append({'idiom': 'mac', 'size': f'{pt}x{pt}', 'scale': f'{scale}x', 'filename': name})
    info = {'author': 'xcode', 'version': 1}
    with open(os.path.join(out, 'Contents.json'), 'w') as f:
        json.dump({'images': images, 'info': info}, f, indent=2)
    with open(os.path.join(ROOT, 'App', 'Assets.xcassets', 'Contents.json'), 'w') as f:
        json.dump({'info': info}, f, indent=2)
    icon.save(os.path.join(ROOT, 'docs', 'icon.png'))


if __name__ == '__main__':
    main()
