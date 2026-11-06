# M3d Forest Monsters Implementation Plan

> **For agentic workers:** Implement this plan task-by-task, checking off each step. Steps use checkbox (`- [ ]`) syntax for tracking. Runs on the same branch/PR as M3c (`m3c/rooms-warps`).

**Goal:** Six new forest monsters (deer, boar, poison mushroom, macaque, green pit viper, kong-koi ghost) placed per room with the approved levels, some never striking first.

**Architecture:** `Monster` generalises `Wolf`: the shared body (health, status, knockback, wander, leash/return, A* steering, stuck rules, respawn) stays; a `temper` (aggressive / passive / flee / ambush) decides when to chase, and an attack kind (melee+charge, ring, ranged, strike, stomp) decides how to hurt. Wolves stay on their own class until the end, then become a `Monster` config (Task 4) so the ten existing wolf tests keep guarding the shared body. Rooms read a monster list per room from `data/rooms_src.json`.

**Tech Stack:** Godot 4.5.1 GDScript; PixelLab `create_character` (pro, style = wolf/hero) + `animate_character` skeleton-v3; `vfx_workbench` (free); tools `extract_sheet.py`, `normalize_cells.py`.

**Spec:** `docs/superpowers/specs/2026-11-07-m3d-forest-monsters-design.md` (owner approved 2026-11-07)

## Global Constraints
- Numbers exactly as spec §2 (HP/ATK/DEF/EXP formulas, speeds, ranges, warnings, cooldowns), all in `data/balance.json` under `monsters.<id>`; ids `deer`, `boar`, `shroom`, `macaque`, `viper`, `kongkoi` (+ existing `wolf`).
- Monsters never crit; respawn 20 s; leash 320 px → return home and heal.
- Passive: `deer` never deals damage, flees 160 px/s for 3 s when hit; `boar`/`shroom` deal no damage until hit, then chase (`boar` 120 px/s, `shroom` 40 px/s). Aggressive: `macaque` aggro 140, `viper` reveals at 70, `kongkoi` and wolves per spec.
- Drops: `kongkoi` uses the kong-koi column (gear 9%, ore 35%), all others the wolf column; `deer` gold ×2.
- Placement exactly spec §3 (room, level, counts); wolf packs Lv1/3/5 → c1r0/c2r2/c1r2.
- Art budget ~420 gen, hard stop 500 for all six. Generate one monster fully and review before the next. Directions: generate S, SE, E, NE, N and mirror the west ones (saves ~40%); log every call in `docs/pixellab-budget.md`.

## Review Focus
1. Shooting a passive boar from max range and backing off → it chases, then leashes home healed; it never damages before being hit (Task 2: `test_boar_peaceful_until_hit`).
2. A deer hit while cornered against trees → flees along a route, never stuck jittering, never damages (Task 2: `test_deer_flees_without_damage`).
3. Poison cloud from a dead mushroom when the hero walks through it later → ticks only while inside, ends after 2 s (Task 3: `test_death_cloud`).
4. Macaque fruit hitting a tree trunk between it and the hero → stops at blocked cells (Task 3: `test_fruit_stops_at_trees`).
5. Leaving a room while a monster is mid-attack or a projectile is in flight → nothing lingers into the next room (Task 4: `test_room_switch_clears_attacks`).

---

### Task 1: Monster art (≈420 gen, one monster at a time)

**Files:** Create `assets/monsters/<id>/` strips + `manifest.json` per monster (same shape as `assets/wolf/manifest.json`: directions, cell, frames per anim), `assets/fx/<fx>.png` (fruit, spore_ring, poison_mist, stomp_ring) + fx manifest entries; Modify `docs/pixellab-budget.md`.

Animations per monster (names used by code): `deer` pose/run/death · `boar` pose/run/attack/charge/death · `shroom` pose(sleep)/walk/attack/death · `macaque` pose/run/throw/death · `viper` pose(coiled)/move/strike/death · `kongkoi` pose/hop/stomp/death. Cells: deer/boar/kongkoi 48 px art, shroom/macaque/viper 32–40 px art, padded like the wolf to a shared feet anchor.

- [ ] Per monster: log estimate → `create_character` (pro, style ref = wolf south) → review → skeleton-v3 animations for S/SE/E/NE/N → mirror → extract + normalize → manifest → review sheet by eye → log real cost. Stop and report if a monster fails twice.
- [ ] VFX in `vfx_workbench` (free).
- [ ] Commit per monster `M3d art: <id>`.

### Task 2: Monster body + tempers (passive, flee)

**Files:** Create `scripts/monsters/monster.gd`, `scripts/monsters/monster_group.gd`; Modify `data/balance.json` (`monsters.*`); Test `tests/test_monsters.gd`.

**Interfaces:** `Monster.make(kind: String, level: int) -> Monster` · `stats() -> {hp, atk, def, exp}` · `temper: String` ("aggressive"|"passive"|"flee"|"ambush") · `provoked: bool` · same signals/methods the wolf has (`died`, `health`, `receive_hit`, `step(delta, hero)`, `hurt_point()`, `revive()`) · `MonsterGroup` (generalised `WolfPack`): `kind`, `level`, `count`, `home`, `nav`, `unreachable_at`, `spawn()`, `alert(h)`, `monsters`.

- [ ] Failing tests: `test_stats_match_spec` (every kind at its min and max level: HP/ATK/DEF/EXP from spec §2) · `test_boar_peaceful_until_hit` · `test_deer_flees_without_damage` · `test_shroom_wakes_when_hit` · `test_respawn_20s` · `test_leash_home_heals`.
- [ ] Implement body (lifted from `wolf.gd`) + passive/flee tempers; run; commit `M3d Task 2`.

### Task 3: Attacks (charge, spore ring, fruit, strike, stomp)

**Files:** Modify `monster.gd`; Create `scripts/monsters/fruit.gd`, `scripts/monsters/hazard_cloud.gd`; Test `tests/test_monsters.gd`.

- [ ] Failing tests: `test_boar_charge_warns_then_hits` (0.6 s warn, 160 px in 0.5 s, ATK×1.6, cooldown 6 s) · `test_spore_ring` (r40, warn 0.6 s, ATK×0.8 + poison 20%/s 3 s) · `test_death_cloud` · `test_macaque_keeps_range_and_throws` (90–130 px, every 1.6 s, ATK×0.8, hops back <50 px) · `test_fruit_stops_at_trees` · `test_viper_hidden_until_close` (alpha low until 70 px; strike warn 0.3 s, 70 px in 0.2 s, ATK×1.4) · `test_kongkoi_stomp` (r48, warn 0.8 s, ATK×1.5, cooldown 4 s).
- [ ] Implement; run; commit `M3d Task 3`.

### Task 4: Rooms place monsters; wolves join Monster

**Files:** Modify `data/rooms_src.json` (+ regenerate `data/rooms.json`), `scripts/dev/test_ground.gd`, `scripts/monsters/wolf.gd` → wolf becomes `Monster` kind `wolf` (keep its tests green), loot (`kongkoi` column, deer gold ×2); Test `tests/test_room_switch.gd`.

- [ ] Failing tests: `test_room_monsters_match_spec` (every room: kinds, counts, levels from spec §3) · `test_every_spawn_point_walkable` · `test_room_switch_clears_attacks` · `test_kongkoi_drop_column` · `test_deer_double_gold`.
- [ ] Implement; full suite; screenshots of every monster in its room; commit `M3d Task 4`.
