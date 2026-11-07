#!/usr/bin/env python3
"""M4a: paste the approved join inpaints (assets/map/painted/world/J*_inpaint.png + _mask.png) into the
multiband-blended world, blending each redrawn area's edge with a Laplacian pyramid so the colour
step at the mask edge disappears (owner chose method "C", 2026-11-07).
Usage: python3 tools/painted_world_joins.py <world_mb.png> <out.png>"""
import json, sys
import numpy as np, cv2
from PIL import Image

LV, P, CORE = 5, 64, 20
JOINS = {  # name: top-left of the 340x340 window in world pixels
    "J1": (594, 394),
    "J2": (566, 1174),
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
    S = inp.shape[0]
    src = world[y0 - P:y0 + S + P, x0 - P:x0 + S + P]
    B = src.copy()
    B[P:P + S, P:P + S] = inp * msk[..., None] + B[P:P + S, P:P + S] * (1 - msk[..., None])
    m = np.zeros(src.shape[:2], np.float32); m[P:P + S, P:P + S] = msk
    out = lap_blend(src, B, m)
    core = cv2.erode((m > 0.5).astype(np.uint8), np.ones((3, 3), np.uint8), iterations=CORE).astype(np.float32)
    core = cv2.GaussianBlur(core, (0, 0), 5)[..., None]
    world[y0 - P:y0 + S + P, x0 - P:x0 + S + P] = np.clip(out * (1 - core) + B * core, 0, 255)

def main(src, dst, root="assets/map/painted/world"):
    w = np.asarray(Image.open(src).convert("RGB")).astype(np.float32)
    H, W = w.shape[:2]
    w = np.pad(w, ((P, P), (P, P), (0, 0)), mode="edge")
    for name, (x0, y0) in JOINS.items():
        inp = np.asarray(Image.open(f"{root}/{name}_inpaint.png").convert("RGB")).astype(np.float32)
        msk = np.asarray(Image.open(f"{root}/{name}_mask.png").convert("L")).astype(np.float32) / 255
        place(w, inp, msk, x0 + P, y0 + P)
    Image.fromarray(w[P:P + H, P:P + W].astype(np.uint8)).save(dst)

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
