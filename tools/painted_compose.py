#!/usr/bin/env python3
"""Composes the final painted map chunks from the raw PixelLab scene chunks.

  assets/map/painted/raw/c{col}r{row}.png   chunks exactly as create_image_pro made them
  assets/map/painted/raw/patch_*.png        inpainted windows that join paths across chunk edges
  assets/map/painted/clumps/k*.png          canopy clumps (recoloured to the map's canopy palette)
  data/map_painted_src.json                 "patches": [{file, at, mask: [x, y, w, h] inside the patch}]

Steps: paste the raw chunks, paste the patches, then cover every stretch of chunk edge that runs
through dense forest with canopy clumps (the edges of independently painted chunks never match),
and cut the result back into assets/map/painted/c{col}r{row}.png. Then run tools/painted_map.py.
"""
import json
import random

import numpy as np
from PIL import Image

from painted_map import CHUNK, classify

ROOT = "."
STEP = 72          # clump spacing along a seam
CHECK = 28         # half-size of the square that must be canopy for a clump to go there
FOREST = 0.80
MAX_OVER_GROUND = 60   # px of walkable ground a clump may cover (tiny grass specks between trees)


def main():
    src = json.load(open(f"{ROOT}/data/map_painted_src.json"))
    gc, gr = src["grid"]
    W, H = gc * CHUNK[0], gr * CHUNK[1]
    full = Image.new("RGBA", (W, H))
    for r in range(gr):
        for c in range(gc):
            full.paste(Image.open(f"{ROOT}/assets/map/painted/raw/c{c}r{r}.png").convert("RGBA"), (c * CHUNK[0], r * CHUNK[1]))
    patched = []
    for p in src.get("patches", []):
        im = Image.open(f"{ROOT}/{p['file']}").convert("RGBA")
        full.paste(im, tuple(p["at"]))
        mx, my, mw, mh = p.get("mask", [0, 0, im.width, im.height])   # only the masked part was redrawn
        x0, y0 = p["at"][0] + mx, p["at"][1] + my
        patched.append((x0, y0, x0 + mw, y0 + mh))

    walk, canopy = classify(np.asarray(full.convert("RGB")))
    clumps = [Image.open(f"{ROOT}/assets/map/painted/clumps/k{i}.png").convert("RGBA") for i in range(4)]
    rng = random.Random(7)
    points = []
    for c in range(1, gc):
        points += [(c * CHUNK[0], y) for y in range(STEP // 2, H, STEP)]
    for r in range(1, gr):
        points += [(x, r * CHUNK[1]) for x in range(STEP // 2, W, STEP)]
    # the edges of each patch's redrawn area are seams too
    for (a, b, c2, d) in patched:
        points += [(a, y) for y in range(b + STEP // 2, d, STEP)] + [(c2, y) for y in range(b + STEP // 2, d, STEP)]
        points += [(x, b) for x in range(a + STEP // 2, c2, STEP)] + [(x, d) for x in range(a + STEP // 2, c2, STEP)]
    placed = 0
    for (x, y) in points:
        box = canopy[max(0, y - CHECK):y + CHECK, max(0, x - CHECK):x + CHECK]
        if box.size == 0 or box.mean() < FOREST: continue
        k = rng.choice(clumps)
        if rng.random() < 0.5: k = k.transpose(Image.FLIP_LEFT_RIGHT)
        px, py = x - k.width // 2 + rng.randint(-8, 8), y - k.height // 2 + rng.randint(-8, 8)
        # never paint leaves over open ground (trails, clearings)
        alpha = np.asarray(k)[..., 3] > 0
        x0, y0 = max(0, px), max(0, py)
        x1, y1 = min(W, px + k.width), min(H, py + k.height)
        under = walk[y0:y1, x0:x1] & alpha[y0 - py:y1 - py, x0 - px:x1 - px]
        if under.sum() > MAX_OVER_GROUND: continue
        full.alpha_composite(k, (px, py))
        placed += 1
    for r in range(gr):
        for c in range(gc):
            box = (c * CHUNK[0], r * CHUNK[1], (c + 1) * CHUNK[0], (r + 1) * CHUNK[1])
            full.crop(box).convert("RGB").save(f"{ROOT}/assets/map/painted/c{c}r{r}.png")
    print("patches %d, clumps %d" % (len(patched), placed))


if __name__ == "__main__":
    main()
