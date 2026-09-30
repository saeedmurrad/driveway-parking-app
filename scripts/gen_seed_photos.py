#!/usr/bin/env python3
"""Generates simple illustrated 'space photos' (PNG, pure Python) for the demo seed data."""
import struct, zlib, os, random

W, H = 640, 400
OUT = os.path.join(os.path.dirname(__file__), "..", "backend", "seed-photos")
os.makedirs(OUT, exist_ok=True)


def png(path, px):
    raw = b"".join(b"\x00" + bytes(row) for row in px)
    def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def mix(a, b, t): return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def rect(px, x0, y0, x1, y1, c):
    for y in range(max(0, y0), min(H, y1)):
        row = px[y]
        for x in range(max(0, x0), min(W, x1)):
            row[x * 3:x * 3 + 3] = bytes(c) if False else bytearray(c)


def scene(i):
    rnd = random.Random(i)
    sky_top = [(120, 170, 230), (250, 190, 140), (150, 190, 220), (110, 140, 200)][i % 4]
    sky_bot = [(215, 235, 250), (255, 235, 200), (225, 235, 245), (190, 210, 235)][i % 4]
    wall = [(214, 182, 150), (190, 120, 100), (225, 220, 205), (160, 170, 180)][(i // 2) % 4]
    roof = [(120, 70, 60), (70, 80, 95), (100, 100, 105), (150, 90, 70)][(i + 1) % 4]
    car = [(200, 40, 50), (40, 90, 170), (235, 235, 235), (30, 30, 35), (230, 180, 40)][i % 5]
    px = [bytearray(W * 3) for _ in range(H)]
    for y in range(H):
        c = mix(sky_top, sky_bot, y / 240) if y < 240 else (95, 140, 85)
        px[y][:] = bytes(c) * W
    rect(px, 0, 250, W, H, (92, 92, 98))                     # tarmac
    rect(px, 0, 240, W, 252, (160, 160, 165))                # kerb
    bx = 60 + rnd.randint(0, 40)
    rect(px, bx, 90, bx + 300, 250, wall)                    # house
    for k in range(10):                                      # roof
        rect(px, bx - 14 + k * 3, 70 + k * 2, bx + 314 - k * 3, 92 + k * 2, roof)
    rect(px, bx + 30, 130, bx + 90, 190, (200, 225, 240))    # windows
    rect(px, bx + 210, 130, bx + 270, 190, (200, 225, 240))
    rect(px, bx + 130, 160, bx + 180, 250, (90, 60, 40))     # door
    rect(px, bx + 320, 250, W, H, (130, 130, 135))           # driveway slab
    rect(px, bx + 340, 330, W - 20, 334, (240, 240, 240))    # bay lines
    rect(px, bx + 340, 270, bx + 344, 334, (240, 240, 240))
    cx = bx + 360
    rect(px, cx, 290, cx + 170, 326, car)                    # car body
    rect(px, cx + 35, 266, cx + 130, 292, mix(car, (255, 255, 255), 0.25))
    rect(px, cx + 45, 272, cx + 75, 290, (190, 215, 235))
    rect(px, cx + 85, 272, cx + 120, 290, (190, 215, 235))
    for wx in (cx + 30, cx + 125):
        rect(px, wx, 316, wx + 28, 340, (25, 25, 28))
    return px


for i in range(8):
    png(os.path.join(OUT, f"seed-{i + 1}.png"), scene(i))
print("wrote", len(os.listdir(OUT)), "photos to", os.path.abspath(OUT))
