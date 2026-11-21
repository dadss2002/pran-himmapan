"""PRAN big-map layout draft (Claude-designed, 0 PixelLab gen).

World 4096x4096 px = 128x128 cells of 32 px. Writes:
  layout.json  - terrain grid + landmarks + waypoints + monster packs (design data)
  layout.png   - numbered review image (Thai legend)
Run: python3 -I make_layout.py OUT_DIR FONT_DIR
"""
import json, math, random, sys
from collections import deque
from PIL import Image, ImageDraw, ImageFont

OUT, FONTS = sys.argv[1], sys.argv[2]
N = 128          # cells per side
CELL = 32        # px per cell in game
rng = random.Random(20261121)

# terrain codes
FOREST, GRASS, PATH, WATER, BRIDGE, CLIFF, ROCK, STONE, POND, ARENA, CHEDI = range(11)
BLOCKED = {FOREST, WATER, CLIFF, POND, CHEDI}
COLORS = {
    FOREST: (34, 64, 38), GRASS: (104, 150, 72), PATH: (176, 146, 96), WATER: (64, 128, 190),
    BRIDGE: (150, 100, 56), CLIFF: (92, 84, 80), ROCK: (150, 140, 120), STONE: (186, 180, 160),
    POND: (52, 110, 150), ARENA: (170, 120, 90), CHEDI: (120, 112, 100),
}
g = [[FOREST] * N for _ in range(N)]

def inside(x, y): return 0 <= x < N and 0 <= y < N

def blob(cx, cy, r, code, keep=()):
    """Noisy round clearing."""
    ph = [rng.uniform(0, 6.28) for _ in range(3)]
    for y in range(int(cy - r * 1.4), int(cy + r * 1.4) + 1):
        for x in range(int(cx - r * 1.4), int(cx + r * 1.4) + 1):
            if not inside(x, y): continue
            a = math.atan2(y - cy, x - cx)
            rr = r * (1 + 0.16 * math.sin(3 * a + ph[0]) + 0.1 * math.sin(5 * a + ph[1]) + 0.06 * math.sin(7 * a + ph[2]))
            if math.hypot(x - cx, y - cy) <= rr and g[y][x] not in keep:
                g[y][x] = code

def spline(pts, step=0.25):
    """Catmull-Rom through pts, returns dense points."""
    out = []
    p = [pts[0]] + pts + [pts[-1]]
    for i in range(1, len(p) - 2):
        p0, p1, p2, p3 = p[i - 1], p[i], p[i + 1], p[i + 2]
        n = max(2, int(math.dist(p1, p2) / step))
        for k in range(n):
            t = k / n
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[j]) + (-p0[j] + p2[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2
                                  + (-p0[j] + 3 * p1[j] - 3 * p2[j] + p3[j]) * t3) for j in (0, 1)))
    out.append(pts[-1])
    return out

def stamp(line, w, code, wobble=0.0, only=None):
    ph = rng.uniform(0, 6.28)
    for i, (x, y) in enumerate(line):
        ww = w * (1 + wobble * math.sin(i * 0.05 + ph))
        for yy in range(int(y - ww) - 1, int(y + ww) + 2):
            for xx in range(int(x - ww) - 1, int(x + ww) + 2):
                if inside(xx, yy) and math.hypot(xx + 0.5 - x, yy + 0.5 - y) <= ww:
                    if only is None or g[yy][xx] in only:
                        g[yy][xx] = code

