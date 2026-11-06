# M2b Loot & Progression — Implementation Plan

> **For agentic workers:** Implement this plan task-by-task, checking off each step. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Killing wolves pays: loot drops and flies to the hero, EXP fills, levels go up (to cap 10), MP and the first two skills work, potions heal, and progress survives a reload.

**Architecture:** Same pattern as M2a: numbers in `data/balance.json`, pure rule classes (`Progression`, `Loot`, `Inventory`, `SaveGame`) unit-tested headless, scene nodes (`LootDrop`, hero/HUD changes) driven by `step()`. Skills reuse the shoot animation and the Arrow class (piercing flag, fan of arrows).

**Tech Stack:** Godot 4.5.1 GDScript, PixelLab `vfx_workbench` (free) for skill/level-up/pickup effects, xvfb screenshots.

**Spec:** `docs/superpowers/specs/2026-11-06-m2-design.md` §2 (M2b row), §5.3–5.6, §6; `docs/spec-numbers.md` §1, §3, §5, §8, §10; `docs/skills.md` §1; `docs/gems.md` §2, §6. Branch `m2b/loot` from `m2a/combat`.

## Global Constraints
- Everything in M2a's Global Constraints still holds (Godot 4.5.1, balance.json only, PixelLab logging, run tests before claiming).
- EXP to next level = round(45 × L^1.8 × 1.035^L) (Lv1→2 = 47); phase-1 cap Lv10 — EXP stops there.
- Wolf EXP 8+5l; ×0.3 when the wolf is 6+ levels below the hero.
- Death: lose 5% of the current level bar, never below 0, never de-level.
- Level-up: full HP and MP, "Lv ขึ้น" text + level-up effect.
- MP = 50+5(L−1), regen 6/s. ศรทะลวง Lv1: 180%, pierces everything in line, 220 px, CD 4 s, MP 8. ศรกระจาย Lv3: 5 arrows over 45°, 70% each, CD 6 s, MP 12. Skill level = char level − unlock level + 1; +5% damage and −1% cooldown (max −30%) per skill level above 1.
- Potions: HP/MP restore 40% of max, shared cooldown 10 s; start kit 5 HP + 3 MP.
- Wolf drops: gold 3–6+l (always), ore 25%, gem 1% (type uniform over the gems.md list), equipment 6% → **M2c** (not in this plan).
- Pickup: magnet radius 64 px, 260 px/s, lifetime 60 s; bag 24 slots, stacks of 99; bag full → item stays on the ground with "กระเป๋าเต็ม".
- Save `user://save.json` on level-up, pickup, every 30 s and on quit; version field; a broken save never crashes the game.

## Review Focus
1. Save file missing, corrupt JSON or an older/newer `version` → game starts fresh, keeps the bad file as `save.bad.json`, no crash → `test_load_corrupt_save_starts_fresh` (Task 2).
2. One kill worth several levels, and reaching Lv10 → levels increase one by one with a level-up event each; at Lv10 EXP stays 0 and the bar shows full → `test_multi_level_and_cap` (Task 1).
3. Death right after a level-up (0 EXP in the bar) → EXP stays 0, level unchanged → `test_death_penalty_never_negative` (Task 1).
4. Bag full while gold, ore and a gem drop → gold still collected (gold is not a slot), ore/gem stay on the ground → `test_bag_full_gold_still_collected` (Task 3).
5. Skill pressed with too little MP, on cooldown, while rolling or dead → refused and no MP spent → `test_skill_refused_keeps_mp` (Task 5).

---

