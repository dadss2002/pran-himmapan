# M3c Forest Rooms + Warps Implementation Plan

> **For agentic workers:** Implement this plan task-by-task, checking off each step. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the one big painted map with 12 one-screen rooms (the seamless raw chunks) joined by warp circles, and stop the hero getting stuck.

**Architecture:** A Python tool turns `data/rooms_src.json` + `assets/map/painted/raw/c{c}r{r}.png` into `data/rooms.json` (per-room smoothed walk grid, leaf overlay, snapped warps). A pure `RoomSet` reads it and hands out one `PaintedLayout` per room; `test_ground` rebuilds the `PaintedMap`, packs and drops when the hero steps into a `Warp`. The hero's feet become a horizontal capsule so it slides along jagged edges.

**Tech Stack:** Godot 4.5.1 GDScript, headless `tests/run_tests.gd`, xvfb screenshots, Python 3 + numpy/scipy/PIL for the tool, PixelLab `vfx_workbench` (free) for the warp ring.

**Spec:** `docs/superpowers/specs/2026-11-07-m3c-rooms-warps-design.md` (owner agreed 2026-11-07)

## Global Constraints
- 0 PixelLab gen. Only `vfx_workbench` (free).
- 12 rooms = raw chunks c0r0…c2r3, each 688×384, no patches, no clumps. Start room `c1r1`.
- 11 links: c0r0↕c0r1, c0r1↕c0r2, c0r2↕c0r3, c0r1↔c1r1, c1r0↕c1r1, c1r1↔c2r1, c2r0↕c2r1, c2r1↕c2r2, c0r2↔c1r2, c1r2↕c1r3, c1r3↔c2r3.
- Packs (balance.json order Lv1, Lv3, Lv5): index 0 in c1r0, 1 in c2r2, 2 in c2r3. Levels/counts unchanged.
- Warp: radius 14 px; fade 0.3 s; arrival 40 px inward from the paired warp; a warp re-arms only after the hero is more than 22 px from it.
- Leaving a room drops its wolves and unpicked drops; entering spawns its pack fresh at home. Save on every warp; save stores `room`.
- Hero feet: CapsuleShape2D radius 8, height 20, rotated 90°, at (0, -6) (same 20×16 extent).
- Thai UI text; branch `m3c/rooms-warps` + PR; no merge without an order.

## Review Focus
1. Wolves of the Lv5 room standing near the entry warp when the hero arrives → pack is fresh at home, hero is not inside bite range on arrival (Task 3: `test_arrival_safe_from_pack`).
2. Hero dies inside a room → respawns at that room's spawn, not in another room (Task 3: `test_death_respawns_in_room`).
3. Bag or skill panel open (tree paused) while standing on a warp → nothing happens until closed (Task 3: `test_no_warp_while_paused`).
4. Save holding an unknown room id ("c9r9") or none (old save) → starts in `c1r1` at its spawn (Task 3: `test_bad_room_in_save`).
5. Rolling into a warp → arrives, roll ends, hero can move at once (Task 3: `test_roll_into_warp`).

---

### Task 1: Room data tool and RoomSet

**Files:**
- Create: `tools/painted_rooms.py`, `data/rooms_src.json`, `data/rooms.json`, `assets/map/painted/rooms/overlay_c{c}r{r}.png`, `docs/preview/m3c_rooms_debug.png`
- Create: `scripts/map/room_set.gd`
- Modify: `scripts/map/painted_layout.gd` (from_dict accepts a room dict, see below)
- Delete: `tools/painted_compose.py`, `data/map_painted.json`, `data/map_painted_src.json`, `assets/map/painted/c?r?.png`, `assets/map/painted/canopy_*.png` (keep `raw/`, `clumps/`)
- Test: `tests/test_rooms.gd`

