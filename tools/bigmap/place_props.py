"""Scatter the picked PixelLab props over the assembled big map (preview + placement list).

python3 -I place_props.py LAYOUT.json PROPS_DIR GROUND.png OUT_DIR
Writes OUT_DIR/bigmap_props.png (ground + Y-sorted props) and OUT_DIR/props_placement.json
(name, foot x/y in px = sprite foot (bottom of the opaque bbox), sprite size, blocks, foot box [x,y,w,h] or null,
floor = drawn flat under the y-sorted world, deck = walkable bridge deck rect [x,y,w,h] in px) for the Godot build.
Deterministic (fixed seeds). Boxes, floor and deck are data only: the preview image does not use them.
"""
import json, sys, random, math
from PIL import Image

LAYOUT, PROPS, GROUND, OUT = sys.argv[1:5]
L = json.load(open(LAYOUT, encoding="utf-8"))
g = L["grid"]; N = len(g); T = 32
man = json.load(open(f"{PROPS}/props_manifest.json", encoding="utf-8"))
img = {k: Image.open(f"{PROPS}/{k}.png").convert("RGBA") for k in man}

def at(x, y): return g[y][x] if 0 <= x < N and 0 <= y < N else "F"
def near(x, y, chars, r):
    return any(at(xx, yy) in chars for yy in range(y - r, y + r + 1) for xx in range(x - r, x + r + 1))

