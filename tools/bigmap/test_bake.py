"""Checks for the baked big map (data/bigmap/world.json + assets/map/bigmap/ground_atlas.png).

Run from the repo root:  python3 -I tools/bigmap/test_bake.py
Re-bakes into a temp dir and compares with the committed files (so they are up to date and the bake is
deterministic), then checks the committed data against the layout, the assembled ground and the props.
"""
import base64, json, math, os, subprocess, sys, tempfile
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
tmp = tempfile.mkdtemp(prefix="bake_test_")
run("bake_world.py", LAYOUT, TILES, PROPS, f"{tmp}/world.json", f"{tmp}/atlas.png")
check(open(f"{tmp}/world.json", "rb").read() == open(WORLD, "rb").read(), "committed world.json == fresh bake")
check(open(f"{tmp}/atlas.png", "rb").read() == open(ATLAS, "rb").read(), "committed ground_atlas.png == fresh bake")
run("assemble.py", LAYOUT, TILES, tmp)
run("place_props.py", LAYOUT, PROPS, f"{tmp}/bigmap_full.png", tmp)

L = json.load(open(LAYOUT)); g = L["grid"]
w = json.load(open(WORLD))
man = json.load(open(f"{PROPS}/props_manifest.json"))
placement = json.load(open(f"{tmp}/props_placement.json"))

