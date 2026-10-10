"""生成本示例原创贴图；只使用 Python 标准库。运行无需联网。"""
from pathlib import Path
import math
import random
import struct
import zlib

OUT = Path(__file__).parent / 'assets'
OUT.mkdir(exist_ok=True)

def png(name, width, height, rows):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    data = b''.join(b'\0' + bytes(row) for row in rows)
    content = b'\x89PNG\r\n\x1a\n'
    content += chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))
    content += chunk(b'IDAT', zlib.compress(data, 9)) + chunk(b'IEND', b'')
    (OUT / name).write_bytes(content)

def clamp(value):
    return max(0, min(255, int(value)))

rng = random.Random(71)
W, H = 480, 300
heights = []
pixels = []
for y in range(H):
    hrow, row = [], []
    for x in range(W):
        center = 148 + 43 * math.sin(x / 76) + 15 * math.sin(x / 32)
        width = 34 + 6 * math.sin(x / 51)
        distance = abs(y - center)
        elevation = 0.13 + (distance / width) ** 1.55 * 0.22
        island = math.exp(-(((x - 266) / 24) ** 2 + ((y - 129) / 16) ** 2))
        elevation += island * 0.64
        elevation += 0.012 * math.sin(x / 5) * math.sin(y / 7)
        elevation = max(0.03, min(0.99, elevation))
        elevation = round(elevation * 48) / 48
        hrow.append(elevation)
        jitter = rng.randrange(-7, 8)
        cell = math.sin((x // 7) * 17 + (y // 5) * 9)
        if elevation < 0.40:
            color = (109, 115, 99)
        elif elevation < 0.59:
            color = (148, 143, 104)
        elif elevation < 0.73:
            color = (116, 127, 77)
        else:
            color = (67, 99, 62)
        grain = jitter + cell * 6
        if elevation > 0.73 and rng.random() < 0.075:
            grain += 14
        row.append(tuple(clamp(c + grain) for c in color))
    heights.append(hrow)
    pixels.append(row)

# 原图中绘制碎石；在水域里仍能看清，便于观察扭曲。
for _ in range(560):
    x, y = rng.randrange(5, W - 5), rng.randrange(5, H - 5)
    if heights[y][x] > 0.66:
        continue
    rx, ry = rng.randrange(2, 6), rng.randrange(1, 4)
    base = rng.randrange(105, 150)
    for dy in range(-ry, ry + 1):
        for dx in range(-rx, rx + 1):
            if (dx / rx) ** 2 + (dy / ry) ** 2 <= 1:
                shade = 12 if dy < 0 else (-18 if dy == ry else 0)
                pixels[y + dy][x + dx] = (base + shade, base + shade, base - 14 + shade)

png('riverbed.png', W, H, [[c for pixel in row for c in pixel] for row in pixels])
png('height.png', W, H, [[clamp(h * 255) for h in row for _ in range(3)] for row in heights])

# 周期函数生成可平铺噪声和焦散，不使用第三方图片。
N = 128
noise, caustics = [], []
for y in range(N):
    nr, cr = [], []
    for x in range(N):
        u, v = x / N * math.tau, y / N * math.tau
        a = (math.sin(u * 2 + math.sin(v * 3)) + math.sin(v * 2 - u)) / 2
        b = (math.cos(v * 3 + math.sin(u * 2)) + math.sin(u + v * 2)) / 2
        nr.extend([clamp((a * .5 + .5) * 255), clamp((b * .5 + .5) * 255), 128])
        ridge = abs(math.sin(u * 3 + math.sin(v * 2)) + math.cos(v * 3 + math.cos(u * 2)))
        light = math.exp(-ridge * 12)
        cr.extend([clamp(light * 255)] * 3)
    noise.append(nr)
    caustics.append(cr)
png('noise.png', N, N, noise)
png('caustics.png', N, N, caustics)
print('Generated four textures in', OUT)
