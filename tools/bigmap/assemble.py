"""Paint the big-map layout with the PixelLab Wang tilesets (preview only, no Godot).

python3 -I assemble.py LAYOUT.json TILES_DIR OUT_DIR
TILES_DIR holds the extracted 128x128 / 128x256 sheets (t1..t8) and t5_meta.txt.
Writes OUT_DIR/bigmap_full.png (4096x4096) and OUT_DIR/bigmap_cells.json (tile choice per cell).
"""
import json, sys, random
from collections import Counter
from PIL import Image

LAYOUT, TILES, OUT = sys.argv[1:4]
L = json.load(open(LAYOUT))
N, T = len(L["grid"]), 32
GRASS, PATH, THICKET, WATER, ROCK, CLIFF, STONE, POND, ARENA = "grass path thicket water rock cliff stone pond arena".split()
CH = {"F": THICKET, ".": GRASS, "=": PATH, "~": WATER, "#": WATER, "^": CLIFF, "r": ROCK, "s": STONE,
      "o": POND, "A": ARENA, "C": STONE}
cell = [[CH[c] for c in row] for row in L["grid"]]
# visual clean-up (collision still comes from the layout grid): every pair that has no tileset
# gets a buffer terrain between, decided from the ORIGINAL cells so nothing chains along a path
orig = [row[:] for row in cell]
def near(x, y, kinds, r=2):
    return any(orig[yy][xx] in kinds for yy in range(max(0, y-r), min(N, y+r+1)) for xx in range(max(0, x-r), min(N, x+r+1)))
for y in range(N):
    for x in range(N):
        t = orig[y][x]
        if t == PATH:
            for f in (ROCK, STONE, ARENA):
                if near(x, y, {f}, 1): cell[y][x] = f; break
            else:
                if near(x, y, {THICKET, WATER, POND}, 2) or near(x, y, {ROCK, STONE, ARENA}, 3): cell[y][x] = GRASS
        elif t == THICKET and near(x, y, {WATER, POND}): cell[y][x] = GRASS
        elif t == THICKET and near(x, y, {CLIFF, ROCK, ARENA}, 2): cell[y][x] = ROCK
        elif t == THICKET and near(x, y, {CLIFF, ROCK, ARENA}, 4): cell[y][x] = GRASS
        elif t == CLIFF and near(x, y, {THICKET}, 1) and not near(x, y, {ROCK}, 1): cell[y][x] = CLIFF
        elif t == ARENA and near(x, y, {CLIFF, THICKET}): cell[y][x] = ROCK

# standard 16-tile layout: (x,y) -> corners NW NE SW SE, True = upper
STD = {}
for line in open(f"{TILES}/t1_meta.txt"):
    pos, cor = line.split(":")
    STD[tuple(c == "upper" for c in cor.split())] = tuple(int(v) for v in pos.split(","))
SETS = {  # (lower, upper): sheet file
    (PATH, GRASS): "t1_path_grass", (GRASS, THICKET): "t2_grass_thicket", (WATER, GRASS): "t3_stream_grass",
    (GRASS, ROCK): "t4_grass_rock", (GRASS, STONE): "t6_grass_temple", (ROCK, ARENA): "t7_rock_arena",
    (POND, GRASS): "t8_pond_grass",
}
sheets = {k: Image.open(f"{TILES}/{v}.png").convert("RGBA") for k, v in SETS.items()}
pair_of = {}
for lo, up in SETS: pair_of[frozenset((lo, up))] = (lo, up)
FULL = {}  # terrain -> (sheet key, pos)
for (lo, up) in SETS:
    FULL.setdefault(lo, ((lo, up), STD[(False,) * 4])); FULL.setdefault(up, ((lo, up), STD[(True,) * 4]))
