"""Recover a VFX sheet with semi-transparent pixels from a workbench preview.

The preview composites RGBA frames over BG (31,37,44). Opaque pixels come through exactly;
a translucent pixel shows as round(a*c + (1-a)*BG). Given the effect's translucent colours
(from `pixelart_workbench extract-palette`), each composite is mapped back to its RGBA.
Composites that match no single translucent colour (overlaps) are kept with the best-fitting
known translucent alpha, so the decal still blends over the ground.

Usage: python3 tools/extract_fx.py <preview.png> <out.png> --cell 98x106 --cols 8 --rows 5
         --frames 0-22 --translucent '#2a050866,#7a0e1466,...'
Writes a horizontal strip of the chosen frames.
"""
import argparse
from PIL import Image

BG = (31, 37, 44)

def parse_hex(h):
    h = h.strip().lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4, 6))

def comp(c):
    a = c[3] / 255.0
    return tuple(int(round(a * c[i] + (1 - a) * BG[i])) for i in range(3))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src"); ap.add_argument("out")
    ap.add_argument("--cell", required=True); ap.add_argument("--cols", type=int, required=True)
    ap.add_argument("--rows", type=int, required=True); ap.add_argument("--frames", required=True)
    ap.add_argument("--translucent", default="")
    a = ap.parse_args()
    cw, ch = (int(v) for v in a.cell.split("x"))
    f0, f1 = (int(v) for v in a.frames.split("-"))
    trans = [parse_hex(t) for t in a.translucent.split(",") if t.strip()]
    lut = {comp(t): t for t in trans}
    alphas = sorted({t[3] for t in trans}) or [255]
    im = Image.open(a.src).convert("RGBA")
    W, H = im.size
    sheet = im.crop((0, H - a.rows * ch, a.cols * cw, H))
    n = f1 - f0 + 1
    out = Image.new("RGBA", (n * cw, ch), (0, 0, 0, 0))
    src = sheet.load(); dst = out.load()
    exact = approx = 0
    for k, f in enumerate(range(f0, f1 + 1)):
        cx, cy = (f % a.cols) * cw, (f // a.cols) * ch
        for y in range(ch):
            for x in range(cw):
                p = src[cx + x, cy + y][:3]
                if p == BG:
                    continue
                if p in lut:
                    dst[k * cw + x, y] = lut[p]; exact += 1
                    continue
                # opaque colour, or an overlap of translucent layers: pick the alpha that
                # yields a valid colour closest to the darkest translucent shade
                best = None
                for al in [255] + alphas[::-1]:
                    af = al / 255.0
                    c = tuple(int(round((p[i] - (1 - af) * BG[i]) / af)) for i in range(3))
                    if all(0 <= v <= 255 for v in c):
                        best = c + (al,)
                        if al == 255: break
                dst[k * cw + x, y] = best; approx += 1
    out.save(a.out)
    print(f"ok {a.out} {out.size} frames {n} translucent-exact {exact} other {approx}")

if __name__ == "__main__":
    main()