# ---- design (cells) -------------------------------------------------------
LM = {  # landmarks: id -> (x, y, Thai name, level band)
    1: (14, 110, "ศาลพรานต้นทาง (จุดเกิด + หินวาร์ป 1)", "Lv1"),
    2: (40, 90, "ทุ่งหญ้าชายป่า", "Lv1–2"),
    3: (34, 60, "วงเห็ดริมลำธาร", "Lv3–4"),
    4: (20, 24, "บ่อน้ำเก่าในดงลึก (ทางตัน มีหีบ)", "Lv4"),
    5: (57, 57, "สะพานไม้ข้ามลำธาร 1", ""),
    6: (79, 62, "ซากวัดร้าง + เจดีย์ (หินวาร์ป 2)", "Lv5–6"),
    7: (66, 89, "สะพานหิน 2 (ทางวน)", ""),
    8: (90, 92, "บึงสระบัว", "Lv6–7"),
    11: (70, 24, "ดงไผ่เหนือวัด (ทางตัน มีหีบ)", "Lv6"),
    12: (114, 78, "ซอกผาตะวันออก (ทางตัน มีหีบ)", "Lv7"),
    9: (98, 34, "เนินหินผาชัน (หินวาร์ป 3)", "Lv8–9"),
    10: (111, 13, "ลานบอส (ล็อกลาน)", "Lv10"),
}
WAYPOINTS = [(16, 107), (83, 66), (100, 38)]
STREAM = [(57, -2), (53, 20), (60, 40), (56, 58), (64, 76), (66, 92), (62, 108), (70, 130)]
MAIN = [(14, 110), (26, 104), (40, 90), (36, 76), (34, 60), (46, 56), (57, 57), (68, 60), (79, 62),
        (88, 52), (94, 42), (98, 34), (104, 26), (111, 13)]
SIDE_NW = [(34, 60), (28, 46), (24, 34), (20, 24)]
SIDE_N = [(79, 62), (78, 48), (72, 36), (70, 24)]
SIDE_E = [(96, 96), (106, 90), (114, 78)]
LOOP = [(40, 90), (54, 92), (66, 89), (80, 94), (96, 96), (94, 82), (86, 72), (79, 62)]

# rock highland in the NE: everything there that stays forest turns to cliff
def in_highland(x, y): return x > 78 and y < 52 and (x - 78) + (52 - y) > 18

# clearings
blob(14, 110, 10, GRASS); blob(40, 90, 14, GRASS); blob(34, 60, 12, GRASS); blob(20, 24, 9, GRASS)
blob(79, 62, 16, GRASS); blob(97, 96, 15, GRASS); blob(98, 34, 11, GRASS); blob(111, 13, 12, GRASS)
blob(70, 24, 10, GRASS); blob(114, 78, 8, GRASS); blob(92, 22, 7, GRASS)
blob(52, 106, 8, GRASS); blob(24, 80, 8, GRASS); blob(12, 66, 6, GRASS); blob(30, 40, 6, GRASS)
blob(110, 112, 8, GRASS); blob(104, 108, 5, GRASS)   # side pockets
# corridors (walkable band, then a dirt path in the middle)
for line, w in ((MAIN, 4.6), (SIDE_NW, 3.4), (LOOP, 4.0), (SIDE_N, 3.4), (SIDE_E, 3.2), ([(12, 66), (24, 80), (40, 90)], 3.0), ([(97, 96), (110, 112)], 3.2)):
    sp = spline(line)
    stamp(sp, w, GRASS, wobble=0.35)
for line, w in ((MAIN, 1.3), (SIDE_NW, 0.9), (LOOP, 1.1), (SIDE_N, 0.9), (SIDE_E, 0.9)):
    stamp(spline(line), w, PATH, only={GRASS})
# highland: floor becomes rock, forest border becomes cliff
for y in range(N):
    for x in range(N):
        if in_highland(x, y):
            g[y][x] = CLIFF if g[y][x] == FOREST else (ROCK if g[y][x] == GRASS else g[y][x])
# temple ruins: stone floor + chedi + pillar stumps
for y in range(55, 70):
    for x in range(72, 88):
        if g[y][x] in (GRASS, PATH) and rng.random() > 0.08: g[y][x] = STONE
for y in range(58, 61):
    for x in range(80, 83): g[y][x] = CHEDI
