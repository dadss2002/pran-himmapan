"""Ice block for a frozen monster (M5b Task 7 review, owner 2026-11-10: "a frozen monster gets an ice-block overlay so it
differs from slowed ... hand-drawn, 0 gen"). Pixel art drawn here by hand, pixel by pixel (no PixelLab, no AI):
    python3 -I tools/ice_block_art.py
Writes
  assets/fx/ice_block.png        32x32 nine-patch (margins NINE = 10): a translucent pale-ice face, a dark-blue outline
                                 with chamfered corners, a light rim, a white top / left highlight, glints in the top-left
                                 corner and crystal shards poking out of three corners. Wolf stretches it round the body.
  assets/fx/ice_block_boxes.json the body box of every monster kind per direction, in sprite px relative to the feet
                                 anchor (union of the opaque pixels of every pose + run frame of that direction), so the
                                 block fits the body it freezes: {kind: {direction: [x, y, w, h]}}.
"""
import json, os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets/fx")
S, NINE, IN = 32, 10, 3          # texture size, nine-patch margin, outline inset (room for the corner shards)

OUTLINE = (20, 66, 110, 255)     # #14426e
RIM = (127, 212, 255, 255)       # #7fd4ff (the frost streak's blue)
HI = (255, 255, 255, 255)
FACE = (214, 242, 255, 92)       # #d6f2ff, ~36 %: the frozen body shows through, paler
GLINT = (255, 255, 255, 200)
SHARD = (168, 236, 255, 255)     # #a8ecff
SHARD_HI = (255, 255, 255, 255)


def draw_block():
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    p = im.load()
    lo, hi = IN, S - 1 - IN       # outline square lo..hi
    cut = 2                       # chamfer
    def inside(x, y, d=0):        # inside the chamfered square shrunk by d
        a, b = lo + d, hi - d
        if not (a <= x <= b and a <= y <= b): return False
        c = cut
        return (x - a) + (y - a) >= c and (b - x) + (y - a) >= c and (x - a) + (b - y) >= c and (b - x) + (b - y) >= c
    for y in range(S):
        for x in range(S):
            if inside(x, y, 2): p[x, y] = FACE
            elif inside(x, y, 1): p[x, y] = RIM
            elif inside(x, y, 0): p[x, y] = OUTLINE
    # white highlight along the top and the left inner rim (edges tile, so it runs the whole side)
    for x in range(lo + 3, hi - 2):
        p[x, lo + 1] = HI
    for y in range(lo + 3, hi - 6):
        p[lo + 1, y] = HI
    # glints on the face, inside the top-left corner patch (corners never stretch)
    for i in range(4):
        p[lo + 3 + i, lo + 6 - i] = GLINT
    for i in range(2):
        p[lo + 3 + i, lo + 8 - i] = GLINT
    # a sparkle in the bottom-right corner
    cx, cy = hi - 4, hi - 4
    for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
        p[cx + dx, cy + dy] = GLINT if (dx, dy) != (0, 0) else HI
    # crystal shards poking out of three corners: a 2 px thick diagonal crystal, light core, white tip, dark edge
    TL = ["W...",
          ".SO.",
          ".LSO",
          "..OS"]                  # top-left stamp, (0, 0) = 2 px out from the outline corner; mirrored for the others
    col = {"W": SHARD_HI, "S": SHARD, "L": SHARD_HI, "O": OUTLINE}
    def stamp(fx, fy):
        for j, row in enumerate(TL):
            for i, ch in enumerate(row):
                if ch == ".": continue
                x = (lo - 2 + i) if fx > 0 else (hi + 2 - i)
                y = (lo - 2 + j) if fy > 0 else (hi + 2 - j)
                if p[x, y][3] == 0 or ch in "WSL": p[x, y] = col[ch]
    stamp(1, 1); stamp(-1, 1); stamp(1, -1)
    return im


def kinds():
    out = {"wolf": os.path.join(ROOT, "assets/wolf/manifest.json")}
    base = os.path.join(ROOT, "assets/monsters")
    for k in sorted(os.listdir(base)):
        m = os.path.join(base, k, "manifest.json")
        if os.path.exists(m): out[k] = m
    return out


def boxes():
    res = {}
    for kind, mp in kinds().items():
        m = json.load(open(mp)); d0 = os.path.dirname(mp); res[kind] = {}
        for d in m["directions"]:
            x0 = y0 = 10 ** 9; x1 = y1 = -10 ** 9
            for anim in ("pose", "run"):
                if anim not in m["frames"]: continue
                cw, chh = m["cell"][anim]; ax, ay = m["anchor"][anim]
                sheet = Image.open(os.path.join(d0, "%s_%s.png" % (anim, d))).convert("RGBA")
                for i in range(int(m["frames"][anim][d])):
                    bb = sheet.crop((i * cw, 0, (i + 1) * cw, chh)).getchannel("A").point(lambda a: 255 if a > 40 else 0).getbbox()
                    if not bb: continue
                    x0 = min(x0, bb[0] - ax); y0 = min(y0, bb[1] - ay); x1 = max(x1, bb[2] - ax); y1 = max(y1, bb[3] - ay)
            res[kind][d] = [x0, y0, x1 - x0, y1 - y0]
    return res


if __name__ == "__main__":
    im = draw_block()
    im.save(os.path.join(OUT, "ice_block.png"))
    b = boxes()
    with open(os.path.join(OUT, "ice_block_boxes.json"), "w") as f:
        json.dump({"_doc": "tools/ice_block_art.py: body box per kind / direction, sprite px from the feet anchor [x, y, w, h]",
                   "nine": NINE, "inset": IN, "boxes": b}, f, indent=1, ensure_ascii=False)
    print("wrote assets/fx/ice_block.png", im.size, "and ice_block_boxes.json", {k: v["south"] for k, v in b.items()})
