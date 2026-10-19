#!/usr/bin/env python3
"""Writes the procedural sample models in Resources/samples/ (MIT, ours) and
renders docs/samples.png with voxthumb. Needs Pillow for the strip.

Run from the repo root: scripts/make-samples.py
"""
import math
import os
import random
import struct
import subprocess
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'Resources', 'samples')


def chunk(cid, content, children=b''):
    return cid + struct.pack('<ii', len(content), len(children)) + content + children


def vox_string(s):
    b = s.encode()
    return struct.pack('<i', len(b)) + b


def vox_dict(d):
    return struct.pack('<i', len(d)) + b''.join(vox_string(k) + vox_string(v) for k, v in d.items())


def write(name, models, palette, placements=None):
    """models: [(size, {(x,y,z): index})]; placements: [(model, (tx,ty,tz), rot_byte)]."""
    body = b''
    for (sx, sy, sz), voxels in models:
        body += chunk(b'SIZE', struct.pack('<iii', sx, sy, sz))
        body += chunk(b'XYZI', struct.pack('<i', len(voxels)) + b''.join(bytes((*p, c)) for p, c in voxels.items()))
    if placements:
        n = len(placements)
        # Root transform 0 → group 1 → (transform, shape) pairs.
        body += chunk(b'nTRN', struct.pack('<i', 0) + vox_dict({}) + struct.pack('<iiii', 1, -1, 0, 1) + vox_dict({}))
        body += chunk(b'nGRP', struct.pack('<i', 1) + vox_dict({}) + struct.pack('<i', n)
                      + b''.join(struct.pack('<i', 2 + 2 * i) for i in range(n)))
        for i, (m, t, r) in enumerate(placements):
            frame = {'_t': ' '.join(map(str, t)), '_r': str(r)}
            body += chunk(b'nTRN', struct.pack('<i', 2 + 2 * i) + vox_dict({})
                          + struct.pack('<iiii', 3 + 2 * i, -1, 0, 1) + vox_dict(frame))
            body += chunk(b'nSHP', struct.pack('<i', 3 + 2 * i) + vox_dict({}) + struct.pack('<ii', 1, m) + vox_dict({}))
    rgba = bytearray(1024)
    for i, c in enumerate(palette):
        rgba[i * 4:i * 4 + 4] = bytes((*c, 255))
    body += chunk(b'RGBA', bytes(rgba))
    with open(os.path.join(OUT, name), 'wb') as f:
        f.write(b'VOX ' + struct.pack('<i', 200) + chunk(b'MAIN', b'', body))


def island():
    rnd = random.Random(7)
    n, v = 40, {}
    for x in range(n):
        for y in range(n):
            d = math.hypot(x - n / 2, y - n / 2) / (n / 2)
            if d > 1:
                continue
            h = int(3 + 9 * (1 - d) ** 1.5 + 2 * math.sin(x / 4) * math.cos(y / 5))
            for z in range(max(h, 1)):
                v[(x, y, z)] = 1 if z == h - 1 else (2 if z > h - 4 else 3)
            if d < 0.55 and rnd.random() < 0.025:  # trees
                for z in range(h, h + 4):
                    v[(x, y, z)] = 4
                for dx in range(-2, 3):
                    for dy in range(-2, 3):
                        for dz in range(0, 3):
                            if abs(dx) + abs(dy) + dz < 4 and (x + dx, y + dy, h + 3 + dz) not in v:
                                if 0 <= x + dx < n and 0 <= y + dy < n:
                                    v[(x + dx, y + dy, h + 3 + dz)] = 5
    pal = [(108, 186, 84), (150, 110, 70), (120, 120, 128), (110, 76, 52), (60, 150, 80)]
    write('island.vox', [((n, n, 20), v)], pal)


def sponge():
    n, v = 27, {}
    for x in range(n):
        for y in range(n):
            for z in range(n):
                a, b, c, hole = x, y, z, False
                while a or b or c:
                    if (a % 3 == 1) + (b % 3 == 1) + (c % 3 == 1) >= 2:
                        hole = True
                        break
                    a, b, c = a // 3, b // 3, c // 3
                if not hole:
                    v[(x, y, z)] = 1 + (x + y + z) * 4 // (3 * n)
    write('sponge.vox', [((n, n, n), v)], [(244, 120, 90), (240, 170, 80), (250, 214, 110), (120, 200, 190)])


def figures():
    """A small scene graph: one model placed three times, rotated and mirrored."""
    v = {}
    for z in range(0, 6):  # legs
        v[(2, 2, z)] = v[(5, 2, z)] = 1
    for x in range(1, 7):  # body
        for z in range(6, 13):
            for y in range(1, 4):
                v[(x, y, z)] = 2
    for x in range(2, 6):  # head
        for y in range(0, 5):
            for z in range(13, 17):
                v[(x, y, z)] = 3
    v[(2, 0, 15)] = v[(5, 0, 15)] = 4  # eyes, facing −y
    v[(0, 2, 10)] = v[(7, 2, 10)] = 3  # hands
    ground = {(x, y, 0): 5 + (x // 4 + y // 4) % 2 for x in range(36) for y in range(20)}
    pal = [(70, 70, 90), (230, 110, 90), (250, 214, 180), (30, 30, 40), (200, 200, 210), (180, 180, 196)]
    # _r: 4 = identity, 17 = quarter turn about Z, 20 = mirrored X.
    write('figures.vox', [((8, 5, 17), v), ((36, 20, 1), ground)], pal,
          [(1, (0, 0, 0), 4), (0, (-10, 0, 9), 4), (0, (0, 2, 9), 17), (0, (10, 0, 9), 20)])


def main():
    os.makedirs(OUT, exist_ok=True)
    island(); sponge(); figures()
    subprocess.run(['swift', 'build', '-c', 'release', '--product', 'voxthumb'], cwd=ROOT, check=True)
    names = ['island', 'figures', 'sponge']
    strip = Image.new('RGBA', (len(names) * 512, 512))
    for i, n in enumerate(names):
        png = os.path.join(ROOT, '.build', n + '.png')
        subprocess.run([os.path.join(ROOT, '.build', 'release', 'voxthumb'),
                        os.path.join(OUT, n + '.vox'), png, '512'], check=True)
        strip.alpha_composite(Image.open(png).convert('RGBA'), (i * 512, 0))
    strip.save(os.path.join(ROOT, 'docs', 'samples.png'))


if __name__ == '__main__':
    main()
