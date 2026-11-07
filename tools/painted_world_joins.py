#!/usr/bin/env python3
"""M4a: paste the approved join inpaints (assets/map/painted/world/J*_inpaint.png + _mask.png) into the
multiband-blended world, blending each redrawn area's edge with a Laplacian pyramid so the colour
step at the mask edge disappears (owner chose method "C", 2026-11-07).
Usage: python3 tools/painted_world_joins.py <world_mb.png> <out.png>"""
import json, sys
import numpy as np, cv2
from PIL import Image

LV, P, CORE = 5, 64, 20
JOINS = {  # name: top-left of the inpaint window in world pixels (340x340 or 512x384)
    "J1": (432, 384),
    "J2": (432, 1152),
}

def lap_blend(a, b, m):
    ga, gb, gm = [a], [b], [m]
    for _ in range(LV):
        ga.append(cv2.pyrDown(ga[-1])); gb.append(cv2.pyrDown(gb[-1])); gm.append(cv2.pyrDown(gm[-1]))
    up = lambda x, ref: cv2.pyrUp(x, dstsize=(ref.shape[1], ref.shape[0]))
    la = [ga[i] - up(ga[i + 1], ga[i]) for i in range(LV)] + [ga[LV]]
    lb = [gb[i] - up(gb[i + 1], gb[i]) for i in range(LV)] + [gb[LV]]
    out = None
    for i in range(LV, -1, -1):
        w = gm[i][..., None]
        l = la[i] * (1 - w) + lb[i] * w
        out = l if out is None else up(out, l) + l
    return out

def place(world, inp, msk, x0, y0):
    Hh, Ww = inp.shape[:2]
    src = world[y0 - P:y0 + Hh + P, x0 - P:x0 + Ww + P]
    B = src.copy()
    B[P:P + Hh, P:P + Ww] = inp * msk[..., None] + B[P:P + Hh, P:P + Ww] * (1 - msk[..., None])
    m = np.zeros(src.shape[:2], np.float32); m[P:P + Hh, P:P + Ww] = msk
    out = lap_blend(src, B, m)
    core = cv2.erode((m > 0.5).astype(np.uint8), np.ones((3, 3), np.uint8), iterations=CORE).astype(np.float32)
    core = cv2.GaussianBlur(core, (0, 0), 5)[..., None]
    world[y0 - P:y0 + Hh + P, x0 - P:x0 + Ww + P] = np.clip(out * (1 - core) + B * core, 0, 255)

def grass_fill(w, box, tile_box, fade=None, seed=4):
    """Free fix (owner-approved for the J2 path end): replace dark tree-edge pixels left just outside a
    redrawn area with a mirrored tile of plain grass; optionally fade a dirt path end into the grass."""
    x0, y0, x1, y1 = box
    tx0, ty0, tx1, ty1 = tile_box
    tile = w[ty0:ty1, tx0:tx1].copy()
    big = np.concatenate([tile, tile[:, ::-1]], 1); big = np.concatenate([big, big[::-1]], 0)
    g = lambda y, x: big[(y - y0) % big.shape[0], (x - x0) % big.shape[1]]
    hsv = cv2.cvtColor(np.clip(w, 0, 255).astype(np.uint8), cv2.COLOR_RGB2HSV).astype(np.float32)
    H, S, V = hsv[..., 0] * 2, hsv[..., 1] / 255, hsv[..., 2] / 255
    for y in range(y0, y1):
        for x in range(x0, x1):
            if (120 <= H[y, x] <= 215 and S[y, x] > 0.4) or V[y, x] < 0.36:
                w[y, x] = g(y, x)
    if fade:
        fx0, fy0, fx1, fy1 = fade
        rng = np.random.default_rng(seed)
        for y in range(fy0, fy1):
            for x in range(fx0, fx1):
                if abs(H[y, x] - 30) < 25 and S[y, x] < 0.5 and (x - fx0) / (fx1 - fx0) + rng.normal(0, 0.2) > 0.6:
                    w[y, x] = g(y, x)

POST = {"J2": dict(box=(778, 1316, 800, 1392), tile_box=(805, 1352, 835, 1386), fade=(766, 1326, 790, 1386))}

def main(src, dst, root="assets/map/painted/world"):
    w = np.asarray(Image.open(src).convert("RGB")).astype(np.float32)
    H, W = w.shape[:2]
    w = np.pad(w, ((P, P), (P, P), (0, 0)), mode="edge")
    for name, (x0, y0) in JOINS.items():
        inp = np.asarray(Image.open(f"{root}/{name}_inpaint.png").convert("RGB")).astype(np.float32)
        msk = np.asarray(Image.open(f"{root}/{name}_mask.png").convert("L")).astype(np.float32) / 255
        place(w, inp, msk, x0 + P, y0 + P)
        if name in POST:
            f = POST[name]
            sh = lambda b: tuple(v + P for v in b)
            grass_fill(w, sh(f["box"]), sh(f["tile_box"]), sh(f["fade"]) if f.get("fade") else None)
    Image.fromarray(w[P:P + H, P:P + W].astype(np.uint8)).save(dst)

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
