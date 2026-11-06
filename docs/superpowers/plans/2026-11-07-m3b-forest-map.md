# M3b Forest Map Implementation Plan

> **For agentic workers:** Implement this plan task-by-task, checking off each step. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the checker floor and wooden posts with a PixelLab forest that looks like the owner's first image: grass, dark forest floor, ponds with rock cliffs, a wide stone path, Y-sorted trees and props that block only at their feet, and the three wolf packs moved to the new layout.

**Architecture:** The map is data (`data/map_forest.json`): a 60×40 cell grid of terrain shapes, a prop list, pack homes and hero spawn. A pure `ForestLayout` turns the shapes into a corner grid, picks each cell's tileset and corner mask, and answers "is this point blocked". `ForestMap` (a Node2D) builds one TileMapLayer per tileset, one StaticBody2D for blocked water cells and the map border, and the props into the Y-sorted `World`. `test_ground.gd` uses it instead of `_draw()` and `POSTS`.

**Tech Stack:** Godot 4.5.1 GDScript, headless runner `tests/run_tests.gd`, xvfb screenshots. PixelLab: `create_tiles_pro` (tileset, 10 gen each), `create_map_object` (1 gen each), `vfx_workbench` (free).

**Spec:** `docs/superpowers/specs/2026-11-07-m3b-forest-map-design.md` (owner approved 2026-11-07), reference `docs/reference/forest_reference.png`, `docs/design-brief.md`, `docs/art-style.md`.

## Global Constraints
- Map 1920×1280 px, 32×32 grid (60×40 cells). Trees 96×128 and 64×64, props 32–64, structures 96–160. Y-sort with hero and wolves.
- Budget approved: estimate ~70 gen, hard stop at 110 gen for all of M3b. Before each generation, write the estimate; after it, log the real cost in `docs/pixellab-budget.md`. Generate the first tileset alone and confirm it can be saved into the repo before generating anything else.
- Ground tilesets: `create_tiles_pro`, `tile_feature: "tileset"`, 32 px, `tile_view: "top-down"`, `palette` taken from the reference image. Props: `create_map_object`, view "high top-down", style taken from the reference.
- Collision only at tree/rock/well/pillar feet, on water cells and on the map border. Grass, forest floor, stone, flowers and carpet are walkable.
- No numbers for combat or loot change. Pack level and count stay in `balance.json`; only positions move into the map file.
- Remove the "PLACEHOLDER floor/posts" label, `POSTS`, `_post()` and the checker `_draw()`.
- Thai report to owner; branch `m3b/forest-map` + PR; no merge without an order.

## Review Focus
1. The hero rolls or a lunging wolf is knocked toward the map edge or into a pond → stops at the border/water collider, never ends up outside the map or on water (Task 4: `test_border_and_water_stop_roll`).
2. A wolf dies at the pond's edge or beside a tree → no drop lands on a water cell or inside a prop footprint (Task 4: `test_drops_avoid_water_and_props`).
3. The hero walks around a tree: standing above its feet he is drawn behind the canopy, below its feet in front of it (Task 4: `test_tree_y_sort`).
4. A later layout edit puts the hero spawn or a pack home on water or inside a tree's feet → the layout check fails in tests, never at play time (Task 3: `test_layout_valid`).
5. One cell touching grass, stone and water at once (three terrains) has no tile in any set → the layout check rejects it (Task 3: `test_three_terrains_rejected`).

---

### Task 1: Ground tilesets (30 gen)

**Files:**
- Create: `tools/palette_from_image.py`, `data/style/forest_palette.json`
- Create: `assets/map/tiles/forest_floor.png`, `water.png`, `stone.png`, `assets/map/tiles/manifest.json`
- Modify: `docs/pixellab-budget.md`, `docs/art-style.md` (one line: map ground uses the forest palette)

**Interfaces:**
- Produces: `assets/map/tiles/manifest.json` = `{"<terrain>": {"file": "res://assets/map/tiles/<terrain>.png", "tile": 32, "masks": {"<mask 0-15>": [col, row]}}}` where the mask bit order is NW<<3 | NE<<2 | SW<<1 | SE and a set bit means that corner is the named terrain (grass otherwise). Mask 15 = full terrain, mask 0 = full grass.