FULL[GRASS] = ((PATH, GRASS), STD[(True,) * 4])
# optional full-tile variants (create_tiles_pro): file var_<terrain>.png (8 per row) + keep list
import os
VAR = {}
for terr, keep in ((STONE, [0, 1, 2, 3, 4, 6, 8, 10, 11, 12, 14, 15]), (ARENA, None)):
    f = f"{TILES}/var_{terr if terr != STONE else 'temple'}.png"
    if os.path.exists(f):
        vs = Image.open(f).convert("RGBA")
        n = (vs.width // T) * (vs.height // T)
        keep = keep if keep is not None else json.load(open(f[:-4] + "_keep.json")) if os.path.exists(f[:-4] + "_keep.json") else list(range(n))
        VAR[terr] = [vs.crop(((i % (vs.width // T)) * T, (i // (vs.width // T)) * T, (i % (vs.width // T)) * T + T, (i // (vs.width // T)) * T + T)) for i in keep]
VAR_RATE = 0.35
cliff_sheet = Image.open(f"{TILES}/t5_rock_cliff.png").convert("RGBA")
CLIFF_TILES = []
for line in open(f"{TILES}/t5_meta.txt"):
    pos, _, pat = [s.strip() for s in line.split("|")]
    CLIFF_TILES.append((tuple(int(v) for v in pos.split(",")), [[int(v) for v in r.split(",")] for r in pat.split(";")]))

PRIO = [WATER, POND, CLIFF, THICKET, STONE, ARENA, ROCK, PATH, GRASS]
def vert(vx, vy):
    seen = [cell[y][x] for y in (vy - 1, vy) for x in (vx - 1, vx) if 0 <= x < N and 0 <= y < N]
    return min(seen, key=PRIO.index)
V = [[vert(x, y) for x in range(N + 1)] for y in range(N + 1)]

# cliff vertices: 1 cliff, 0 other, 2 = transition (lower vertex directly south of a cliff vertex)
CV = [[1 if V[y][x] == CLIFF else 0 for x in range(N + 1)] for y in range(N + 1)]
for y in range(1, N + 1):
    for x in range(N + 1):
        if CV[y][x] == 0 and CV[y - 1][x] == 1: CV[y][x] = 2
def cv(y, x): return CV[y][x] if 0 <= y <= N and 0 <= x <= N else -1
def cliff_tile(cy, cx):
    best, bs = None, -10**9
    for pos, pat in CLIFF_TILES:
        s = 0
        for i in range(4):
            for j in range(4):
                want, have = pat[i][j], cv(cy - 1 + i, cx - 1 + j)
                if want == 255 or have == -1: continue
                centre = i in (1, 2) and j in (1, 2)
                s += (10 if centre else 1) if have == want else (-30 if centre else -1)
        if s > bs: bs, best = s, pos
    return best

out = Image.new("RGBA", (N * T, N * T))
choice, fallback = [], Counter()
for y in range(N):
    row = []
    for x in range(N):
        c = [V[y][x], V[y][x + 1], V[y + 1][x], V[y + 1][x + 1]]
        cc = [CV[y][x], CV[y][x + 1], CV[y + 1][x], CV[y + 1][x + 1]]
        if any(v in (1, 2) for v in cc) and all(t in (ROCK, CLIFF) for t in c):
            pos = cliff_tile(y, x)
            out.paste(cliff_sheet.crop((pos[0], pos[1], pos[0] + T, pos[1] + T)), (x * T, y * T))
            row.append(f"cliff:{pos[0]},{pos[1]}"); continue
        s = set(c)
        if len(s) > 2 or (len(s) == 2 and frozenset(s) not in pair_of):
            fallback[frozenset(s)] += 1
            cnt = Counter(c)
            keep = [t for t, _ in cnt.most_common()]
            a = keep[0]
            b = next((t for t in keep[1:] if frozenset((a, t)) in pair_of), None)
            if b is None and GRASS in pair_of and frozenset((a, GRASS)) in pair_of: b = GRASS
            c = [t if t in (a, b) else (b or a) for t in c]
            s = set(c)
        if len(s) == 1:
            key, pos = FULL[c[0]] if c[0] in FULL else FULL[GRASS]
            # free variety: mirror full tiles (stone bricks only left-right) so big areas don't repeat
            h = (x * 73856093 ^ y * 19349663) & 3
            img = sheets[key].crop((pos[0], pos[1], pos[0] + T, pos[1] + T))
            r = random.Random(x * 1009 + y * 7919)
            if c[0] in VAR and r.random() < VAR_RATE:
                k = r.randrange(len(VAR[c[0]]))
                out.paste(VAR[c[0]][k], (x * T, y * T)); row.append(f"var_{c[0]}:{k}"); continue
            if c[0] not in (GRASS, ROCK, THICKET): h = 0
            if h & 1: img = img.transpose(Image.FLIP_LEFT_RIGHT)
            if h & 2 and c[0] != STONE: img = img.transpose(Image.FLIP_TOP_BOTTOM)
            out.paste(img, (x * T, y * T)); row.append(f"{SETS[key]}:{pos[0]},{pos[1]}:f{h if c[0] != STONE else h & 1}"); continue
        else:
            lo, up = pair_of[frozenset(s)]
            key, pos = (lo, up), STD[tuple(t == up for t in c)]
        out.paste(sheets[key].crop((pos[0], pos[1], pos[0] + T, pos[1] + T)), (x * T, y * T))
        row.append(f"{SETS[key]}:{pos[0]},{pos[1]}")
    choice.append(row)
out.save(f"{OUT}/bigmap_full.png")
json.dump({"cells": choice}, open(f"{OUT}/bigmap_cells.json", "w"))
print("fallback cells:", sum(fallback.values()), {"/".join(sorted(k)): v for k, v in fallback.most_common(8)})
