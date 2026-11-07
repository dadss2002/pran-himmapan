#!/usr/bin/env python3
"""M4a: free fixes for the leftover forest seams (points 1-8 in docs/preview/m4a/seam_candidates.png).
No PixelLab gen. Tools: tone_seam (colour step), LaMa (lines in canopy/grass, tools/lama_fill.py),
texture-synthesis (blurred bush areas). Runs after painted_world_joins.py.

Usage: python3 tools/painted_world_fixes.py <world_j.png> <out.png> [point ...]
"""
import sys, os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
from painted_world_joins import tone_seam
from lama_fill import fill


def organic_band(size, pts, width, seed=0, wobble=4):
    """Mask (255 = fill) along a polyline with a wobbly edge so no straight line shows afterwards."""
    rng = np.random.default_rng(seed)
    m = Image.new("L", size, 0); d = ImageDraw.Draw(m)
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        n = max(2, int(np.hypot(x1 - x0, y1 - y0) // 6))
        for t in np.linspace(0, 1, n):
            r = width / 2 + rng.uniform(-wobble, wobble)
            x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            d.ellipse((x - r, y - r, x + r, y + r), fill=255)
    return np.asarray(m.filter(ImageFilter.MaxFilter(3)))


def lama_band(w, x0, y0, pts, width, seed=0):
    """LaMa fill a wobbly band (pts in world px) inside the 512x512 window at (x0, y0)."""
    win = w[y0:y0 + 512, x0:x0 + 512].astype(np.uint8)
    mask = organic_band((512, 512), [(x - x0, y - y0) for x, y in pts], width, seed)
    w[y0:y0 + 512, x0:x0 + 512] = fill(win, mask).astype(np.float32)


def snap_box(w, ref, box, colours=32, region=None):
    """Snap pixels in box (x0,y0,x1,y1) to a k-means palette of the ORIGINAL picture around it, so a
    tone ramp or AI fill becomes crisp pixel-art colours again. region=(x0,y0,x1,y1) to sample from."""
    import cv2
    x0, y0, x1, y1 = box; rx0, ry0, rx1, ry1 = region or (x0 - 80, y0 - 60, x1 + 80, y1 + 60)
    src = ref[ry0:ry1, rx0:rx1].reshape(-1, 3).astype(np.float32)
    _, _, pal = cv2.kmeans(src, colours, None, (3, 20, 1.0), 3, cv2.KMEANS_PP_CENTERS)
    a = w[y0:y1, x0:x1].reshape(-1, 3)
    d = ((a[:, None, :] - pal[None]) ** 2).sum(-1)
    w[y0:y1, x0:x1] = pal[d.argmin(1)].reshape(y1 - y0, x1 - x0, 3)


def p1(w):
    """Point 1 (c1r1 grass left of the stone circle): colour step down column x=1503, y 505-640.
    Approved 2026-11-07 after: grass band by texture-synthesis, tree จ below completed by mirroring
    its intact right half, then the mirror's fold healed from crown pixels."""
    ref = w.copy()
    band = organic_band(w.shape[1::-1], [(1503, 505), (1502, 560), (1504, 600), (1503, 640)], 22, seed=3, wobble=6) > 0
    sample = np.zeros(w.shape[:2], bool); sample[480:680, 1391:1611] = True
    ts_fill(w, band, 1311, 380, sample=sample & ~band, seed=2)
    mirror_crown(w, ref, 1503, 565, 690, (1523, 640), clear_to=660)
    heal_crease(w, 1503, 576, 668, (1425, 575, 1585, 690), width=12, seed=9,
                notch=[(1498, 590), (1520, 590), (1501, 621)])


TS = "/tmp/ts_dl/texture-synthesis-0.8.2-x86_64-unknown-linux-musl/texture-synthesis"


def crown_mask(img):
    """Tree crown pixels in this painting: dark teal (blue > red); grass is bright yellow-green."""
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    return (0.3 * r + 0.59 * g + 0.11 * b < 120) & (b > r)


def ts_fill(w, hole, x0, y0, sample_rows=(60, 200), seed=2, tmp="/tmp/m4a/tsfix", sample=None):
    """texture-synthesis fill of `hole` (world bool mask) inside the 384x384 crop at (x0, y0),
    sampling only non-crown pixels in rows sample_rows of the crop (grass)."""
    import subprocess
    os.makedirs(tmp, exist_ok=True)
    crop = w[y0:y0 + 384, x0:x0 + 384].astype(np.uint8)
    hm = hole[y0:y0 + 384, x0:x0 + 384]
    if sample is None:
        sm = np.zeros((384, 384), bool); sm[sample_rows[0]:sample_rows[1], 40:340] = True
        sm &= ~crown_mask(crop.astype(int)) & ~hm
    else:
        sm = sample[y0:y0 + 384, x0:x0 + 384] & ~hm
    Image.fromarray(crop).save(f"{tmp}/crop.png")
    Image.fromarray(np.where(hm, 0, 255).astype(np.uint8)).save(f"{tmp}/mask.png")
    Image.fromarray((sm * 255).astype(np.uint8)).save(f"{tmp}/smask.png")
    subprocess.run([TS, "--out-size", "384", "--inpaint", f"{tmp}/mask.png", "--sample-masks", f"{tmp}/smask.png",
                    "--cauchy", "0.5", "--seed", str(seed), "--no-progress", "-o", f"{tmp}/out.png",
                    "generate", f"{tmp}/crop.png"], check=True)
    w[y0:y0 + 384, x0:x0 + 384] = np.asarray(Image.open(f"{tmp}/out.png").convert("RGB")).astype(np.float32)


def mirror_crown(w, ref, axis, y0, y1, seed_xy, half=84, src_w=90, clear_to=None):
    """Complete a tree crown cut by a seam: mirror the intact half (right of `axis`, taken from the
    un-edited picture `ref`) onto the left. Only the crown blob containing seed_xy is copied; leftover
    crown on the left that the mirror does not cover is cleared to grass with texture-synthesis."""
    import cv2
    cm = crown_mask(ref.astype(int))
    reg = cm[y0:y1, axis:axis + src_w].astype(np.uint8)
    _, lab = cv2.connectedComponents(reg, connectivity=4)
    blob = lab == lab[seed_xy[1] - y0, seed_xy[0] - axis]
    nb = cv2.filter2D(blob.astype(np.uint8), -1, np.ones((3, 3), np.float32))
    keep = np.zeros_like(cm); keep[y0:y1, axis:axis + src_w] = blob & (nb >= 5)
    t0 = axis - half; tx = np.arange(t0, axis); sx = 2 * axis - 1 - tx
    src = ref[y0:y1][:, sx]; srcm = keep[y0:y1][:, sx]
    tgt = crown_mask(w[y0:y1, t0:axis].astype(int))
    hole = np.zeros(w.shape[:2], bool); hole[y0:y1, t0:axis] = tgt & ~srcm
    hole[clear_to or y1:] = False
    hole = cv2.dilate(hole.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0
    ts_fill(w, hole, axis - 192, y0 - 130)
    r = w[y0:y1, t0:axis]; r[srcm] = src[srcm]


def heal_crease(w, axis, y0, y1, box, width=10, seed=3, notch=None):
    """Remove the fold line a mirror leaves down its axis: re-synthesise a wobbly band around it
    from crown pixels only (texture-synthesis keeps crisp pixel-art clusters)."""
    band = organic_band(w.shape[1::-1], [(axis, y0), (axis + 1, (y0 + y1) // 2), (axis, y1)], width, seed, wobble=3) > 0
    sample = np.zeros(w.shape[:2], bool); x0, by0, x1, by1 = box
    sample[by0:by1, x0:x1] = crown_mask(w[by0:by1, x0:x1].astype(int))
    import cv2
    inside = cv2.erode(crown_mask(w.astype(int)).astype(np.uint8), np.ones((3, 3), np.uint8)) > 0
    band &= inside          # never paint crown into the grass around the tree
    if notch:               # a light wedge left between the two lobes: fill it with crown as well
        m = Image.new("L", w.shape[1::-1], 0); ImageDraw.Draw(m).polygon(notch, fill=255)
        band |= np.asarray(m) > 0
    sample &= ~band
    ts_fill(w, band, axis - 192, y0 - 130, sample=sample, seed=seed)





def blur_mask(w, box, cell=8, limit=20):
    """Blocks left soft by the earlier multiband seam blend: a crisp pixel-art 8x8 block has few
    colours, a blended one has many. Returns a world bool mask of those blocks inside box."""
    x0, y0, x1, y1 = box
    a = w[y0:y1, x0:x1].astype(np.int64)
    code = (a[..., 0] << 16) | (a[..., 1] << 8) | a[..., 2]
    m = np.zeros(w.shape[:2], bool)
    for by in range(0, y1 - y0 - cell + 1, cell):
        for bx in range(0, x1 - x0 - cell + 1, cell):
            if len(np.unique(code[by:by + cell, bx:bx + cell])) >= limit:
                m[y0 + by:y0 + by + cell, x0 + bx:x0 + bx + cell] = True
    return m


def recrisp(w, box, sample_box, seed=2, limit=20):
    """Re-synthesise the soft blocks inside box from crisp pixels of sample_box (texture-synthesis),
    in 384px crops along the box."""
    hole = blur_mask(w, box, limit=limit)
    sx0, sy0, sx1, sy1 = sample_box
    samp = np.zeros(w.shape[:2], bool); samp[sy0:sy1, sx0:sx1] = True
    samp &= ~blur_mask(w, sample_box, limit=limit)
    x0, y0, x1, y1 = box
    cy = max(0, (y0 + y1) // 2 - 192)
    for cx in range(x0, x1, 300):
        cx = min(cx, w.shape[1] - 384)
        h = hole.copy(); h[:, :cx] = False; h[:, min(cx + 300, x1):] = False
        if h.any():
            ts_fill(w, h, cx, cy, sample=samp, seed=seed)


def tree_mask(ref, ellipses, seed_xy, crown_bottom=None):
    """Silhouette of one whole tree/bush in the un-edited picture: crown (dark teal) + trunk (dark
    purple-brown) inside the given ellipses, the blob connected to seed_xy, holes filled. Below
    crown_bottom only trunk pixels are kept, so the shadow under the crown is not cut out as a block."""
    import cv2
    a = ref.astype(int); r, g, b = a[..., 0], a[..., 1], a[..., 2]
    lum = 0.3 * r + 0.59 * g + 0.11 * b
    roi = Image.new("L", ref.shape[1::-1], 0); d = ImageDraw.Draw(roi)
    for e in ellipses:
        d.ellipse(e, fill=255)
    roi = np.asarray(roi) > 0
    trunk = (g < r + 6) & (lum < 80)
    m = (((lum < 120) & (b > r)) | trunk) & roi
    m = cv2.morphologyEx(m.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8)) > 0
    _, lab = cv2.connectedComponents(m.astype(np.uint8), connectivity=8)
    k = lab[seed_xy[1], seed_xy[0]]
    if k == 0:   # seed on a light leaf: take the biggest blob inside the ellipses
        k = np.bincount(lab[roi & (lab > 0)]).argmax()
    m = lab == k
    ff = (~m).astype(np.uint8) * 255; fm = np.zeros((ff.shape[0] + 2, ff.shape[1] + 2), np.uint8)
    cv2.floodFill(ff, fm, (0, 0), 0); m |= (ff > 0) & roi
    if crown_bottom is not None:
        tk = cv2.dilate(trunk.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0
        m[crown_bottom:] &= tk[crown_bottom:]
        _, lab = cv2.connectedComponents(m.astype(np.uint8), connectivity=8)
        m = lab == lab[seed_xy[1], seed_xy[0]]
    return m


def stamp(w, ref, mask, dx, dy):
    """Paste the masked tree from `ref` moved by (dx, dy): a whole tree placed over a cut one."""
    ys, xs = np.where(mask)
    w[ys + dy, xs + dx] = ref[ys, xs]


PROPS = os.path.join(os.path.dirname(__file__), "..", "assets", "map", "painted", "props")


def place_bush(w, name, cx, by, pal_box, shadow=True):
    """Paste a PixelLab bush prop (assets/map/painted/props/<name>.png, 0 gen - already paid) with its
    feet at (cx, by): colours snapped to the palette of pal_box, interior near-black softened to the
    forest's dark teal, 1px outline in the tree-outline colour, soft contact shadow underneath."""
    import cv2
    b = Image.open(os.path.join(PROPS, name + ".png")).convert("RGBA")
    b = b.crop(b.getbbox()); a = np.asarray(b).astype(np.float32)
    rgb, al = a[..., :3], a[..., 3] > 0
    x0, y0, x1, y1 = pal_box
    _, _, pal = cv2.kmeans(w[y0:y1, x0:x1].reshape(-1, 3).astype(np.float32), 40, None,
                           (3, 20, 1.0), 3, cv2.KMEANS_PP_CENTERS)
    d = ((rgb[al][:, None, :] - pal[None]) ** 2).sum(-1); rgb[al] = pal[d.argmin(1)]
    er = cv2.erode(al.astype(np.uint8), np.ones((3, 3), np.uint8)) > 0
    dark = er & (rgb.sum(-1) < 150)
    rgb[dark] = rgb[dark] * 0.45 + np.array([22, 74, 80], np.float32) * 0.55
    rgb[al & ~er] = (9, 40, 65)
    h, wd = al.shape; X, Y = int(cx - wd / 2), int(by - h)
    if shadow:
        sh = Image.new("L", w.shape[1::-1], 0)
        ImageDraw.Draw(sh).ellipse((cx - wd * 0.48, by - h * 0.30, cx + wd * 0.48, by + 5), fill=120)
        sa = np.asarray(sh.filter(ImageFilter.GaussianBlur(4))).astype(np.float32)[..., None] / 255.0
        w[:] = w * (1 - sa) + np.array([8, 30, 28], np.float32) * sa
    reg = w[Y:Y + h, X:X + wd]; reg[al] = rgb[al]


def p2(w):
    """Point 2 (row seam y=768, x 688-1180 beside the stone road): texture-synthesis band over the
    line, then whole trees from elsewhere in the map stamped over the cut ones (owner: method 1)."""
    ref = w.copy()
    pts = [(690, 768), (760, 769), (840, 767), (920, 769), (1000, 768), (1080, 767), (1180, 768)]
    band = organic_band(w.shape[1::-1], pts, 18, seed=2, wobble=5) > 0
    band[:, :689] = False
    samp = np.zeros(w.shape[:2], bool); samp[700:840, 688:1200] = True; samp &= ~band
    b1 = band.copy(); b1[:, 1000:] = False; ts_fill(w, b1, 688, 600, sample=samp, seed=2)
    b2 = band.copy(); b2[:, :1000] = False; ts_fill(w, b2, 880, 600, sample=samp, seed=2)
    # ค+จ: whole tree from above the dirt path (x 748-880, y 596-727), trunk on จ's trunk (approved).
    # Stamped bushes for ก, ข, ง were tried and looked pasted (owner 2026-11-07) - left as the healed forest.
    t_path = tree_mask(ref, [(748, 592, 884, 700), (775, 680, 860, 732)], (815, 650), 694)
    stamp(w, ref, t_path, 96, 126)
    # ฉ: the seam blur continued right of the old band up to x 1376 - re-synthesise it crisp
    recrisp(w, (1166, 740, 1376, 800), (1166, 690, 1376, 860), seed=2)


POINTS = {"1": p1, "2": p2}


def main(src, dst, pts):
    w = np.asarray(Image.open(src).convert("RGB")).astype(np.float32)
    for p in pts or POINTS:
        POINTS[p](w)
    Image.fromarray(np.clip(w, 0, 255).astype(np.uint8)).save(dst)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3:])