for (x, y) in ((74, 57), (86, 57), (74, 67), (86, 67), (77, 64)): g[y][x] = CHEDI
# lotus pond
blob(100, 100, 6, POND)
# boss arena floor
for y in range(N):
    for x in range(N):
        if math.hypot(x - 111, y - 13) <= 9 and g[y][x] != FOREST: g[y][x] = ARENA
# stream last (cuts everything), bridges where the routes cross it
stream = spline(STREAM)
stamp(stream, 1.7, WATER, wobble=0.25)
for bx, by in ((57, 57), (66, 89)):
    for y in range(by - 2, by + 3):
        for x in range(bx - 4, bx + 5):
            if g[y][x] == WATER: g[y][x] = BRIDGE
# map edge: solid forest / cliff ring 3 cells
for y in range(N):
    for x in range(N):
        if x < 3 or y < 3 or x >= N - 3 or y >= N - 3:
            g[y][x] = CLIFF if in_highland(x, y) else FOREST

# ---- checks ---------------------------------------------------------------
def walk(x, y): return inside(x, y) and g[y][x] not in BLOCKED
def bfs(sx, sy):
    seen = {(sx, sy)}; q = deque([(sx, sy)])
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (x + dx, y + dy)
            if n not in seen and walk(*n): seen.add(n); q.append(n)
    return seen
reach = bfs(14, 110)
problems = [f"landmark {k} unreachable" for k, (x, y, *_ ) in LM.items() if (x, y) not in reach and walk(x, y)]
problems += [f"landmark {k} blocked" for k, (x, y, *_ ) in LM.items() if not walk(x, y) and k not in ()]
problems += [f"waypoint {i+1} unreachable" for i, (x, y) in enumerate(WAYPOINTS) if (x, y) not in reach]
walkable = sum(1 for y in range(N) for x in range(N) if walk(x, y))
unreached = walkable - len(reach)

# ---- monster packs: along the routes, level by zone ------------------------
ZONES = [  # (test(x,y), kinds, level range)
    (lambda x, y: x < 60 and y > 76, ["deer", "boar", "wolf"], (1, 2)),
    (lambda x, y: x < 56 and y <= 76, ["wolf", "shroom", "macaque"], (3, 4)),
    (lambda x, y: 56 <= x < 92 and 50 <= y < 76, ["macaque", "boar", "wolf"], (5, 6)),
    (lambda x, y: y >= 76 and x < 82, ["macaque", "shroom", "boar"], (5, 6)),
    (lambda x, y: y >= 76, ["viper", "shroom", "macaque"], (6, 7)),
    (lambda x, y: x < 82 and y < 50, ["macaque", "viper", "boar"], (6, 6)),
    (lambda x, y: True, ["kongkoi", "viper", "wolf"], (8, 9)),
]
packs = []
safe = [(14, 110), (83, 66), (100, 38)]
pts = spline(MAIN) + spline(SIDE_NW) + spline(LOOP) + spline(SIDE_N) + spline(SIDE_E)
cand = list(pts[::6])
for cx0, cy0, r0 in ((40, 90, 12), (34, 60, 10), (79, 62, 14), (97, 96, 13), (98, 34, 9), (20, 24, 7), (70, 24, 8),
                     (114, 78, 6), (24, 80, 6), (52, 106, 6), (110, 112, 6), (12, 66, 4), (30, 40, 4), (92, 22, 5)):
    for _ in range(16):
        a, rr = rng.uniform(0, 6.28), rng.uniform(0, r0)
        cand.append((cx0 + rr * math.cos(a), cy0 + rr * math.sin(a)))
for i, (x, y) in enumerate(cand):
    cx, cy = int(x + rng.uniform(-3, 3)), int(y + rng.uniform(-3, 3))
    if not walk(cx, cy) or (cx, cy) not in reach: continue
    if any(math.hypot(cx - sx, cy - sy) < 9 for sx, sy in safe): continue
    if math.hypot(cx - 111, cy - 13) < 12: continue
    if any(math.hypot(cx - p["at"][0] / CELL, cy - p["at"][1] / CELL) < 7.2 for p in packs): continue
    for test, kinds, (lo, hi) in ZONES:
        if test(cx, cy):
            packs.append({"kind": rng.choice(kinds), "level": rng.randint(lo, hi), "count": rng.randint(4, 6),
                          "at": [cx * CELL + 16, cy * CELL + 16]})
            break