### Task 1: Progression and loot rules
**Files:** Create `scripts/rules/progression.gd`, `scripts/rules/loot.gd`; Modify `data/balance.json` (keys `exp.{base 45, power 1.8, growth 1.035, cap_level 10, low_level_gap 6, low_level_mult 0.3, death_loss 0.05}`, `mp.{base 50, per_level 5, regen 6}`, `potion.{heal_frac 0.4, cooldown 10, start_hp 5, start_mp 3}`, `loot.wolf.{gold_min 3, gold_max 6, ore 0.25, gem 0.01}`, `gems` list of the 10 gem ids from gems.md, `pickup.{magnet 64, speed 260, lifetime 60}`, `bag.{slots 24, stack 99}`); Test `tests/test_progression.gd`
**Interfaces:** Produces `Progression.exp_to_next(level: int) -> int` · `Progression.add_exp(level: int, exp: int, gain: int) -> Dictionary` {level, exp, levels_gained} · `Progression.kill_exp(monster_exp: int, monster_level: int, hero_level: int) -> int` · `Progression.after_death(level: int, exp: int) -> int` · `Balance.mp(level: int) -> int` · `Loot.roll(kind: String, level: int, rng: RandomNumberGenerator) -> Array` of {id: String, count: int} (ids `gold`, `ore_himmapan`, `gem_<type>`).
- [x] Tests: `test_exp_curve` (L1 47, L2 168, L9 3201) · `test_kill_exp_low_level_penalty` (wolf lv1 exp 13 vs hero lv7 → 4; vs hero lv6 → 13) · `test_multi_level_and_cap` (add 1000 at L1 → L4 with 425 EXP, levels_gained 3; at L9 with 3000 EXP add 5000 → L10, EXP 0, extra discarded; at L10 add 50 → still L10 EXP 0) · `test_death_penalty_never_negative` (L3 exp 0 → 0; L3 exp 100 → 82; L3 exp 10 → 0) · `test_loot_rates_seeded` (10 000 rolls lv1: gold every time in 4..7, ore 23–27%, gem 0.7–1.3%).
- [x] Run → FAIL; implement; run → PASS; commit `feat(m2b): progression + loot rules`.

### Task 2: Inventory and save
**Files:** Create `scripts/rules/inventory.gd`, `scripts/rules/save_game.gd`; Test `tests/test_inventory.gd`
**Interfaces:** `Inventory` (RefCounted): `gold: int`, `slots: Array` of {id, count}, `add(id: String, count: int) -> int` (amount that did NOT fit), `remove(id, count) -> bool`, `count_of(id) -> int`, `is_full_for(id) -> bool`, `to_dict()`, `from_dict(d)`. `SaveGame.save(state: Dictionary, path := "user://save.json") -> bool`, `SaveGame.load_or_new(path := ...) -> Dictionary` with `version 1`, `level`, `exp`, `inventory`.
- [x] Tests: `test_stacking_and_overflow` (99 ore + 5 → second slot; 24 full slots → add returns leftover) · `test_gold_not_a_slot` · `test_save_roundtrip` (temp path) · `test_load_corrupt_save_starts_fresh` (garbage file → new state, `save.bad.json` exists) · `test_load_other_version_starts_fresh`.
- [x] Run → FAIL; implement; run → PASS; commit `feat(m2b): inventory + save`.

### Task 3: Loot drops in the world
**Files:** Create `scripts/loot/loot_drop.gd`, `scenes/loot_drop.tscn`; Modify `scripts/monsters/wolf.gd` (signal `died` already exists; pack/test ground spawns drops), `scripts/dev/test_ground.gd`; Test `tests/test_loot_drop.gd`
**Interfaces:** `LootDrop` (Node2D): `item_id`, `count`, `step(delta: float, hero: Hero, inv: Inventory) -> bool` (true when collected), signal `collected(item_id, count)`. Icons: `coin_gold`, `ore_himmapan`, gems by colour group (attack = gem_red, arrow = gem_blue, utility = gem_green **[my call until the 10 gem icons exist]**).
- [x] Tests: `test_magnet_radius_and_speed` (at 70 px stays; at 60 px moves 260 px/s toward the hero, collected on contact) · `test_lifetime_60s` · `test_bag_full_gold_still_collected` · `test_drop_scatter_not_inside_walls` (drops placed around the corpse within 24 px, never inside a post collider).
- [x] Run → FAIL; implement (pop-out arc on spawn, idle bob, `item_glint` on gems, `collect_pop` effect, "กระเป๋าเต็ม" floating text throttled to once per 2 s); run → PASS; commit.