# keep-clear zones: monster packs, spawn, waypoints (cells, radius)
clear = [(p["at"][0] // T, p["at"][1] // T, 3) for p in L["packs"]]
clear += [(L["start"][0] // T, L["start"][1] // T, 3)] + [(w[0] // T, w[1] // T, 3) for w in L["waypoints"]]
def cleared(x, y): return any((x - cx) ** 2 + (y - cy) ** 2 <= r * r for cx, cy, r in clear)

placed = []  # (name, foot_x, foot_y, blocks)
def put(name, cx, cy, blocks, space=0.0, jitter=8, rnd=None):
    """foot of the sprite (bottom of its opaque box) at the centre-bottom of cell (cx, cy)"""
    rnd = rnd or random
    fx = cx * T + T // 2 + rnd.randint(-jitter, jitter)
    fy = cy * T + T - 2 + rnd.randint(-jitter // 2, jitter // 2)
    if space and any((fx - p[1]) ** 2 + (fy - p[2]) ** 2 < (max(space, p[4]) * T) ** 2 for p in placed): return False
    placed.append((name, fx, fy, blocks, space)); return True

def names(prefix, idx=None):
    ks = sorted(k for k in man if k.startswith(prefix + "_"))
    return [ks[i - 1] for i in idx] if idx else ks
TREE64 = names("tree", [1, 4, 5, 6, 7, 8, 9]); BANANA = names("tree", [2]); BAMBOO = names("tree", [3])
BIG = names("banyan") + names("raintree")
ROCK = names("rock", [1, 2, 5, 6, 8, 9, 10]); LOG = names("rock", [3, 4, 7])
FLOWER = names("decor", [2, 3, 4, 5, 15, 17, 18, 22]); BUSH = names("decor", [1, 6, 7, 11, 12, 13, 14, 16, 19, 20, 21, 23])
MUSH = names("decor", [8, 9, 10])
LOTUS = names("pond", [1, 2, 3, 6, 14, 17]); PAD = names("pond", [4, 5, 12, 15, 18, 19]); REED = names("pond", [7, 8, 9, 13, 16, 20])
RUIN = names("ruin", [1, 2, 3, 5, 6, 7, 8, 10, 11, 12, 14, 15, 16])
ARENA_EDGE = names("arena", [1, 2, 4, 5, 6, 7, 8, 9, 10, 11])

r = random.Random(20261121)
# 1) fixed landmark pieces
put("chedi_01", 81, 60, True, jitter=0)
for (cx, cy), n in zip([(74, 57), (86, 57), (74, 67), (86, 67)], ["prang_01", "prang_02", "chedi_02", "ruin_13"]):
    put(n, cx, cy, True, jitter=0)
put("ruin_04", 77, 64, True, jitter=0)
put("ruin_13", 14, 108, True, jitter=0)          # start shrine
put("ruin_09", 20, 24, True, jitter=0)           # old well (stone ring)
for cx, cy in [(106, 8), (116, 8), (106, 19), (116, 19)]: put("arena_03", cx, cy, True, jitter=0)  # braziers
# bridges: centre on the bridge cells of each crossing
for (lx, ly), n in [((57, 57), "bridge_wood_01"), ((66, 89), "bridge_stone_01")]:
    cells = [(x, y) for y in range(ly - 6, ly + 7) for x in range(lx - 8, lx + 9) if at(x, y) == "#"]
    mx = sum(c[0] for c in cells) / len(cells) * T + T / 2; my = sum(c[1] for c in cells) / len(cells) * T + T / 2
    bb = man[n]["bbox"]  # centre the deck on the crossing; foot = bottom of the sprite's opaque box
    placed.append((n, int(mx), int(my + (bb[3] - bb[1]) / 2), False, 0))

# arena rim: pillars/statues/bones around the edge, centre left open for the fight
rim = [(x, y) for y in range(N) for x in range(N) if g[y][x] == "A" and near(x, y, "r", 1)]
r.shuffle(rim)
for k, (x, y) in enumerate(rim):
    put(ARENA_EDGE[k % len(ARENA_EDGE)], x, y, True, space=3.5, jitter=4, rnd=r)
# 2) forest edge: big trees, then 64px trees between them
edge = [(x, y) for y in range(N) for x in range(N) if g[y][x] == "F" and near(x, y, ".=sor", 1)]
r.shuffle(edge)
for x, y in edge:
    if not cleared(x, y): put(r.choice(BIG), x, y, True, space=3.2, rnd=r)
for x, y in edge:
    if not cleared(x, y) and r.random() < 0.5: put(r.choice(TREE64 + BANANA), x, y, True, space=1.6, rnd=r)

# 3) themed spots
for y in range(N):
    for x in range(N):
        c = g[y][x]
        if (x - 34) ** 2 + (y - 60) ** 2 <= 25 and c == "." and r.random() < 0.3: put(r.choice(MUSH), x, y, False, space=0.8, rnd=r)
        if (x - 70) ** 2 + (y - 24) ** 2 <= 30 and c in ".F" and r.random() < 0.35: put(BAMBOO[0], x, y, True, space=1.3, rnd=r)

# 4) scatter by terrain
for y in range(N):
    for x in range(N):
        c = g[y][x]; q = r.random()
        if c in "=#~^AC" or near(x, y, "=", 1) and c != "o":
            if c == "~" and near(x, y, ".", 1) and q < 0.10: put(r.choice(REED), x, y, False, space=1.0, rnd=r)
            continue
        if cleared(x, y) and c != "o": continue
        if c == ".":
            if q < 0.012: put(r.choice(TREE64), x, y, True, space=2.5, rnd=r)
            elif q < 0.020: put(r.choice(ROCK + LOG), x, y, True, space=2.0, rnd=r)
            elif q < (0.16 if near(x, y, "F", 2) else 0.07): put(r.choice(BUSH if near(x, y, "F", 2) else FLOWER + BUSH), x, y, False, space=0.9, rnd=r)
        elif c == "s":
            if q < 0.07: put(r.choice(RUIN), x, y, True, space=2.2, rnd=r)
            elif q < 0.10: put(r.choice(BUSH), x, y, False, space=1.0, rnd=r)
        elif c == "r":
            if x > 85 and y < 50 and q < 0.012: put(r.choice(names("deadtree")), x, y, True, space=5.0, rnd=r)
            elif q < 0.05: put(r.choice(ROCK), x, y, True, space=2.0, rnd=r)
            elif q < 0.08: put(r.choice(BUSH), x, y, False, space=1.0, rnd=r)
        elif c == "o":
            edge_o = near(x, y, ".", 1)
            if edge_o and q < 0.25: put(r.choice(REED + LOTUS), x, y, False, space=0.9, rnd=r)
            elif not edge_o and q < 0.12: put(r.choice(LOTUS + PAD), x, y, False, space=1.2, rnd=r)

# compose, Y-sorted by foot
out = Image.open(GROUND).convert("RGBA")
for n, fx, fy, _, _ in sorted(placed, key=lambda p: p[2]):
    im = img[n]; bb = man[n]["bbox"]
    out.alpha_composite(im, (max(0, fx - im.width // 2), max(0, fy - bb[3])))
out.save(f"{OUT}/bigmap_props.png")
def im_size(n): return list(img[n].size)
TREES = ("tree_", "banyan_", "raintree_", "deadtree_")
# buildings and big ruins (walls, rubble, fallen stupa, well, shrine, arch, stairs, root-head): their box covers
# ~70% of the sprite's opaque base, so the hero cannot walk over the base (AI decision, task-1 review item 5)
STRUCTURES = ("chedi_", "prang_") + tuple(f"ruin_{i:02d}" for i in (2, 3, 4, 7, 8, 9, 10, 13, 14, 16))
BASE_BAND, BASE_ALPHA, STRUCT_SHARE = 12, 128, 0.7
FLOOR = ("bridge_",) + tuple(f"pond_{i:02d}" for i in (4, 5, 12, 15, 19))  # flat: bridges, floating pads/rosettes
# walkable deck inside each bridge sprite (sprite px, x0, y0, x1, y1): the opaque bbox minus the rails along the
# top and the front (bottom) edge and the abutment feet under the deck; read from the sprites by eye
DECK = {"bridge_wood_01": (9, 54, 199, 104), "bridge_stone_01": (10, 52, 198, 116)}
def base_span(n):
    """x0, x1 (sprite px, end exclusive) of the solid pixels in the bottom BASE_BAND rows of the opaque bbox"""
    bb = man[n]["bbox"]; a = img[n].getchannel("A")
    xs = [x for y in range(bb[3] - BASE_BAND, bb[3]) for x in range(bb[0], bb[2]) if a.getpixel((x, y)) >= BASE_ALPHA]
    return min(xs), max(xs) + 1
def foot_box(n, fx, fy, blocks):
    """Collision box [x, y, w, h] on the foot line (bottom of the opaque bbox). Trees: trunk, 1/4 bbox width,
    8-12 px high, centred under the bbox. Structures: 70% of the solid base width, centred on the base, 16 px
    high at most. Others: 1/3 bbox width, 8-16 px high, centred under the bbox. Min 12 px wide."""
    if not blocks: return None
    bb = man[n]["bbox"]; bw, bh = bb[2] - bb[0], bb[3] - bb[1]
    left = fx - img[n].width // 2
    if n.startswith(STRUCTURES):
        b0, b1 = base_span(n)
        w = max(12, round((b1 - b0) * STRUCT_SHARE)); cx = left + (b0 + b1) // 2
        h = min(16, max(8, round(bh * 0.25)))
    else:
        tree = n.startswith(TREES)
        w = max(12, round(bw / 4 if tree else bw / 3)); cx = left + (bb[0] + bb[2]) // 2
        h = min(12 if tree else 16, max(8, round(bh * (0.1 if tree else 0.25))))
    return [cx - w // 2, fy - h, w, h]
def deck(n, fx, fy):
    if n not in DECK: return None
    x0, y0, x1, y1 = DECK[n]; left, top = fx - img[n].width // 2, fy - man[n]["bbox"][3]
    return [left + x0, top + y0, x1 - x0, y1 - y0]
json.dump([{"name": n, "x": fx, "y": fy, "size": im_size(n), "blocks": b, "box": foot_box(n, fx, fy, b),
            "floor": n.startswith(FLOOR), "deck": deck(n, fx, fy)}
           for n, fx, fy, b, _ in placed],
          open(f"{OUT}/props_placement.json", "w", encoding="utf-8"), indent=0)
from collections import Counter
print(len(placed), Counter(n.rsplit("_", 1)[0] for n, *_ in placed).most_common())
