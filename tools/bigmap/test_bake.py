"""Checks for the baked big map (data/bigmap/world.json + assets/map/bigmap/ground_atlas.png).

Run from the repo root:  python3 -I tools/bigmap/test_bake.py
Re-bakes into a temp dir and compares with the committed files (so they are up to date and the bake is
deterministic), then checks the committed data against the layout, the assembled ground and the props.
"""
import base64, json, math, os, re, subprocess, sys, tempfile
from collections import deque
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
HERE = os.path.join(ROOT, "tools", "bigmap")
LAYOUT = os.path.join(ROOT, "data", "bigmap", "layout_v1.json")
TILES = os.path.join(ROOT, "assets", "map", "bigmap", "tiles")
PROPS = os.path.join(ROOT, "assets", "map", "bigmap", "props")
WORLD = os.path.join(ROOT, "data", "bigmap", "world.json")
ATLAS = os.path.join(ROOT, "assets", "map", "bigmap", "ground_atlas.png")
T, C, N = 32, 8, 128
W = N * T // C  # walk cells per side (512)
OPEN_CH, BLOCK_CH = set(".=#rsAC"), set("F~^o")

fails, passes = [], 0
def check(cond, msg):
    global passes
    if cond: passes += 1
    else: fails.append(msg); print("FAIL", msg)

def run(script, *args):
    subprocess.run([sys.executable, "-I", os.path.join(HERE, script), *args], check=True, cwd=ROOT,
                   stdout=subprocess.DEVNULL)

# ---- committed files exist and match a fresh bake ----------------------------------------------------
if not (os.path.exists(WORLD) and os.path.exists(ATLAS)):
    print("FAIL world.json / ground_atlas.png missing (run bake_world.py)"); sys.exit(1)
def load(p): return json.load(open(p, encoding="utf-8"))
def pixels(p): im = Image.open(p).convert("RGBA"); return im.size, im.tobytes()
with tempfile.TemporaryDirectory(prefix="bake_test_") as tmp:
    # the temp atlas is outside the repo: the bake refuses to guess its res:// path, so pass the real one
    out = subprocess.run([sys.executable, "-I", os.path.join(HERE, "bake_world.py"), LAYOUT, TILES, PROPS, f"{tmp}/w.json", f"{tmp}/a.png"],
                         cwd=ROOT, capture_output=True, text=True)
    check(out.returncode != 0 and "outside the repo" in out.stderr, "bake refuses an output outside the repo without --atlas-res")
    run("bake_world.py", LAYOUT, TILES, PROPS, f"{tmp}/world.json", f"{tmp}/atlas.png",
        "--atlas-res", "res://assets/map/bigmap/ground_atlas.png")
    check(open(f"{tmp}/world.json", "rb").read() == open(WORLD, "rb").read(), "committed world.json == fresh bake (bytes)")
    check(pixels(f"{tmp}/atlas.png") == pixels(ATLAS), "committed ground_atlas.png == fresh bake (size + pixels)")
    run("assemble.py", LAYOUT, TILES, tmp)
    run("place_props.py", LAYOUT, PROPS, f"{tmp}/bigmap_full.png", tmp)
    full = Image.open(f"{tmp}/bigmap_full.png").convert("RGBA"); full.load()
    placement = load(f"{tmp}/props_placement.json")

L = load(LAYOUT); g = L["grid"]
w = load(WORLD)
man = load(f"{PROPS}/props_manifest.json")

# ---- header ------------------------------------------------------------------------------------------
check(w["size"] == [4096, 4096] and w["tile"] == T and w["cell"] == C, "size/tile/cell")
check(w["atlas"]["file"] == "res://assets/map/bigmap/ground_atlas.png", "atlas res path")
check(w["props_dir"] == "res://assets/map/bigmap/props", "props res path")
check(os.path.exists(os.path.join(TILES, ".gdignore")), "tile sheets folder hidden from Godot (.gdignore)")
doc = w["_doc"]
check(all(t in doc for t in ("w1..w3", "c4 c11 c12", "foot point", "ring barrier", "hero-roomy", "constants")),
      "_doc: frozen ids, foot points, ring barrier, pack members on roomy cells")

