# แผนที่ใหญ่ในเกม — Implementation Plan

> **For agentic workers:** Implement this plan task-by-task, checking off each step. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 16 room-and-warp forest with the one 4096×4096 map Claude laid out (PixelLab tiles + props), keeping hero level/items/gems.

**Architecture:** Offline tools bake everything the game needs into `data/bigmap/world.json` + one ground atlas PNG. In the game a pure-rules `BigWorld` reads it (walk grid, packs, stones, chests, arena); a `BigMapScene` draws ground as a `TileMapLayer` and props as Y-sorted `Sprite2D`s with foot boxes. Monster packs stream in and out around the hero and keep their state (RoomReset rules: dead stay dead until a waypoint trip or a new game). The old room code stays in the repo, unused by the main scene.

**Tech Stack:** Godot 4.5.1 GDScript, Python 3 + Pillow tools, headless tests (`tests/run_tests.gd`), xvfb screenshots.

**Spec:** `docs/superpowers/specs/2026-11-21-big-map-design.md` (layout, owner answers, in-game rules), `data/bigmap/layout_v1.json`.

## Global Constraints
- Map 4096×4096 px, grid 128×128 of 32 px; walk grid 8 px cells (512×512) like `PaintedLayout`.
- Owner rules (2026-11-21): dead monsters return only on waypoint travel or a new game · packs exactly as `layout_v1.json` (kind, count, level) with members placed at random round the pack point each build · boss arena = existing e0 behaviour, sets from `RoomLevels`, level = zone before + 1 (Lv10) · chests at landmarks 4, 11, 12: `Loot.roll(kind, level, rng, true)` ×3, kind/level = the nearest pack in the layout, **once per save**, chest vanishes with an existing sparkle.
- New game / load = hero at the start (`layout.start`), fog all dark, waypoint 1 unlocked; level, bag, gems, gear, skills kept.
- No new game numbers beyond the spec. Every ⚙ constant cites the spec line.
- Save v5; v4 loads (old room waypoints dropped). Never load a newer version than the game knows (B15).
- Cheat checks in the save: waypoint ids ⊂ {w1,w2,w3}; chest ids ⊂ {c4,c11,c12}, no duplicates; signature as v4. These id sets are **constants in code**, never read from world.json (a modded build could widen them); a test checks world.json ids equal the constants.
- Bridges and other `floor: true` props are drawn on a layer under the y-sorted world; pack members are placed on open, hero-roomy cells near the pack point, never on raw ring points.
- Mobile: one `TileMapLayer`, props culled by `VisibleOnScreenNotifier2D`/`PerfSaver`; no 4096² texture.
- Tests headless; don't claim pass without running `godot --headless -s tests/run_tests.gd`.

## Review Focus
1. Hero walks over a bridge — the bridge cells are water in the terrain but must be walkable (walk grid from layout `#` = open).
2. Hero stands where a pack streams in — packs never spawn on screen or inside 3 cells of the hero (spawn ring outside the view).
3. Loading a v4 save with room waypoint ids (`c1r1`, `c0r2`…) — must load, ids dropped, w1 unlocked, nothing else lost.
4. Chest opened, then waypoint trip or reload — stays gone (once per save); a save with `chests: ["c4","c4","x"]` is rejected as tampered.
5. Boss arena fight then waypoint away mid-fight — arena unlocks, pack re-rolls, no stuck lock.

---

### Task 1: Bake world data and ground atlas

**Files:**
- Create: `tools/bigmap/bake_world.py`, `data/bigmap/world.json`, `assets/map/bigmap/ground_atlas.png`
- Modify: `tools/bigmap/assemble.py` (also write per-cell tile key; no behaviour change), `tools/bigmap/place_props.py` (foot box per prop)
- Test: `tools/bigmap/test_bake.py` (python, run directly)

**Interfaces — Produces** `world.json`:
`{"size":[4096,4096], "tile":32, "cell":8, "atlas":{"file":"res://assets/map/bigmap/ground_atlas.png","cols":N}, "ground":[128*128 atlas indices, row-major], "flip":[128*128 0..3], "walk":"<base64 bits 512*512, 1 = blocked>", "props":[{"name","x","y","box":[x,y,w,h] or null}], "start":[x,y], "stones":[{"id":"w1","at":[x,y]}...], "chests":[{"id":"c4","at":[x,y],"kind","level"}...], "packs":[{"id":"p0","kind","level","count","at":[x,y],"elite":bool}...], "arena":{"rect":[x,y,w,h],"gate":[x,y]}, "zones":[{"name","rect","levels"}]}`

