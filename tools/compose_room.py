#!/usr/bin/env python3
"""Compose a room from PixelLab props instead of generating a whole painting (0 gen).

  python3 tools/compose_room.py e2        reads data/compose/e2.json

Writes, next to the painted rooms so tools/painted_rooms.py treats it like any other room:
  assets/map/painted/raw/<id>.png        the room picture (688x384)
  assets/map/painted/raw/<id>_walk.png   white = walkable (exact, from prop footprints)
  assets/map/painted/raw/<id>_over.png   white = drawn over the hero (tree tops, border canopy)

Design rules applied here (docs/design/design-research.md):
  - ground from grass patches cut out of painted rooms, quilted with ragged seams (no grid look)
  - props drawn back to front (by feet y), each grounded by a short soft shadow
  - border forest from staggered rows of canopy clumps; only trunks and bush bases block in the middle
  - small things gather at the base of big things (flowers / mushrooms around trees and bushes)
"""
import json
import random
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SIZE = (688, 384)
RAW = ROOT / "assets/map/painted/raw"
PROPS = json.loads((ROOT / "assets/map/props/manifest.json").read_text())


def grass_patches(sources, size, want, rng):
    """Square grass-only patches cut out of painted rooms (hue 55-100, saturated, bright)."""
    import colorsys
    from scipy import ndimage
    out = []
    for rid in sources:
        rgb = np.asarray(Image.open(RAW / f"{rid}.png").convert("RGB"))
        flat = rgb.reshape(-1, 3)
        cols, inv = np.unique(flat, axis=0, return_inverse=True)
        ok = np.array([(55 <= colorsys.rgb_to_hsv(*(c / 255))[0] * 360 <= 100) and
                       colorsys.rgb_to_hsv(*(c / 255))[1] >= 0.4 and colorsys.rgb_to_hsv(*(c / 255))[2] >= 0.55
                       for c in cols])
        grass = ok[inv].reshape(rgb.shape[:2])
        er = ndimage.binary_erosion(grass, np.ones((size, size), bool))
        ys, xs = np.nonzero(er)
        for i in rng.sample(range(len(xs)), min(want * 4, len(xs))):
            cy, cx = ys[i], xs[i]
            out.append(rgb[cy - size // 2:cy + size // 2, cx - size // 2:cx + size // 2])
    # keep patches of one tone (middle of the brightness range) so the quilt has no light/dark blotches
    lum = np.array([p.mean() for p in out])
    lo, hi = np.percentile(lum, 30), np.percentile(lum, 70)
    return [Image.fromarray(p) for p, l in zip(out, lum) if lo <= l <= hi][:want]


def ragged_mask(size, rng):
    """A blob mask that fills the middle and frays at the edge, so quilted patches have no straight seams."""
    m = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(m)
    c = size / 2
    for _ in range(14):
        r = rng.uniform(size * 0.22, size * 0.42)
        x, y = c + rng.uniform(-size * 0.18, size * 0.18), c + rng.uniform(-size * 0.18, size * 0.18)
        d.ellipse((x - r, y - r, x + r, y + r), fill=255)
    # hard 1-bit edge keeps the pixel look (no soft blending)
    return m.point(lambda v: 255 if v > 127 else 0)


def ground(spec, rng):
    src = grass_patches(spec.get("from", ["w1", "e0"]), 64, 40, rng)
    img = Image.new("RGB", SIZE)
    # base fill: plain grid of patches (covers everything), then ragged patches on top hide the grid
    for y in range(0, SIZE[1], 64):
        for x in range(0, SIZE[0], 64):
            img.paste(rng.choice(src).transpose(rng.choice([Image.FLIP_LEFT_RIGHT, Image.FLIP_TOP_BOTTOM, Image.ROTATE_180])), (x, y))
    for _ in range(spec.get("quilt", 120)):
        p = rng.choice(src)
        if rng.random() < 0.5: p = p.transpose(Image.FLIP_LEFT_RIGHT)
        img.paste(p, (rng.randrange(-32, SIZE[0] - 32), rng.randrange(-32, SIZE[1] - 32)), ragged_mask(64, rng))
    if "brightness" in spec: img = ImageEnhance.Brightness(img).enhance(spec["brightness"])
    if "saturation" in spec: img = ImageEnhance.Color(img).enhance(spec["saturation"])
    return img.convert("RGBA")


def load_prop(name):
    if name.startswith("clump:"):
        im = Image.open(ROOT / f"assets/map/painted/clumps/{name[6:]}.png").convert("RGBA")
        return im, {"feet": [im.width // 2, im.height - 12], "foot": None, "clump": True}
    m = PROPS[name]
    return Image.open(ROOT / m["file"].replace("res://", "")).convert("RGBA"), m


def main(rid):
    spec = json.loads((ROOT / f"data/compose/{rid}.json").read_text())
    rng = random.Random(spec.get("seed", 1))
    img = ground(spec.get("ground", {}), rng)
    walk = np.ones((SIZE[1], SIZE[0]), bool)
    over = np.zeros((SIZE[1], SIZE[0]), bool)
    items = []
    for p in spec["props"]:
        items.append(dict(p))
    # small things at the base of big things
    for p in list(items):
        for _ in range(p.get("base_decor", 0)):
            name = rng.choice(spec.get("decor", ["flowers_a", "mushroom"]))
            items.append({"name": name, "at": [p["at"][0] + rng.randint(-34, 34), p["at"][1] + rng.randint(2, 14)]})
    for s in spec.get("scatter", []):
        x0, y0, w, h = s["area"]
        for _ in range(s["count"]):
            items.append({"name": rng.choice(s["names"]), "at": [x0 + rng.randrange(w), y0 + rng.randrange(h)]})
    items.sort(key=lambda p: p["at"][1])                     # back to front
    shade = Image.new("RGBA", SIZE, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shade)
    sprites = []
    for p in items:
        im, m = load_prop(p["name"])
        if p.get("flip"): im = im.transpose(Image.FLIP_LEFT_RIGHT)
        if p.get("dark"): im = ImageEnhance.Brightness(im).enhance(p["dark"])
        fx, fy = m["feet"]
        x, y = int(p["at"][0] - fx), int(p["at"][1] - fy)
        sprites.append((im, x, y, p, m))
        foot = m.get("foot")
        if foot and not m.get("flat"):                       # short soft shadow under anything that stands up
            w, h = foot[0] * 0.75 + 6, foot[1] * 0.75 + 3
            sd.ellipse((p["at"][0] - w, p["at"][1] - h * 0.6, p["at"][0] + w, p["at"][1] + h * 0.9), fill=(10, 20, 15, 70))
    img.alpha_composite(shade.filter(ImageFilter.GaussianBlur(1)).point(lambda v: v))
    for im, x, y, p, m in sprites:
        img.alpha_composite(im, (max(x, 0), max(y, 0)), (max(-x, 0), max(-y, 0)))
        a = np.zeros((SIZE[1], SIZE[0]), bool)
        alpha = np.asarray(im.split()[3]) > 40
        ys, xs = np.nonzero(alpha)
        ys2, xs2 = ys + y, xs + x
        keep = (ys2 >= 0) & (ys2 < SIZE[1]) & (xs2 >= 0) & (xs2 < SIZE[0])
        a[ys2[keep], xs2[keep]] = True
        if m.get("clump"):
            walk &= ~a                                         # border canopy: solid and over the hero
            over |= a
        elif m.get("foot") and not m.get("flat"):
            fw, fh = m["foot"]
            cx, cy = p["at"]
            yy, xx = np.ogrid[:SIZE[1], :SIZE[0]]
            walk &= ~(((xx - cx) / (fw / 2 + 2)) ** 2 + ((yy - cy) / (fh / 2 + 2)) ** 2 <= 1.0)
            if p["name"].startswith("tree"):
                top = a.copy()
                top[int(cy) - 14:, :] = False                  # trunk base stays under the hero
                over |= top
    Image.fromarray(np.asarray(img.convert("RGB"))).save(RAW / f"{rid}.png")
    Image.fromarray((walk * 255).astype(np.uint8)).save(RAW / f"{rid}_walk.png")
    Image.fromarray((over * 255).astype(np.uint8)).save(RAW / f"{rid}_over.png")
    print(f"{rid}: {len(items)} props, walkable {walk.mean():.0%}")


if __name__ == "__main__":
    main(sys.argv[1])