packs.append({"kind": "kongkoi", "level": 10, "count": 6, "at": [111 * CELL, 13 * CELL], "arena": True, "elite": 1})

# ---- write data -----------------------------------------------------------
CH = "F.=~#^rsoAC"  # one char per code
data = {
    "_doc": "Claude-designed big-map layout draft 2026-11-21 (owner: แผนที่ใหญ่ระดับ PoE 4096x4096, ผังโดย Claude, ภาพองค์ประกอบจาก PixelLab). 0 gen.",
    "size": [N * CELL, N * CELL], "cell": CELL, "legend": {c: n for c, n in zip(CH, ["forest", "grass", "path", "water", "bridge", "cliff", "rock", "stone", "pond", "arena", "chedi"])},
    "grid": ["".join(CH[g[y][x]] for x in range(N)) for y in range(N)],
    "start": [14 * CELL + 16, 110 * CELL + 16],
    "waypoints": [[x * CELL + 16, y * CELL + 16] for x, y in WAYPOINTS],
    "landmarks": [{"id": k, "at": [x * CELL + 16, y * CELL + 16], "name": n, "levels": lv} for k, (x, y, n, lv) in LM.items()],
    "packs": packs,
}
json.dump(data, open(f"{OUT}/layout.json", "w"), ensure_ascii=False, indent=1)

# ---- review image ---------------------------------------------------------
S = 8  # preview px per cell -> 1024x1024 map
PANEL = 470
img = Image.new("RGB", (N * S + PANEL, N * S), (24, 24, 28))
d = ImageDraw.Draw(img)
for y in range(N):
    for x in range(N):
        c = COLORS[g[y][x]]
        if g[y][x] == FOREST and (x * 7 + y * 13) % 5 == 0: c = (28, 54, 32)
        d.rectangle([x * S, y * S, x * S + S - 1, y * S + S - 1], fill=c)
f_big = ImageFont.truetype(f"{FONTS}/Kanit-SemiBold.ttf", 22)
f = ImageFont.truetype(f"{FONTS}/Kanit-Regular.ttf", 17)
f_s = ImageFont.truetype(f"{FONTS}/Kanit-Regular.ttf", 13)
# packs
for p in packs:
    x, y = p["at"][0] / CELL * S, p["at"][1] / CELL * S
    col = (230, 60, 60) if p.get("arena") else (250, 210, 90)
    d.ellipse([x - 5, y - 5, x + 5, y + 5], fill=col, outline=(0, 0, 0))
    d.text((x + 6, y - 9), str(p["level"]), font=f_s, fill=(255, 255, 255), stroke_width=2, stroke_fill=(0, 0, 0))
# waypoints
for i, (x, y) in enumerate(WAYPOINTS):
    X, Y = x * S + 4, y * S + 4
    d.polygon([(X, Y - 9), (X + 7, Y), (X, Y + 9), (X - 7, Y)], fill=(120, 220, 255), outline=(0, 0, 0))
# landmarks: numbered red circles
for k, (x, y, n, lv) in LM.items():
    X, Y = x * S + 4, y * S + 4
    d.ellipse([X - 15, Y - 15, X + 15, Y + 15], outline=(235, 30, 30), width=3)
    d.ellipse([X + 8, Y - 26, X + 30, Y - 4], fill=(235, 30, 30))
    d.text((X + 19, Y - 15), str(k), font=f_s, fill=(255, 255, 255), anchor="mm")