- [ ] Write `test_bake.py`: atlas ≤ 1024×1024; every ground index < atlas tile count; walk bit at a bridge cell (57,57)*32 is open and at a water cell (56,40)*32 blocked; start/stones/chests/pack points open; 58 packs; 3 stones; 3 chests whose kind/level equal the nearest pack.
- [ ] Run it: fails (no file).
- [ ] Implement `bake_world.py LAYOUT TILES PROPS OUT_JSON OUT_ATLAS`: dedupe 32 px tiles from the assembler's output into an atlas (flips as flags, not new tiles); walk grid = blocked for F ~ ^ o and grid edge, open for . = # r s A C, then props with `blocks` add a foot box (bottom 1/4 of bbox width × 8–16 px); stones = layout waypoints `w1..w3`; chests = landmarks 4/11/12; arena rect = bbox of `A` cells, gate = path cell entering it.
- [ ] Run test: PASS. Commit.

### Task 2: `BigWorld` rules (pure)

**Files:** Create `scripts/rules/big_world.gd`; Test: `tests/run_tests.gd` (new `test_big_world_*`)

**Interfaces — Produces:**
- `static func open(path := "res://data/bigmap/world.json") -> BigWorld`
- `func blocked_at(p: Vector2) -> bool` · `func make_nav() -> AStarGrid2D` (8 px cells, same as `PaintedLayout.make_nav`)
- `func packs_near(p: Vector2, r: float) -> Array[String]` · `func pack(id) -> Dictionary`
- `func zone_level(p: Vector2) -> int` (level of the nearest pack; for HUD and arena "zone before")
- `func in_arena(p: Vector2) -> bool`
- Also act as the `layout` the hero/monsters already take (`blocked_at`, `size_px()`).

- [ ] Tests: `blocked_at` matches Task 1 cases; nav path start→boss gate exists; `packs_near(start, 500)` returns only packs of level ≤ 2; `zone_level` near the arena gate = the level of the nearest layout pack (read it from world.json, not a literal); `in_arena` follows `arena.centre`/`radius` (true at the centre, false at the gate and one cell outside the disc).
- [ ] Implement; run tests; commit.

### Task 3: Big map scene (ground, props, hero, camera)

**Files:** Create `scripts/map/big_map.gd` (Node2D), Modify `scripts/dev/test_ground.gd` (a `use_big_map := true` path in `build()` that skips RoomSet/warps), Test: `tests/screenshots_bigmap.gd`

**Interfaces — Consumes:** `BigWorld`. **Produces:** `BigMap.build(w: BigWorld) -> void`, `BigMap.ground: TileMapLayer`, props under the y-sorted `world` node.

- [x] Test (headless, `tests/test_big_map.gd`): after `build()`, hero at `world.start`, `ground.get_used_cells().size() == 16384`, blocker count == props with a box; hero cannot walk into water at (56,40). *(Done: colliders = merged walk-grid cells only, checked cell for cell; prop boxes are inside blocked cells so they get no extra colliders — ai-decisions แผนที่-5. Water at (59,40) + off the bridge deck; bridge crossed east→west.)*
- [x] Implement: TileSet from atlas (32 px, flips via alternative tiles), one TileMapLayer z below world; `floor: true` props (bridges, pads) on a layer under the y-sorted world; terrain colliders (water/forest/cliff/rock cells) from the walk grid by reusing PaintedMap's rect merge (pull `_build_blockers` into a static helper taking a WalkGrid; ~494 rects); build `make_nav()` exactly once; commit the `.import` files for the atlas and bigmap props; props as Sprite2D offset so the foot sits on `(x,y)`; StaticBody2D boxes from `box`; camera limits 0..4096.
- [x] Screenshot `docs/preview/bigmap/game_start.png` (xvfb, opengl3) + `game_bridge.png` (+ `game_temple.png`, `game_arena.png`; `tests/screenshots_bigmap.gd` also checks the ground pixel for pixel and canvas culling). Commit.

### Task 4: Pack streaming with kept state

**Files:** Create `scripts/rules/pack_stream.gd`; Modify `test_ground.gd`; Test: run_tests

**Interfaces — Produces:** `PackStream.new(world: BigWorld, seed: int)`, `func step(hero: Vector2, view: Rect2) -> Dictionary` returns `{"spawn":[ids], "despawn":[ids]}`, `func keep(id, snapshot: Array)`, `func kept(id) -> Array`, `func reroll(seed)` (forgets all kept, revives all), `const SPAWN_R`, `const DESPAWN_R` (⚙ choose ≥ 1.25× / 1.75× the view diagonal; AI decision, log in ai-decisions).

