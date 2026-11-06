# M1 Hero Prototype Implementation Plan

> **For agentic workers:** Implement this plan task-by-task, checking off each step. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Godot 4.5 scene where the archer hero walks in 8 directions, idles, and shoots arrows, with the bow drawn as a separate layer — verified headless with tests and a real screenshot.

**Architecture:** PixelLab sprites → `tools/extract_sheet.py` → per-animation strips in `assets/hero/` + `assets/hero/manifest.json`. Godot loads the manifest into `SpriteFrames` at runtime (`HeroSprites.gd`). `Hero.gd` (CharacterBody2D) owns movement, facing and state; `BowLayer.gd` draws the bow sprite above/below the body per facing and state. Game rules that have numbers live in `scripts/rules/combat.gd` as pure static functions so they can be unit-tested.

**Tech Stack:** Godot 4.5.1 (GDScript), Python 3 + Pillow for asset extraction, xvfb + opengl3 for screenshots.

**Spec:** docs/design-brief.md, docs/spec-numbers.md (§1–2), docs/art-style.md

## Global Constraints
- Tile grid 32×32; hero sprite 48×48 (shoot canvas 64×64); collision box ~20×16 at the feet; Y-sort on.
- Walk speed 110 px/s; basic shot range 220 px, cooldown 0.8 s, 100% ATK.
- Damage = ATK × mult × (1 − DEF/(DEF+100)) × rand(0.9, 1.1); crit ×1.5; minimum 1.
- All art from PixelLab via the style lock; anything not from PixelLab is labelled placeholder.
- 8 facings in order: south, south-east, east, north-east, north, north-west, west, south-west.
- Work lands on branch `m1/hero-prototype`, PR to main.

## Review Focus
1. Diagonal input (e.g. up+right) must pick the diagonal facing, not snap to a cardinal → test `test_facing_from_vector`.
2. Releasing all input keeps the last facing (hero must not turn south) → test `test_facing_kept_when_idle`.
3. Shooting while moving fires in the facing direction and respects the 0.8 s cooldown → test `test_shot_cooldown`.
4. Damage never drops below 1 even at huge DEF → test `test_damage_floor`.
5. A missing animation strip must fail loudly at load, not show an invisible hero → test `test_manifest_complete`.

---

### Task 1: Hero sprite assets
**Files:** Create `assets/hero/<anim>_<dir>.png`, `assets/hero/manifest.json`, `tools/build_hero_manifest.py`; Test `tools/test_assets.py`
**Interfaces:** Produces `manifest.json` = `{"cell": {"<anim>": [w,h]}, "frames": {"<anim>": {"<dir>": n}}, "fps": {"<anim>": n}}`; anims `idle` (4 f, 6 fps), `walk` (8 f, 10 fps), `shoot` (9 f, 14 fps).
- [x] Write `test_assets.py`: every anim×8 dirs strip exists, width = frames × cell width, has transparent pixels.
- [x] Run → FAIL (no assets).
- [x] Extract via `pixelart_workbench join … --as rows` + `extract_sheet.py`; write `build_hero_manifest.py`.
- [x] Run → PASS. Commit.

### Task 2: Godot project + combat rules
**Files:** Create `project.godot`, `scripts/rules/combat.gd`, `tests/run_tests.gd`, `tests/test_combat.gd`
**Interfaces:** `Combat.damage(atk: float, mult: float, def: float, crit: bool, roll: float) -> int`; `Combat.facing_from_vector(v: Vector2, last: int) -> int` (0..7 in the Global Constraints order).
- [x] Tests: `test_damage_basic` (atk 18, mult 1, def 6, roll 1.0 → 17), `test_damage_floor` (atk 1, def 100000 → 1), `test_facing_from_vector` (Vector2(1,-1) → 3 north-east; Vector2(0,1) → 0 south), `test_facing_kept_when_idle` (Vector2.ZERO, last 5 → 5).
- [x] `godot --headless --script tests/run_tests.gd` → FAIL, implement, → PASS. Commit.

### Task 3: Hero scene (movement, animation, bow layer, shooting)
**Files:** Create `scenes/hero.tscn`, `scripts/hero/hero.gd`, `scripts/hero/hero_sprites.gd`, `scripts/hero/bow_layer.gd`, `scenes/arrow.tscn`, `scripts/arrow.gd`; Test `tests/test_hero.gd`
**Interfaces:** `HeroSprites.build(manifest_path: String) -> SpriteFrames` (anim names `<anim>_<dir>`); `Hero.try_shoot() -> bool`; `Hero.facing: int`; `Hero.state: String` (`idle|walk|shoot`).
- [x] Tests: `test_manifest_complete` (24 animations), `test_shot_cooldown` (two `try_shoot()` within 0.8 s → second false; after 0.8 s → true).
- [x] Implement: 110 px/s movement, facing via `Combat.facing_from_vector`, bow layer behind body for south-ish facings and on top for north-ish ones while walking; bow in front, aimed along facing, during `shoot`; arrow flies 220 px then frees.
- [x] Run tests → PASS. Commit.

### Task 4: Test ground + screenshot
**Files:** Create `scenes/test_ground.tscn`, `scripts/test_ground.gd`, `tools/screenshot.gd`
- [x] Test ground: 32 px grid floor (placeholder, labelled in code), hero in the middle, a few Y-sorted placeholder posts to check walking behind/in front.
- [x] `xvfb-run godot --rendering-driver opengl3 --path . -- --shot docs/preview/m1_*.png` scripted: idle, walking NE, shooting E.
- [x] Look at the shots (verification-before-completion). Commit + PR.

## Self-review
- Spec coverage: §1 speed, §2 damage, art-style sizes and Y-sort → Tasks 2–4. Skills, gems, monsters, map are later milestones (out of scope).
- Proportion: plan shorter than the code it describes.

## Execution notes (2026-11-06)
- All cells normalised to 64x64 with the feet anchor (32,54) (`tools/normalize_cells.py`): template anims come on a 48 canvas, custom/skeleton anims on 64.
- Screenshot script is `tests/screenshots.gd` (waits on physics frames; render frames run faster under xvfb).
- Bow when shooting is drawn in front except for north (NE/NW hold it out to the side, so it stays visible).
- Known: shoot strips carry 314 colours (custom v3 output) versus 37–157 for template anims; the NW shoot has white flash pixels in a few frames; on south/east/west idle/walk the bow on the back is fully hidden by the body.