# scale references: one game screen 640x360 and one old room 512x512
d.rectangle([8 * S, 4 * S, 8 * S + 20 * S, 4 * S + int(11.25 * S)], outline=(255, 255, 255), width=2)
d.text((8 * S + 3, 4 * S + int(11.25 * S) + 2), "1 จอเกม", font=f_s, fill=(255, 255, 255), stroke_width=2, stroke_fill=(0, 0, 0))
d.rectangle([32 * S, 4 * S, 48 * S, 20 * S], outline=(255, 160, 255), width=2)
d.text((32 * S + 3, 20 * S + 2), "ห้องเดิม 1 ห้อง", font=f_s, fill=(255, 160, 255), stroke_width=2, stroke_fill=(0, 0, 0))
# panel
px = N * S + 16; yy = 14
d.text((px, yy), "PRAN แผนที่ใหญ่ — ผังร่างโดย Claude", font=f_big, fill=(255, 255, 255)); yy += 34
d.text((px, yy), "4096×4096 px · 128×128 ช่อง 32 px · 0 gen", font=f, fill=(200, 200, 200)); yy += 30
for k, (x, y, n, lv) in sorted(LM.items()):
    d.ellipse([px, yy + 2, px + 20, yy + 22], fill=(235, 30, 30))
    d.text((px + 10, yy + 12), str(k), font=f_s, fill=(255, 255, 255), anchor="mm")
    txt = n + (f"  [{lv}]" if lv else "")
    d.text((px + 28, yy), txt, font=f, fill=(255, 255, 255)); yy += 27
yy += 8
for code, name in ((GRASS, "หญ้า (เดินได้)"), (PATH, "ทางดิน"), (FOREST, "ดงไม้ทึบ (กำแพง)"), (WATER, "ลำธาร"), (BRIDGE, "สะพาน"),
                   (CLIFF, "หน้าผา (กำแพง)"), (ROCK, "พื้นหินบนเนิน"), (STONE, "ลานหินวัดร้าง"), (CHEDI, "เจดีย์/เสา (กำแพง)"),
                   (POND, "สระบัว"), (ARENA, "ลานบอส")):
    d.rectangle([px, yy + 3, px + 18, yy + 19], fill=COLORS[code], outline=(0, 0, 0)); d.text((px + 28, yy), name, font=f, fill=(230, 230, 230)); yy += 24
yy += 6
d.ellipse([px + 4, yy + 6, px + 14, yy + 16], fill=(250, 210, 90), outline=(0, 0, 0)); d.text((px + 28, yy), f"ฝูงมอน (เลขคือเลเวล) {len(packs)-1} ฝูง", font=f, fill=(230, 230, 230)); yy += 24
d.ellipse([px + 4, yy + 6, px + 14, yy + 16], fill=(230, 60, 60), outline=(0, 0, 0)); d.text((px + 28, yy), "ลานบอส (มอนหัวหน้า Lv10 จนกว่าจะมีสมิง)", font=f, fill=(230, 230, 230)); yy += 24
X, Y = px + 9, yy + 11
d.polygon([(X, Y - 9), (X + 7, Y), (X, Y + 9), (X - 7, Y)], fill=(120, 220, 255), outline=(0, 0, 0)); d.text((px + 28, yy), "หินวาร์ป 3 จุด", font=f, fill=(230, 230, 230)); yy += 32
d.text((px, yy), "เส้นทาง: 1→2→3→5→6→9→10\nทางวน: 2→7→8→6 · ทางตัน: 3→4, 6→11, 8→12", font=f, fill=(255, 230, 150)); yy += 56
d.text((px, yy), f"ตรวจ: เดินถึงทุกจุด {'ผ่าน' if not problems else 'ไม่ผ่าน'}\nช่องเดินได้ {walkable} · เข้าไม่ถึง {unreached}", font=f, fill=(150, 255, 150) if not problems else (255, 120, 120))
img.save(f"{OUT}/layout.png")
print("problems:", problems, "walkable:", walkable, "unreached:", unreached, "packs:", len(packs))
