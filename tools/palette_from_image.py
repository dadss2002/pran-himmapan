#!/usr/bin/env python3
"""Print a JSON palette (hex list) taken from an image: median-cut, then drop near-duplicates.
Usage: python3 tools/palette_from_image.py IMAGE [COUNT] > data/style/forest_palette.json"""
import json
import sys

from PIL import Image


def palette(path: str, count: int) -> list:
    img = Image.open(path).convert("RGB")
    q = img.quantize(colors=count * 2, method=Image.Quantize.MEDIANCUT)
    raw = q.getpalette()[: count * 2 * 3]
    used = sorted(q.getcolors(), reverse=True)            # (pixels, index), most used first
    out = []
    for _, i in used:
        c = tuple(raw[i * 3: i * 3 + 3])
        if all(sum((a - b) ** 2 for a, b in zip(c, o)) > 18 ** 2 for o in out):
            out.append(c)
        if len(out) == count:
            break
    return ["#%02x%02x%02x" % c for c in out]


if __name__ == "__main__":
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 24
    print(json.dumps({"source": sys.argv[1], "colors": palette(sys.argv[1], n)}, indent=1))
