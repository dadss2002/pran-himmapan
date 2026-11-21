"""Bake the big map into what the game reads: data/bigmap/world.json + one ground atlas PNG.

python3 -I bake_world.py LAYOUT.json TILES_DIR PROPS_DIR OUT_WORLD.json OUT_ATLAS.png
Runs assemble.py (ground) and place_props.py (props, foot boxes, floor flags, bridge decks) in a temp dir, then:
- ground atlas: unique 32 px tiles of the assembled 4096 map; a tile that is a mirror of one already kept is
  stored as a flip flag (0 none, 1 h, 2 v, 3 h+v) instead of a new tile;
- walk grid (8 px cells, 512x512, 1 = blocked): layout F ~ ^ o blocked, . = r s A C open, map edge blocked;
  a bridge (#) cell is open only when it lies inside a bridge prop's deck rect (rails and open water blocked);
  then every prop foot box blocks the cells it overlaps;
- start, stones (layout waypoints w1..w3), chests (landmarks 4, 11, 12; kind/level of the nearest layout
  pack), packs (layout, arena pack excluded), arena (disc of A cells, its bbox, the gate on the approach path
  just outside both, the layout's arena pack), zones (layout zones, first match wins).
Deterministic: same inputs, same bytes.
"""
import base64, heapq, json, math, os, subprocess, sys, tempfile
from PIL import Image

LAYOUT, TILES, PROPS, OUT_JSON, OUT_ATLAS = sys.argv[1:6]
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
T, C = 32, 8                      # ground tile px, walk cell px
K = T // C                        # walk cells per tile side
OPEN_CH = set(".=#rsAC")          # walkable layout chars (# only on a bridge deck; C = chedi floor, its prop's box blocks)
CHEST_IDS = (4, 11, 12)           # spec: dead-end chests at landmarks 4 old well, 11 bamboo, 12 east cliff nook
CHEST_SPRITE = "chest_01"

def res_path(p): return "res://" + os.path.relpath(os.path.abspath(p), ROOT).replace(os.sep, "/")
def load(p): return json.load(open(p, encoding="utf-8"))

L = load(LAYOUT); g = L["grid"]; N = len(g)
W = N * T // C
man = load(os.path.join(PROPS, "props_manifest.json"))
with tempfile.TemporaryDirectory(prefix="bake_world_") as tmp:
    for script, args in (("assemble.py", (LAYOUT, TILES, tmp)),
                         ("place_props.py", (LAYOUT, PROPS, os.path.join(tmp, "bigmap_full.png"), tmp))):
        subprocess.run([sys.executable, "-I", os.path.join(HERE, script), *args], check=True, stdout=subprocess.DEVNULL)
    full = Image.open(os.path.join(tmp, "bigmap_full.png")).convert("RGBA")
    placement = load(os.path.join(tmp, "props_placement.json"))

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
decks = [p["deck"] for p in placement if p.get("deck")]
def on_deck(cx, cy):  # the whole 8 px cell inside a bridge deck rect
    return any(d[0] <= cx * C and cx * C + C <= d[0] + d[2] and d[1] <= cy * C and cy * C + C <= d[1] + d[3] for d in decks)