- [ ] Tests: spawn only for packs outside `view` and inside SPAWN_R; a pack despawned with 2 of 6 dead comes back with 4 alive at the kept positions; after `reroll` all 6 alive at new random spots round the pack point (seeded, deterministic); dead pack never respawns without reroll.
- [ ] Implement using `WolfPack.snapshot`; members on open roomy cells in a local window round the pack's `home` (never `at`, never raw ring points; do NOT run `MonsterPiles.prepare` over the whole map — its flood covers 92k cells); `home` is spawn centre, leash and respawn point; elite packs keep `elite`. Playtest: the pack at the wood bridge head (p10) must not jam the crossing.
- [ ] Commit.

### Task 5: Waypoint stones w1–w3 + travel re-roll

**Files:** Modify `scripts/rules/waypoints.gd` (ids from world stones; START = "w1"), `scripts/ui/waypoint_list.gd` (Thai names from landmarks 1, 6, 9), `test_ground.gd`; Test: run_tests

- [ ] Tests: w1 unlocked on a fresh state; touching w2 unlocks it; travel to w2 = fade, hero lands next to w2, `PackStream.reroll` called, chests unchanged.
- [ ] Implement; commit.

### Task 6: Boss arena (e0 behaviour in the big map)

**Files:** Modify `test_ground.gd`, maybe `scripts/rules/room_levels.gd` (a helper taking a level instead of a room id); Test: run_tests

- [ ] Read how `arena` rooms behave today (`rooms.json` e0, `groups_for`, `choose_arena_set`, HUD/minimap arena flag) and reproduce it for `BigWorld.in_arena`: arena set chosen by `RoomLevels.arena_set(sets, hero.level, zone_level(gate))`, monsters at `RoomLevels.arena_level(9)` = 10.
- [ ] Tests: entering the arena builds the chosen set at Lv10; waypoint travel mid-fight clears it and the next entry re-chooses.
- [ ] Commit.

### Task 7: Chests (once per save)

**Files:** Create `scripts/map/chest.gd`; Modify `scripts/rules/save_game.gd` (`chests` key), `test_ground.gd`; Test: run_tests

**Interfaces — Produces:** `Chest.make(id, at) -> Chest`, signal `opened(id)`; `SaveGame` state key `"chests": Array[String]`.

- [ ] Tests: opening c4 drops the items of `Loot.roll(kind, level, rng, true)` ×3 (seeded rng, compare); opened id saved; after reload and after waypoint travel c4 is not built; `_state_ok` rejects unknown or duplicate ids.
- [ ] Implement: touch to open (same radius as stones), sparkle FX from the existing manifest, drops via `LootDrop.scatter`.
- [ ] Commit.

### Task 8: Fog, minimap, full map

**Files:** Modify `scripts/rules/fog_grid.gd` (one room "world", 32 px cells → 128×128), `scripts/ui/mini_map.gd`, `scripts/ui/world_map.gd`, `test_ground.gd`; Create `assets/map/bigmap/overview_512.png` (from the baked map); Test: run_tests + screenshot

- [ ] Decide (ai-decisions) what the HUD/minimap shows as an area level: the zone band (`zones[].levels`) or `zone_level` (nearest pack); they disagree at ~6 % of points.
- [ ] Tests: fog reveals cells within RADIUS of the hero in the world grid; minimap shows the area round the hero (not the whole 4096) with stones/chests/arena marks; full map shows the overview under the fog.
- [ ] Implement; screenshots `game_minimap.png`, `game_worldmap.png`; commit.

### Task 9: Save v5 + migration + cheat checks

**Files:** Modify `scripts/rules/save_game.gd`; Test: run_tests

- [ ] Tests: v4 save with room waypoints loads as v5, waypoints = ["w1"], items/level/gems equal; v5 round trip; v6 save refused (B15); tampered waypoints/chests rejected; signature covers the new keys.
- [ ] Implement; bump `VERSION := 5`, new SIG_KEY text; commit.

### Task 10: Switch the game over, perf pass, web build

**Files:** Modify `test_ground.gd` (big map is the only path in the main scene; room path kept for old tests behind a flag), `scripts/rules/perf_saver.gd` (props count), docs (risks, STATE); Test: full suite + web export

- [ ] Run the whole suite headless; fix old room tests by running them with the room flag.
- [ ] Web export (`build/web`), measure frame time headless with 60 packs streamed; screenshots of start, bridge, temple, pond, arena.
- [ ] Update `docs/risks.md`, budget, ai-decisions; draft PR to main with the test link; report to the owner.
