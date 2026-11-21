"""Bake the big map into what the game reads: data/bigmap/world.json + one ground atlas PNG.

python3 -I bake_world.py LAYOUT.json TILES_DIR PROPS_DIR OUT_WORLD.json OUT_ATLAS.png
Runs assemble.py (ground) and place_props.py (props + foot boxes) into a temp dir, then:
- ground atlas: unique 32 px tiles of the assembled 4096 map; a tile that is a mirror of one already kept is
  stored as a flip flag (0 none, 1 h, 2 v, 3 h+v) instead of a new tile;
- walk grid (8 px cells, 512x512, 1 = blocked): layout F ~ ^ o blocked, . = # r s A C open, map edge blocked,
  then every prop foot box blocks the cells it overlaps; bridge (#) cells are always left open;
- start, stones (layout waypoints w1..w3), chests (landmarks 4, 11, 12; kind/level of the nearest layout
  pack), packs (layout, arena pack excluded), arena (bbox of A cells + the cell the walk route enters by),
  zones (make_layout.py ZONES as rects, first match wins).
Deterministic: same inputs, same bytes.
"""
import base64, json, math, os, subprocess, sys, tempfile
from collections import deque
from PIL import Image

LAYOUT, TILES, PROPS, OUT_JSON, OUT_ATLAS = sys.argv[1:6]
HERE = os.path.dirname(os.path.abspath(__file__))
T, C = 32, 8                      # ground tile px, walk cell px
OPEN_CH = set(".=#rsAC")          # walkable layout chars (C = chedi floor: its prop's foot box blocks)
CHEST_IDS = (4, 11, 12)           # spec: dead-end chests at landmarks 4 old well, 11 bamboo, 12 east cliff nook
CHEST_BBOX = (2, 5, 46, 44)       # chest_01.png opaque bbox (48 px sprite), for the clear-spot search
# make_layout.py ZONES, as cell rects (x, y, w, h), first match wins; levels = the pack level range there
ZONES = [((0, 77, 60, 51), (1, 2)), ((0, 0, 56, 77), (3, 4)), ((56, 50, 36, 26), (5, 6)), ((0, 76, 82, 52), (5, 6)),
         ((0, 76, 128, 52), (6, 7)), ((0, 0, 82, 50), (6, 6)), ((0, 0, 128, 128), (8, 9))]

L = json.load(open(LAYOUT)); g = L["grid"]; N = len(g)
W = N * T // C
man = json.load(open(os.path.join(PROPS, "props_manifest.json")))

tmp = tempfile.mkdtemp(prefix="bake_world_")
def run(script, *args):
    subprocess.run([sys.executable, "-I", os.path.join(HERE, script), *args], check=True, stdout=subprocess.DEVNULL)
run("assemble.py", LAYOUT, TILES, tmp)
run("place_props.py", LAYOUT, PROPS, os.path.join(tmp, "bigmap_full.png"), tmp)
full = Image.open(os.path.join(tmp, "bigmap_full.png")).convert("RGBA")
placement = json.load(open(os.path.join(tmp, "props_placement.json")))

# ---- ground atlas ------------------------------------------------------------------------------------------
tiles, canon, ground, flip = [], {}, [], []
for y in range(N):
    for x in range(N):
        t = full.crop((x * T, y * T, x * T + T, y * T + T))
        b = t.tobytes()
        if b not in canon:
            n = len(tiles); tiles.append(t)
            for f, im in ((0, t), (1, t.transpose(Image.FLIP_LEFT_RIGHT)), (2, t.transpose(Image.FLIP_TOP_BOTTOM)),
                          (3, t.transpose(Image.ROTATE_180))):
                canon.setdefault(im.tobytes(), (n, f))
        n, f = canon[b]
        ground.append(n); flip.append(f)