### Task 4: Hero EXP, level-up, MP, HUD
**Files:** Modify `scripts/hero/hero.gd`, `scripts/ui/hud.gd`, `scripts/dev/test_ground.gd`; Test `tests/test_hero_progress.gd`
**Interfaces:** Hero gains `exp: int`, `mp: float`, `inventory: Inventory`, signals `leveled_up(level: int)`, `exp_changed()`; `gain_exp(amount: int)`; MP regen in `step`; death applies `Progression.after_death`. HUD: EXP bar value, MP bar + "MP x / y", gold label, level label.
- [x] Tests: `test_kill_gives_exp` (wolf lv1 killed by hero lv1 → +13) · `test_level_up_heals_and_raises_stats` (HP 120→132 max at L2, full HP/MP, signal once) · `test_mp_regen_6_per_s` · `test_death_costs_5_percent`.
- [x] Run → FAIL; implement (+ level-up effect from `vfx_workbench` part `level_up`, "Lv ขึ้น" text); run → PASS; commit.

### Task 5: Skills and potions
**Files:** Create `scripts/hero/skills.gd`; Modify `scripts/arrow.gd` (`pierce: bool` — hits each enemy once, keeps flying), `scripts/hero/hero.gd`, `scripts/ui/touch_buttons.gd` (skill/potion buttons live, unlock labels, MP-short tint), `project.godot` (actions `skill_1` 1, `skill_2` 2, `potion_hp` Q, `potion_mp` E); Test `tests/test_skills.gd`
**Interfaces:** `Hero.try_skill(id: String) -> bool` (`"piercing"`, `"spread"`), `Hero.try_potion(kind: String) -> bool` (`"hp"`, `"mp"`), `Skills.damage_mult(id, char_level) -> float`, `Skills.cooldown(id, char_level) -> float`, `Skills.unlock_level(id) -> int`.
- [x] Tests: `test_piercing_hits_every_enemy_in_line` (3 dummies in a row → each hit once at 180% atk) · `test_spread_five_arrows_45deg` (directions at −22.5…+22.5°, each 70%) · `test_spread_locked_before_lv3` · `test_skill_scaling` (piercing at L5 → skill level 5 → ×1.20 damage, CD 4×0.96) · `test_skill_refused_keeps_mp` (MP 7 → piercing refused, MP still 7; on cooldown; while rolling; while dead) · `test_potion_shared_cooldown` (HP potion then MP potion within 10 s → second refused; heals 40% of max, count −1; count 0 → refused).
- [x] Run → FAIL; implement (skills auto-aim like the basic shot, use the shoot clip, effects from `vfx_workbench`: gold trail for piercing, pikul-ring burst for spread — log 0 gen); run → PASS; commit.

### Task 6: Test ground, save hookup, screenshots, PR
**Files:** Modify `scripts/dev/test_ground.gd` (load/save, autosave timer 30 s, save on quit), `tests/screenshots.gd`
- [x] Wire save/load; test `test_ground_autosave_writes_file` (temp path override).
- [x] Full suite + assets test → PASS. Screenshots `m2b_loot_magnet.png`, `m2b_level_up.png`, `m2b_piercing.png`, `m2b_spread.png`, `m2b_potion.png`, `m2b_hud_exp_mp.png`; look at each.
- [x] Verify, commit, push, draft PR (base `m2a/combat`), fresh reviewer on the branch, Thai report with screenshots.

## Execution notes (2026-11-06)
- Test runner bug found while writing Task 4: a test that hit a script error returned null and was counted as a pass. Fixed on m2a/combat and here; all earlier tests re-checked and genuinely pass.
- Gem icons: 3 colours mapped by group (balance.json "gem_icon_group") until the 10 gem icons are generated — that needs PixelLab credits → waiting for owner approval (owner rule 2026-11-06: credit work waits, free work continues every 15 min).
- Effects (level-up, pickup, piercing trail, spread burst, lock-on) were made with vfx_workbench: 0 gen.
