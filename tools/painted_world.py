#!/usr/bin/env python3
"""M4a trial (owner 2026-11-07: "แผนที่แบบเกมไดโบ", free first): joins the 12 painted rooms and the
4 arenas into one 5x4 world picture, with free seam treatment only (0 PixelLab gen).

  column 0 = west arenas (w1 row 1, w3 row 3), columns 1-3 = c0..c2, column 4 = east arenas
  (e0 row 0, e2 row 2). The four empty cells stay dark (owner: "ปล่อยมืดแบบไดโบ").

Seam treatment, all free:
  1. the M3b path patches (raw/patch_*.png, data kept from git 9b660e0) pasted where they were
  2. a narrow mirrored cross-fade across every chunk edge (BLEND px each side), so the hard
     colour step becomes a short gradient
  3. canopy clumps (painted/clumps/k*.png) over seam stretches that run through dense forest
  4. a soft fade to black where the map meets an empty cell or the world edge

Writes /tmp/m4a/world_raw.png (plain join) and /tmp/m4a/world_free.png (treated), plus crops.
Usage: python3 tools/painted_world.py
"""
import json
import random
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
from painted_rooms import classify  # noqa: E402

RAW = Path("assets/map/painted/raw")
CLUMPS = Path("assets/map/painted/clumps")
OUT = Path("/tmp/m4a")
CW, CH = 688, 384
COLS, ROWS = 5, 4
BLEND = 14            # px each side of a seam
STEP, CHECK, FOREST, MAX_OVER_GROUND = 72, 28, 0.80, 60
PATCH_FEATHER = 9
FALLOFF = 170         # px over which a seam's colour step is spread
DARK = 56             # px of fade into an empty cell

# M3b path patches (positions in the old 3x4 map; shifted one column right here)
PATCHES = [
    ("patch_V1", (560, 400), (40, 110, 216, 170)),
    ("patch_V2", (520, 800), (40, 100, 216, 150)),
    ("patch_V3", (1248, 384), (0, 110, 216, 170)),
    ("patch_V3b", (1150, 384), (40, 110, 216, 140)),
    ("patch_V4", (1248, 1152), (40, 100, 176, 200)),
    ("patch_H3", (928, 256), (0, 88, 256, 80)),
    ("patch_H8", (880, 1024), (0, 80, 256, 96)),
]


def layout():
    cells = {}
    for r in range(4):
        for c in range(3):
            cells[(c + 1, r)] = f"c{c}r{r}"
    cells[(0, 1)] = "w1"
    cells[(0, 3)] = "w3"
    cells[(4, 0)] = "e0"
    cells[(4, 2)] = "e2"
    return cells


def load(name):
    im = Image.open(RAW / f"{name}.png").convert("RGB")
    if name == "e2" and not (RAW / "e2.png").exists():
        im = Image.open(RAW / "w1.png").convert("RGB").transpose(Image.FLIP_LEFT_RIGHT)
    return np.asarray(im).astype(np.float32)


def compose():
    cells = layout()
    W, H = COLS * CW, ROWS * CH
    full = np.zeros((H, W, 3), np.float32)
    filled = np.zeros((ROWS, COLS), bool)
    for (c, r), name in cells.items():
        full[r * CH:(r + 1) * CH, c * CW:(c + 1) * CW] = load(name)
        filled[r, c] = True
    raw = full.copy()
    for name, (ax, ay), (mx, my, mw, mh) in PATCHES:
        p = np.asarray(Image.open(RAW / f"{name}.png").convert("RGB")).astype(np.float32)
        x, y = ax + CW, ay
        # only the masked window was redrawn; feather its border into the chunk under it
        a = np.zeros(p.shape[:2], np.float32)
        a[my:my + mh, mx:mx + mw] = 1.0
        from scipy import ndimage
        a = ndimage.uniform_filter(a, PATCH_FEATHER)[..., None] * (a[..., None] > 0)
        a = np.clip(ndimage.uniform_filter(a[..., 0], PATCH_FEATHER), 0, 1)[..., None]
        under = full[y:y + p.shape[0], x:x + p.shape[1]]
        full[y:y + p.shape[0], x:x + p.shape[1]] = p * a + under * (1 - a)
    return raw, full, filled, cells


def tone_match(img, filled):
    """Spread each seam's low-frequency colour step over FALLOFF px on both sides (half each),
    so lighter grass on one side meets darker grass on the other without a visible line."""
    from scipy import ndimage
    out = img.copy()
    ramp = np.clip(1.0 - np.arange(FALLOFF) / FALLOFF, 0, 1)[None, :, None]
    for r in range(ROWS):
        for c in range(1, COLS):
            if not (filled[r, c - 1] and filled[r, c]): continue
            x = c * CW
            ys = slice(r * CH, (r + 1) * CH)
            dl = out[ys, x - 6:x].mean(axis=1)
            dr = out[ys, x:x + 6].mean(axis=1)
            d = ndimage.gaussian_filter1d(dr - dl, 20, axis=0)[:, None, :] / 2.0
            out[ys, x - FALLOFF:x] += d * ramp[:, ::-1]
            out[ys, x:x + FALLOFF] -= d * ramp
    rampv = np.clip(1.0 - np.arange(FALLOFF) / FALLOFF, 0, 1)[:, None, None]
    for r in range(1, ROWS):
        for c in range(COLS):
            if not (filled[r - 1, c] and filled[r, c]): continue
            y = r * CH
            xs = slice(c * CW, (c + 1) * CW)
            dt = out[y - 6:y, xs].mean(axis=0)
            db = out[y:y + 6, xs].mean(axis=0)
            d = ndimage.gaussian_filter1d(db - dt, 20, axis=0)[None, :, :] / 2.0
            out[y - FALLOFF:y, xs] += d * rampv[::-1]
            out[y:y + FALLOFF, xs] -= d * rampv
    return np.clip(out, 0, 255)