cols = min(32, math.ceil(math.sqrt(len(tiles))))
rows = math.ceil(len(tiles) / cols)
if cols * T > 1024 or rows * T > 1024: sys.exit(f"atlas too big: {len(tiles)} tiles")
atlas = Image.new("RGBA", (cols * T, rows * T))
for i, t in enumerate(tiles): atlas.paste(t, ((i % cols) * T, (i // cols) * T))
atlas.save(OUT_ATLAS)

# ---- walk grid -------------------------------------------------------------------------------------------------
K = T // C
blocked = bytearray(W * W)
for y in range(N):
    for x in range(N):
        if g[y][x] not in OPEN_CH:
            for dy in range(K):
                blocked[(y * K + dy) * W + x * K: (y * K + dy) * W + x * K + K] = b"\x01" * K
for i in range(W):
    blocked[i] = blocked[(W - 1) * W + i] = blocked[i * W] = blocked[i * W + W - 1] = 1
props = []
for p in placement:
    n = p["name"]; bb = man[n]["bbox"]
    box = p["box"]
    if box:
        for cy in range(max(0, box[1] // C), min(W, (box[1] + box[3] - 1) // C + 1)):
            for cx in range(max(0, box[0] // C), min(W, (box[0] + box[2] - 1) // C + 1)):
                if g[cy // K][cx // K] != "#": blocked[cy * W + cx] = 1
    props.append({"name": n, "x": p["x"], "y": p["y"], "foot": [p["size"][0] // 2, bb[3]], "box": box})
bits = bytearray(W * W // 8)
for i, v in enumerate(blocked):
    if v: bits[i >> 3] |= 1 << (i & 7)

def blk(cx, cy): return not (0 <= cx < W and 0 <= cy < W) or blocked[cy * W + cx] == 1
def roomy(cx, cy): return all(not blk(cx + dx, cy + dy) for dx in (-1, 0, 1) for dy in (-2, -1, 0))

# ---- points ------------------------------------------------------------------------------------------------------
packs_l = [p for p in L["packs"] if not p.get("arena")]
packs = [{"id": f"p{i}", "kind": p["kind"], "level": p["level"], "count": p["count"], "at": p["at"],
          "elite": bool(p.get("elite"))} for i, p in enumerate(packs_l)]
stones = [{"id": f"w{i + 1}", "at": at} for i, at in enumerate(L["waypoints"])]
lm = {l["id"]: l for l in L["landmarks"]}

# blocking prop sprites (opaque bbox in world px): a chest must not stand inside or behind one
solid = []
for p in placement:
    if not p["blocks"]: continue
    bb = man[p["name"]]["bbox"]; left = p["x"] - p["size"][0] // 2; top = p["y"] - bb[3]
    solid.append((left + bb[0], top + bb[1], left + bb[2], top + bb[3]))
def chest_spot(home):
    """Nearest 8 px cell centre to the landmark where a hero fits, the cell's layout tile is open ground and the
    chest sprite overlaps no blocking prop sprite."""
    hx, hy = home
    cand = sorted(((cx * C + C // 2, cy * C + C // 2) for cy in range((hy - 160) // C, (hy + 160) // C)
                   for cx in range((hx - 160) // C, (hx + 160) // C)), key=lambda q: (math.dist(q, home), q[1], q[0]))
    for x, y in cand:
        if not roomy(x // C, y // C) or g[y // T][x // T] not in ".=rs": continue
        r = (x - 24 + CHEST_BBOX[0], y - CHEST_BBOX[3] + CHEST_BBOX[1], x - 24 + CHEST_BBOX[2], y)
        if any(r[0] < s[2] and s[0] < r[2] and r[1] < s[3] and s[1] < r[3] for s in solid): continue
        return [x, y]
    sys.exit(f"no chest spot near {home}")
chests = []
for k in CHEST_IDS:
    home = lm[k]["at"]
    near = min(packs_l, key=lambda p: math.dist(p["at"], home))
    chests.append({"id": f"c{k}", "at": chest_spot(home), "kind": near["kind"], "level": near["level"]})

# ---- arena: bbox of A cells; gate = the open cell the shortest walk from the start enters the arena by ----------
A = [(x, y) for y in range(N) for x in range(N) if g[y][x] == "A"]
ax0, ay0 = min(a[0] for a in A), min(a[1] for a in A); ax1, ay1 = max(a[0] for a in A), max(a[1] for a in A)
s0 = (L["start"][0] // T, L["start"][1] // T)
parent = {s0: None}; q = deque([s0]); gate = None
while q and gate is None:
    x, y = q.popleft()
    for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
        if n in parent or not (0 <= n[0] < N and 0 <= n[1] < N) or g[n[1]][n[0]] not in OPEN_CH: continue
        parent[n] = (x, y)
        if g[n[1]][n[0]] == "A": gate = (x, y); break
        q.append(n)
arena = {"rect": [ax0 * T, ay0 * T, (ax1 - ax0 + 1) * T, (ay1 - ay0 + 1) * T], "gate": [gate[0] * T + T // 2, gate[1] * T + T // 2]}

# ---- zones -------------------------------------------------------------------------------------------------------
def in_rect(r, x, y): return r[0] <= x < r[0] + r[2] and r[1] <= y < r[1] + r[3]
zones = []
for i, (r, lv) in enumerate(ZONES):
    mine = [l for l in L["landmarks"] if next(j for j, (rr, _) in enumerate(ZONES) if in_rect(rr, l["at"][0] // T, l["at"][1] // T)) == i]
    pick = next((l for l in mine if l["levels"]), mine[0] if mine else None)
    name = pick["name"].split(" (")[0] if pick else f"z{i + 1}"
    zones.append({"name": name, "rect": [v * T for v in r], "levels": list(lv)})

world = {
    "_doc": "Baked by tools/bigmap/bake_world.py from data/bigmap/layout_v1.json - do not edit. ground[i]/flip[i]: "
            "cell i = y*128+x, atlas tile index and flip (0 none, 1 h, 2 v, 3 h+v); atlas tile n at "
            "((n % cols)*32, (n / cols)*32). walk: base64, 512x512 bits for 8 px cells, bit i = y*512+x is "
            "(byte i>>3 >> (i&7)) & 1, 1 = blocked. props: foot (x, y) in px, foot = pixel in the sprite that sits "
            "there, box [x,y,w,h] or null. zones: first match wins.",
    "size": [N * T, N * T], "tile": T, "cell": C,
    "atlas": {"file": "res://assets/map/bigmap/ground_atlas.png", "cols": cols, "count": len(tiles)},
    "props_dir": "res://assets/map/bigmap/props",
    "ground": ground, "flip": flip, "walk": base64.b64encode(bytes(bits)).decode(),
    "props": props, "start": L["start"], "stones": stones, "chests": chests, "packs": packs,
    "arena": arena, "zones": zones,
}
def dump(v): return json.dumps(v, ensure_ascii=False, separators=(",", ":"))
lines = []
for k, v in world.items():
    if isinstance(v, list) and v and isinstance(v[0], dict):
        lines.append(f"{dump(k)}:[\n" + ",\n".join(dump(e) for e in v) + "\n]")
    else:
        lines.append(f"{dump(k)}:{dump(v)}")
with open(OUT_JSON, "w", encoding="utf-8") as fh:
    fh.write("{\n" + ",\n".join(lines) + "\n}\n")
print(f"atlas {len(tiles)} tiles ({cols} cols, {atlas.size[0]}x{atlas.size[1]}), props {len(props)} "
      f"(boxes {sum(1 for p in props if p['box'])}), packs {len(packs)}, stones {len(stones)}, chests "
      f"{[(c['id'], c['at'], c['kind'], c['level']) for c in chests]}, arena {arena}, "
      f"blocked {sum(blocked)}/{W * W}")
