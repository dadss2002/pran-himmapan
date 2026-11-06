#!/usr/bin/env python3
"""Turn a PixelLab create_tiles_pro corner tileset (joined 16x1 sheet preview from pixelart_workbench) into a
clean game strip. The generator draws a dark 1px frame plus a shade line inside each tile; the 2px band on every
side is replaced by its mirror from just inside, so tiles join without grid lines.
Usage: import_tileset.py SHEET OUT_PNG [--header 18] [--remap '{"#2e3743":"#2c473b"}']
SHEET: 16 tiles of 32px in tile_N order (N = PixelLab corner mask, set bit = first terrain)."""
import argparse
import json

from PIL import Image

T = 32


def hexrgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sheet")
    ap.add_argument("out")
    ap.add_argument("--header", type=int, default=18)
    ap.add_argument("--remap", default="{}")
    a = ap.parse_args()
    src = Image.open(a.sheet).convert("RGBA")
    im = src.crop((0, a.header, 16 * T, a.header + T))
    px = im.load()
    for i in range(16):
        x0 = i * T
        for k in range(T):          # rows: 0<-4, 1<-3, 31<-27, 30<-28
            for dst, s in ((0, 4), (1, 3), (31, 27), (30, 28)):
                px[x0 + k, dst] = px[x0 + k, s]
        for k in range(T):          # columns, same mirror
            for dst, s in ((0, 4), (1, 3), (31, 27), (30, 28)):
                px[x0 + dst, k] = px[x0 + s, k]
    remap = {hexrgb(k): hexrgb(v) for k, v in json.loads(a.remap).items()}
    for y in range(T):
        for x in range(16 * T):
            c = px[x, y]
            if c[:3] in remap:
                px[x, y] = remap[c[:3]] + (c[3],)
    im.save(a.out)


if __name__ == "__main__":
    main()