blocked = bytearray(W * W)
for cy in range(W):
    for cx in range(W):
        ch = g[cy // K][cx // K]
        if ch not in OPEN_CH or (ch == "#" and not on_deck(cx, cy)): blocked[cy * W + cx] = 1
for i in range(W):
    blocked[i] = blocked[(W - 1) * W + i] = blocked[i * W] = blocked[i * W + W - 1] = 1
props = []
for p in placement:
    n = p["name"]; bb = man[n]["bbox"]; box = p["box"]
    if box:
        for cy in range(max(0, box[1] // C), min(W, (box[1] + box[3] - 1) // C + 1)):
            for cx in range(max(0, box[0] // C), min(W, (box[0] + box[2] - 1) // C + 1)):
                blocked[cy * W + cx] = 1
    e = {"name": n, "x": p["x"], "y": p["y"], "foot": [p["size"][0] // 2, bb[3]], "box": box, "floor": p["floor"]}
    if p.get("deck"): e["deck"] = p["deck"]
    props.append(e)
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
cb = man[CHEST_SPRITE]["bbox"]; chest_half = man[CHEST_SPRITE]["size"] // 2
def chest_spot(home):
    """Nearest 8 px cell centre to the landmark where a hero fits, the cell's layout tile is open ground and the
    chest sprite (foot = this point) overlaps no blocking prop sprite."""
    hx, hy = home
    cand = sorted(((cx * C + C // 2, cy * C + C // 2) for cy in range((hy - 160) // C, (hy + 160) // C)
                   for cx in range((hx - 160) // C, (hx + 160) // C)), key=lambda q: (math.dist(q, home), q[1], q[0]))
    for x, y in cand:
        if not roomy(x // C, y // C) or g[y // T][x // T] not in ".=rs": continue
        r = (x - chest_half + cb[0], y - cb[3] + cb[1], x - chest_half + cb[2], y)
        if any(r[0] < s[2] and s[0] < r[2] and r[1] < s[3] and s[1] < r[3] for s in solid): continue
        return [x, y]
    sys.exit(f"no chest spot near {home}")
chests = []
for k in CHEST_IDS:
    home = lm[k]["at"]
    near = min(packs_l, key=lambda p: math.dist(p["at"], home))
    chests.append({"id": f"c{k}", "at": chest_spot(home), "kind": near["kind"], "level": near["level"]})

# ---- arena ---------------------------------------------------------------------------------------------------------
# make_layout.py: A = every non-forest cell within 9 cells (cell index distance) of cell (111, 13) = landmark 10.
# centre = that cell's centre; radius = farthest A-cell centre + half a cell, so in_arena(p) = |p - centre| <= radius
# holds on every A cell and fails one cell outside the disc.
A = [(x, y) for y in range(N) for x in range(N) if g[y][x] == "A"]
boss = next(p for p in L["packs"] if p.get("arena"))
centre = lm[10]["at"]
radius = round(max(math.dist((x * T + T // 2, y * T + T // 2), centre) for x, y in A)) + T // 2
ax0, ay0 = min(a[0] for a in A), min(a[1] for a in A); ax1, ay1 = max(a[0] for a in A), max(a[1] for a in A)
rect = [ax0 * T, ay0 * T, (ax1 - ax0 + 1) * T, (ay1 - ay0 + 1) * T]
# gate: walk the cheapest route start -> arena centre (path '=' cells cost 1, other open cells 2); from where it
# enters the arena walk back to the first cell wholly outside both the disc and the rect
s0 = (L["start"][0] // T, L["start"][1] // T); goal = (centre[0] // T, centre[1] // T)
dist, prev, heap = {s0: 0}, {}, [(0, s0[1], s0[0])]
while heap:
    d, y, x = heapq.heappop(heap)
    if (x, y) == goal: break
    if d > dist[(x, y)]: continue
    for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
        if not (0 <= n[0] < N and 0 <= n[1] < N) or g[n[1]][n[0]] not in OPEN_CH: continue
        nd = d + (1 if g[n[1]][n[0]] == "=" else 2)
        if nd < dist.get(n, 1 << 30): dist[n] = nd; prev[n] = (x, y); heapq.heappush(heap, (nd, n[1], n[0]))
route = [goal]
while route[-1] != s0: route.append(prev[route[-1]])
route.reverse()
def outside(c):
    px, py = c[0] * T + T // 2, c[1] * T + T // 2
    in_rect = rect[0] - T // 2 < px < rect[0] + rect[2] + T // 2 and rect[1] - T // 2 < py < rect[1] + rect[3] + T // 2
    return not in_rect and math.dist((px, py), centre) >= radius + T * math.sqrt(2) / 2
entry = next(i for i, c in enumerate(route) if g[c[1]][c[0]] == "A")
gate = next(c for c in reversed(route[:entry]) if outside(c))
arena = {"centre": centre, "radius": radius, "rect": rect, "gate": [gate[0] * T + T // 2, gate[1] * T + T // 2],
         "pack": {"kind": boss["kind"], "level": boss["level"], "count": boss["count"], "at": boss["at"],
                  "elite": bool(boss.get("elite"))}}

# ---- zones (layout_v1.json "zones", written by make_layout.py); name = first landmark inside with a level band ------
def in_rect(r, x, y): return r[0] <= x < r[0] + r[2] and r[1] <= y < r[1] + r[3]
LZ = L["zones"]
zones = []
for i, z in enumerate(LZ):
    mine = [l for l in L["landmarks"] if next(j for j, zz in enumerate(LZ) if in_rect(zz["rect"], *l["at"])) == i]
    pick = next((l for l in mine if l["levels"]), mine[0] if mine else None)
    zones.append({"name": pick["name"].split(" (")[0] if pick else f"z{i + 1}", "rect": z["rect"], "levels": z["levels"]})

world = {
    "_doc": "Baked by tools/bigmap/bake_world.py from data/bigmap/layout_v1.json - do not edit. "
            "ground[i]/flip[i]: cell i = y*128+x, atlas tile index and flip (0 none, 1 h, 2 v, 3 h+v); atlas tile n at "
            "((n % cols)*32, (n / cols)*32). "
            "walk: base64, 512x512 bits for 8 px cells, bit i = y*512+x is (byte i>>3 >> (i&7)) & 1, 1 = blocked. "
            "props: x, y = the sprite's foot point in px (bottom of its opaque bbox), foot = that pixel inside the "
            "sprite; box [x,y,w,h] collision or null; floor = draw flat under the y-sorted world (bridges, pads); "
            "deck = a bridge's walkable rect. chests: at = the chest sprite's foot point (bottom of its opaque bbox). "
            "packs: members must be placed on open, hero-roomy walk cells near at, never on raw ring points. "
            "arena: the fight area is the disc centre/radius (rect = its bounds only); rock surrounds the disc on "
            "every side, so the lock must be a ring barrier round the disc, not a door at the gate; gate = the "
            "approach-path cell just outside disc and rect; pack = the layout's boss pack (not in packs). "
            "zones: first match wins. Ids are frozen (saves use them): stones w1..w3, chests c4 c11 c12; "
            "the game keeps these id sets as constants and must not read them from this file.",
    "size": [N * T, N * T], "tile": T, "cell": C,
    "atlas": {"file": res_path(OUT_ATLAS), "cols": cols, "count": len(tiles)},
    "props_dir": res_path(PROPS),
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
      f"(boxes {sum(1 for p in props if p['box'])}, floor {sum(1 for p in props if p['floor'])}), packs {len(packs)}, "
      f"stones {len(stones)}, chests {[(c['id'], c['at'], c['kind'], c['level']) for c in chests]}, "
      f"arena {arena}, blocked {sum(blocked)}/{W * W}")