- [ ] **Step 1:** `python3 tools/palette_from_image.py docs/reference/forest_reference.png 24 > data/style/forest_palette.json` (median-cut, drops near-duplicates; prints hex list). Check the list holds the reference's greens, cliff greys and water blues.
- [ ] **Step 2:** Log estimate (10 gen) and generate **grass → dark forest floor** only. Fetch the result and save PNG + per-tile corner data into the repo. If the image cannot be saved locally, stop and report before spending more.
- [ ] **Step 3:** Log estimate (20 gen) and generate **grass → water with dark rock cliff edge** and **grass → stone pavement**. Save both.
- [ ] **Step 4:** Write `manifest.json` from the corner data the tool returned (not by eye). Look at all three sheets next to the reference; one regeneration per set at most if a set is off-style (counted in the budget).
- [ ] **Step 5:** Log real cost. Commit `M3b Task 1: forest ground tilesets`.

### Task 2: Props (~19 gen)

**Files:**
- Create: `assets/map/props/<id>.png`, `assets/map/props/manifest.json`
- Modify: `docs/pixellab-budget.md`

**Interfaces:**
- Produces: `assets/map/props/manifest.json` = `{"<id>": {"file": "res://assets/map/props/<id>.png", "size": [w, h], "feet": [x, y], "foot": [w, h] | null, "flat": bool}}`. `feet` = pixel in the image that touches the ground (node origin); `foot` = blocking box centred on `feet` (null = no collider); `flat` props are drawn under everything (not Y-sorted).
- Ids: `tree_round_a`, `tree_round_b`, `tree_round_c` (96×128) · `bush_a`, `bush_b` (64×64) · `well_stone` (96×96) · `pillar_stone` (32×64) · `bridge_wood` (96×64, flat) · `stump_a`, `stump_b` · `rock_a`, `rock_b`, `rock_c` · `mushroom` · `flowers_a`, `flowers_b`, `flowers_c` (flat) · `flower_carpet_red` (64×64, flat).

- [ ] **Step 1:** Log estimate (19 gen). Generate each prop with `create_map_object`, high top-down, reference image as style. Save PNGs.
- [ ] **Step 2:** Fill `manifest.json`: `feet` at the bottom-centre of the trunk/base, `foot` = trunk/base width × ~1/3 of it (trees ~20×10, rocks ~28×12, well ~64×24, pillar ~20×10).
- [ ] **Step 3:** Review against the reference; regenerate failures (each 1 gen, counted).
- [ ] **Step 4:** Log real cost. Commit `M3b Task 2: forest props`.

### Task 3: Layout data and ForestLayout rules

**Files:**
- Create: `data/map_forest.json`, `scripts/map/forest_layout.gd`
- Modify: `data/balance.json` (remove `hero_spawn` and `packs[].at`; keep `packs[].level/count`, `map_size`)
- Test: `tests/test_forest_layout.gd`

**Interfaces:**
- Consumes: both manifests (Tasks 1–2).
- Produces: `data/map_forest.json` = `{"cells": [60, 40], "base": "grass", "terrain": [{"t": "forest_floor"|"water"|"stone", "rect": [x, y, w, h]} | {"t": ..., "ellipse": [cx, cy, rx, ry]}], "walk": [[x, y, w, h]], "props": [{"id": "...", "at": [px, py]}], "fx": [{"id": "water_ripple", "at": [px, py]}], "hero_spawn": [px, py], "pack_homes": [[px, py] ×3]}` — shapes in cell units, applied in order on the corner grid (61×41); `walk` rects clear water blocking (under the bridge).
- Produces: `ForestLayout.load(path := "res://data/map_forest.json") -> ForestLayout` · `corners() -> PackedStringArray` (61×41, row-major) · `cell(x: int, y: int) -> Dictionary` `{terrain: String, mask: int}` (terrain "grass" with mask 0 when all corners are grass) · `cell_blocked(x, y) -> bool` (≥2 water corners and not inside a `walk` rect) · `blocked_at(p: Vector2) -> bool` (blocked cell, outside the map, or inside a prop `foot` box) · `validate() -> Array[String]` (empty = ok).
- Layout intent (from the reference): forest-floor band 3 cells round the border and clumps under trees; stone path cells 28–31 running from y 3 to y 27, with a branch to each upper clearing; two ponds lower-left and lower-right joined by a stream at y ≈ 30 that the bridge crosses at x 28–31 (one grass cell between stone and water); pack homes = upper-left clearing (L1), upper-right clearing (L3), south of the stream (L5); hero spawn on the path at the map centre; border lined with big trees.