# ---- header ------------------------------------------------------------------------------------------
check(w["size"] == [4096, 4096] and w["tile"] == T and w["cell"] == C, "size/tile/cell")
check(w["atlas"]["file"] == "res://assets/map/bigmap/ground_atlas.png", "atlas res path")

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
full = Image.open(f"{tmp}/bigmap_full.png").convert("RGBA")
rebuilt = Image.new("RGBA", full.size)
for k in range(N * N):
    rebuilt.paste(FLIP[w["flip"][k]](tiles[w["ground"][k]]), ((k % N) * T, (k // N) * T))
check(rebuilt.tobytes() == full.tobytes(), "atlas + ground + flip rebuild bigmap_full.png pixel for pixel")

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
check(all(cell_all(x, y, False) for y in range(N) for x in range(N) if g[y][x] == "#"), "every bridge (#) cell fully open")
check(all(blk(i, 0) and blk(i, W - 1) and blk(0, i) and blk(W - 1, i) for i in range(W)), "map edge blocked")
open_cells = [(x, y) for y in range(N) for x in range(N) if g[y][x] in OPEN_CH]
some_prop_blocked = sum(1 for x, y in open_cells if not cell_all(x, y, False))
check(some_prop_blocked > 0, "props add blocked cells on open ground")

# ---- props ---------------------------------------------------------------------------------------------
P = w["props"]
check(len(P) == len(placement) and [p["name"] for p in P] == [q["name"] for q in placement], "props = placement list")
check(all((p["box"] is None) == (not q["blocks"]) for p, q in zip(P, placement)), "box iff prop blocks")
check(all(p["box"] is None for p in P if p["name"].startswith("bridge")), "bridges never block")
check(all(p["name"] != "chest_01" for p in P), "chest is not a prop")
box_ok = True
for p in P:
    b = p["box"]
    if b is None: continue
    bb = man[p["name"]]["bbox"]; bw = bb[2] - bb[0]
    box_ok &= max(12, round(bw / 4)) - 1 <= b[2] <= max(12, round(bw / 3)) + 1 and 8 <= b[3] <= 16
    box_ok &= b[1] + b[3] == p["y"] and abs(b[0] + b[2] / 2 - p["x"]) <= bw / 2  # sits on the foot line
    for cy in range(b[1] // C, (b[1] + b[3] - 1) // C + 1):  # every walk cell under the box blocks (bridge decks stay open)
        for cx in range(b[0] // C, (b[0] + b[2] - 1) // C + 1):
            box_ok &= blk(cx, cy) or g[cy * C // T][cx * C // T] == "#"
check(box_ok, "foot boxes: width 1/4..1/3 bbox (min 12), height 8..16, on the foot, cells blocked")
check(all(len(p["foot"]) == 2 for p in P), "props carry their sprite foot anchor")

# ---- points: start, stones, chests, packs ----------------------------------------------------------------
check(w["start"] == L["start"], "start = layout start")
st = w["stones"]
check([s["id"] for s in st] == ["w1", "w2", "w3"] and [s["at"] for s in st] == L["waypoints"], "3 stones w1..w3 = layout waypoints")
packs_l = [p for p in L["packs"] if not p.get("arena")]
pk = w["packs"]
check(len(pk) == 58 and len(packs_l) == 58, "58 packs (arena pack excluded)")
check([p["id"] for p in pk] == [f"p{i}" for i in range(58)], "pack ids p0..p57")
check(all(a["kind"] == b["kind"] and a["level"] == b["level"] and a["count"] == b["count"] and a["at"] == b["at"]
          and a["elite"] is bool(b.get("elite")) for a, b in zip(pk, packs_l)), "packs = layout (kind, level, count, at, elite)")
lm = {l["id"]: l["at"] for l in L["landmarks"]}
ch = w["chests"]
check([c["id"] for c in ch] == ["c4", "c11", "c12"], "3 chests c4 c11 c12")
for c in ch:
    home = lm[int(c["id"][1:])]
    near = min(packs_l, key=lambda p: math.dist(p["at"], home))
    check(c["kind"] == near["kind"] and c["level"] == near["level"], f"{c['id']} kind/level = nearest layout pack")
    check(math.dist(c["at"], home) <= 128, f"{c['id']} within 4 cells of landmark")
pts = [("start", w["start"])] + [(s["id"], s["at"]) for s in st] + [(c["id"], c["at"]) for c in ch] + [(p["id"], p["at"]) for p in pk]
# start, stones, chests: a hero stands right there. Pack points only need to be open (as PaintedLayout.validate):
# members are spread round the point, and a themed prop (bamboo) may stand 2 walk cells above one (p35).
for name, (x, y) in pts:
    hero_here = not name.startswith("p")
    check(not blk_px(x, y) and (roomy(x // C, y // C) or not hero_here), f"{name} open" + (" with room for a hero" if hero_here else ""))

# ---- arena -------------------------------------------------------------------------------------------------
A = [(x, y) for y in range(N) for x in range(N) if g[y][x] == "A"]
ax0, ay0 = min(a[0] for a in A), min(a[1] for a in A); ax1, ay1 = max(a[0] for a in A), max(a[1] for a in A)
check(w["arena"]["rect"] == [ax0 * T, ay0 * T, (ax1 - ax0 + 1) * T, (ay1 - ay0 + 1) * T], "arena rect = bbox of A cells")
gx, gy = w["arena"]["gate"]
gcx, gcy = gx // T, gy // T
check(g[gcy][gcx] in OPEN_CH and g[gcy][gcx] != "A", "gate on an open non-arena cell")
check(any(g[gcy + dy][gcx + dx] == "A" for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))), "gate next to the arena")
check(not blk_px(gx, gy) and roomy(gx // C, gy // C), "gate open with room for a hero")

# ---- reachability for a hero-sized body (props must not cut routes) -----------------------------------------
s0 = (w["start"][0] // C, w["start"][1] // C)
seen = {s0}; q = deque([s0])
while q:
    x, y = q.popleft()
    for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
        if n not in seen and roomy(*n): seen.add(n); q.append(n)
for name, (x, y) in pts[1:] + [("gate", (gx, gy))]:
    check(any((x // C + dx, y // C + dy) in seen for dx in (-1, 0, 1) for dy in (-1, 0, 1)), f"{name} reachable from start")
check(any((ax * 4 + 2, ay * 4 + 2) in seen for ax, ay in A), "arena floor reachable from start")

# ---- zones -------------------------------------------------------------------------------------------------
Z = w["zones"]
check(len(Z) >= 1 and Z[-1]["rect"] == [0, 0, 4096, 4096], "zones end with a catch-all")
def zone_of(x, y):
    return next(z for z in Z if z["rect"][0] <= x < z["rect"][0] + z["rect"][2] and z["rect"][1] <= y < z["rect"][1] + z["rect"][3])
check(all(zone_of(*p["at"])["levels"][0] <= p["level"] <= zone_of(*p["at"])["levels"][1] for p in pk),
      "every pack level inside its zone's levels (first match)")
check(all(z["name"] for z in Z), "zones named")

print(f"\n{passes} passed, {len(fails)} failed")
sys.exit(1 if fails else 0)