**Interfaces:**
- Produces `data/rooms.json` = `{"start": "c1r1", "size": [688, 384], "cell": 8, "rooms": {"<id>": {"image": "res://assets/map/painted/raw/<id>.png", "overlay": "res://…/overlay_<id>.png" | null, "blocked": ["#..#", …], "spawn": [x, y], "warps": [{"id": "north"|"south"|"east"|"west", "at": [x, y], "to": "<room id>", "to_warp": "<id>"}], "pack": 0|1|2|-1, "pack_home": [x, y] | null, "fx": [{"id": "water_ripple", "at": [x, y]}]}}}`. Room `raw/` images must load in game: drop the `.gdignore` in `raw/` (keep it in `clumps/`) and drop `raw/*` from the export exclude.
- Tool rules: walk guess = `classify` from `tools/painted_map.py` (move it into `painted_rooms.py`, delete `painted_map.py`); smoothing per room: binary closing of walk (3×3), then binary opening of walk (cross), then fill blocked islands < 10 cells, drop walk islands < 8 cells, then hand edits; warps and spawn snap to the nearest cell where a hero-sized body fits (`roomy`, 3 rows); a room without `spawn` in src uses its first warp's arrival point.
- Produces `RoomSet.open(path := "res://data/rooms.json") -> RoomSet` · `start: String` · `ids() -> PackedStringArray` · `room(id: String) -> Dictionary` · `layout(id: String) -> PaintedLayout` · `warp(id: String, warp_id: String) -> Dictionary` · `arrival(id: String, warp_id: String) -> Vector2` (40 px from the warp toward the room centre, moved to the nearest roomy cell) · `validate() -> Array[String]`.
- `PaintedLayout.from_dict` also accepts `{"size", "cell", "blocked", "image", "overlay", "spawn", "pack_home", "fx"}`: image → `chunks = [{file, at: (0,0)}]`, overlay → `overlays`, spawn → `hero_spawn`, pack_home → `pack_homes = [home]`. `validate()` checks packs only against its own homes (no balance-count check when built from a room).