- [ ] **Step 1: Failing tests** `test_mask_bits` (a 2×2 water ellipse gives the expected masks on its four edge cells, NW<<3|NE<<2|SW<<1|SE) · `test_layout_valid` (`validate()` is empty: hero spawn and every pack home on an unblocked cell, clear of any `foot`; every prop inside the map; every terrain in the tiles manifest; every prop id in the props manifest) · `test_three_terrains_rejected` (a test layout with stone touching water → `validate()` names the cell) · `test_blocked_at` (pond centre true, path centre false, a tree's feet true, 1 px outside the map true, bridge middle false) · `test_three_packs_keep_balance` (homes count == `balance.packs` count).
- [ ] **Step 2: Run** `$G --headless --path . --script tests/run_tests.gd` → new tests fail.
- [ ] **Step 3: Implement** `forest_layout.gd` (pure, no scene access) and author `map_forest.json`.
- [ ] **Step 4: Run** → pass; existing 203 still pass except the ground tests that read the removed balance keys (fixed in Task 4 — note which).
- [ ] **Step 5: Commit** `M3b Task 3: forest layout data and rules`.

### Task 4: ForestMap builder and test ground

**Files:**
- Create: `scripts/map/forest_map.gd`
- Modify: `scripts/dev/test_ground.gd` (build `ForestMap`, spawn/pack homes from the layout, `_blocked` → `layout.blocked_at`, delete `POSTS`, `_post`, `_draw`, `GREENS`, the PLACEHOLDER label)
- Test: `tests/test_forest_map.gd`, `tests/test_ground.gd` (spawn expectation from the layout; `test_roll_stops_at_collider` uses a tree instead of a post)

**Interfaces:**
- Consumes: `ForestLayout` (Task 3), manifests (Tasks 1–2).
- Produces: `ForestMap.build(layout: ForestLayout, world: Node2D) -> void` — adds itself under `test_ground` below `World` with: one `TileMapLayer` per terrain (z_index -10, built from the manifest atlas, one tile per cell by mask), flat props (z_index -9), a `StaticBody2D` "Blockers" (layer 1) holding one rectangle per horizontal run of blocked cells plus four border walls; non-flat props go into `world` as `Node2D` at `at` with a `Sprite2D` offset so `feet` sits on the origin and, when `foot` is set, a `StaticBody2D` child (layer 1) with that box. `ForestMap.props -> Array[Node2D]`.

- [ ] **Step 1: Failing tests** `test_builds_layers_and_props` (3 TileMapLayers; cell at the pond centre uses the water set mask 15; prop count == layout props; flat props not under `world`) · `test_tree_y_sort` (tree node is a child of the Y-sorted `world`, `position` == its feet; hero above the feet has smaller y) · `test_hero_blocked_by_tree_feet` (hero walks into a tree for 1 s of physics frames and stops before the foot box) · `test_border_and_water_stop_roll` (roll toward the left border and into a pond: final position stays inside the map and on an unblocked cell) · `test_drops_avoid_water_and_props` (`LootDrop.scatter` beside the pond with the ground's `_blocked`, 200 seeded tries: no point where `blocked_at` is true) · `test_packs_spawn_walkable` (every wolf's spawn point is unblocked) · `test_no_placeholder_label`.
- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement** `forest_map.gd`, wire `test_ground.gd`.
- [ ] **Step 4: Run** → all pass.
- [ ] **Step 5: Commit** `M3b Task 4: forest map in the test ground`.

### Task 5: Pond ripple effect (0 gen)

**Files:**
- Create: `assets/fx/water_ripple.png`
- Modify: `assets/fx/manifest.json`, `scripts/map/forest_map.gd` (play looping fx from `layout.fx`)
- Test: `tests/test_forest_map.gd` (`test_fx_points_play`)

- [ ] **Step 1: Failing test** `test_fx_points_play` (one looping FxSprite per `fx` entry, at its point, `water_ripple` exists in the fx manifest).
- [ ] **Step 2:** Make the ripple in `vfx_workbench` (free), palette = forest palette water blues, export → horizontal strip + manifest entry (loop true).
- [ ] **Step 3: Implement**, run → pass. Commit `M3b Task 5: pond ripple`.

### Task 6: Screenshots, verification, PR

**Files:**
- Create: `tests/screenshots_m3b.gd`, `docs/screenshots/m3b_*.png`

- [ ] **Step 1:** `screenshots_m3b.gd` shoots: spawn on the path · upper-left pack clearing · pond with cliff and ripple · bridge over the stream · hero half behind a tree · a drop beside the pond · phone layout with `--touch`.
- [ ] **Step 2:** `xvfb-run -a $G --path . --rendering-driver opengl3 --script tests/screenshots_m3b.gd -- --touch`; look at every shot next to the reference.
- [ ] **Step 3:** Full run `$G --headless --path . --script tests/run_tests.gd` → `RESULT passed=N failed=0`; `xvfb-run … tests/touch_check.gd` → `TOUCH PASS`.
- [ ] **Step 4:** Budget table final total; PR (draft → ready) with group tags `[แผนที่]` `[พร็อพ]` `[ชน/Y-sort]` `[เครดิต]`, screenshots, real gen used; fresh reviewer on the whole branch; fix findings; report to the owner in Thai. No merge without an order.

## ทำจริงต่างจากแผน (บันทึก 2026-11-07)
- พื้นทั้ง 3 ชุดรวมเป็นรูปเดียว `assets/map/tiles/ground.png` (แถวละชุด) ใช้ TileMapLayer เดียวชื่อ Ground แทน 3 ชั้น · tile ของ PixelLab ตั้งบิตเมื่อมุมนั้นเป็น "หญ้า" จึงใช้ tile `mask ^ 15` (บันทึกใน manifest)
- tile ที่ได้มีกรอบเข้ม 1px + เส้นเงาด้านใน → `tools/import_tileset.py` สะท้อนแถบ 2px จากด้านในทับ และเปลี่ยนสีพื้นป่าเทาฟ้าเป็นเขียวมอส (ฟรี) · tile เต็มช่องพลิกตามตำแหน่งให้ลายซ้ำน้อยลง
- `ForestLayout.load` ชื่อ `open()` (load เป็นฟังก์ชันของ GDScript) · `walk` เป็นสี่เหลี่ยมหน่วย px (สะพานในภาพกว้าง 44 px · ทางเดินบนสะพาน 40 px)
- มุมที่ยื่นออกมามุมเดียว (ปลายวงรี) ถูกเกลี่ยกลับเป็นหญ้า เพื่อไม่ให้ขอบบ่อเป็นติ่ง
- เลย์เอาต์สร้างจาก `tools/gen_forest_layout.py` (ต้นไม้ 2 แถวรอบขอบ + กลุ่มต้นไม้บนพื้นป่าทึบ) · เพิ่มกฎ: พร็อพที่ตั้งได้ห้ามยืนในน้ำ
- พร็อพ: ดอกไม้ชุดที่ 3 เจน 2 ครั้งได้ภาพเกือบว่าง และพรมดอกแดงออกมาเป็นก้อนกลม → ไม่ใช้ทั้งคู่ · ใช้ gen รวม 49 (30 พื้น + 19 พร็อพ)
- หลังรีวิว: ช่องขอบน้ำที่น้ำอยู่ครึ่งเดียวกันเฉพาะครึ่งที่เป็นน้ำ (ฮีโร่หยุดตรงขอบที่เห็น) · ช่องที่น้ำแตะมุมเดียวเดินได้
- หลังรีวิว **[ปรับเอง]**: หมาป่าไถลไปตามโคนต้นไม้/ขอบน้ำแทนการหยุดนิ่ง · ไล่แล้วไม่คืบ 1.5 วินาที (ขยับไม่ถึง 8 px) → เลิกไล่ กลับบ้านเลือดเต็ม (กันยืนยิงข้ามน้ำฟรี) · เดินกลับบ้านแล้วติด → วาร์ปกลับบ้าน · ค่าอยู่ใน balance.json `wolf.stuck_time` / `wolf.stuck_distance`
- เทสต์เพิ่ม: หมาป่าเลิกไล่ข้ามน้ำ, หมาป่าที่ติดตอนกลับถึงบ้าน, collider ตรงกับ blocked_at ทุกจุดทุก 6 px ทั่วแผนที่