# ---- atlas + ground ----------------------------------------------------------------------------------
atlas = Image.open(ATLAS).convert("RGBA")
cols, count = w["atlas"]["cols"], w["atlas"]["count"]
check(atlas.width <= 1024 and atlas.height <= 1024, f"atlas <= 1024x1024 ({atlas.size})")
check(atlas.width == cols * T and atlas.height == math.ceil(count / cols) * T, "atlas size = cols x rows of 32")
check(len(w["ground"]) == N * N and len(w["flip"]) == N * N, "ground/flip have 128*128 entries")
check(all(0 <= i < count for i in w["ground"]), "every ground index < atlas tile count")
check(all(f in (0, 1, 2, 3) for f in w["flip"]), "flip values 0..3")
check(len(set(w["ground"])) == count, "every atlas tile is used")
tiles = [atlas.crop(((i % cols) * T, (i // cols) * T, (i % cols) * T + T, (i // cols) * T + T)) for i in range(count)]
check(len({t.tobytes() for t in tiles}) == count, "atlas tiles are unique")
FLIP = {0: lambda t: t, 1: lambda t: t.transpose(Image.FLIP_LEFT_RIGHT), 2: lambda t: t.transpose(Image.FLIP_TOP_BOTTOM),
        3: lambda t: t.transpose(Image.ROTATE_180)}
rebuilt = Image.new("RGBA", full.size)
for k in range(N * N):
    rebuilt.paste(FLIP[w["flip"][k]](tiles[w["ground"][k]]), ((k % N) * T, (k // N) * T))
check(rebuilt.tobytes() == full.tobytes(), "atlas + ground + flip rebuild bigmap_full.png pixel for pixel")

lm = {l["id"]: l["at"] for l in L["landmarks"]}
A = [(x, y) for y in range(N) for x in range(N) if g[y][x] == "A"]

# ---- walk grid -----------------------------------------------------------------------------------------
raw = base64.b64decode(w["walk"])
check(len(raw) == W * W // 8, "walk = 512*512 bits")
def blk(cx, cy): return cx < 0 or cy < 0 or cx >= W or cy >= W or bool(raw[(cy * W + cx) >> 3] >> ((cy * W + cx) & 7) & 1)
def blk_px(x, y): return blk(int(x) // C, int(y) // C)
def roomy(cx, cy): return all(not blk(cx + dx, cy + dy) for dx in (-1, 0, 1) for dy in (-2, -1, 0))
def centre(x, y): return (x * T + T // 2, y * T + T // 2)
check(not blk_px(*centre(57, 57)), "bridge cell (57,57) open")
# plan said (56,40) is water; in layout_v1 it is forest. Nearest water cell is (59,40). Both must block.
check(g[40][59] == "~" and blk_px(*centre(59, 40)), "water cell (59,40) blocked")
check(g[40][56] == "F" and blk_px(*centre(56, 40)), "forest cell (56,40) blocked")
sub = [(dx, dy) for dy in range(T // C) for dx in range(T // C)]
def cell_all(x, y, want_blocked):
    return all(blk(x * 4 + dx, y * 4 + dy) == want_blocked for dx, dy in sub)
check(all(cell_all(x, y, True) for y in range(N) for x in range(N) if g[y][x] in BLOCK_CH), "every F ~ ^ o cell blocked")
check(all(blk(i, 0) and blk(i, W - 1) and blk(0, i) and blk(W - 1, i) for i in range(W)), "map edge blocked")
open_cells = [(x, y) for y in range(N) for x in range(N) if g[y][x] in OPEN_CH]
some_prop_blocked = sum(1 for x, y in open_cells if not cell_all(x, y, False))
check(some_prop_blocked > 0, "props add blocked cells on open ground")

# ---- props ---------------------------------------------------------------------------------------------
def base_width(n):  # solid (alpha >= 128) x extent of the bottom 12 rows of the opaque bbox
    bb = man[n]["bbox"]; a = Image.open(f"{PROPS}/{n}.png").convert("RGBA").getchannel("A")
    xs = [x for y in range(bb[3] - 12, bb[3]) for x in range(bb[0], bb[2]) if a.getpixel((x, y)) >= 128]
    return max(xs) + 1 - min(xs)
P = w["props"]
check(len(P) == len(placement) and [p["name"] for p in P] == [q["name"] for q in placement], "props = placement list")
check(all((p["box"] is None) == (not q["blocks"]) for p, q in zip(P, placement)), "box iff prop blocks")
check(all(p["box"] is None for p in P if p["name"].startswith("bridge")), "bridges never block")
check(all(p["name"] != "chest_01" for p in P), "chest is not a prop")
check(all(p["rule"] == q["rule"] for p, q in zip(P, placement)) and {p["rule"] for p in P} == {"tree", "structure", "other", "floor"},
      "every prop carries its box rule (tree / structure / other / floor)")
check(all(p["rule"] == "structure" for p in P if p["name"].startswith(("chedi_", "prang_"))), "chedi and prang are structures")
box_ok = True
for p in P:
    b = p["box"]
    if b is None: continue
    n = p["name"]; bb = man[n]["bbox"]; bw = bb[2] - bb[0]
    rl = p["rule"]
    want = max(12, round(base_width(n) * 0.7) if rl == "structure" else round(bw / 4) if rl == "tree" else round(bw / 3))
    ok = rl != "floor" and b[2] == want and 8 <= b[3] <= (12 if rl == "tree" else 16)
    ok &= b[1] + b[3] == p["y"] and abs(b[0] + b[2] / 2 - p["x"]) <= bw / 2  # sits on the foot line, under the sprite
    for cy in range(b[1] // C, (b[1] + b[3] - 1) // C + 1):  # every walk cell under the box blocks
        for cx in range(b[0] // C, (b[0] + b[2] - 1) // C + 1):
            ok &= blk(cx, cy)
    if not ok: print("  bad box", p, "want w", want)
    box_ok &= ok
check(box_ok, "foot boxes: trees 1/4 bbox, structures 70% base, others 1/3 (min 12); 8..16 high; on the foot; cells blocked")
check(any(p["box"] for p in P if p["rule"] == "structure"), "structures present with boxes")
check(all(p["floor"] == (p["rule"] == "floor") for p in P), "floor flag = floor rule")
check(all(p["box"] is None for p in P if p["floor"]), "floor props never block")
check(all(p["floor"] for p in P if p["name"].startswith("bridge_")) and sum(p["name"].startswith("bridge_") for p in P) == 2,
      "both bridges are floor props")

# ---- water drawn on walkable ground blocks -----------------------------------------------------------------------
STD = {}
for line in open(os.path.join(TILES, "t1_meta.txt"), encoding="utf-8"):
    pos, cor = line.split(":"); STD[tuple(c == "upper" for c in cor.split())] = tuple(int(v) for v in pos.split(","))
def full_tile_colours(sheet, upper):
    im = Image.open(os.path.join(TILES, sheet + ".png")).convert("RGB"); x, y = STD[(upper,) * 4]
    return {im.getpixel((x + i, y + j)) for j in range(T) for i in range(T)}
land = full_tile_colours("t3_stream_grass", True) | full_tile_colours("t1_path_grass", True) | full_tile_colours("t1_path_grass", False)
check(not (full_tile_colours("t3_stream_grass", False) & land), "stream water colours never appear in full grass/path tiles")
water = (full_tile_colours("t3_stream_grass", False) | full_tile_colours("t8_pond_grass", False)) - land  # pond pads share greens
deck_rects = [p["deck"] for p in P if p.get("deck")]
def under_deck(cx, cy):
    return any(d[0] <= cx * C and cx * C + C <= d[0] + d[2] and d[1] <= cy * C and cy * C + C <= d[1] + d[3] for d in deck_rects)
rgb = full.convert("RGB").load()
wet_open = [(cx, cy) for cy in range(W) for cx in range(W) if g[cy // 4][cx // 4] in ".=" and not blk(cx, cy) and not under_deck(cx, cy)
            and sum(rgb[cx * C + i, cy * C + j] in water for j in range(C) for i in range(C)) * 2 > C * C]
check(not wet_open, f"no open . / = walk cell is mostly stream/pond pixels ({wet_open[:5]})")
for tx, ty in ((54, 59), (64, 91)):  # tiles the reviewer saw drawn as open water
    check(sum(blk(tx * 4 + dx, ty * 4 + dy) for dx, dy in sub) >= 12, f"water-drawn tile ({tx},{ty}) mostly blocked")

# ---- bridges: only the deck is walkable; each deck joins both banks --------------------------------------------
decks = [p["deck"] for p in P if p.get("deck")]
check(len(decks) == 2 and all("deck" not in p for p in P if not p["name"].startswith("bridge_")), "a deck on each bridge only")
for p in P:
    if not p.get("deck"): continue
    d, bb = p["deck"], man[p["name"]]["bbox"]
    left, top = p["x"] - p["foot"][0], p["y"] - p["foot"][1]
    check(left + bb[0] <= d[0] and d[0] + d[2] <= left + bb[2] and top + bb[1] <= d[1] and d[1] + d[3] <= top + bb[3],
          f"{p['name']} deck inside its opaque bbox")
def in_deck(cx, cy):
    return any(d[0] <= cx * C and cx * C + C <= d[0] + d[2] and d[1] <= cy * C and cy * C + C <= d[1] + d[3] for d in decks)
hash_open = [(cx, cy) for cy in range(W) for cx in range(W) if g[cy // 4][cx // 4] == "#" and not blk(cx, cy)]
check(len(hash_open) > 0 and all(in_deck(cx, cy) for cx, cy in hash_open), "every open cell on a # tile lies inside a bridge deck")
check(sum(1 for cy in range(W) for cx in range(W) if g[cy // 4][cx // 4] == "#" and blk(cx, cy)) > 0, "# cells off the deck block")
check(not blk_px(*centre(57, 57)), "bridge cell (57,57) open (on the wood deck)")
def flood(starts, ok):
    seen = set(starts); q = deque(starts)
    while q:
        x, y = q.popleft()
        for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if n not in seen and ok(*n): seen.add(n); q.append(n)
    return seen
for d in decks:
    hx = [cx for cy in range(d[1] // C, (d[1] + d[3]) // C) for cx in range(W) if g[cy // 4][cx // 4] == "#"]
    x0, x1 = min(hx), max(hx)  # walk-cell columns of the water under the deck
    wx0, wx1, wy0, wy1 = x0 - 8, x1 + 8, d[1] // C - 4, (d[1] + d[3]) // C + 4  # local window: no other crossing
    def ok(cx, cy): return wx0 <= cx <= wx1 and wy0 <= cy <= wy1 and roomy(cx, cy)
    west = [(cx, cy) for cy in range(wy0, wy1 + 1) for cx in range(wx0, x0) if ok(cx, cy)]
    east = [(cx, cy) for cy in range(wy0, wy1 + 1) for cx in range(x1 + 1, wx1 + 1) if ok(cx, cy)]
    check(west and east, f"deck {d}: both banks have room for a hero")
    check(bool(flood(west, ok) & set(east)), f"deck {d}: west bank -> east bank for a hero-sized body")
    check(bool(flood(east, ok) & set(west)), f"deck {d}: east bank -> west bank for a hero-sized body")
check(all(len(p["foot"]) == 2 for p in P), "props carry their sprite foot anchor")

# ---- points: start, stones, chests, packs ----------------------------------------------------------------
check(w["start"] == L["start"], "start = layout start")
st = w["stones"]
check([s["id"] for s in st] == ["w1", "w2", "w3"] and [s["at"] for s in st] == L["waypoints"], "3 stones w1..w3 = layout waypoints")
packs_l = [p for p in L["packs"] if not p.get("arena")]
pk = w["packs"]
check(len(pk) == 58 and len(packs_l) == 58, "58 packs (arena pack excluded)")
check(all(p["at"] != w["arena"]["pack"]["at"] for p in pk), "arena pack not in packs")
check([p["id"] for p in pk] == [f"p{i}" for i in range(58)], "pack ids p0..p57")
check(all(a["kind"] == b["kind"] and a["level"] == b["level"] and a["count"] == b["count"] and a["at"] == b["at"]
          and a["elite"] is bool(b.get("elite")) for a, b in zip(pk, packs_l)), "packs = layout (kind, level, count, at, elite)")
ch = w["chests"]
check([c["id"] for c in ch] == ["c4", "c11", "c12"], "3 chests c4 c11 c12")
for c in ch:
    home = lm[int(c["id"][1:])]
    near = min(packs_l, key=lambda p: math.dist(p["at"], home))
    check(c["kind"] == near["kind"] and c["level"] == near["level"], f"{c['id']} kind/level = nearest layout pack")
    check(math.dist(c["at"], home) <= 128, f"{c['id']} within 4 cells of landmark")
    cb, half = man["chest_01"]["bbox"], man["chest_01"]["size"] // 2
    r = (c["at"][0] - half + cb[0], c["at"][1] - cb[3] + cb[1], c["at"][0] - half + cb[2], c["at"][1])
    hidden = False
    for p in P:
        if p["box"] is None: continue
        bb = man[p["name"]]["bbox"]; left, top = p["x"] - p["foot"][0], p["y"] - p["foot"][1]
        hidden |= r[0] < left + bb[2] and left + bb[0] < r[2] and r[1] < top + bb[3] and top + bb[1] < r[3]
    check(not hidden, f"{c['id']} sprite overlaps no blocking prop sprite")
pts = [("start", w["start"])] + [(s["id"], s["at"]) for s in st] + [(c["id"], c["at"]) for c in ch] + [(p["id"], p["at"]) for p in pk]
# start, stones, chests: a hero stands right there. Pack points stay the layout's points (owner: packs exactly as the
# layout) and need not be open themselves: members go on hero-roomy cells round the point ("pack room" below).
# p35 has a bamboo trunk 2 cells above it; p10 is on a '#' tile just below the wood deck (water there).
for name, (x, y) in pts:
    if name.startswith("p"): continue
    check(not blk_px(x, y) and roomy(x // C, y // C), f"{name} open with room for a hero")

# ---- arena -------------------------------------------------------------------------------------------------
ax0, ay0 = min(a[0] for a in A), min(a[1] for a in A); ax1, ay1 = max(a[0] for a in A), max(a[1] for a in A)
check(w["arena"]["rect"] == [ax0 * T, ay0 * T, (ax1 - ax0 + 1) * T, (ay1 - ay0 + 1) * T], "arena rect = bbox of A cells")
ar = w["arena"]; ctr, rad, rect = ar["centre"], ar["radius"], ar["rect"]
check(ctr == lm[10], "arena centre = landmark 10")
def in_arena(x, y): return math.dist((x, y), ctr) <= rad
disc = {(x, y) for y in range(N) for x in range(N) if math.dist(centre(x, y), ctr) <= rad - T // 2}
check(set(A) == disc, "A cells = the disc (cell centres within radius - half a cell)")
check(all(in_arena(*centre(x, y)) for x, y in A) and in_arena(*ctr), "in_arena true on every A cell and the centre")
check(not in_arena(ctr[0], ctr[1] + rad + T) and not in_arena(ctr[0] - rad - T, ctr[1]), "in_arena false one cell outside the disc")
gx, gy = ar["gate"]
gcx, gcy = gx // T, gy // T
check(not in_arena(gx, gy) and math.dist((gx, gy), ctr) >= rad + T * math.sqrt(2) / 2, "gate cell wholly outside the disc")
check(not (rect[0] - T // 2 < gx < rect[0] + rect[2] + T // 2 and rect[1] - T // 2 < gy < rect[1] + rect[3] + T // 2),
      "gate cell wholly outside the arena rect")
check(g[gcy][gcx] == "=", "gate on the approach path")
check(math.dist((gx, gy), ctr) - rad <= 3 * T, "gate within 3 cells of the disc edge")
check(not blk_px(gx, gy) and roomy(gx // C, gy // C), "gate open with room for a hero")
entries = {(x + dx, y + dy) for x, y in A for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
           if g[y + dy][x + dx] in OPEN_CH and g[y + dy][x + dx] != "A"}
check(len(entries) >= 20 and all(g[y][x] in "r=" for x, y in entries), f"open rock rings the disc ({len(entries)} entry cells): lock = ring barrier")
boss = next(p for p in L["packs"] if p.get("arena"))
check(ar["pack"] == {"kind": boss["kind"], "level": boss["level"], "count": boss["count"], "at": boss["at"], "elite": True},
      "arena.pack = the layout's arena pack")

# ---- reachability for a hero-sized body (props must not cut routes) -----------------------------------------
s0 = (w["start"][0] // C, w["start"][1] // C)
seen = flood([s0], roomy)
for name, (x, y) in pts[1:] + [("gate", (gx, gy))]:
    if name.startswith("p"): continue  # packs: their home is checked below
    check((x // C, y // C) in seen, f"{name} reachable from start")
check(any((ax * 4 + 2, ay * 4 + 2) in seen for ax, ay in A), "arena floor reachable from start")

# ---- pack homes: a ring of count members at MonsterPiles.pile_radius(kind, n) = body / sin(PI / n) + 0.5 ---------
# (body = feet width x monster_scale) fits on reachable hero-roomy cells round home, at some rotation
feet = max(float(re.search(r'id="feet"\]\s*size = Vector2\(([\d.]+)', open(os.path.join(ROOT, "scenes", f), encoding="utf-8").read()).group(1))
           for f in ("wolf.tscn", "monster.tscn"))
body = feet * load(os.path.join(ROOT, "data", "balance.json"))["monster_scale"]
def ring_fits(c, n, steps=72):
    rr = body / math.sin(math.pi / n) + 0.5
    for k in range(steps):
        a0 = 2 * math.pi / n * k / steps
        if all(roomy(int(c[0] + rr * math.cos(a0 + 2 * math.pi * i / n)) // C, int(c[1] + rr * math.sin(a0 + 2 * math.pi * i / n)) // C)
               for i in range(n)): return True
    return False
def home_ok(c, n):
    cell = (int(c[0]) // C, int(c[1]) // C)
    return g[int(c[1]) // T][int(c[0]) // T] != "#" and cell in seen and roomy(*cell) and ring_fits(c, n)
for p in pk:
    h, n = p["home"], p["count"]
    check(g[h[1] // T][h[0] // T] != "#", f"{p['id']} home not on a bridge tile")
    check(math.dist(h, p["at"]) <= 64, f"{p['id']} home within 64 px of its layout point")
    check((h[0] // C, h[1] // C) in seen and roomy(h[0] // C, h[1] // C), f"{p['id']} home reachable, room for a body")
    check(ring_fits(h, n), f"{p['id']} a ring of {n} fits round home")
    check(h == p["at"] or not home_ok(p["at"], n), f"{p['id']} home moved only because its layout point does not fit")
shifted = {p["id"] for p in pk if p["home"] != p["at"]}
check({"p1", "p10", "p24", "p25", "p28", "p39", "p43", "p45", "p47", "p48", "p50", "p56"} <= shifted,
      f"the reviewer's 12 cramped packs got a shifted home ({sorted(shifted)})")
p10 = next(p for p in pk if p["id"] == "p10")
check(g[p10["home"][1] // T][p10["home"][0] // T] in ".=" and p10["home"][0] < 54 * T, "p10 home on the west bank")

# ---- zones -------------------------------------------------------------------------------------------------
Z = w["zones"]
check(len(Z) >= 1 and Z[-1]["rect"] == [0, 0, 4096, 4096], "zones end with a catch-all")
def zone_of(x, y):
    return next(z for z in Z if z["rect"][0] <= x < z["rect"][0] + z["rect"][2] and z["rect"][1] <= y < z["rect"][1] + z["rect"][3])
check(all(zone_of(*p["at"])["levels"][0] <= p["level"] <= zone_of(*p["at"])["levels"][1] for p in pk),
      "every pack level inside its zone's levels (first match)")
check(all(z["name"] for z in Z), "zones named")
check([(z["rect"], z["levels"]) for z in Z] == [(z["rect"], z["levels"]) for z in L["zones"]], "zones = layout zones")

print(f"\n{passes} passed, {len(fails)} failed")
sys.exit(1 if fails else 0)