def mirror_blend(img, filled):
    """Cross-fade each shared chunk edge: each side is extended by mirroring its own pixels
    across the seam, and the two extensions are mixed with a linear ramp."""
    out = img.copy()
    w = np.linspace(0.0, 1.0, 2 * BLEND)[None, :, None]       # 0 = left/top side, 1 = right/bottom
    for r in range(ROWS):
        for c in range(1, COLS):
            if not (filled[r, c - 1] and filled[r, c]): continue
            x = c * CW
            ys = slice(r * CH, (r + 1) * CH)
            left = img[ys, x - BLEND:x]                         # last BLEND px of the left chunk
            right = img[ys, x:x + BLEND]
            a = np.concatenate([left, left[:, ::-1]], axis=1)    # left extended into the right
            b = np.concatenate([right[:, ::-1], right], axis=1)
            out[ys, x - BLEND:x + BLEND] = a * (1 - w) + b * w
    wv = np.linspace(0.0, 1.0, 2 * BLEND)[:, None, None]
    for r in range(1, ROWS):
        for c in range(COLS):
            if not (filled[r - 1, c] and filled[r, c]): continue
            y = r * CH
            xs = slice(c * CW, (c + 1) * CW)
            top = out[y - BLEND:y, xs]
            bot = out[y:y + BLEND, xs]
            a = np.concatenate([top, top[::-1]], axis=0)
            b = np.concatenate([bot[::-1], bot], axis=0)
            out[y - BLEND:y + BLEND, xs] = a * (1 - wv) + b * wv
    return out


def clumps(img, filled):
    H, W = img.shape[:2]
    pil = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).convert("RGBA")
    walk, canopy = classify(np.asarray(pil.convert("RGB")))
    ks = [Image.open(CLUMPS / f"k{i}.png").convert("RGBA") for i in range(4)]
    rng = random.Random(7)
    pts = []
    for r in range(ROWS):
        for c in range(1, COLS):
            if filled[r, c - 1] and filled[r, c]:
                pts += [(c * CW, y) for y in range(r * CH + STEP // 2, (r + 1) * CH, STEP)]
    for r in range(1, ROWS):
        for c in range(COLS):
            if filled[r - 1, c] and filled[r, c]:
                pts += [(x, r * CH) for x in range(c * CW + STEP // 2, (c + 1) * CW, STEP)]
    placed = 0
    for (x, y) in pts:
        box = canopy[max(0, y - CHECK):y + CHECK, max(0, x - CHECK):x + CHECK]
        if box.size == 0 or box.mean() < FOREST: continue
        k = rng.choice(ks)
        if rng.random() < 0.5: k = k.transpose(Image.FLIP_LEFT_RIGHT)
        px, py = x - k.width // 2 + rng.randint(-8, 8), y - k.height // 2 + rng.randint(-8, 8)
        alpha = np.asarray(k)[..., 3] > 0
        x0, y0, x1, y1 = max(0, px), max(0, py), min(W, px + k.width), min(H, py + k.height)
        under = walk[y0:y1, x0:x1] & alpha[y0 - py:y1 - py, x0 - px:x1 - px]
        if under.sum() > MAX_OVER_GROUND: continue
        pil.alpha_composite(k, (px, py))
        placed += 1
    return np.asarray(pil.convert("RGB")).astype(np.float32), placed


def darken(img, filled):
    """Fade to black over DARK px wherever a filled cell meets an empty cell or the world edge."""
    H, W = img.shape[:2]
    inside = np.kron(filled, np.ones((CH, CW), bool))
    from scipy import ndimage
    dist = ndimage.distance_transform_edt(np.pad(inside, 1, constant_values=False))[1:-1, 1:-1]
    k = np.clip(dist / DARK, 0, 1)[..., None]
    return img * k


def main():
    OUT.mkdir(exist_ok=True)
    raw, full, filled, cells = compose()
    free = mirror_blend(tone_match(full, filled), filled)
    free, n = clumps(free, filled)
    free = darken(free, filled)
    raw = darken(raw, filled)
    for name, a in [("world_raw", raw), ("world_free", free)]:
        Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(OUT / f"{name}.png")
    print("world %dx%d, clumps %d" % (COLS * CW, ROWS * CH, n))


if __name__ == "__main__":
    main()