- [ ] **Step 1: Failing tests** `test_rooms_data_valid` (12 rooms; `validate()` empty) · `test_links_are_pairs` (every warp's `to`/`to_warp` exists and points back; exactly the 11 links of Global Constraints) · `test_every_room_reachable_from_start` (BFS over warps from `c1r1` reaches all 12) · `test_warps_and_spawn_connected_in_room` (each room: `layout.reachable` between spawn and every warp) · `test_arrival_clear_of_warp` (every `arrival` is not blocked and 22–60 px from its warp) · `test_packs_in_their_rooms` (pack 0 in c1r0, 1 in c2r2, 2 in c2r3; ring points unblocked) · `test_no_stray_specks` (no walkable island smaller than 8 cells and no blocked island smaller than 10 cells inside walkable ground).
- [ ] **Step 2:** Write `rooms_src.json` (warp positions at each painted trail's end near the room edge) and the tool; run `python3 tools/painted_rooms.py`; look at `docs/preview/m3c_rooms_debug.png` (blocked tinted, warps and spawn marked); adjust warps/edits until every trail end is open.
- [ ] **Step 3: Implement** `room_set.gd` and the `from_dict` change.
- [ ] **Step 4: Run** `$G --headless --path . --script tests/run_tests.gd` → new tests pass.
- [ ] **Step 5: Commit** `M3c Task 1: room data and RoomSet`.

### Task 2: Hero capsule and the no-stuck walk test

**Files:**
- Modify: `scenes/hero.tscn` (Feet → CapsuleShape2D radius 8, height 20, rotation 90°, position (0, -6))
- Test: `tests/test_rooms.gd` (`test_hero_walks_every_route`), `tests/test_ground.gd` (roll test still passes)

**Interfaces:**
- Consumes: `RoomSet.layout`, `PaintedLayout.make_nav`, `PaintedMap.build`.
- Produces nothing new for later tasks.

- [ ] **Step 1: Failing test** `test_hero_walks_every_route`: for every room, build a `PaintedMap` + hero under a Node2D in the tree; for every pair (spawn or warp → every other warp) take the nav path and drive `hero.step(1/60, dir_to_next_waypoint)` with physics frames; the hero must end within 12 px of the goal within `path_length / hero_walk_speed × 1.6 + 1` s. Failure message names room, from, to and where it stopped.
- [ ] **Step 2: Run** → note which routes fail with the rectangle feet (record in the commit message).
- [ ] **Step 3: Implement** the capsule; if a route still fails, fix the room's src edits / smoothing in Task 1's data, not the test.
- [ ] **Step 4: Run** all tests → pass (incl. `test_roll_stops_at_collider`).
- [ ] **Step 5: Commit** `M3c Task 2: capsule feet, every room route walkable`.

### Task 3: Warps and room switching in the test ground

**Files:**
- Create: `scripts/map/warp.gd`
- Modify: `scripts/dev/test_ground.gd`, `scripts/rules/save_game.gd`
- Delete/replace: `tests/test_painted_map.gd` → `tests/test_room_switch.gd` (port its collider/overlay/drops/wolf tests to "the current room")
- Test: `tests/test_room_switch.gd`, `tests/test_ground.gd`

**Interfaces:**
- Consumes: `RoomSet` (Task 1).
- Produces: `Warp` (`class_name Warp extends Node2D`): `warp_id: String`, `to_room: String`, `to_warp: String`, `armed := true`, `step(hero_pos: Vector2) -> bool` (true once when an armed warp has the hero within 14 px; re-arms beyond 22 px) · test_ground: `rooms: RoomSet`, `room_id: String`, `warps: Array[Warp]`, `go_to(id: String, via_warp := "") -> void` (frees map/packs/drops/warps, builds the room, places the hero at `arrival` or the room spawn, sets `hero.spawn_point`, disarms the arrival warp, saves), signal `room_changed(id: String)`, fade = a CanvasLayer ColorRect black 0 → 1 → 0 over 0.3 s (visual only; the switch itself happens at once) · SaveGame state gains `"room": String` (kept as-is by save; `load_or_new` keeps it when it is a String, else drops it; VERSION stays 3).

- [ ] **Step 1: Failing tests** `test_starts_in_start_room` · `test_warp_moves_to_paired_room` (hero on c1r1 `west` warp → after 2 physics frames room `c0r1`, hero at `arrival("c0r1", "east")`) · `test_no_bounce` (60 frames standing after arrival → still `c0r1`) · `test_bag_and_level_kept` · `test_save_remembers_room` (warp, new ground with same save → `c0r1`) · `test_bad_room_in_save` (room "c9r9" and no room → `c1r1` at spawn) · `test_pack_only_in_its_room` (c1r0 has pack 0 only; c1r1 none) · `test_leaving_clears_drops` · `test_arrival_safe_from_pack` (enter c2r3: every wolf ≥ 60 px from the hero, all at full HP) · `test_death_respawns_in_room` (die in c2r2 → respawn there at its spawn) · `test_no_warp_while_paused` (bag open on a warp, 30 frames → same room; close → warps) · `test_roll_into_warp` (dodge onto a warp → arrives, `hero.state` not "roll" after 0.5 s, moves on input) · ported: `test_colliders_match_blocked_at` (current room), `test_drops_avoid_blocked`, `test_wolves_route_round_trees` / `test_wolves_give_up_on_an_unreachable_hero` re-pointed at spots inside c1r0 (pick with the tool's debug image; fail if the spot is invalid).
- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement** `warp.gd`, `go_to`, save `room`; delete `data/map_painted*`-based code paths.
- [ ] **Step 4: Run** all tests → pass; `xvfb-run … tests/touch_check.gd` → TOUCH PASS.
- [ ] **Step 5: Commit** `M3c Task 3: warps and room switching`.

### Task 4: Warp ring look, screenshots, PR

**Files:**
- Create: `assets/fx/warp_ring.png` (+ manifest entry, loop), `tests/screenshots_m3c.gd`, `docs/preview/m3c_*.png`
- Modify: `scripts/map/warp.gd` (plays `warp_ring` under characters, z −9), `docs/pixellab-budget.md` (0 gen line), `tools/demo_video.gd` (route through two warps)

- [ ] **Step 1:** Make the ring in `vfx_workbench` (e.g. `soft_glow` + `rune_circle`, pale gold/teal, ~40×24), export, strip + manifest.
- [ ] **Step 2:** `screenshots_m3c.gd`: every room once with the hero at its spawn or first arrival, one shot mid-fade, one on a warp.
- [ ] **Step 3:** Full tests, touch check, demo clip; web export to `gh-pages` `/m3c/` preview.
- [ ] **Step 4:** Draft PR → fresh reviewer on the whole branch → fix → ready; Thai report with group tags. No merge without an order.
