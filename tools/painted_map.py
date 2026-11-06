#!/usr/bin/env python3
"""Builds the painted forest map (M3b round 2) from its PixelLab scene chunks.

Inputs
  assets/map/painted/c{col}r{row}.png   one 688x384 painted chunk per grid cell
  data/map_painted_src.json             hand data: grid, spawn, pack homes, fx, and edits
                                        ("walk"/"block" pixel rects that override the colour guess)
Outputs
  data/map_painted.json                 what the game reads: size, chunk files, blocked cells (8 px),
                                        overlays, spawn, pack homes, fx
  assets/map/painted/canopy_c{col}r{row}.png   leaves that hang over walkable ground, drawn above characters
  docs/preview/m3b_painted_debug.png    the map at 1/2 size with blocked cells tinted red (for review)

Walkable is guessed from colour (the chunks use a small palette): yellow-greens = grass, low-saturation
light greys/browns = stone and dirt; blue-greens, teal and purples (canopy, water, trunks, cliffs) block.
Usage: python3 tools/painted_map.py
"""
import colorsys
import json

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = "."
CELL = 8
CHUNK = (688, 384)
OVERHANG_UP = 48      # canopy pixels up to this far above walkable ground can cover a character's head
OVERHANG_SIDE = 12


def classify(rgb: np.ndarray):
    """Per-pixel walkable and canopy masks from an HxWx3 uint8 image."""
    flat = rgb.reshape(-1, 3)
    cols, inv = np.unique(flat, axis=0, return_inverse=True)
    walk_c = np.zeros(len(cols), bool)
    canopy_c = np.zeros(len(cols), bool)
    for i, c in enumerate(cols):
        h, s, v = colorsys.rgb_to_hsv(*(c / 255.0))
        h *= 360
        grass = 40 <= h <= 118 and v >= 0.50 and s >= 0.3
        ground = s < 0.30 and v >= 0.38
        dirt = (h <= 45 or h >= 350) and s < 0.5 and v >= 0.45
        walk_c[i] = grass or ground or dirt
        water = 172 <= h <= 192 and v >= 0.45
        canopy_c[i] = 120 <= h <= 215 and s > 0.4 and not water
    shape = rgb.shape[:2]
    return walk_c[inv].reshape(shape), canopy_c[inv].reshape(shape)


def main():
    src = json.load(open(f"{ROOT}/data/map_painted_src.json"))
    gc, gr = src["grid"]
    W, H = gc * CHUNK[0], gr * CHUNK[1]
    full = Image.new("RGB", (W, H))
    for r in range(gr):
        for c in range(gc):
            full.paste(Image.open(f"{ROOT}/assets/map/painted/c{c}r{r}.png").convert("RGB"), (c * CHUNK[0], r * CHUNK[1]))
    rgb = np.asarray(full)
    walk_px, canopy_px = classify(rgb)

    # 8 px cells: walkable when most of the cell is ground
    cw, ch = W // CELL, H // CELL
    frac = walk_px.reshape(ch, CELL, cw, CELL).mean(axis=(1, 3))
    walk = frac >= 0.55
    # flowers/mushrooms/rocks leave small holes in grass: fill blocked islands under 6 cells;
    # drop walkable specks under 8 cells (sunlit leaves)
    lab, n = ndimage.label(~walk)
    sizes = ndimage.sum(np.ones_like(lab), lab, range(1, n + 1))
    for i, s in enumerate(sizes, 1):
        if s < 6: walk[lab == i] = True
    lab, n = ndimage.label(walk)
    sizes = ndimage.sum(np.ones_like(lab), lab, range(1, n + 1))
    for i, s in enumerate(sizes, 1):
        if s < 8: walk[lab == i] = False
    # hand edits (pixel rects), in order
    for e in src.get("edits", []):
        x, y, w, h = e["rect"]
        walk[y // CELL:(y + h + CELL - 1) // CELL, x // CELL:(x + w + CELL - 1) // CELL] = e["op"] == "walk"
    # the map border always blocks
    walk[0, :] = walk[-1, :] = False
    walk[:, 0] = walk[:, -1] = False

    # canopy overhang: canopy pixels just above (and beside) walkable ground
    walk_full = np.kron(walk, np.ones((CELL, CELL), bool))
    near = np.zeros_like(walk_full)
    for dy in range(0, OVERHANG_UP + 1, 2):
        shifted = np.zeros_like(walk_full)
        shifted[:H - dy] = walk_full[dy:]
        near |= shifted
    near = ndimage.binary_dilation(near, structure=np.ones((1, 2 * OVERHANG_SIDE + 1), bool))
    over = canopy_px & near & ~walk_full
    overlays = []
    for r in range(gr):
        for c in range(gc):
            x0, y0 = c * CHUNK[0], r * CHUNK[1]
            m = over[y0:y0 + CHUNK[1], x0:x0 + CHUNK[0]]
            if not m.any(): continue
            rgba = np.dstack([rgb[y0:y0 + CHUNK[1], x0:x0 + CHUNK[0]], (m * 255).astype(np.uint8)])
            name = f"canopy_c{c}r{r}.png"
            Image.fromarray(rgba, "RGBA").save(f"{ROOT}/assets/map/painted/{name}")
            overlays.append({"file": f"res://assets/map/painted/{name}", "at": [x0, y0]})

    out = {
        "size": [W, H], "cell": CELL, "chunk": list(CHUNK), "grid": [gc, gr],
        "chunks": [{"file": f"res://assets/map/painted/c{c}r{r}.png", "at": [c * CHUNK[0], r * CHUNK[1]]}
                   for r in range(gr) for c in range(gc)],
        "overlays": overlays,
        "hero_spawn": src["hero_spawn"], "pack_homes": src["pack_homes"], "fx": src.get("fx", []),
        "blocked": ["".join("." if v else "#" for v in row) for row in walk],
    }
    with open(f"{ROOT}/data/map_painted.json", "w") as f:
        json.dump(out, f, ensure_ascii=False, indent=0)

    # review image: half size, blocked cells tinted
    dbg = full.copy().convert("RGBA")
    tint = np.zeros((H, W, 4), np.uint8)
    tint[~walk_full] = (255, 0, 0, 70)
    tint[over] = (255, 255, 0, 90)
    dbg.alpha_composite(Image.fromarray(tint, "RGBA"))
    for p in [src["hero_spawn"]] + src["pack_homes"]:
        x, y = p
        for dx in range(-6, 7):
            for dy in (-1, 0, 1):
                for q in ((x + dx, y + dy), (x + dy, y + dx)):
                    if 0 <= q[0] < W and 0 <= q[1] < H: dbg.putpixel(q, (255, 255, 255, 255))
    dbg.resize((W // 2, H // 2), Image.NEAREST).save(f"{ROOT}/docs/preview/m3b_painted_debug.png")
    print("map %dx%d, walkable cells %d / %d, overlays %d" % (W, H, walk.sum(), walk.size, len(overlays)))


if __name__ == "__main__":
    main()
