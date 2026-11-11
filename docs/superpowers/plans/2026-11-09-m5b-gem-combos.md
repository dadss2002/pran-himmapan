# M5b Gem Combos (ท่าผสม 2 เม็ด + ท่าขั้นสูง 3 เม็ด) Implementation Plan

> **For agentic workers:** Implement this plan task-by-task, checking off each step. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two gems that form a recipe on one skill become a named combo (8 recipes), three become an advanced combo (8 recipes). Every skill gets 2 gem slots from unlock. The skill panel shows the combo live, a toast announces each first discovery, and a recipe book (สมุดสูตร) lists the recipes. The three area skills ห่าศร, กับดักหนาม and ศรเพลิง are built in this milestone (owner 2026-11-09), so the 6 area recipes can form in game, and the 4 touch skill buttons become an assignable skill bar.

**Architecture:** Recipes and every number live in `data/balance.json` → `gem_combos.recipes`. A pure rules script (`GemCombo`) works out which recipe a skill's open sockets form. `SkillBuild` folds the stat-level parts into the build. A per-press ledger (`ComboCast`) enforces the per-cast caps and once-per-target rules. `Arrow` applies the on-hit effects. Monsters get freeze, mark, trail-burn and zone statuses in `StatusEffects`. The UI reads the same rules (`SkillText`) so the panel, the HUD and combat always agree. Discovered recipe ids go into the signed save as a new optional, range-checked key. Area skills (Tasks 8a–8e): `Skills` / `SkillBuild` become data-driven (id list, skill `kind`, area keys). `Hero._release` branches on `kind`: `arrows` keeps the current path, and ศรเพลิง rides it, so every arrow combo works on it; `rain` spawns an `ArrowRain`; `trap` adds a `ThornTrap` to a capped `TrapSet`. Rain and trap hits go through one shared `SkillHit` helper. `StatusEffects` gets a root (ตรึง) status. A 4-slot skill bar (second optional, range-checked save key `bar`) maps the touch buttons and keys 1–4 to skills.

**Tech Stack:** Godot 4.5.1 (GDScript), headless test runner `tests/run_tests.gd`, xvfb + opengl3 screenshots, existing FX sheets in `assets/fx/manifest.json`.

**Spec:** `docs/superpowers/specs/2026-11-08-gem-combos.md` (Option A + "ตัวเลขเสนอ" §1–§5 + effect-reuse table; owner approval line 2026-11-08 and owner addendum 2026-11-09 at the end override earlier lines; the area-skill decisions D1–D8 of 2026-11-09 are the last block). Base gem rules: `docs/gems.md` (approved 2026-11-06; §2 gives the area skills' MP and labels). Area skill numbers: `docs/skills.md` rows 36, 42, 53 (approved 2026-11-06). Numbers' source: `tools/gem_combo_sim.py`. Cheat rules: `docs/risks.md` S1/S5/B14/B15/B9.

## Global Constraints

- Engine Godot 4.5.1. Tests: `godot --headless --path . --script tests/run_tests.gd`; one file: `TEST_ONLY=test_gem_combo godot --headless --path . --script tests/run_tests.gd`. A test returns `""` on pass, an error string on fail. Expected output on pass: `RESULT passed=N failed=0`.
- Branch `m5b/gem-combos` (the coordinator creates it from `m5a/pixelfx`). Commit per task. The coordinator opens a draft PR to main. No claims of passing without a real run (CLAUDE.md).
- **Slots (owner approval 2026-11-08):** `gem_slots = [1, 1, 10, 50]`, meaning every skill has 2 slots from unlock, slot 3 opens at skill level 10 and slot 4 at skill level 50. Skill level = char level − unlock + 1 (`Skills.skill_level`).
- **Owner 2026-11-09:** socketed gems stay where they are ("อยู่ที่เดิม"). A gem in a slot that is not open goes back to the bag and is never lost: if the bag is full it stays socketed until there is room. A closed-slot gem has no effect (builds read open slots only).
- **MP:** per-gem MP multipliers stay as in docs/gems.md §5 (split ×1.4, ricochet ×1.3, pierce ×1.2, homing ×1.2, multiply ×1.5, expand ×1.3, extend ×1.2, execute ×1.2, leech ×1.2, element ×1.3). Combos add no MP multiplier and no discount.
- **Resolution:** a 3-gem advanced recipe replaces its 2-gem base(s) ("ไม่ได้ทั้งสองอย่าง"). Gems outside the recipe keep their normal effect. Only one element gem per skill: the existing same-type rule (`hero.gd:160`, all elements share type `element`) already enforces this, and it stays. Recipe gem keys are gem types, with the element gems as `fire` / `ice` / `lightning`.
- **One combo per skill** (plan decision, open question Q1): the highest tier wins, and ties go to data order. The only way to have two candidates is 4 slots at skill Lv50.
- **Bosses freeze like any monster** (owner 2026-11-08: "บอสแข็งได้เหมือนมอนอื่น"). The spec row's "บอสช้าลง 60% 1 วิแทน" is NOT implemented. Elites freeze too.
- **MP on kill:** bloodthirst +2 MP per kill, at most **6** per press. Rahu +3 per kill, at most **9** per press. Never above max MP.
- Combo numbers are the spec §1/§2 values at gem Lv1 and stay flat at any gem level (open question Q2). The gems' own effects keep scaling.
- **Combo numbers (spec §1, §2, verbatim):** see Task 2 `test_recipes_match_spec`. Those values are the only new game numbers. The trail's half-width reuses `shot.arrow_hit_radius` (10), the bolt range reuses `elements.lightning.range` (120) and the trail tick reuses `elements.fire.tick` (1.0), so no number goes in that is not approved.
- **Secondary hits** (plan decision): blasts, bolts, shockwaves, shatters and trail ticks are hits of the same press. Blasts, bolts, shockwaves and shatters can crit with the arrow's crit chance; **trail ticks never roll: each tick is multiplied by the press's expected crit factor 1 + crit_chance × (crit_mult − 1) (`Combat.expected_crit`, as `tools/gem_combo_sim.py`), and burn ticks use the rolled hit they came from, as today** (Task 5 review I3). They leech, and count kills for MP-on-kill. **Burn and fire-trail kills count too** (owner 2026-11-09: "นับทุกแบบ"). They heal and refund MP through the `ComboCast` of the press that applied them, still capped at 6 / 9 MP per press. They never trigger combo effects themselves: no trail, bounce, bolt, blast, freeze count or mark from a secondary hit. Per-line effects (trail, line-end blast) belong to primary arrows only (the ones `Hero._release` fires).
- **Save (risks.md S5/B14/B15):** `SaveGame.VERSION` stays **4**. Add an optional `"combos"` key: an Array of unique known recipe id Strings. Anything else fails the whole save (Q3 a). The signature covers it. A missing key loads as `[]`.
- **Art:** 0 PixelLab gen. Effects reuse the manifest ids `piercing_trail, spread_burst, chain_zap, hit_spark, water_ripple, status_burn, status_frost, lock_on, warp_ring, crit_hit, pickup_pop`, recoloured through `modulate` only. Record "M5b: 0 gen" in `docs/pixellab-budget.md`.
- **Copy (verbatim):** toast `ค้นพบท่าผสม!`, book title `สมุดสูตร`, undiscovered `???`. Skill panel §5 strings: see Task 11. Colours: gains `#6ccf62` (SkillPanel.UP), losses / MP up `#ff9d8a` (SkillPanel.DOWN), combo name and frame `#edbb55` (SkillPanel.GOLD).
- Rules live in `scripts/rules/` with no scene access (risks.md §3, server-portable). Everything stays client-side (S1). The final report must say that online play will need a server to decide this.
- Owner reports are in Thai, short and factual (CLAUDE.md).
- **Area skills (owner 2026-11-09, spec D1–D8):** numbers verbatim from docs/skills.md: ห่าศร (`arrow_rain`) unlock 7, circle r64, 3 s, a tick of 40% every 0.5 s (240% in all), CD 10, MP 18; กับดักหนาม (`thorn_trap`) unlock 10, placed ≤ 160 px, root 2 s + 150%, up to 2 placed, CD 8, MP 12; ศรเพลิง (`fire_arrow`) unlock 10, 200% + burn 20%/s for 3 s (= `elements.fire`), r32 blast on hit, CD 6, MP 14. Per-level scaling is the existing `skills.per_level_*`. Owner decisions: **D1** both Lv10 skills open at Lv10 (no job system yet); 4 skill buttons, assigned from the skill screen. **D2** auto-target the nearest monster (ห่าศร within 220 px, trap within 160 px); no monster → at the hero's feet. **D3** root stops movement only, a rooted monster in reach can still attack, windups are not cancelled, bosses and elites are rooted, roots don't stack, and a trap ignores a monster already rooted. **D4** a trap stays until stepped on, trigger radius 16 px (×1.3 with expand), max 2, cleared on room change / warp / hero death. **D5** ศรเพลิง blast r32 = 100% of that hit on the others, who also burn; range 220. **D6** extend: ห่าศร 3 → 3.9 s (whole ticks only: 7), trap root 2 → 2.6 s; ห่าศร range 220. **D7** an ice or lightning gem on ศรเพลิง **replaces** its own fire (no burn, that element's effect instead); a fire gem keeps the burn (×1.1, no double burn); the arrow's own fire never counts as a fire gem for recipes. **D8** 3-gem area recipes need skill Lv10 (char Lv16 ห่าศร / Lv19 กับดัก, ศรเพลิง), above the phase-1 cap: built and tested, ??? in the book.
- **Area hits:** rain ticks and trap triggers are **primary hits of the press**. They can crit, leech, apply the element gem's status and count kills through the press's `ComboCast`. They never produce arrow-only combo effects (trail, bounce, bolts, mark, freeze count, shatter). ศรเพลิง's own r32 blast is a secondary hit (`Arrow.blast`).
- **Area art:** the 2 icons and the ground trap sprite are the owner's PixelLab picks (30 gen, already logged). Paths are placeholder-tolerant. `Skills.icon(id)` returns `res://assets/skills/<id>.png` when `ResourceLoader.exists`, else `res://assets/skills/slot_empty.png`. The trap sprite is looked up at `res://assets/props/thorn_trap.png`, then `res://assets/fx/thorn_trap.png`; with neither present, `ThornTrap` draws a placeholder (brown ring + 6 spikes, marked as a placeholder in a comment). Tests pass with and without the files. After the coordinator installs the PNGs, run `godot --headless --path . --import` once before screenshots. Area effects reuse manifest ids: 0 gen.
- **Transient objects are never saved:** rains and traps are freed on room change, warp (`begin_warp`, like arrows' `halt()`, B20) and hero death.

## Review Focus

1. **A save with sockets on a skill that has no numbers or is still locked** (e.g. `"arrow_rain": [expand gem]`, which `_skills_ok` accepts today, or 3 gems on piercing at char Lv1). `Skills.unlock_level("arrow_rain")` asserts on a missing key. Loading must not crash, and the gems must go back to the bag (or stay inert if the bag is full). → Task 1 `test_after_load_returns_gems_from_unknown_and_closed_slots`.
2. **Several touches on one target in one press** (3 split lines through a boss, bounce arrows, overlapping trails). A reasonable player expects one shatter, one freeze and one trail tick per second, not three. → Task 4 `test_trail_does_not_stack`, Task 7 `test_anodard_shatters_once_per_target_per_press`, Task 7 `test_frost_freezes_once_on_third_hit`.
3. **A freeze landing during an attack windup** (lunge_warn / bite / ring / throw), or on a dying monster. The attack must not go off while the monster is frozen, the warning must hide, and a dead monster ignores the freeze. → Task 4 `test_freeze_cancels_windup_and_holds`.
4. **Previewing a gem when every open slot is full** (the panel replaces slot 1), or a swap that breaks a combo. The live title, gold frames and deltas must match what socketing would really do. → Task 11 `test_preview_full_slots_breaks_combo`.
5. **The save's discovered list**: an old v4 save without the key must load and quietly mark combos that its sockets already form (no toast storm on load). Unknown ids, duplicates or non-strings must fail the save. → Task 10 `test_old_v4_save_loads_and_marks_silently`, `test_bad_combos_refuse_save`.
6. **One cap per press across every kind of kill** (rain ticks, trap trigger, ศรเพลิง blast, burns and trails applied by the press). A ledger left behind on a burn must not give a second 6 / 9. → Task 8 `test_burn_kill_counts_and_shares_cap`, Task 8b `test_rain_kill_counts_for_sustain`.
7. **A rain or trap outliving a warp or room change** (B20). → Task 8b `test_rain_freed_on_warp`, Task 8c `test_traps_cleared_on_warp_death_room`.
8. **Gems on a new skill at the edge of its unlock** (ศรเพลิง gems in a Lv9 save must be refused, Lv10 accepted; `_skills_ok` is data-driven since Task 1: test it, don't assume it), and the `bar` key. → Task 8a `test_save_gems_on_new_skills`, Task 8e `test_bad_bar_refuses_save`.

---

## File Structure

| File | Responsibility |
|---|---|
| `data/balance.json` | `gem_slots` → `[1,1,10,50]`; new `gem_combos` {`_doc`, `recipes`: 16 rows in data order} |
| `scripts/rules/gem_combo.gd` (new, `GemCombo`) | Recipe data access, gem keys, `resolve`, effect text, area/zone helpers |
| `scripts/rules/combo_cast.gd` (new, `ComboCast`) | Per-press ledger: MP refund cap, hit counts, once-per-target, Rahu HP bonus |
| `scripts/rules/skill_text.gd` (new, `SkillText`) | Skill panel title / description / numbers with deltas (pure) |
| `scripts/rules/skill_build.gd` | Adds `combo`, combo stat effects |
| `scripts/rules/save_game.gd` | `combos` key: new_state, `_combos_ok`, load normalise |
| `scripts/hero/skills.gd` | `exists(id)` guard |
| `scripts/hero/hero.gd` | Open-slot builds, `return_closed_gems`, ComboCast per press, kill/crit hooks, discovery |
| `scripts/monsters/status_effects.gd` | freeze + lock, mark, trail burn, zone |
| `scripts/monsters/wolf.gd` | status API, freeze hold, taken multiplier, frost tint while frozen |
| `scripts/arrow.gd` | primary flag, combo on-hit dispatch, `blast`, `bolts`, chain bounces |
| `scripts/combo/fire_trail.gd` (new, `FireTrail`) | Ground fire line that applies trail burn |
| `scripts/fx/combo_fx.gd` (new, `ComboFx`) | Plays a recipe's tinted reuse effect for an event |
| `scripts/ui/skill_panel.gd` | Name above icon, live text, gold frames, toast, recipe book |
| `scripts/dev/test_ground.gd` | Save/load `combos`, `hero.after_load` |
| `tests/dummy_enemy.gd` | StatusEffects, die-on-hit, records crit chance |
| `tests/test_gem_combo.gd`, `test_combo_cast.gd`, `test_status_combo.gd`, `test_arrow_combos.gd`, `test_save_combos.gd`, `test_skill_text.gd`, `test_skill_panel_combos.gd` (new) | Tests per task |
| `tests/screenshots_m5b_combos.gd` (new) | Acceptance images → `docs/preview/m5b/` |
| `docs/gems.md`, `docs/superpowers/specs/2026-11-06-m3a-gems-enhance-design.md`, `docs/risks.md`, `docs/pixellab-budget.md`, `tools/gem_combo_sim.py` | Slot rule text, combos section, risks, budget |
| `data/balance.json` `skills.arrow_rain/thorn_trap/fire_arrow`, `skill_labels` | Area skill numbers (Task 8a) |
| `scripts/combat/skill_hit.gd` (new, `SkillHit`) | One hit from an area skill: crit, leech, element status, combo kill/crit hooks |
| `scripts/skills/arrow_rain.gd` (new, `ArrowRain`), `scripts/skills/thorn_trap.gd` (new, `ThornTrap`) | Rain circle ticks; trap trigger, root, spent sprite |
| `scripts/rules/trap_set.gd` (new, `TrapSet`) | At most `max_traps` armed traps, oldest removed |
| `scripts/ui/touch_buttons.gd`, `scripts/ui/hud.gd`, `project.godot` | 4-slot skill bar on touch and keys 1–4 |
| `docs/skills.md` | Dated note with the D1–D8 answers |
| `tests/test_area_skills.gd`, `tests/test_skill_bar.gd` (new) | Area skill and skill bar tests |

Task order puts what phase 1 can use first (piercing/spread recipes, Tasks 3–8). Then the three area skills and the skill bar (Tasks 8a–8e), then the area recipes on those real skills (Task 9). 8a needs only Tasks 1–2; 8b and 8c need Tasks 3, 4 and 8; 8d needs Task 5.

---

### Task 1: Every skill gets 2 slots from unlock; closed-slot gems go back to the bag

**Files:**
- Modify: `data/balance.json:478-483` (`gem_slots`)
- Modify: `scripts/hero/skills.gd` (add `exists`)
- Modify: `scripts/hero/hero.gd:137-145` (`build`, `gem_slots`), add `return_closed_gems`
- Modify: `scripts/ui/skill_panel.gd:278-279` (slot help text)
- Modify: `scripts/rules/save_game.gd:153-161` (`_skills_ok`: refuse two gems of one type in a skill)
- Modify: `tests/test_gem.gd:70-74`, `tests/test_hero_gems.gd:36`, `tests/test_save_hardening.gd` (new test)
- Modify: `docs/gems.md` §3 (table + phase-1 line), `docs/superpowers/specs/2026-11-06-m3a-gems-enhance-design.md:36` (add a "superseded 2026-11-08" note pointing to the combos spec), `tools/gem_combo_sim.py:133` (`slots()` → 2 from unlock, 3 at 10, 4 at 50)
- Test: `tests/test_gem.gd`, `tests/test_hero_gems.gd`

**Interfaces:**
- Consumes: `Gem.slots_for(skill_level: int) -> int` (unchanged code, new data)
- Produces: `Skills.exists(id: String) -> bool`; `Hero.open_gems(skill_id: String) -> Array` (sockets sliced to `gem_slots(skill_id)`, padded with nulls); `Hero.build(skill_id)` now uses `open_gems`; `Hero.return_closed_gems() -> int` (gems moved to the bag); `Hero.gem_slots(id)` returns 0 for a skill where `not Skills.exists(id)`

- [x] **Step 1: Write the failing tests**

```gdscript
# tests/test_gem.gd: replace test_slots_by_level
func test_slots_by_level():
	var want := {0: 0, 1: 2, 9: 2, 10: 3, 49: 3, 50: 4}
	for lv in want:
		if Gem.slots_for(lv) != want[lv]: return "slots_for(%d) = %d, want %d" % [lv, Gem.slots_for(lv), want[lv]]
	return ""

func test_new_slot_rule_never_closes_a_slot():   # owner 2026-11-09: the rule change only opens slots
	var old := [1, 10, 30, 50]
	for lv in range(0, 61):
		var n_old := 0
		for t in old: if lv >= t: n_old += 1
		if Gem.slots_for(lv) < n_old: return "skill Lv%d: %d < old %d" % [lv, Gem.slots_for(lv), n_old]
	return ""
```

```gdscript
# tests/test_hero_gems.gd: line 36 becomes
	elif h.socket("piercing", 2, 1) != "ช่องยังไม่เปิด": r = "slot 3 opens at skill level 10"
# new tests
func test_two_slots_from_unlock():          # Lv1 piercing and Lv3 spread both take 2 gems
	# h = _hero(3) with split + multiply in the bag: socket piercing 0 and 1 → "" ; spread 0 and 1 → "" ; piercing 2 → "ช่องยังไม่เปิด"
func test_slot_three_at_skill_level_ten():   # _hero(10): socket("piercing", 2, i) == ""; _hero(9): == "ช่องยังไม่เปิด"
func test_after_load_returns_gems_from_unknown_and_closed_slots():
	# _hero(1); set_skill_gems({"piercing": [split, multiply, execute], "arrow_rain": [expand]}); empty bag
	# return_closed_gems() == 2; skill_gems.piercing == [split, multiply] (index 2 now null or trimmed);
	# skill_gems.arrow_rain has no gems; bag holds gem_execute and gem_expand with their data unchanged
func test_closed_gem_stays_when_bag_full_and_is_inert():
	# bag filled to bag.slots; same sockets → return_closed_gems() == 0; piercing still has 3 gems;
	# is_equal_approx(h.build("piercing").mp, 8 * 1.4 * 1.5)   # execute (×1.2) in slot 3 ignored
```

```gdscript
# tests/test_save_hardening.gd: new test. A skill never holds two gems of one type in game (hero.gd:160);
# that includes two element gems (one element per skill, combo spec). A save that does is hand-made → refused (Q3 a).
func test_duplicate_gem_type_in_skill_refuses_save():
	# signed save, "skills": {"piercing": [element fire, element ice]} → load_or_new() == new_state(); same for [split, split]
```

- [x] **Step 2: Run them and check they fail**

Run: `TEST_ONLY=test_gem godot --headless --path . --script tests/run_tests.gd` and `TEST_ONLY=test_hero_gems ...`
Expected: FAIL `slots_for(1) = 1, want 2`; `return_closed_gems` not found.

- [x] **Step 3: Implement**

`gem_slots: [1, 1, 10, 50]`. Add `Skills.exists(id) -> bool` (= `Balance.has("skills.%s.unlock" % id)`). In `Hero.gem_slots`, return 0 when the skill does not exist. Add `Hero.open_gems`, and have `build()` use it. `return_closed_gems()` walks every skill in `skill_gems` from the highest index down. For each gem at an index ≥ `gem_slots(id)` it calls `inventory.add_gem(g)`. On success it sets that socket to null; on failure it leaves the gem there. It emits `gems_changed` if anything moved. `_skills_ok` keeps a per-skill set of gem types and returns false on a repeat. The game can't produce one, so no real save is lost (B14). The panel text becomes `"ช่องเจม: 2 ช่องตั้งแต่ปลดสกิล · ช่องที่ 3 ที่เลเวลสกิล %d · ช่องที่ 4 ที่เลเวลสกิล %d · ถอดเจมฟรี เจมเก็บ EXP ไว้"`, filled from `gem_slots[2]` and `gem_slots[3]`. Update docs/gems.md §3 to the 1/1/10/50 table, and replace its phase-1 note with "ศรทะลวงได้ 3 ช่องที่ตัวละคร Lv10 · สกิลอื่น 2 ช่อง". In the sim, `slots(L, s)` becomes `0 if sl < 1 else 2 + (sl >= 10) + (sl >= 50)`.

- [x] **Step 4: Run them and check they pass.** The same commands give `failed=0`. Then run the full suite to catch any other test that assumed 1 slot at Lv1 (`test_skill_panel`, `touch_check`). Fix those assertions to the new rule only.

- [x] **Step 5: Commit**

```bash
git add data/balance.json scripts/hero/skills.gd scripts/hero/hero.gd scripts/ui/skill_panel.gd scripts/rules/save_game.gd tests/test_gem.gd tests/test_hero_gems.gd tests/test_save_hardening.gd docs/gems.md docs/superpowers/specs/2026-11-06-m3a-gems-enhance-design.md tools/gem_combo_sim.py
git commit -m "M5b Task 1: 2 gem slots from unlock (slot 3 at skill Lv10), closed-slot gems back to the bag"
```

**Done (2026-11-09):** `gem_slots [1,1,10,50]`; `Skills.exists`; `Hero.open_gems` / `return_closed_gems` (build and gem EXP read open slots only; called after load in test_ground and when the skill screen opens); `socket` guards skills with no numbers; save `_skills_ok(sk, level)` refuses two gems of one type in a skill and gems on a skill that does not exist or is locked at the save's level (read from balance.json, so the M5b area skills need no code change); closed-slot gems in a save are kept (owner: never lost). Panel help = `SkillPanel.SLOT_HELP` (wraps), previews use open slots. Changed assertions (owner 2026-11-08 slot rule): test_gem `test_slots_by_level`, test_hero_gems line 36 (slot 3 instead of slot 2 closed at Lv1); test_save_hardening `_rich()` now fills distinct fitting types on existing skills only (it held 4 same-type gems per skill and gems on ห่าศร, which the game cannot make). New: test_gem 1, test_hero_gems 5, test_save_hardening 3, test_skill_panel 1, test_ground 1. Sim: 2-gem rows change (Lv5 ×1.44→×1.54 single target; Lv10 pack ×1.73→×1.77), 3-gem rows unchanged. Full suite: `RESULT passed=494 failed=0`. Risk B24 added.

---

### Task 2: Recipe data and the GemCombo resolver (all 16)

**Files:**
- Modify: `data/balance.json` (add `gem_combos`)
- Create: `scripts/rules/gem_combo.gd`
- Test: `tests/test_gem_combo.gd`

**Interfaces:**
- Consumes: `Gem.fits(type, skill_id)`, `Gem.display_name(type)`, `Balance.data()`
- Produces (`class_name GemCombo`, all static):
  - `recipes() -> Array` (rows in data order), `ids() -> Array`, `recipe(id: String) -> Dictionary` (`{}` if unknown)
  - `p(id: String, key: String, default := 0.0) -> float`
  - `gem_key(gem: Dictionary) -> String`: `gem.element` for `type == "element"`, otherwise `gem.type`
  - `key_name(key: String) -> String`: `"ธาตุ" + elements[key].name` for element keys, otherwise `Gem.display_name(key)`
  - `resolve(skill_id: String, gems: Array) -> Dictionary`: `{}` or `{"id": String, "tier": int, "name": String, "slots": Array}` (socket indices of the recipe's gems, ascending)
  - `describe(id: String) -> String`: the Thai effect line with numbers from data (used by the book and the panel)

Recipe row shape (`gem_combos.recipes[i]`):
`{"id", "tier": 2|3, "name", "gems": [keys], "bases": [ids] (tier 3 only), <numbers>, "fx": {event: [{"fx": manifest_id, "tint": "#rrggbb"}]}}`

Data order (phase-1 usable first): `fire_fan, thunder_hop, hawk_eye, bloodthirst, frost_shard, brahmastra, thousand_bolts, garuda, anodard, rahu, shockwave, hunter_zone, fire_burst, hellfield, earth_piercer, meteor_rain`.

- [x] **Step 1: Write the failing tests**

```gdscript
# tests/test_gem_combo.gd
const SPEC := {   # spec §1 and §2 at gem Lv1, verbatim
	"fire_fan":      {"tier": 2, "name": "ศรพัดเพลิง", "gems": ["split", "fire"], "trail_secs": 2.0, "trail_frac": 0.20},
	"thunder_hop":   {"tier": 2, "name": "ศรอสนีกระโดด", "gems": ["ricochet", "lightning"], "extra_bounces": 1, "bolts": 1, "bolt_frac": 0.50},
	"hawk_eye":      {"tier": 2, "name": "ศรตาเหยี่ยว", "gems": ["homing", "execute"], "homing_full": 1, "crit_bonus": 0.15, "mark_secs": 4.0, "mark_taken": 0.20},
	"bloodthirst":   {"tier": 2, "name": "ศรกระหายเลือด", "gems": ["leech", "multiply"], "leech_add": 0.03, "kill_heal_frac": 0.03, "kill_mp": 2, "kill_mp_cap": 6},
	"frost_shard":   {"tier": 2, "name": "ศรเกล็ดน้ำแข็ง", "gems": ["ice", "split"], "freeze_hits": 3, "freeze_secs": 1.0, "freeze_lock_secs": 5.0, "bonus_vs_chilled": 0.25},
	"shockwave":     {"tier": 2, "name": "ศรคลื่นกระแทก", "gems": ["pierce", "expand"], "blast_on_pierce": 1, "blast_radius": 32, "blast_frac": 0.80},
	"hunter_zone":   {"tier": 2, "name": "อาณาเขตพราน", "gems": ["expand", "extend"], "zone_slow": 0.30, "zone_taken": 0.10},
	"fire_burst":    {"tier": 2, "name": "ศรเพลิงระเบิด", "gems": ["fire", "expand"], "area_radius_bonus": 0.20, "burn_all": 1},
	"brahmastra":    {"tier": 3, "name": "พัดเพลิงพรหมาสตร์", "gems": ["split", "fire", "multiply"], "bases": ["fire_fan"], "trail_secs": 3.0, "trail_frac": 0.30, "blast_on_line_end": 1, "blast_radius": 32, "blast_frac": 0.50},
	"thousand_bolts":{"tier": 3, "name": "ศรอสนีพันสาย", "gems": ["ricochet", "lightning", "split"], "bases": ["thunder_hop"], "bolts": 2, "bolt_frac": 0.50},
	"garuda":        {"tier": 3, "name": "ศรเนตรพญาครุฑ", "gems": ["homing", "execute", "multiply"], "bases": ["hawk_eye"], "homing_full": 1, "crit_bonus": 0.15, "mark_secs": 4.0, "mark_taken": 0.30, "sure_crit_marked": 1},
	"anodard":       {"tier": 3, "name": "ศรผลึกอโนดาต", "gems": ["ice", "split", "execute"], "bases": ["frost_shard"], "freeze_hits": 3, "freeze_secs": 1.0, "freeze_lock_secs": 5.0, "sure_crit_chilled": 1, "blast_on_chilled": 1, "blast_radius": 32, "blast_frac": 0.50},
	"rahu":          {"tier": 3, "name": "ศรราหูอมจันทร์", "gems": ["leech", "multiply", "execute"], "bases": ["bloodthirst"], "hp_min": 0.70, "hp_bonus": 0.30, "leech_add": 0.03, "crit_heal_frac": 0.01, "kill_mp": 3, "kill_mp_cap": 9},
	"hellfield":     {"tier": 3, "name": "ทุ่งเพลิงบรรลัยกัลป์", "gems": ["expand", "extend", "fire"], "bases": ["hunter_zone", "fire_burst"], "zone_slow": 0.30, "zone_taken": 0.20, "burn_all": 1},
	"earth_piercer": {"tier": 3, "name": "ศรอัคนีทะลวงพิภพ", "gems": ["pierce", "expand", "fire"], "bases": ["shockwave", "fire_burst"], "blast_on_pierce": 1, "blast_radius": 40, "blast_frac": 1.00, "blast_burn": 1},
	"meteor_rain":   {"tier": 3, "name": "ฝนดาวไฟ", "gems": ["split", "fire", "expand"], "bases": ["fire_fan", "fire_burst"], "blast_on_hit": 1, "blast_radius": 40, "blast_frac": 0.80},
}
func test_recipes_match_spec()            # 16 rows, ids() in the data order above, each SPEC key equal (floats is_equal_approx)
func test_bases_are_subsets()             # every tier-3 base exists, is tier 2, and its gems ⊂ the tier-3 gems
func test_every_recipe_formable()         # each recipe's gems fit at least one label set in {["arrow"], ["area","dot"], ["trap","area"], ["arrow","area"]}
func test_no_three_gem_collision()        # every legal 3-key set (distinct, ≤1 element) holding ≥2 tier-2 recipes equals a tier-3 recipe (spec "กติกาเสริม")
func test_gem_key_maps_elements()         # gem_key({type:"element", element:"ice"}) == "ice"; gem_key({type:"split"}) == "split"; key_name("fire") == "ธาตุไฟ"
func test_resolve_two()                   # resolve("piercing", [split, element fire]) == {"id":"fire_fan","tier":2,"name":"ศรพัดเพลิง","slots":[0,1]}
func test_resolve_three_replaces_base()   # [split, fire, multiply] → id "brahmastra", tier 3, slots [0,1,2]
func test_resolve_order_and_nulls()       # [null, fire, split] → fire_fan slots [1,2]; all 6 orders of the brahmastra gems → "brahmastra"
func test_resolve_ignores_unfit_and_junk()# piercing [expand, extend] → {}; [ {} , "x", 3 ] → {} with no error; [split] → {}
func test_resolve_extra_gem_keeps_combo() # [split, fire, leech] → fire_fan, slots [0,1]
func test_four_gems_one_combo()           # piercing [homing, execute, multiply, leech] → id "garuda" (tier 3, first in data order), never two
func test_describe_has_numbers()          # describe("fire_fan") contains "2 วิ" and "20%"; describe("rahu") contains "70%" and "9"
```

For area recipes, the tests add `Balance.data()["skill_labels"]["test_fire_arrow"] = ["arrow", "area"]`, call `Balance.clear_cache()`, and remove the key at the end.

- [x] **Step 2: Run and check it fails.** `TEST_ONLY=test_gem_combo ...` → FAIL, "GemCombo" not declared.

- [x] **Step 3: Implement.** Add the `gem_combos` block with exactly the SPEC values and the fx rows from Task 5's table. Write `GemCombo` with the signatures above. `resolve` keeps only Dictionary gems that fit, maps them to keys, and picks the first tier-3 recipe in data order whose keys ⊆ the set. If there is none, it picks the first tier-2 recipe the same way. `slots` = indices of the gems whose keys are in the recipe. `describe` builds its text from the row's numbers: one `match` on id, with the sentences taken from the spec's ผลพิเศษ/ผล columns.

- [x] **Step 4: Run and check it passes.** `TEST_ONLY=test_gem_combo` → `failed=0`. Also run `TEST_ONLY=test_balance` so the JSON still parses.

- [x] **Step 5: Commit** `git commit -m "M5b Task 2: gem combo recipes (16) in balance.json + GemCombo resolver"`

**Done (2026-11-09):** `balance.json gem_combos` (`_doc` + 16 `recipes` in book order; every number = spec §1/§2 at gem Lv1; tier-3 rows carry only their own row's numbers, owner ②; `fx` rows from the Task 5 table, all ids checked against `assets/fx/manifest.json`, `#ffffff` = no recolour; the lightning rows use `bounce` → hit_spark and `bolt` → chain_zap so พันสาย plays chain_zap once per bolt). `scripts/rules/gem_combo.gd` (`GemCombo`, static, no scene access): `recipes`, `ids`, `recipe`, `p`, `gem_key`, `key_type` (added: "fire" → "element", for `Gem.fits`), `key_name` (drops the item name's "เจม" prefix so the book reads "แยกศร + ธาตุไฟ"), `resolve(skill_id, gems) -> {} | {id, tier, name, slots}` (ignores non-Dictionaries, unfit gems, element gems with no element and repeated keys; ignores gem level; highest tier, then book order), `describe` (no boss-slow clause on the frost rows). Callers pass `hero.open_gems(id)`. `tests/test_gem_combo.gd` (15, all new): the plan's 12 plus `test_spot_check_against_spec_text`, `test_combo_flat_at_any_gem_level`, `test_closed_slot_gem_never_forms_a_combo`; 4-gem cases: homing+execute+multiply+leech → garuda; split+fire+expand+pierce on an arrow+area skill → earth_piercer; two tier-2 candidates → the earlier book row. `test_no_three_gem_collision` counts only sets some label set can hold (pierce+expand+extend holds shockwave + hunter_zone but fits no skill). Seen failing first ("GemCombo" not declared); mutation check (one number changed, tie-break flipped) failed 2 tests as expected. No existing assertion changed. Full suite: `RESULT passed=509 failed=0`.

---

### Task 3: SkillBuild combo stats and the ComboCast per-press ledger

**Files:**
- Modify: `scripts/rules/skill_build.gd`
- Create: `scripts/rules/combo_cast.gd`
- Test: `tests/test_combo_cast.gd`; add to `tests/test_skill_text.gd` later. Build tests go in `tests/test_gem_combo.gd` (section "build").

**Interfaces:**
- Consumes: `GemCombo.resolve`, `GemCombo.p`
- Produces:
  - `SkillBuild.of(...)` gains output keys `"combo": Dictionary` (the resolve result) and `"extra_bounces": int`. `crit` adds `crit_bonus`. `leech` adds `leech_add` (owner 2026-11-09: the leech gem's own leech + a flat 3 %; was `leech_mult` ×2 before the Task 2 review). With `homing_full`, homing does not multiply `per_arrow`. `mp` is unchanged by combos.
  - `class_name ComboCast extends RefCounted`: `func _init(id := "", hp_frac := 1.0)`, `var id: String`, `func dmg_bonus() -> float` (Rahu: `hp_bonus` if `hp_frac >= hp_min`, else 0), `func refund_mp(per_kill: int) -> int` (granted after the cap), `func count_hit(target_key: int) -> int` (returns the new count), `func once(tag: String, target_key: int) -> bool`. Task 3 review (done in Task 4): `static func from_build(b: Dictionary, hp_frac := 1.0) -> ComboCast` (numbers from `b.combo_p`, the press's single source; use it in `Hero._release`), `func refund_kill() -> int` (this press's stored `kill_mp` under the cap; Task 8 calls it instead of `refund_mp(int(kill_mp))`), `once` keyed by tag then target (no string per call)

- [x] **Step 1: Write the failing tests**

```gdscript
# build (char Lv10, gem Lv1, no options, hero_stats {"crit": 0.05, "element_dmg": 0.0, "skill_cd_cut": 0.0})
func test_build_spec_section5_numbers():  # piercing [split]: arrow_mult≈1.566 mp≈11.2 combo {} ; [split, fire]: 1.7226, 14.56, combo.id "fire_fan"; [split, fire, multiply]: 2.32551, 21.84, "brahmastra"
func test_combo_adds_no_mp():             # for every recipe formable on piercing: mp == 8 × Π gem mp multipliers (is_equal_approx)
func test_hawk_eye_homing_full_crit():    # [homing, execute] Lv1: arrow_mult ≈ Skills.damage_mult("piercing",1) (no ×0.9); crit ≈ 0.05+0.15+0.15
func test_homing_alone_keeps_penalty():   # [homing]: arrow_mult ≈ 1.8 × 0.9
func test_sustain_leech_is_gem_plus_flat_three(): # [leech, multiply] Lv1 leech ≈ 0.03 + 0.03 = 0.06; leech gem Lv5 → ≈ (0.03+0.004) + 0.03 (owner 2026-11-09: leech_add, not ×2)
func test_thunder_hop_extra_bounce():     # [ricochet, lightning] extra_bounces == 1; [ricochet, lightning, split] (thousand_bolts) extra_bounces == 0
# tests/test_combo_cast.gd
func test_bloodthirst_refund_caps_at_6(): # c = ComboCast.new("bloodthirst"); [c.refund_mp(2) ×4] == [2,2,2,0]
func test_rahu_refund_caps_at_9():        # ComboCast.new("rahu"): refund_mp(3) ×4 == [3,3,3,0]
func test_no_combo_no_refund():           # ComboCast.new("").refund_mp(2) == 0; ComboCast.new("fire_fan").refund_mp(2) == 0
func test_once_per_target():              # once("shatter", 7) true, again false; once("shatter", 8) true; once("freeze", 7) true
func test_count_hit():                    # count_hit(5) → 1, 2, 3; count_hit(6) → 1
func test_rahu_hp_threshold():            # ComboCast.new("rahu", 0.70).dmg_bonus() ≈ 0.30; 0.69 → 0.0; ComboCast.new("garuda", 1.0) → 0.0
```

- [x] **Step 2: Run and check they fail** (`TEST_ONLY=test_combo_cast`, `TEST_ONLY=test_gem_combo`).
- [x] **Step 3: Implement** the changes and the class as listed. The refund cap comes from `GemCombo.p(id, "kill_mp_cap")`, and the per-kill amount from `p(id, "kill_mp")`. `refund_mp` takes the per-kill amount so Task 8 can pass it in.
- [x] **Step 4: Run and check they pass.** Then run the full suite: `test_hero_gems`, `test_arrow_gems` and `test_skill_panel` must stay green, because a build without a combo is unchanged.
- [x] **Step 5: Commit** `git commit -m "M5b Task 3: SkillBuild combo stats + ComboCast per-press ledger (MP-on-kill caps 6/9)"`

**Done (2026-11-09):** Owner 2026-11-09 (Task 2 review): `balance.json` bloodthirst / rahu `leech_mult: 2.0` → `leech_add: 0.03` (the leech gem's own leech + a flat 3 %: 6 % at gem Lv1, 7.9 % at Lv20), `describe()` now reads "ดูดเลือด… +3% (บวกกับเจมดูดเลือด)". `GemCombo`: id → row map rebuilt only when the recipe list itself is replaced (`recipe` / `p` allocate nothing), new `numbers(id)` (a float copy of a row's numbers). `SkillBuild.of` adds `combo` (= `GemCombo.resolve`, unchanged), `combo_p` (= `GemCombo.numbers`, copied once per press, so Task 4+ hits read the build, not the data) and `extra_bounces`; `crit` + `crit_bonus`; `leech` + `leech_add`; `homing_full` drops the homing ×0.9; `mp` unchanged. `scripts/rules/combo_cast.gd` (`ComboCast`, RefCounted, pure): `_init(id, hp_frac)` copies kill_mp / kill_mp_cap / kill_heal_frac / crit_heal_frac / rahu hp bonus once; `refund_mp(per_kill)` (granted after the per-press cap, 0 for junk), `mp_refunded()`, `count_hit`, `once`, `dmg_bonus`. Plan test `test_bloodthirst_doubles_leech` became `test_sustain_leech_is_gem_plus_flat_three` (owner decision). New tests: test_gem_combo +11 (the plan's build tests, `test_build_carries_combo_and_numbers`, `test_combo_values_flat_at_any_gem_level_in_build` (every arrow recipe, gem Lv1 vs Lv20: combo numbers equal, the build's crit/leech minus the gems' own part = the flat combo value), `test_hero_build_reads_open_slots_only`, `test_every_combo_reader_uses_open_gems` (source guard: no `SkillBuild.of` / `GemCombo.resolve` fed from `skill_gems`), `test_recipe_lookup_cache`); test_combo_cast 10 (the plan's 6 + partial/junk refund, numbers copied at press, presses separate, `test_refund_cap_below_press_cost`). Changed assertions: test_gem_combo SPEC rows bloodthirst / rahu (`leech_add` instead of `leech_mult`) and `test_describe_has_numbers` (+3 %, no ×), both owner 2026-11-09. Seen failing first (ComboCast not declared; leech 0.03 vs 0.06; homing 2.349 vs 2.61). Mutation checks: leech scaling with gem level → 2 fails; `hero.build` on raw sockets → 2 fails. Full suite: `RESULT passed=530 failed=0`. Risk B25 added.

---

### Task 4: Monster statuses: freeze (with lock), mark, trail burn, zone

**Files:**
- Modify: `scripts/monsters/status_effects.gd`, `scripts/monsters/wolf.gd` (status API near :186, `receive_hit` :213, `tick_burn` :345, `step` :354, `status_tint` :298, `_update_status_fx` :290)
- Modify: `tests/dummy_enemy.gd`
- Test: `tests/test_status_combo.gd`

**Interfaces:**
- Produces on `StatusEffects`: `apply_freeze(secs: float, lock_secs: float) -> bool` (false while locked or already frozen); `is_frozen() -> bool`; `apply_mark(taken: float, secs: float)` (keeps the highest `taken` while active and refreshes the time); `is_marked() -> bool`; `apply_trail(per_tick: float, hold: float, source: Object)` (keeps the highest per_tick; burns while `hold` > 0; ticks every `elements.fire.tick`); `apply_zone(slow: float, taken: float, hold: float)`; `taken_mult() -> float` = 1 + mark + zone_taken (owner 2026-11-09: mark and zone ADD, +50 % not ×1.56; was (1 + mark) × (1 + zone_taken)); `speed_mult()` = 0 when frozen, otherwise (1 − ice slow if slowed) × (1 − zone slow if in zone); `tick()` returns burn + trail damage; `clear()` clears everything.
- Produces on `Wolf` (and the same names on `tests/dummy_enemy.gd`): `apply_freeze(secs, lock_secs) -> bool`, `apply_mark(taken, secs)`, `apply_trail(raw_per_tick, hold, source)` (applies its own DEF: per_tick = raw × (1 − def/(def+100))), `apply_zone(slow, taken, hold)`, `is_frozen()`, `is_chilled()` (slowed or frozen), `is_marked()`. `receive_hit` multiplies `mult` by `status.taken_mult()`. Burn and trail ticks are multiplied by it too.

- [x] **Step 1: Write the failing tests**

```gdscript
func test_freeze_once_per_lock():          # s.apply_freeze(1.0, 5.0) true; tick(0.5); apply → false; tick(0.5): not frozen; tick(3.9): apply false; tick(0.2): apply true
func test_frozen_speed_zero():             # frozen: speed_mult() == 0.0; after thaw with ice slow 0.4 and zone 0.3: ≈ 0.6 × 0.7
func test_mark_keeps_highest():            # apply_mark(0.2,4); apply_mark(0.3,4) → taken_mult ≈ 1.3; apply_mark(0.2,4) → still 1.3; tick(4.01) → 1.0
func test_trail_does_not_stack():          # apply_trail(10, 0.25, null) ×3 then tick(1.0) == 10 (not 30); with burn 5 → 15
func test_freeze_cancels_windup_and_holds():
	# a boar (lunge) in "lunge_warn" with the telegraph visible → apply_freeze(1.0, 5.0)
	# → telegraph_visible() == false, state not in attack states, position unchanged after step(0.5),
	#   the hero takes no damage during the freeze; after step(0.6) it moves again
func test_elite_freezes_too():             # set_elite(true): apply_freeze(1.0, 5.0) == true, is_frozen()
func test_dead_monster_ignores_freeze():   # health to 0 → apply_freeze returns false; status_tint() alpha 0
func test_marked_wolf_takes_20pct_more():  # two wolves with the same Combat.rng seed; one apply_mark(0.2, 4): dealt ≈ round(plain × 1.2) (±1)
func test_frozen_tint_is_frost():          # while frozen, status_tint() == frost tint (same as slowed)
```

- [x] **Step 2: Run and check it fails** (`TEST_ONLY=test_status_combo`).
- [x] **Step 3: Implement.** In `Wolf.step`, after `_update_status_fx()`, a frozen monster gets `velocity = Vector2.ZERO` and the body animation paused; the step returns before the state `match` (cooldowns still tick). `apply_freeze` on a monster in an attack windup (any of `_fight_states()` other than chase) ends it: `_end_lunge()`, `_show_telegraph(false)`, state set to `"chase"`, and its attack cooldown is left as it was. Frost FX and tint show while frozen. `Monster.step` (monster.gd:148) gets no special case, since its windups go through `super.step`. Check ring and throw too, and cancel their telegraphs the same way.
- [x] **Step 4: Run and check it passes.** Run `TEST_ONLY=test_status_combo`, then `test_monsters`, `test_elite` and the tint tests (`test_frost_tint_reads_as_ice_on_every_monster`) to catch regressions.
- [x] **Step 5: Commit** `git commit -m "M5b Task 4: freeze (5 s lock, bosses too), mark, non-stacking trail burn, zone statuses"`

**Done (2026-11-09):** `StatusEffects` (pure): `apply_freeze(secs, lock, cast) -> bool` (lock per target, counted from the freeze, max(lock, secs); refused while frozen/locked), `is_frozen`, `apply_mark` (highest taken kept, any re-mark refreshes the time), `is_marked`, `apply_trail(per_tick, hold, source, cast)` (highest per_tick while held; first tick on contact, then every `elements.fire.tick`, never more often, stepping out and back in included), `in_trail`, `apply_zone` (highest slow / taken while held), `in_zone`, `taken_mult()` = (1+mark)(1+zone) applied to hits and to burn/trail ticks, `speed_mult()` 0 when frozen; every status keeps the `ComboCast` of the press that applied it (`burn_cast`, `trail_cast` = newer application like `burn_source`; `freeze_cast` = first, a refused freeze keeps it; `mark_cast`, `zone_cast`); `tick_cast` / `tick_source` = the ONE ledger + source of the DoT that dealt the last tick (larger tick, ties burn; `clear()` leaves them so the Task 8 kill hook reads them after the killing tick). `Wolf`: `apply_freeze` (dead → false; ends any windup in `_fight_states()` except chase: `_end_lunge`, telegraph/ring hidden, state chase, cooldowns untouched), `apply_mark`, `apply_trail` (own DEF, no roll), `apply_zone`, `is_frozen`, `is_chilled`, `is_marked`, `apply_status(..., cast)`; `receive_hit` × `taken_mult()`; a frozen `step` holds (velocity 0, body paused, flash still shown, cooldowns tick, no state change, no throw) and returns before the state match; frost tint + frost overlay while frozen (frost-wins and PerfSaver shedding unchanged). No monster script may override the freeze (owner: bosses freeze too; there is no boss monster yet). `tests/dummy_enemy.gd`: same status API on a real `StatusEffects` (+ `def`, `freezes`, `statuses`, `tick_status`); `receive_hit` unchanged. Task 3 review follow-ups: M1 `GemCombo` cache also rebuilds when the list is resized in place (row `id`s are never edited in place: documented); M3 `ComboCast.once` keyed tag → target (no string per call); M4 `refund_kill()` (stored kill_mp, shares the cap with `refund_mp`, kept); M5 `ComboCast.from_build(b, hp_frac)` reads `b.combo_p` (`_init` takes an optional numbers dict); M6 plan text (Task 2 SPEC, Task 3 interfaces/test name → `leech_add`), Task 8 text now uses `from_build` / `refund_kill` / `tick_cast`; Task 10 / 11 gained the closed-slot behaviour tests and the widened open-gems guard (to implement there: skill_panel.gd still reads `hero.skill_gems` at 4 places). New tests: test_status_combo 21 (the plan's 9 + ring/throw cancel, re-entry tick, zone, DoT × taken, casts, tick_cast, clear, no-override guard, frozen overlay + saver, trail DEF, trail tick damage, dummy API), test_combo_cast +3, test_gem_combo +1. Plan wording changed in one test: after the thaw the boar "acts again" (moves or starts a new windup) instead of "moves", because its lunge cooldown is left as it was (0) so it re-warns at once. No existing assertion changed. Seen failing first (missing API / from_build / cache missed append); mutation checks: no frozen hold → 2 fails, no windup cancel → 2, trail `+=` → 1, re-entry tick → 1, no taken_mult on hits → 1. Full suite: `RESULT passed=555 failed=0` (530 + 25 new; a first run had 554/1: `test_waypoints::test_travel_rerolls_and_lands_by_the_stone` "current-room trip kept the same piles", a timing flake (global RNG drawn by monsters during a real-time fade); passed 3/3 alone and in the clean rerun; no shared code). Risk B26 added, B25 updated.

**Done — Task 4 review fixes (2026-11-09):** **I1** a burn's `burn_leech` / `burn_source` end with the burn and in `clear()`; `tick()` exposes each DoT's part of the step (`last_burn_dmg/leech/source`, `last_trail_dmg/leech/source`) and `Wolf.tick_burn` leeches each part with its own fraction to its own source, read before the damage (a killing tick clears the statuses). Reading: Global Constraints says trail ticks are hits of their press that "can … leech"; Task 8 only removes the crit from DoT ticks; the leech gem is "3 % of damage dealt"; so a trail leeches with its **own** press's leech (`apply_trail(..., cast, leech := 0.0)` on StatusEffects / Wolf / dummy; Task 5 text updated to pass `build.leech`), never the burn's. **I2** trail ticks are burn-style: one tick at the end of each full `elements.fire.tick` in the fire; the in-fire clock continues across exits shorter than the hold and restarts when the hold runs out → a stationary target gets exactly round(secs / tick) ticks per **isolated** trail (fire_fan 2, brahmastra 3, = tools/gem_combo_sim.py; Task 4 review, Task 5: back-to-back or overlapping trails share the target's one clock, at most 1 tick/s in all, with the highest per_tick and the newest application's ledger / leech / source, risks.md B26), provided hold 0.25 + the arrow's flight past it (≤ 0.61 s) < 1 s; a monster crossing a line in < 1 s (hold included) takes no trail tick (was: one on contact). **M1** owner "ไม่กระเด็น ติดอยู่กับที่": `Wolf._push` does nothing while frozen (knockback and the crowd), `receive_hit` skips knockback while frozen, `WolfPack._separate` never moves a frozen monster (others still move off it). **M2** the no-override guard scans scripts/monsters recursively + any script extending a monster, and also flags `_hold_frozen` / `_push` / `push`; new guard: every state a monster script (with its base scripts) assigns is in its `_fight_states()` or is idle / dead / return / flee. **M3** B26's "ledger held ≤ 3 s" corrected (held while the status lasts, refreshed by re-application; a DoT kill's `tick_cast` stays on the dead monster until its next status tick or it is freed). **M4** both DoTs ticking on a step: a ledger that still pays (MP under its cap, or a kill heal) beats a 0-MP one; both / neither pay → larger tick, ties burn (one ledger per step, a kill pays once). **M6** the windup test's frozen window is warning + lunge + 0.3 s (freeze warning + lunge + 0.5 s), hero damage checked first; the post-thaw check is `moved ≥ 0.5 px or state in lunge_warn / lunge / bite`. **Flake** `test_waypoints::test_travel_rerolls_and_lands_by_the_stone`: asserts the seed changed and the piles equal `rooms.piles("c2r0", groups, room_seed(pile_seed, "c2r0"))`; "different homes" only when the two seeds' bank entries differ (game re-roll unchanged). Mark × zone left as is (owner undecided). Tests: test_status_combo +7 (`test_trail_ticks_match_the_sim`, `test_dot_kill_credits_the_paying_ledger`, `test_burn_leech_ends_with_the_burn`, `test_wolf_leeches_each_dot_part_only`, `test_frozen_monster_is_not_knocked_back`, `test_frozen_monster_is_not_pushed_by_the_crowd`, `test_every_attack_state_is_a_fight_state`); changed: `test_trail_ticks_once_a_second_on_reentry` (approved-number fix: 2 s at the line's edge = 2 ticks, re-entry after the hold = no early tick), `test_wolf_trail_tick_damages` (no tick before 1 s, then one; no knockback), `test_tick_cast_names_one_ledger` (two 0-MP ledgers; the paying case moved to the M4 test), the windup test and `test_no_monster_opts_out_of_freeze` (tightened / widened). None loosened. Seen failing first (8 fails before the fix); mutation checks: freeze that cancels the windup but does not hold → "the hero was hit by a frozen boar" (the old 0.5 s window could not catch it), no frozen push guard → both M1 tests, `hop` removed from `_fight_states` → fight-state guard, a boss in scripts/monsters/bosses/ overriding apply_freeze → no-override guard, a script elsewhere entering `slam_warn` → fight-state guard; waypoints: a forced same-bank-entry re-roll fails the old assertion ("bank entries 28 → 28") and passes the new one. Full suite: `RESULT passed=562 failed=0`. Risk B26 updated.

---

### Task 5: Combo FX helper, primary arrows, fire trail and line-end blast (ศรพัดเพลิง, พัดเพลิงพรหมาสตร์)

**Files:**
- Create: `scripts/fx/combo_fx.gd`, `scripts/combo/fire_trail.gd`
- Modify: `scripts/arrow.gd` (`primary`, `_combo_on_hit`, `_secondary_hit`, `blast`, trail ownership in `launch` / `_finish`), `scripts/hero/hero.gd:545-583` (`_release` creates `ComboCast`, puts it in `b["cast"]`, sets `a.primary = true`; rahu's `dmg_bonus` multiplies the arrow mult)
- Modify: `data/balance.json` `gem_combos.recipes[*].fx` (the table below)
- Test: `tests/test_arrow_combos.gd`

FX reuse table (spec "เอฟเฟกต์ที่ใช้ซ้ำ"; tints are Claude-chosen hex values for the spec's colour words):

| recipe | event → fx (tint) |
|---|---|
| fire_fan / brahmastra | trail → fire_trail (PixelFX T2 fire/campfire, owner 2026-11-09; was piercing_trail #ff8a3d + status_burn); brahmastra line_end → fire_blast (PixelFX B2 explosions/grenade; was spread_burst #ff8a3d) |
| thunder_hop / thousand_bolts | bounce → chain_zap + hit_spark (#7fd4ff); thousand_bolts plays chain_zap once per bolt |
| shockwave / earth_piercer | blast → water_ripple (#fff1e0); earth_piercer adds spread_burst (#ff8a3d) + status_burn |
| hawk_eye / garuda | mark → lock_on (garuda #edbb55); crit → crit_hit |
| hunter_zone / hellfield | zone → warp_ring (#6ccf62; hellfield #ff8a3d) + hellfield status_burn |
| frost_shard / anodard | trail → piercing_trail (#7fd4ff); freeze → status_frost; anodard shatter → spread_burst (#7fd4ff) |
| bloodthirst / rahu | hit → hit_spark (#ff4a4a; rahu #6a2a8a); kill → pickup_pop (same tint) |
| fire_burst / meteor_rain | blast → spread_burst (#ff8a3d) + status_burn |

**Interfaces:**
- Consumes: `ComboCast`, `GemCombo.p`, `StatusEffects`/Wolf `apply_trail`
- Produces: `ComboFx.play(parent: Node, combo_id: String, event: String, at: Vector2) -> Array` (the FxSprites it spawned; `[]` when there is no entry or PerfSaver sheds it); `FireTrail` (`extends Node2D`): `setup(from: Vector2, atk: float, mult: float, frac: float, secs: float, targets: Array, source: Node)`, `extend_to(p: Vector2)`, `finish()` (starts the `secs` countdown, then frees itself), `step(delta: float)` (callable without a tree); `Arrow.primary: bool`; `Arrow.blast(at: Vector2, radius: float, frac: float, burn: bool, include: Node2D = null, skip: Array = []) -> int` (number of targets hit; secondary hits); `Arrow._secondary_hit(t: Node2D, frac: float) -> int`

- [x] **Step 1: Write the failing tests**

```gdscript
func test_every_recipe_fx_exists():        # for all recipes, all events: fx id in FxSprite._manifest(), Color.html_is_valid(tint)
func test_fire_fan_trail_20pct_2s():       # primary arrow with build of piercing [split, fire] Lv1 crossing a DEF-0 dummy: dummy received apply_trail(raw ≈ 0.20 × atk × arrow_mult);
                                            # the trail exists for 2.0 s after the arrow is spent, then frees (step it without a tree)
func test_brahmastra_trail_30pct_3s():     # [split, fire, multiply]: raw ≈ 0.30 × atk × arrow_mult, lifetime 3.0 s
func test_three_trails_burn_once_per_sec():# 3 split lines through one dummy near the origin: dummy HP loss over 1.0 s == one trail tick
func test_brahmastra_line_end_blast():     # each of the 3 lines blasts once at its end: a dummy 31 px from a line end gets one hit with mult ≈ arrow_mult × 0.50; one at 33 px gets none; 3 blasts total
func test_secondary_hits_trigger_nothing():# brahmastra + ricochet gem: blast hits spawn no Arrow (spawned signal count 0 from blasts), no new FireTrail
func test_bounce_arrows_lay_no_trail():    # fire_fan + ricochet: the bounce arrow's primary == false and it creates no FireTrail
func test_no_combo_arrow_unchanged():      # build without a combo: no FireTrail, no blast (existing test_arrow_gems stay green)
```

- [x] **Step 2: Run and check it fails** (`TEST_ONLY=test_arrow_combos`).
- [x] **Step 3: Implement.** A primary arrow whose `build.combo` has `trail_secs` creates one FireTrail at launch, calls `extend_to` every advance, and calls `finish()` in `_finish`/`halt`. `halt()` (warp) frees the trail immediately so no damage happens after the warp (B20). The trail damages targets within `t.hurt_radius()` (else `shot.arrow_hit_radius`) of the segment by calling `t.apply_trail(frac × atk × mult, 0.25, source, build.cast, build.leech)` each step (Task 4 review: a trail tick leeches its own press's leech, never a burn's; it ticks at the end of each full second in the fire, so a stationary target gets exactly 2 / 3 ticks per isolated trail as simulated (back-to-back trails share one clock: at most 1 tick/s), which needs hold 0.25 + the arrow's flight past it < 1 s: keep the hold at 0.25 and add that count to `test_fire_fan_trail_20pct_2s` / `test_brahmastra_trail_30pct_3s`; `test_three_trails_burn_once_per_sec` reads the HP loss over 1.0 s + one frame). `blast_on_line_end` → `blast(position, r, frac, false)` once in `_finish`, primary arrows only. `_secondary_hit` calls `t.receive_hit(atk, mult × frac, at, crit_chance, crit_mult)` and then `_leech` and the kill hook from Task 8. It never calls `_after_hit`.
- [x] **Step 4: Run and check it passes.** Run `TEST_ONLY=test_arrow_combos`, then `test_arrow_gems` and `test_hero_gems`.
- [x] **Step 5: Commit** `git commit -m "M5b Task 5: combo FX reuse + fire trail and line-end blast (ศรพัดเพลิง, พรหมาสตร์)"`

**Done (2026-11-09):** `scripts/fx/combo_fx.gd` (`ComboFx.play(parent, combo_id, event, at, dir := ZERO, decor := true) -> Array`: the recipe's `fx` rows as reused manifest effects, tint by `modulate` only (parsed once), `piercing_trail` turned along the line; PerfSaver sheds `PerfSaver.DECORATIVE` extras or plays their fallback (crit_hit → hit_spark), never the streak or a blast; 0 gen). `scripts/combo/fire_trail.gd` (`FireTrail`: `setup(from, atk, mult, frac, secs, targets, source, cast, leech, combo)`, `extend_to`, `finish`, `step` (no tree needed, allocates nothing), `halt`; applies `apply_trail(frac × atk × mult, HOLD 0.25, shooter, build.cast, build.leech)` to targets within hurt_radius of the line; z −5 like hazard clouds; look = ≤ 6 streaks every 44 px as the line grows + a flame on marks 1/3/5 (`MAX_FX` 9; flames moved off mark 0 after the screenshot showed 3 stacked into one column by the hero); a line too short for a mark gets one streak at its end). `Arrow`: `primary`, lazy trail on the first step, `_end_line` once per primary arrow on `_finish` (trail.finish + พรหมาสตร์ `blast(position, 32, 0.5, false)` + spread_burst scaled to the blast's 64 px), `blast(at, r, frac, burn, include, skip) -> int`, `_secondary_hit` (receive_hit + leech; never `_after_hit`; Task 8 kill hook goes there), `combo_id()`; `halt()` ends the trail at once and skips the blast. `Hero._release`: one `ComboCast.from_build(b, hp/max_hp)` per press in `b["cast"]`, rahu's `dmg_bonus` multiplies the arrow mult; `_fire` with a build sets `primary` (bounces and basic shots are not). `TestGround`: the warp's dark halts `FireTrail`s too and `go_to` frees them (B20). Task 4 review notes: `Wolf.tick_burn` leeches DoT parts under 1 HP (was dropped by `if burn <= 0: return`) via static `Wolf.leech_to`, no per-step array; `tests/dummy_enemy.gd` `tick_status` leeches the same way. Tests: `tests/test_arrow_combos.gd` 18 new (the plan's 8 + ComboFx tint/saver, halt, FX cap + no allocation + saver keeps damage, short trail, press cast + leech, one cast per press, rahu bonus, basic shot, trail at warp / room change in the test ground); test_status_combo +2 (`test_wolf_leeches_fractional_dot_parts`, `test_dummy_tick_leeches_like_wolf`). Changed assertions (all tightened, none loosened): `test_wolf_leeches_each_dot_part_only` runs to 4.5 s so a trail-only tick lands after the burn ended; `test_trail_ticks_match_the_sim` uses the longest range of any arrow skill and asserts hold + flight < 1 tick; `test_no_monster_opts_out_of_freeze` also flags `func tick_burn` and a `func step(` without `super.step(` in a monster script, and `_monster_scripts` walks `get_base_script()` (a class_name subclass outside scripts/monsters is scanned; also widens `test_every_attack_state_is_a_fight_state`); test_waypoints "different homes" skipped only when the bank exists and both seeds pick the same entry. In `test_three_trails_burn_once_per_sec` / the leech test the fire gem's own burn (from the arrows' hits) is counted next to the trail tick. Seen failing first (ComboFx / FireTrail not declared; fractional leech 0.55 vs 1.1; dummy leech 0). Mutation checks, each caught: bounce arrows primary, `_after_hit` on a blast hit, halt keeping the trail, no saver shedding, no streak cap, a second line-end blast, no rahu bonus, the warp not stopping trails, a skill range of 400 (flight margin), a class_name boss outside scripts/monsters overriding `tick_burn` / `step` without super (with super: allowed). Screenshots (xvfb + opengl3, `tests/screenshots_m5b_combos.gd`): `docs/preview/m5b/fire_fan_ingame(_x3).png`, `brahmastra_ingame(_x3).png`, `brahmastra_saver_ingame(_x3).png`; the lines read clearly; the reused flames are faint (mostly smoke) and the tinted spread_burst reads as a flat orange disc: for the owner to judge. `docs/pixellab-budget.md`: Task 5 0 gen. Full suite: `RESULT passed=582 failed=0`. Risks: B26 updated (per isolated trail, shared clock, newest ledger, fractional leech, guards), B27 added.


**Done — Task 5 review fixes (2026-11-09, mechanics only; trail/blast look, tints and scales unchanged):** I1 `FireTrail` follows the arrow's real path: every 44 px of path flown a point is recorded (≤ `MAX_STREAKS` 6, a `PackedVector2Array` sized once in `setup`), the streak is laid there (turned along the path), and damage tests the polyline from → points → to (a path past 264 px uses the chord after point 6; the longest arrow skill flies 220 px). I2 a line that ends on a hit never line-end-blasts the monster it struck (`_finish(struck)` → `blast(..., skip = [struck])`); ฝนดาวไฟ's on-hit blast (Task 9) keeps `include` for its own target. I3 trail per tick = frac × atk × mult × `Combat.expected_crit(crit_chance, crit_mult)` = 1 + clamp(chance) × (crit_mult − 1) (no per-tick roll, = the sim); Global Constraints and Task 8 text now say so (burn keeps the rolled hit). M1 `blast(..., once_tag)`: line-end blasts use `cast.once("line_end", target)`, one per target per press. M2 `Wolf.def_factor()` cached (rebuilt on level / elite / `stats_tag()` change, `Monster.stats_tag()` = kind; `def_builds` counts rebuilds). M3 risks B27 death note fixed (loot yes, EXP no, no leech). M5 the fire gem's burn on an arrow hit carries `build.cast`. M6 dummy DEF explicitly float (it was already float: `def / (def + 100.0)` is int / float in GDScript; made explicit). M7 `_trail_case` documents its frame-counting assumptions. Owner 2026-11-09 (same round): mark + zone ADD (`taken_mult` = 1 + mark + zone, ×1.5 not ×1.56); a waypoint trip's re-roll never gives the destination its current pile layout (`RoomReset.distinct_seed(old, new, id, bank size)`: steps the seed until the bank entry differs; no bank / 1 entry: the seed differs; `TestGround.reroll(seed, dest)`, `travel_to_waypoint` passes its room; one bank lookup, no placement pass). Tests new: test_arrow_combos `test_homing_trail_follows_the_path` (path bends ≥ 90°), `test_line_end_blast_skips_the_struck_target`, `test_trail_tick_uses_expected_crit`, `test_line_end_blast_once_per_target_per_press`, `test_fire_gem_burn_carries_the_press_cast`; test_status_combo `test_wolf_trail_def_factor_cached`; test_room_reset `test_distinct_seed_never_repeats_the_entry`, `test_reroll_with_a_clashing_seed_changes_the_room`. Changed: `test_trail_fx_bounded` uses a real Wolf and runs through fade/_end (+ DEF built once); `test_zone_slow_and_taken_keep_highest` mark + zone 1.56 → 1.5 (owner decision); test_waypoints `test_travel_rerolls_and_lands_by_the_stone` always asserts a different bank entry and homes (was skipped on a ~1/64 clash). Seen failing first (with no-op API stubs: 10 failures for the expected reasons); mutation checks caught: chord-only damage, no kind in the DEF cache key. Full suite: `RESULT passed=590 failed=0`.

**Done — Task 5 review 2 fixes (2026-11-09):** I1 ("re-roll ห้ามได้ผังเดิมซ้ำ" = never the layout the player LAST SAW in a room, not the room's entry under the current seed): `RoomReset` keeps a per-room memory `_shown` (id → {seed, size, entry}) via `mark_shown`, recorded by `TestGround.go_to` whenever a room with monsters is built (fresh or kept); it survives `reroll_all` and lasts the session (not saved: a load is a new game with a new random layout and pile seed, like fog and kept rooms; noted in risks B28). `RoomReset.reroll_seed(new, dest, all_rooms := GUARD_ALL_ROOMS)` steps the seed until it differs from the current one and no guarded room (`guarded()`) repeats its last-shown seed/entry; `const GUARD_ALL_ROOMS := false` (destination only; `true` = every room shown this session, the room being left too; owner asked). `TestGround.reroll(seed, dest)` uses it; `RoomReset.distinct_seed` stays as the single-room helper. Minor 4: `reroll` no longer calls `groups_for(dest)` (no e0 set choice / global RNG before `arena_set = -1`). Minor 1: StatusEffects header says taken_mult = 1 + mark + zone. Minor 2/3: `FireTrail` keeps its path's bounding box (`_lo`/`_hi`, grown in `extend_to`) and `_near(p, r)` returns false outside the box grown by r before any segment check (`seg_checks` counts them for tests). Tests new: test_room_reset `test_a_b_a_trip_never_repeats_the_last_shown_layout` (banks 64/7/2/0 × 300 seeds; asserts the old guard would have missed), `test_guard_all_rooms_switch` (both settings, 200 seeds), `test_game_a_b_a_trip_never_repeats` (c1r2 → c2r0 → c1r2 in the game); test_arrow_combos `test_trail_marks_cover_the_longest_range` (shot.range and every skills.*.range from balance.json), `test_trail_box_skips_far_targets`. Docs: risks B27 note, new B28.

---

### Task 6: Lightning combos (ศรอสนีกระโดด, ศรอสนีพันสาย)

**Files:**
- Modify: `scripts/arrow.gd` (`_spawn_bounce` :103-118, bounce event, `bolts`)
- Test: `tests/test_arrow_combos.gd`

**Interfaces:**
- Consumes: `build.extra_bounces`, `GemCombo.p(id, "bolts" / "bolt_frac")`, `Arrow._secondary_hit`, `ComboFx.play(..., "bounce", at)`
- Produces: `Arrow.bolts(from: Vector2, n: int, frac: float, skip: Array) -> int` (hits the n nearest distinct live targets within `elements.lightning.range`, skipping `skip`)

- [x] **Step 1: Write the failing tests**

```gdscript
func test_thunder_hop_two_bounces_on_piercing():  # piercing [ricochet, lightning] Lv1, dummies A (in line), B, C chained within 120 px:
                                                  # hit order A, B, C (gem's 1 bounce + 1 extra); without the combo (ricochet only) only A, B (existing rule)
func test_thunder_hop_bolt_per_bounce():          # dummy D near each bounce point (not A/B/C): D gets one hit per bounce with mult ≈ arrow_mult × bounce_mult^k × 0.50
func test_thousand_bolts_two_bolts_no_extra():    # [ricochet, lightning, split]: each line bounces once (no extra); each bounce bolts the 2 nearest distinct targets at 0.50
func test_bolt_without_target_is_safe():          # lone target: no error, bolts(...) == 0
func test_lightning_gem_chain_still_works():      # element lightning's own +1 target ×0.8 still happens on primary hits (gems keep working)
```

- [x] **Step 2: Run and check it fails.**
- [x] **Step 3: Implement.** On spawning a bounce arrow, the child gets `bounces = base_child + parent.build.extra_bounces` and `extra_bounces = 0`. This adds exactly +1 to each chain, piercing lines included. At every bounce event, `bolts(from, p("bolts"), p("bolt_frac"), [struck, next])` runs. A bolt is a secondary hit.
- [x] **Step 4: Run and check it passes.** Run `test_arrow_combos` and `test_arrow_gems` (`test_piercing_bounces_only_from_first_target` must still pass for no-combo builds).
- [x] **Step 5: Commit** `git commit -m "M5b Task 6: lightning combos (+1 bounce, bolts per bounce)"`

**Done (2026-11-09):** `Arrow._spawn_bounce`: the child gets `bounces = (0 if pierce else parent's left − 1) + build.extra_bounces` and `extra_bounces = 0` (exactly +1 per chain; piercing 1 → 2, spread gem Lv1 1 → 2). `Arrow._bounce_event(struck, next)` runs at every bounce (primary and bounce arrows): the recipe's `bounce` effect (hit_spark #7fd4ff) at the bounce point and, when `combo_p.bolts` > 0, `bolts(struck.hurt_point(), bolts, bolt_frac, [struck, next])`. `Arrow.bolts(from, n, frac, skip) -> int`: the n nearest distinct live targets within `elements.lightning.range` (120) via `_nearest`, each a `_secondary_hit` (frac of the bouncing arrow's mult, its crit chance, leech; never `_after_hit`) + the recipe's `bolt` effect (chain_zap, once per bolt); no once-per-target limit (the approved sim counts 3 lines × 2 bolts on the same monsters). Reading resolved: "bolt 50 %" = 50 % of the arrow that bounces (plan test `arrow_mult × bounce_mult^k × 0.50`), so the 2nd bounce's bolt is 0.4 × the hit; tools/gem_combo_sim.py counts ศรอสนีกระโดด per line as 0.8 + 2 × 0.5 = 1.8 × the hit where the game gives 0.64 + 0.5 + 0.4 = 1.54 (pack slightly under the approved table; sim not changed, approved numbers; risks B29). ศรอสนีพันสาย matches the sim exactly (3 lines × 1 bounce × 2 bolts × 0.5). Tests: test_arrow_combos +9 (the plan's 5 + `test_bolts_nearest_in_range_and_secondary`, `test_bounce_and_bolt_fx` (saver on and off), `test_no_lightning_combo_no_bolt` (piercing + spread), `test_thunder_hop_on_spread_adds_one`, and the `_on_spawned` helper so bounce arrows' own bounces are stepped, as `Hero._on_arrow_spawned`). Changed: test helper `_arrow` listens to bounce arrows' bounces too (no assertion changed). Seen failing first (7 fails: no extra bounce, no `bolts`); `test_lightning_gem_chain_still_works` and `test_no_lightning_combo_no_bolt` passed before as regression guards. Mutation checks, each caught: extra_bounces not reset (spread: A→B→C→E), bolts on primary arrows only, a bolt via `_after_hit` (chains + bounces), bolts skipping only the struck target. Risk B29 added.

**Review fixes (2026-11-09, owner decisions on the Task 6 review):** (1) "50% ของนัดแรก คงที่": a bolt is `bolt_frac` of the press's FIRST hit at every bounce. `_spawn_bounce` copies the chain root's mult into the bounce arrow's build (`root_mult`); `_bounce_event` passes `root_mult()` into `bolts(from, n, frac, skip, base := -1.0)` → `_secondary_hit(t, frac, base)`. The "สายฟ้า 50%" text (gem_combo.gd describe) is unchanged and now exact. (2) "เด้งจากตัวแรกที่โดนเท่านั้น": every arrow tries to bounce once, from the first monster it hits (`_bounced = true`; was `= pierce`), so a pierce-gem arrow on ศรกระจาย no longer bounces at each pierced monster; ศรทะลวง and plain ricochet chains unchanged (the chain goes on through the bounce arrows). (3) Reviewer I1 not changed (no owner decision): bounce arrows keep element lightning, so each bounce also fires the gem's own ×0.8 chain; per-press pack numbers vs the sim recorded in risks B29 (piercing +11–12 %; spread +10–13 % when counted on the sim's bouncing lines, but +120 % / +47 % because in the game every spread arrow that hits bounces while the sim counts 1 / 3 lines). Worst case bolts per press: char Lv10 15 (spread thunder_hop, ricochet Lv10), char Lv12 28 (spread thousand_bolts, 7 arrows × 2 × 2). Tests: `test_thunder_hop_bolt_per_bounce` now locks the flat value; + `test_spread_pierce_gem_bounces_from_first_target_only`, `test_lightning_worst_case_bolts_per_press`, `test_thunder_hop_ricochet_lv10_two_plus_one`, `test_bolt_can_crit_and_leeches`; room reset: `test_guard_all_rooms_never_repeats_any_room` reads the real rooms (RoomSet) and bank sizes (PileBank) and asserts rooms-with-bank < smallest bank (review I3), `RoomReset.reroll_seed` warns when it gives up after 4096 tries (M1, `test_reroll_seed_gives_up_when_no_seed_is_free`), B28 explains why every room's entry moves together (odd suffix lengths, 33² ≡ 1 mod 64; M3). Mutation checks, each caught: bolts off the bouncing arrow (3 fails), `_bounced = pierce` (spread + pierce gem: 60 bounces / 60 bolts per press instead of 15).

**Owner fixes (2026-11-10, Task 6 numbers vs the approved sim):** (1) "สายฟ้าคอมโบจาก 1 ลูกต่อการกด": `SkillBuild.of` adds `lines` (the sim's arrow lines: 1, +split's extra arrows → 3) and `SkillBuild.line_of(b, i)` (fan order, symmetric: ศรกระจาย+split 7 arrows → 0,0,1,1,1,2,2); `Hero._release` → `_fire(..., line)` sets `Arrow.line`. `Arrow.carries_lightning()`: decided once at the arrow's first hit, true only for a lightning-combo build when `build.cast.once("lightning_line", line)` succeeds (no ledger = no limit); bounce arrows inherit it (`_spawn_bounce(from, to, carry)`). Only a carrier chain gets `extra_bounces` and `_bounce_event` (bounce FX + bolts); the line's other arrows bounce as the plain ricochet gem. (2) "ลูกเด้งไม่แตกสายโซ่": `Arrow.is_bounce` (set by `_spawn_bounce`); a bounce arrow's hit never fires the lightning gem's ×0.8 chain. Tests (test_arrow_combos): new `test_press_lines_follow_the_sim` (incl. the hero's spread+split press), `test_lightning_combo_one_arrow_per_line` (first to hit carries, two presses), `test_thousand_bolts_one_carrier_per_line` (+ homing), `test_bounce_arrows_never_chain`, `test_lightning_pack_press_matches_sim`; changed `test_lightning_worst_case_bolts_per_press` (owner rule: Lv10 spread thunder_hop 15/15 → 11 bounces / 3 bolts; Lv12 spread thousand_bolts 14/28 → 14 / 12; others unchanged); `_fan` sets each arrow's line. Worst case bolts per press: **12** (char Lv12 ศรกระจาย ศรอสนีพันสาย, ricochet Lv10); phase 1 (Lv10): 6. Pack per press vs `tools/gem_combo_sim.py --press` (new print flag, no number changed; units of the first hit, gem Lv1, crit off): piercing thunder_hop 7.84 vs 8.0 (−2.0 %), piercing thousand_bolts 18.0 vs 18.0 (0 %); spread thunder_hop 12.04 vs 9.8 (+22.9 %), spread thousand_bolts 16.0 vs 14.4 (+11.1 %) — the spread gap is exactly the other arrows' plain ricochet bounces (3 / 2 × bounce_mult 0.8), which the owner keeps but the sim does not count (it counts the ricochet gem as 1 bounce per line); without them −1.6 % / 0 %. Not resolved: needs an owner choice (count plain bounces per hitting arrow in the sim, or no plain bounce on the spread's other arrows); risks B29. Mutation checks, each caught: every arrow carries (4 fails), bounce arrows chain (2), one carrier per press instead of per line (4).

**Fire trail, owner 2026-11-10 ("ทำชีตย่อใหม่ให้เนียน", "ถี่ขึ้นให้เท่าตัวอย่าง"):** `tools/pixelfx_export.py` `fire_trail_small` (`shrink=0.4`, `shrink_cells`): the T2 render's 44×49 cells area-averaged (premultiplied) to **18×20**, feet anchor (22,44) → (9,18), crisp (≥ half solid → opaque; else the glow's own alpha snapped to the sheet's 3 levels 16/59/132; colours snapped to the T2 palette = fire ramp + 2 smoke tones), 45 f @ 15 fps, 810×20 (65 KB); `RETIRED = ["fire_trail"]` removes the full-size entry and sheet (nothing uses it). Export rerun from the clean a841596 checkout (identical to shrinking the committed sheet). `balance.json` fire_fan / brahmastra trail fx → `fire_trail_small`. `FireTrail`: PATCH_SCALE removed (scale 1), `SPACING` 44 → **20**, `MAX_STREAKS` 6 → **12** (240 px ≥ 220); damage still the recorded path (straight lines unchanged); PerfSaver sheds no patch. Tests: new `test_trail_patches_small_sheet_dense` (replaces `test_trail_patches_drawn_at_sample_size`: 1:1, feet on mark, 18×20, 20 px apart, 11 on 220 px, ≤ 12 on 1600 px, saver keeps all, reach = line ± 10 px), test_pixelfx `test_fire_trail_small_is_crisp` (levels, palette, VRAM, fire_trail retired) and FIRE_PICKS row → fire_trail_small; tools/test_pixelfx_export.py +4 shrink cases (solid block → no halo, palette, glow levels, anchor); changed counts 5 → 11 patches per 220 px line (`test_trail_patches_start_at_their_own_frames`, cache test message). Screenshots: `FIRE_SET=dense` + `python3 -I tools/fire_fx_review.py --dense` → docs/preview/m5b/fire_t2_dense_*.png and fire_t2_dense_review.png. Risks B30.

**Sim fix, owner 2026-11-10 ("คงไว้ แก้ตัวเลขอนุมัติให้นับทุกลูก"):** `tools/gem_combo_sim.py` ricochet term counts 1 bounce per arrow that hits on ศรกระจาย (np_ 4 / 5 with split; ศรทะลวง / ศรเพลิง unchanged, 1 per line). `--press`: ศรกระจาย ศรอสนีกระโดด 9.8 → 12.2, ศรอสนีพันสาย 14.4 → 16.0; single target unchanged; corrected figures noted under the owner bullet in the spec (approved tables untouched). `test_lightning_pack_press_matches_sim` now checks every case's raw total at ±3 % (game 12.04 / 16.0: −1.3 % / 0 %); the old "minus plain bounces" path is gone. Risk B29 → 🟢.

**Owner rule, Task 6 review 3 (2026-11-10, "ลูกแรกที่เด้งได้จริง"):** a line's lightning combo goes to the first arrow of the line that can actually bounce (a bounce target within `ricochet.range` when it hits), not merely the first to hit; still one arrow per line per press. Only `Arrow.claim_lightning_line(can_bounce := true)` changed (+ its one call site in `_after_hit_bounce`: `claim_lightning_line(next != null)`): an arrow whose first hit has no bounce target never claims (and never bounces later: every arrow tries once, from its first hit), so the line stays free for the next arrow of that line that bounces; hit order decides (deterministic, homing too). ศรทะลวง unchanged (its line's one arrow either bounces from its first target and carries, or neither). Tests (test_arrow_combos, 3 new): `test_lightning_line_goes_to_first_arrow_that_bounces` (ศรกระจาย: arrow 3 hits a lone monster first and leaves the line free; of the 4 arrows that then bounce only arrow 0, the first, carries: 1 + 1 bounces, 2 bolts, 3 plain), `test_lightning_line_first_bouncer_with_homing` (homing gem: the arrow that kills the weak lone monster does not claim; one carrier among the arrows that reach the pack), `test_piercing_first_target_without_bounce_unchanged` (no bounce, no bolt, line not claimed). Seen failing first (3 fails: carriers [3], carrier's first hit = the lone monster, piercing arrow carried without bouncing). Pack per press vs `tools/gem_combo_sim.py --press` unchanged: piercing thunder_hop 7.84 vs 8.0 (−2.0 %), spread thunder_hop 12.04 vs 12.2 (−1.3 %), piercing thousand_bolts 18.0 vs 18.0 (0 %), spread thousand_bolts 16.0 vs 16.0 (0 %). Risk B29 updated.

---

### Task 7: Mark and frost combos (ศรตาเหยี่ยว, ศรเนตรพญาครุฑ, ศรเกล็ดน้ำแข็ง, ศรผลึกอโนดาต)

**Files:**
- Modify: `scripts/arrow.gd` (`_combo_on_hit` and pre-hit mult/crit), `tests/dummy_enemy.gd` (record `crit_chance` per hit)
- Test: `tests/test_arrow_combos.gd`

**Interfaces:**
- Consumes: `ComboCast.count_hit`, `ComboCast.once`, the Wolf status API, `Arrow.blast`, `ComboFx.play`
- Produces: none new. Arrow behaviour only.

- [x] **Step 1: Write the failing tests**

```gdscript
func test_hawk_eye_marks_20pct_4s():               # hit → dummy.is_marked(), taken_mult ≈ 1.2, gone after 4.01 s
func test_garuda_marks_30pct_and_sure_crit():      # first hit: crit_chance recorded == build.crit; target now marked; next press's hit on it: crit_chance == 1.0; taken ≈ 1.3
func test_frost_freezes_once_on_third_hit():       # piercing [ice, split] one press, 3 lines through one dummy: apply_freeze(1.0, 5.0) called once, on the 3rd hit; 2 hits → no freeze
func test_frost_lock_5s():                         # second press 2 s later, 3 hits → is_frozen() false (lock); press at 5.1 s → frozen again
func test_frost_bonus_vs_chilled():                # hit on a slowed dummy: mult ≈ arrow_mult × 1.25; unslowed: arrow_mult
func test_anodard_sure_crit_vs_chilled():          # slowed or frozen dummy: crit_chance == 1.0
func test_anodard_shatters_once_per_target_per_press(): # 3 lines into one frozen dummy: exactly 1 shatter blast (r32, ×0.50, includes the struck dummy); a dummy 31 px away also takes it; next press shatters again
func test_anodard_has_no_frost_bonus():            # anodard on a slowed dummy: mult == arrow_mult (no ×1.25: the tier-3 row replaces its base)
func test_boss_size_target_freezes():              # a wolf with set_elite(true) hit 3 times by frost_shard → is_frozen() (owner: bosses freeze like others)
```

- [x] **Step 2: Run and check it fails.**
- [x] **Step 3: Implement.** Before a primary or bounce arrow hit, the arrow checks: `sure_crit_marked` and the target is marked → crit_chance 1.0; `sure_crit_chilled` and the target is chilled → 1.0; `bonus_vs_chilled` and the target is chilled → mult × (1 + bonus). After the hit: `mark_secs` → `apply_mark(mark_taken, mark_secs)` plus ComboFx "mark"; `freeze_hits` → if `cast.count_hit(id) == freeze_hits`, call `apply_freeze(freeze_secs, freeze_lock_secs)` plus FX; `blast_on_chilled` and the target was chilled and `cast.once("shatter", id)` → `blast(t.hurt_point(), r, frac, false, t)`.
- [x] **Step 4: Run and check it passes.**
- [x] **Step 5: Commit** `git commit -m "M5b Task 7: mark (ตาเหยี่ยว/ครุฑ) and freeze (เกล็ดน้ำแข็ง/อโนดาต) combos"`

**Done (2026-11-10):** `Arrow._arrow_hit(t)` = every primary / bounce arrow hit: reads chilled / marked BEFORE the hit (the ice gem's slow from the same hit does not count), sure crit 1.0 for `sure_crit_marked` on a marked target and `sure_crit_chilled` on a chilled one, ×1.25 `bonus_vs_chilled` on this arrow's hit only (bounce / chain / burn from the arrow's own mult); then `_after_hit` and `_combo_on_hit(t, was_chilled)`: mark on every arrow hit (`apply_mark(mark_taken, mark_secs, cast)`), freeze when `cast.count_hit(target) == freeze_hits` (exactly once per target per press; no ledger = no freeze), shatter when it was chilled and `cast.once("shatter", target)` → `blast(hurt_point, 32, 0.5, false, t)` + the recipe's `shatter` FX (spread_burst #7fd4ff scaled to 64 px). Secondary hits never mark / count / shatter. Readings (plan decisions): sure crit applies to arrow hits only (Step 3 "a primary or bounce arrow hit"); the shatter rolls the arrow's own crit chance (Global Constraints "shatters can crit with the arrow's crit chance"), so it is not a sure crit even on the frozen target. FX: mark = the recipe's `mark` row (lock_on; garuda #edbb55) on the monster while marked (`Wolf._update_mark_fx`: swapped to the stronger mark's recipe, freed at expiry / death, never shed); frost recipes' `trail` row = a piercing_trail #7fd4ff streak riding the primary arrow (`Arrow.has_combo_streak`; TestGround then skips its plain streak); the `freeze` row = the monster's own frost overlay (not doubled); the `crit` row = TestGround's crit spark (not doubled). `ComboFx.has(id, event)`. `tests/dummy_enemy.gd` records `crit_chances`. `tools/gem_combo_sim.py --press` prints the mark / frost rows (no number changed). Tests (test_arrow_combos, 13 new): the plan's 9 + `test_secondary_hits_never_mark_or_count_freeze` (bounce arrows do mark and count), `test_wolf_shows_the_mark_while_marked`, `test_frost_streak_rides_the_arrow`, `test_mark_frost_press_matches_sim`. Game vs sim per press (ศรทะลวง Lv10, single target, expected crit): hawk_eye 1.175 vs 1.175 (0 %), frost_shard 3.588 vs 3.613 (−0.7 %), anodard 4.650 vs 4.550 (+2.2 %), asserted ±3 %; garuda presses 1.175 / 1.5 = the sim's two branches (the sim mixes them 15 / 85 = 1.451; in game every press after the first is marked: +3.4 %). Pack (7 hits on 5): frost_shard 7.69 vs 8.07 (−4.8 %), anodard 9.05 vs 12.35 (−26.7 %): printed, not asserted (the sim lets every pack monster shatter; owner question, risks B31). Seen failing first (12 fails); mutation checks, each caught: shatter without once-per-target, chilled read after the hit for the shatter. Task 6 review fix first (5abccd4). Full suite: `RESULT passed=636 failed=0`: `carries_lightning()` read-only, `claim_lightning_line()` the one claiming place. Risk B31 added.

**Review fix (2026-11-10, owner Task 7 review):** ① อโนดาต: each monster takes at most one shatter splash per press (`blast(..., "shatter_hit")`, its own shatter's included; the struck target's `once("shatter")` stays) — `test_anodard_splash_once_per_monster_in_a_cluster` (5 slowed dummies within 32 px: exactly 1 splash each per press; without the tag dummy 0 took 5). ② `tools/gem_combo_sim.py` follows the game: frost / อโนดาต pack bonus, sure crit and shatter only on the press's repeat hits (ch = hits − targets), 1 shatter, splash capped; ครุฑ every press marked. `test_mark_frost_press_matches_sim` now asserts every row ±3 % (ครุฑ 1.500 = 1.500, packs 7.688 / 7.687, 9.050 / 9.050); spec note under the owner bullet; ceiling 2.92×. ③ "ช้า" = ice slow / freeze only (unchanged code): `test_zone_slow_is_not_chilled` (dummy + real Wolf). ④ Look: ตาเหยี่ยว mark tint `#ff3050` (balance.json); frozen = `Wolf.FROZEN_TINT #dcf3ff × 0.95` + an ice block (`Wolf._update_ice_block`: NinePatchRect of `assets/fx/ice_block.png`, 32×32 nine-patch drawn pixel by pixel by `tools/ice_block_art.py`, 0 gen; sized from `assets/fx/ice_block_boxes.json` = each kind's body box per direction × size_scale + 5 px; added on the freeze step, hidden + freed on the step it ends, never shed by the PerfSaver); slowed look unchanged. Tests: `test_frozen_tint_is_paler_than_slowed` (was test_frozen_tint_is_frost), `test_frozen_wears_ice_block_sized_to_body`, `test_wolf_shows_the_mark_while_marked` (red). ⑤ `test_secondary_hits_never_mark_or_count_freeze` covers bolts and the shatter; B31 notes the killing hit that still shatters and the ตาเหยี่ยว re-mark refreshing a ครุฑ mark's time. Exit-time leak ("1 RID CanvasItem leaked / ObjectDB instances leaked", since 528ae17): an unfreed `FireTrail.new()` probe in `test_trail_patches_small_sheet_dense` (found by per-test orphan-node count) — now reads the script's constant map. ⑥ Review image docs/preview/m5b/t7_fix_review.png (`T7_FIX=1` screenshots + `tools/mark_frost_review.py --fix`).

---

### Task 8: Sustain combos and MP-on-kill caps (ศรกระหายเลือด, ศรราหูอมจันทร์)

**Files:**
- Modify: `scripts/hero/hero.gd` (add hooks), `scripts/arrow.gd` (kill and crit detection in `_after_hit` and `_secondary_hit`; pass the cast to burns and trails), `scripts/combo/fire_trail.gd` (carries the cast), `scripts/monsters/status_effects.gd` + `scripts/monsters/wolf.gd` (`tick_burn`: kill by a burn or trail tick → combo kill hook), `tests/dummy_enemy.gd` (`die_on_hit`, burn tick)
- Test: `tests/test_arrow_combos.gd`, `tests/test_hero_gems.gd`

**Interfaces:**
- Consumes: `ComboCast.refund_mp`, `ComboCast.dmg_bonus`, `Hero.leech_heal(amount: float)`
- Produces: `Hero.on_combo_kill(cast: ComboCast) -> void` (heals `kill_heal_frac × max_hp` through `leech_heal`; `mp = minf(max_mp(), mp + cast.refund_kill())`); `Hero.on_combo_crit(cast: ComboCast) -> void` (heals `crit_heal_frac × max_hp`). An arrow calls `on_combo_kill` when `amount > 0 and not t.is_alive()` after a direct or secondary hit, and `on_combo_crit` on a crit hit. **Burn and trail kills count too** (owner "นับทุกแบบ"). `apply_status("burn", value, leech, source, cast := null)` and `apply_trail(raw, hold, source, cast := null)` gain an optional trailing `cast`. `StatusEffects` keeps `burn_cast` / `trail_cast` beside `burn_source`, so a re-burn takes the newer cast (built in Task 4, with `freeze_cast` / `mark_cast` / `zone_cast`). When a burn or trail tick in `Wolf.tick_burn` kills, it calls `status.tick_source.on_combo_kill(status.tick_cast)` (the one ledger and source of the DoT that dealt that tick; Task 4; when both tick, a ledger that still pays goes before a 0-MP one, Task 4 review M4; `clear()` on death leaves both) if both are valid. Because that cast is the press's ledger object, it shares that press's 6 / 9 cap. DoT ticks never call `on_combo_crit`: trail ticks use the press's expected crit factor (no roll) and burn ticks are a fraction of the rolled hit that applied them (Task 5 review I3); neither rolls a crit of its own.

**Note (Task 6 review, 2026-11-09):** the lightning gem's own chain hit (`Arrow._after_hit`, `"lightning"` branch: it calls `other.receive_hit(...)` directly, not `_secondary_hit`) must go through the same kill hook (`on_combo_kill` / `on_combo_crit` through `build.cast`), so chain kills count for MP / heal like every other kill ("นับทุกแบบ"). Add a test: a chain kill by a [leech, multiply, element lightning] press refunds MP within the press's cap.

- [x] **Step 1: Write the failing tests**

```gdscript
func test_bloodthirst_mp_cap_6_per_press():   # hero Lv10, mp 40, spread [leech, multiply] (MP 12 × 1.2 × 1.5 = 21.6), 5 die_on_hit dummies killed by the 5 arrows of one press: mp ≈ 40 − 21.6 + 6 (not +10)
func test_cap_resets_each_press():            # after the cooldown a second press kills 3 more: +6 again
func test_bloodthirst_kill_heals_3pct():      # hp = max_hp / 2, dummy deals amount 1 (normal leech stays < 1 HP): after one kill hp == max_hp / 2 + floor(0.03 × max_hp)
func test_rahu_mp_cap_9():                    # [leech, multiply, execute], 5 kills → +9
func test_rahu_bonus_only_at_70pct_hp():      # hp = 0.70 × max: arrow mult ≈ build.arrow_mult × 1.30; hp 0.69 × max: × 1.0 (checked at release)
func test_rahu_crit_heals_1pct():             # forced crit (crit_chance 1.0 via the dummy recording) heals 0.01 × max_hp
func test_refund_never_exceeds_max_mp():      # mp at max − 1, 3 kills → mp == max_mp()
func test_burn_kill_counts_and_shares_cap():  # hero Lv10, piercing [leech, multiply, element fire] (bloodthirst; 3 slots at skill Lv10): 4 dummies in the line, 2 die_on_hit (+4 MP),
                                              # 2 burn and die later to their burn ticks → +2 then +0 (cap 6 for that press); heal 3% max HP per kill
func test_trail_kill_calls_hook():            # a dummy dies to an apply_trail tick fed with a press's cast → hero.on_combo_kill called once with that cast
                                              # (a trail only comes from fire_fan / brahmastra, never with a sustain combo on the same skill, so it grants 0 MP / 0 HP: the hook is for consistency)
func test_dot_kill_after_cap_gives_nothing(): # press already refunded 6 → a later burn kill from the same press gives 0 MP, still heals 3%
func test_bounce_and_bolt_kills_share_cap():  # [leech, multiply] + ricochet: kills by bounce arrows count toward the same 6
```

- [x] **Step 2: Run and check it fails.**
- [x] **Step 3: Implement.** `Hero._release` builds `ComboCast.from_build(b, float(health.hp) / health.max_hp)` once per press and shares it through `b["cast"]` (bounce arrows copy the build shallowly, so they share the same object). Rahu's `dmg_bonus()` is applied once to `b.arrow_mult` at release. Arrows pass `build.cast` into `apply_status("burn", …)` and `FireTrail.setup` / `apply_trail`. The ledger object outlives the press for as long as a burn holds it (RefCounted), and that is intended: its cap is the press's cap.
- [x] **Step 4: Run and check it passes.**
- [x] **Step 5: Commit** `git commit -m "M5b Task 8: sustain combos; MP on kill capped 6 / 9 per press (burn/trail kills count)"`

**Done (2026-11-10):** ONE kill / crit hook for every damage source: `static Hero.combo_hit(source, cast, target, was_alive, amount, crit := false)` (untyped: a freed target / source or no ledger is skipped, never an error). A kill = the hit that kills (alive before, dead after, amount > 0), credited once per target per ledger (`ComboCast.claim_kill` = `once("kill")`, the second guard) → `source.on_combo_kill(cast, target.hurt_point())`; a crit hit → `source.on_combo_crit(cast)`. Callers: `Arrow._credit` after every hit an arrow deals (`_arrow_hit`: primary and bounce arrows; the lightning gem's own chain in `_after_hit` (plan note); `_secondary_hit`: bolts, line-end and shatter blasts), `Wolf.tick_burn` after a burn / trail tick that kills (with `status.tick_cast` / `tick_source`: the press that applied that DoT; never a crit) and the test dummy's `tick_status` the same way. `Hero.on_combo_kill(cast, at := Vector2.INF) -> int` (heals `kill_heal_frac × max HP` through `leech_heal`; `mp = minf(max_mp(), mp + cast.refund_kill())`; nothing while dead and the cap is not spent; during a warp it pays as `on_kill` gives EXP, though no kill can land then; plays the recipe's `kill` effect (pickup_pop, tinted) at the monster when the kill paid); `Hero.on_combo_crit(cast)` (ราหู 1 % max HP through `leech_heal`; nothing while dead). Crit flag: `Wolf.last_hit_crit` (the last hit landed and rolled a crit), dummy `last_hit_crit` = a sure crit (chance ≥ 1.0). `tests/dummy_enemy.gd`: `die_on_hit`, `deal` (the damage a hit reports), `last_hit_crit`, DoT kill → hook. Readings: the recipe's `hit` row (tinted hit_spark) is not played (TestGround's hit spark already shows every hit, as Task 7 did with `crit`): owner question; MP refunded at full MP still spends the cap (plan: refund then clamp); the heal and the MP never exceed max. `tools/gem_combo_sim.py --press` prints the sustain rows (no number changed). Tests: test_arrow_combos +19 (the plan's 11, with `test_rahu_bonus_only_at_70pct_hp` at the exact boundary (passed before the change: a guard), + `test_lightning_chain_kill_refunds_mp` (plan note), `test_every_source_kills_through_one_hook` (primary, bounce, bolt, chain, line end, shatter, burn tick, trail tick), `test_kill_hook_once_per_kill_and_safe`, `test_dot_and_hit_same_frame_credit_once` (real Wolf, both orders), `test_many_trails_one_press_share_cap`, `test_late_burn_kill_credits_its_own_press`, `test_kill_fx_plays_when_paid`, `test_sustain_press_matches_sim`); test_hero_gems +4 (cap / max, dead keeps the cap, warp like on_kill, crit heal ≤ max). `test_bounce_and_bolt_kills_share_cap`: the bounce part is a real ศรทะลวง [leech, multiply, ricochet] press; a bolt never comes with a sustain recipe (one combo per skill), so its part hands a thunder_hop press the same ledger. Game vs `tools/gem_combo_sim.py --press` (ศรทะลวง Lv10, crit counted, units of the first hit): กระหายเลือด single 1.025 vs 1.025 (0 %), ราหู single 1.331 vs 1.331 (0 %; presses at HP ≥ 70 % / < 70 % mixed 70 / 30 as the sim), pack press (3 hits, 2 kills) MP − refund: กระหายเลือด 14.4 − 4 = 10.40 vs 10.40, ราหู 17.28 − 6 = 11.28 vs 11.28 (0 %); the sim does not model leech, the kill heal or the crit heal. Seen failing first (no `Hero.combo_hit`; then with a no-op stub 17 fails for the expected reasons); mutation checks, each caught: `claim_kill` always true, no alive-before check, chain not credited, secondary hits not credited, Wolf DoT kill not hooked, MP not clamped, dead hero spends the cap, one ledger reused across presses (5 fails), DoT kill credited to a ledger other than `tick_cast`. No existing assertion changed. Full suite: `RESULT passed=665 failed=0` (642 + 23), 0 SCRIPT ERROR, no leak at exit. Risks B25 → 🟢, B29 note, B32 added.

- [x] **Review fix (2026-11-11, owner Task 8 review):** ① "นับเฉพาะ MP ที่ได้จริง": `ComboCast.refund_kill_into(room)` grants min(kill_mp, cap left, max MP − MP) and only that real gain spends the cap (`_mp_given` / `mp_refunded()` are floats now; `refund_kill` / `refund_mp` kept, whole MP); `Hero.on_combo_kill` uses it and returns the MP gained (float). Tests: test_hero_gems `test_combo_kill_cap_normal_counts_full_gain`, `test_combo_kill_at_full_mp_keeps_the_cap`, `test_combo_kill_partial_gain_uses_only_the_gain` (+ 0.25 below max); two assertions changed by this decision: `test_combo_kill_pays_under_cap_and_max` ([2, 2, 2, 0] → [2, 1, 0, 0], ledger 3) and test_arrow_combos `test_refund_never_exceeds_max_mp` (ledger 6 → 1). ② heals stay uncapped, every crit of the press heals (unchanged); `test_real_wolf_crit_flag_heals_rahu` (real Wolf and Monster: crit 1.0 → flag + 1 % heal, 0 → no flag, hit on a corpse → no flag, no heal) and the contract `test_every_monster_sets_last_hit_crit` (every script under scripts/monsters, extending wolf.gd or joining "enemies" that writes receive_hit sets last_hit_crit or calls super; wolf.gd resets it before the dead check). ③ "ย้อมสีประกายตีแทน": `Arrow._receive` (every arrow / bounce / chain / secondary hit) sets the target's `spark_tint` to the recipe's "hit" row tint (`ComboFx.spark_tint`: bloodthirst #ff4a4a, rahu #6a2a8a, already in balance.json) for that one receive_hit; `TestGround._on_wolf_hit` recolours the hit spark with `ComboFx.recolor` (shaders/recolor.gdshader, by brightness: modulate cannot turn the orange spark purple); the recipe's "hit" row is otherwise still not played; PerfSaver unchanged (the spark is never hidden; the saver's crit fallback spark is recoloured, crit_hit keeps its look). Tests `test_sustain_hits_carry_the_spark_tint`, `test_hit_spark_recoloured_in_game`. ④ Reviewer M1: `test_respawn_outlasts_every_dot_window` (longest flight incl. 3 bounce legs 2.44 s + max(burn 3 s, trail 3 s + hold 0.25) × extend top ×1.49 = 7.29 s < every `respawn` in balance.json, wolf.respawn 9 s); the "≤ ~3.9 s" comment in combo_cast.gd fixed. Mutation checks, each caught: old cap (refund at full MP), no spark tint, no last_hit_crit reset in Wolf, wolf.respawn 7, a boss script without last_hit_crit. No game number changed. Full suite: `RESULT passed=673 failed=0` (665 + 8), 0 SCRIPT ERROR, no leak at exit. Risks B32 updated.

---

### Task 8a: Area skill data, data-driven skill list, area build keys, icons

**Files:**
- Modify: `data/balance.json` (`skills.arrow_rain`, `skills.thorn_trap`, `skills.fire_arrow`; `skill_labels.thorn_trap`, `skill_labels.fire_arrow`)
- Modify: `scripts/hero/skills.gd` (`active_ids`, `kind`, `display_name`, `icon`)
- Modify: `scripts/rules/skill_build.gd` (`_base` per kind; `expand` / `extend` gems; area keys; ศรเพลิง's own fire)
- Modify: `scripts/hero/hero.gd:35, 214-216` (`skill_gems` keys from `Skills.active_ids()`)
- Modify: `scripts/ui/skill_panel.gd:18-22, 257-280` (`SKILLS` / `SKILL_NAMES` / `SKILL_ICONS` come from `Skills`; remove the dim "ห่าศร · มาในรอบถัดไป" row; rows go inside a `ScrollContainer` so 5 rows fit at 640×360 and in portrait)
- Modify: `tests/test_hero_gems.gd` (Task 1's `test_after_load_returns_gems_from_unknown_and_closed_slots` uses `"arrow_rain"` as the unknown skill. Keep it, since ห่าศร is locked at Lv1, and add the same case with a truly unknown id `"poison_shot"`), `tests/test_save_hardening.gd` (`_rich()` comment: gems on ห่าศร are legal from Lv7 now)
- Test: `tests/test_area_skills.gd` (new)

**Interfaces:**
- Produces: `Skills.active_ids() -> Array` (ids under `skills` that have `unlock`, ordered by unlock level, ties in data order → `["piercing","spread","arrow_rain","thorn_trap","fire_arrow"]`); `Skills.kind(id) -> String` (`"arrows"` | `"rain"` | `"trap"`, from `skills.<id>.kind`, default `"arrows"`); `Skills.display_name(id) -> String` (const table in skills.gd: ศรทะลวง, ศรกระจาย, ห่าศร, กับดักหนาม, ศรเพลิง); `Skills.icon(id) -> String` (fallback in Global Constraints).
- `SkillBuild.of` adds output keys `kind`, `area_mult` (1 + expand effect; 1.0 without the gem) and `dur_mult` (1 + extend effect). Per kind:
  - rain: `radius` = 64 × area_mult, `duration` = 3 × dur_mult, `tick_every` 0.5, `ticks` = floor(duration / tick_every + 1e-6), `arrow_mult` = damage per tick, `cast_range` 220
  - trap: `trigger_radius` = 16 × area_mult, `root_secs` = 2 × dur_mult, `max_traps` 2, `cast_range` 160, `arrow_mult` = trap damage
  - fire_arrow: `arrows` 1, `pierce_all` false, `blast_radius` = 32 × area_mult, `blast_frac` 1.0, range 220. **D7:** with no element gem, the build gets `element = "fire"` and `element_mult = 1.0 + hero_stats.element_dmg` (no ×1.1), so the existing fire path in `Arrow._after_hit` burns. With an element gem, the normal gem path runs: fire ×1.1 and burn (once), ice ×1.1 and slow **without burn**, lightning ×1.1 and chain **without burn**. Recipe keys still come from the gems only (`GemCombo.resolve`), so the arrow's own fire is never a `fire` key. Applying gear `element_dmg` to the arrow's own fire is a plan decision (it is elemental damage).
- Task 9's `GemCombo.area_radius_mult(b)` reads `b.area_mult` and adds `area_radius_bonus`.

balance.json rows:
```json
"arrow_rain": {"unlock": 7, "kind": "rain", "mult": 0.4, "cooldown": 10, "mp": 18, "radius": 64, "duration": 3, "tick": 0.5, "range": 220},
"thorn_trap": {"unlock": 10, "kind": "trap", "mult": 1.5, "cooldown": 8, "mp": 12, "range": 160, "root": 2, "max_traps": 2, "trigger_radius": 16},
"fire_arrow": {"unlock": 10, "mult": 2.0, "cooldown": 6, "mp": 14, "range": 220, "blast_radius": 32, "blast_frac": 1.0}
```
`skill_labels`: `"thorn_trap": ["trap", "area"]`, `"fire_arrow": ["arrow", "element", "area"]` (`arrow_rain` stays `["area", "dot"]`).

- [ ] **Step 1: Write the failing tests**

```gdscript
# tests/test_area_skills.gd
func test_numbers_match_skills_md():   # unlock 7/10/10; mult 0.4/1.5/2.0; cooldown 10/8/6; mp 18/12/14; rain radius 64, duration 3, tick 0.5, range 220;
                                       # trap range 160, root 2, max_traps 2, trigger_radius 16; fire range 220, blast_radius 32, blast_frac 1.0;
                                       # elements.fire burn_frac 0.2 / tick 1.0 / duration 3.0 unchanged
func test_active_ids_order():          # Skills.active_ids() == ["piercing","spread","arrow_rain","thorn_trap","fire_arrow"]
func test_labels():                    # Gem.fits("expand","thorn_trap") and fits("extend","thorn_trap"); fits("split","fire_arrow"); not fits("split","arrow_rain"); fits("extend","arrow_rain"); not fits("extend","fire_arrow")
func test_rain_build_lv7_and_lv10():   # Lv7: arrow_mult ≈ 0.4, cooldown ≈ 10, ticks == 6; Lv10 (skill Lv4): arrow_mult ≈ 0.46, cooldown ≈ 9.7
func test_rain_expand_extend():        # [expand] Lv1: radius ≈ 83.2, mp ≈ 23.4; [extend] Lv1: duration ≈ 3.9, ticks == 7; [expand, extend]: mp ≈ 28.08 (spec §3 28.1)
func test_trap_build():                # Lv10: arrow_mult ≈ 1.5, cooldown 8, mp 12, root_secs 2, trigger_radius 16; [extend]: root_secs ≈ 2.6; [expand]: trigger_radius ≈ 20.8
func test_fire_arrow_build():          # Lv10 []: arrows 1, pierce_all false, arrow_mult ≈ 2.0, blast_radius 32, element "fire";
                                       # [element fire]: element "fire", arrow_mult ≈ 2.2, mp ≈ 18.2; [element ice]: element "ice", arrow_mult ≈ 2.2; [element lightning]: element "lightning";
                                       # [pierce, expand]: mp ≈ 21.84 (spec 21.8); [element fire, expand]: mp ≈ 23.66 (spec 23.7)
func test_fire_arrow_own_fire_not_a_key(): # GemCombo.resolve("fire_arrow", [split]) == {} (no ศรพัดเพลิง without a fire gem)
func test_existing_builds_unchanged(): # piercing / spread builds equal to before for every Task 1 fixture (kind "arrows", area_mult 1.0, dur_mult 1.0, element "" without a gem)
func test_icon_fallback():             # Skills.icon("piercing") ends "piercing.png"; Skills.icon("no_such") ends "slot_empty.png"
func test_panel_lists_five():          # SkillPanel built at hero Lv10: rows for all 5 ids in active_ids order; Lv6: the arrow_rain row shows "ปลดที่ Lv7"
func test_save_gems_on_new_skills():   # signed save at level 9 with "fire_arrow": [multiply gem] → refused (new_state); same at level 10 → loads; "arrow_rain" gems at 6 refused, 7 loads
```

- [ ] **Step 2: Run and check they fail.** `TEST_ONLY=test_area_skills godot --headless --path . --script tests/run_tests.gd` → FAIL, `active_ids` not found.
- [ ] **Step 3: Implement** as listed. `Hero.set_skill_gems` builds its default dict from `active_ids()`. A locked skill's panel row shows `"%s: ปลดที่ Lv%d"`, as the preview lines already do.
- [ ] **Step 4: Run and check they pass.** Run `test_area_skills`, then the full suite (`test_hero_gems`, `test_skill_panel`, `test_save_hardening`, `touch_check`, the portrait layout tests).
- [ ] **Step 5: Commit** `git commit -m "M5b Task 8a: area skill data (ห่าศร/กับดักหนาม/ศรเพลิง), data-driven skill list, area build keys"`

---

### Task 8b: ห่าศร (arrow rain) and the shared SkillHit

**Files:**
- Create: `scripts/combat/skill_hit.gd` (`SkillHit`), `scripts/skills/arrow_rain.gd` (`ArrowRain extends Node2D`)
- Modify: `scripts/hero/hero.gd` (`_release` kind branch; `area_point(range)`; `hit_source(b)`; ComboCast per press for every kind; free rains on `begin_warp` / `_on_died`), `scripts/dev/test_ground.gd` (free rains on `room_changed`; cast FX on `skill_released`)
- Test: `tests/test_area_skills.gd`

**Interfaces:**
- `Hero.hit_source(b: Dictionary) -> Dictionary` = `{"atk", "crit", "crit_mult", "build", "shooter", "cast"}`, built once per press. `b.cast` is the press's `ComboCast` (Task 8), with Rahu's `dmg_bonus` folded in as for arrows.
- `SkillHit.hit(t: Node2D, src: Dictionary, mult: float, at: Vector2) -> int`: calls `t.receive_hit(atk, mult, at, crit, crit_mult)` (the target's `taken_mult` applies inside), then leech, then the build's element status (fire → `apply_status("burn", 0.2 × amount, leech, shooter, cast)`; ice → slow; lightning → one chain to the nearest other live target within `elements.lightning.range` at ×0.8, with at most one `chain_zap` FX per tick), then `shooter.on_combo_crit(cast)` on a crit and `shooter.on_combo_kill(cast)` on a kill. Returns the amount. `Arrow._secondary_hit` may delegate to it if Task 5 tests stay unchanged.
- `Hero.area_point(range_px: float) -> Vector2` (D2): the feet (`global_position`) of the monster `Combat.pick_target(_pos(), pts, hps, range_px)` picks from the same live, not-hidden list as `current_target()` (which always uses `shot.range`, so it is not reused as is); else the hero's own feet.
- `ArrowRain.setup(center: Vector2, b: Dictionary, src: Dictionary, targets: Array)`, `step(delta)` (works without a tree), `ticks_done: int`. At each `tick_every` mark (0.5, 1.0 … for `ticks` ticks), every live target whose feet are within `radius` of `center` takes `SkillHit.hit(t, src, b.arrow_mult, center)`. With zone mods (Task 9) it also calls `t.apply_zone(slow, taken, 0.25)` every step for targets inside. The node frees itself after the last tick.

FX (0 gen): `warp_ring` tinted `#edbb55`, scaled to `radius`, for the whole duration (the "ยันต์วงกลมบนพื้น"). Each tick drops 3 arrow sprites from the existing arrow texture, falling 48 px; they are decoration and are not drawn while PerfSaver is on. One `hit_spark` per target hit. Sound: one `bow_shot` at cast. Hit sounds come from `receive_hit`: if `Sfx` has no throttle, play at most one hit sound per tick. The cast reuses the bow-shot animation.

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_rain_six_ticks_r64():          # hero Lv7, rain at the origin: dummy at 63 px gets 6 hits over 3.0 s, each mult ≈ 0.4; dummy at 65 px gets 0; no hit before t = 0.5
func test_rain_extend_seven_ticks():     # [extend] Lv1: 7 hits, the last at 3.5 s; node freed after it
func test_rain_expand_radius():          # [expand]: dummy at 83 px hit, 84 px not
func test_rain_target_point():           # dummy 200 px away → rain centre == dummy feet; dummy 230 px away → centre == hero feet
func test_rain_costs_and_cooldown():     # Lv10 press: mp −18, cooldown ≈ 9.7; a second press during the cooldown → try_skill false; mp 17 → false
func test_rain_ticks_crit_and_leech():   # [leech]: hero heals 3% of each tick's damage; dummy records crit_chance == build.crit
func test_rain_kill_counts_for_sustain():# [leech, multiply] 4 die_on_hit dummies inside: MP +6 (cap), not +8
func test_rain_fire_gem_burns_all():     # [element fire]: every dummy hit is burning after the first tick
func test_rain_freed_on_warp():          # hero.begin_warp() during the rain → node freed, no further hits
func test_rain_not_overlapping():        # extend at gem Lv20 (0.49) → duration 4.47 s < shortest cooldown 10 × 0.7: two rains never overlap
```

- [ ] **Step 2: Run and check it fails.** **Step 3: Implement.** **Step 4: Run and check it passes**, then run `test_hero`, `test_hero_gems` and `test_arrow_gems`.
- [ ] **Step 5: Commit** `git commit -m "M5b Task 8b: ห่าศร (r64, 6 ticks of 40%) + shared SkillHit"`

---

### Task 8c: กับดักหนาม (thorn trap) and the root status (ตรึง)

**Files:**
- Modify: `scripts/monsters/status_effects.gd` (root), `scripts/monsters/wolf.gd` (`apply_root`, `is_rooted`), `tests/dummy_enemy.gd` (same API)
- Create: `scripts/skills/thorn_trap.gd` (`ThornTrap extends Node2D`), `scripts/rules/trap_set.gd` (`TrapSet extends RefCounted`, pure)
- Modify: `scripts/hero/hero.gd` (`traps: TrapSet`; `_release` trap branch; clear on warp and death), `scripts/dev/test_ground.gd` (clear on `room_changed`)
- Test: `tests/test_area_skills.gd`, `tests/test_status_combo.gd`

**Interfaces:**
- `StatusEffects.apply_root(secs: float)` keeps the larger remaining time and never adds. `is_rooted() -> bool`. `speed_mult()` returns 0 while rooted (beside Task 4's freeze). `clear()` clears it.
- `Wolf.apply_root(secs) -> bool` (false when dead). D3: root stops movement only. Walk, chase and lunge all go through `_move` × `speed_mult`, so a lunge moves 0 px. Windups are **not** cancelled (unlike freeze), and a rooted monster still bites or throws if the hero is in reach. Elites and bosses are rooted too.
- `TrapSet.add(trap) -> Object` (returns the trap removed to keep `max_traps`, the oldest, or null); `armed() -> Array`; `clear()`.
- `ThornTrap.setup(at: Vector2, b: Dictionary, src: Dictionary, targets: Array)`, `step(delta)`. It checks the live targets whose feet are within `trigger_radius` of the trap and **skips monsters already rooted** (D3). If any remain, it fires once: each of them gets `SkillHit.hit(t, src, b.arrow_mult, at)` and `apply_root(b.root_secs)`. Then the trap is spent: its sprite stays closed under the target for `root_secs`, then fades. With a zone recipe (Task 9), the spent trap's circle (`trigger_radius × area_radius_mult`) is the zone for `root_secs`. D4: an armed trap has no time limit.
- Placement: `Hero.area_point(160)`, the monster's feet if within 160 px, else the hero's feet (D2).
- **Note from the Task 7 review (owner 2026-11-10, "นับเฉพาะน้ำแข็ง"):** a root is NOT "ช้า" for the frost combos: `is_chilled()` (Wolf, dummy) must stay `is_slowed() or is_frozen()` and never read `is_rooted()`, so a rooted monster gets no ศรเกล็ดน้ำแข็ง +25 %, no อโนดาต sure crit and no shatter. Add `test_root_is_not_chilled` beside `test_zone_slow_is_not_chilled`.

FX (0 gen): the owner-picked trap sprite (or the placeholder). On trigger, `spread_burst` tinted `#8a6a3a`. The monster's ordinary hit spark plays. No new root overlay: the closed trap under the feet shows the root. The cast reuses the bow-shot animation.

- [ ] **Step 1: Write the failing tests**

```gdscript
# test_status_combo.gd
func test_root_speed_zero_and_ends():    # apply_root(2.0): speed_mult 0; tick(1.99) still rooted; tick(0.02) → speed_mult 1.0
func test_root_keeps_longer_not_sum():   # apply_root(2.0); tick(0.5); apply_root(1.0) → 1.5 left (not 2.5, not 1.0)
func test_rooted_wolf_does_not_move():   # chasing wolf rooted 2 s: position unchanged after step(1.0); a boar in lunge moves 0 px; a bite in reach still lands
func test_dead_ignores_root():           # health 0 → apply_root false
func test_elite_rooted():                # set_elite(true) → apply_root true
# test_area_skills.gd
func test_trap_placed_on_target_within_160(): # dummy 150 px away → trap at dummy feet; 170 px → trap at hero feet
func test_trap_triggers_150_root_2():    # Lv10 trap, dummy moved to 15 px: one hit mult ≈ 1.5, rooted 2.0 s, trap spent; at 17 px nothing
func test_trap_hits_all_inside():        # 2 dummies within 16 px on the same step → both hit and rooted once
func test_max_two_traps_oldest_goes():   # 3 presses (cooldown cleared between): armed() size 2, the first trap freed
func test_second_trap_ignores_rooted():  # 2 traps on one spot, dummy steps in: 1 hit (150%), not 2; after the root ends (2.01 s) the 2nd fires
func test_trap_extend_root():            # [extend]: root 2.6 s
func test_trap_expand_radius():          # [expand]: dummy at 20 px triggers, 21 px does not
func test_traps_cleared_on_warp_death_room(): # begin_warp / death / room_changed → armed() empty, nodes freed
func test_trap_cost_and_cooldown():      # mp −12, cooldown 8; locked at Lv9 (try_skill false)
func test_trap_placeholder_without_art():# with no trap PNG present the trap still builds and draws (no error); with one, it uses the texture
```

- [ ] **Step 2: Run and check it fails.** **Step 3: Implement.** **Step 4: Run and check it passes**, then run `test_status_combo`, `test_monsters` and `test_elite`.
- [ ] **Step 5: Commit** `git commit -m "M5b Task 8c: กับดักหนาม (≤160 px, root 2 s + 150%, max 2) + root status"`

---

### Task 8d: ศรเพลิง (fire arrow): 200%, burn, r32 blast

**Files:**
- Modify: `scripts/arrow.gd` (first-hit own blast for builds with `blast_radius`; element status on blast targets), `scripts/dev/test_ground.gd` (`_on_arrow`: fire-arrow tint and trail)
- Test: `tests/test_area_skills.gd`

**Interfaces:**
- Consumes: `Arrow.blast(at, radius, frac, burn, include, skip)` and `Arrow.primary` (Task 5). The `kind "arrows"` path in `_release` / `_fire` needs no change beyond 8a.
- Behaviour: one arrow, range 220. It stops on the first target unless the pierce gem lets it continue. On its **first** hit (primary arrows only) it calls `blast(t.hurt_point(), b.blast_radius, b.blast_frac, b.element == "fire", null, [t])`. Every other target within the radius takes a secondary hit at the arrow's mult, and the struck target is not hit twice (D5). Blast targets get the build's element status: burn for fire (0.2 × amount per s for 3 s, no stacking), slow for an ice gem, nothing extra for lightning (a secondary hit does not chain). D7: with an ice or lightning gem, neither the arrow nor the blast burns.

FX (0 gen): arrow `modulate` `#ff8a3d` (fire) / `#7fd4ff` (ice gem) / `#fff1a0` (lightning gem), a `piercing_trail` in the same tint, `spread_burst` in the same tint at the blast, and `status_burn` on burning targets (existing overlay).

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_fire_arrow_200_and_burn():      # Lv10, DEF-0 dummy A in line: A hit once, mult ≈ 2.0; A burning, per tick ≈ 0.2 × amount, 3 ticks over 3 s
func test_fire_arrow_blast_r32():         # B 31 px from A's hurt point: one secondary hit, mult ≈ 2.0 × 1.0, burning; C at 33 px untouched; A's hit count == 1
func test_fire_arrow_stops_at_first():    # D behind A in the line, 40 px further: not hit (no pierce gem)
func test_fire_arrow_split_three_blasts():# [split]: 3 arrows ×0.6 each, each first hit blasts once → 3 blasts
func test_fire_arrow_pierce_blast_once(): # [pierce]: passes A and B; own blast only at A (first hit); Task 9 shockwave adds the per-pierce blasts
func test_fire_gem_no_double_burn():      # [element fire]: mult ≈ 2.2; burn per tick == 0.2 × amount (not 0.4)
func test_ice_gem_replaces_burn():        # [element ice]: A slowed and NOT burning; B (blast) slowed and NOT burning; mult ≈ 2.2
func test_lightning_gem_replaces_burn():  # [element lightning]: A not burning; one chain hit ×0.8 on the nearest other target within 120 px; B (blast) not burning, no chain from B
func test_fire_arrow_takes_arrow_combos():# fire_arrow [split, element fire] → combo id "fire_fan" and a FireTrail is created (Task 5 path)
```

- [ ] **Step 2: Run and check it fails.** **Step 3: Implement.** **Step 4: Run and check it passes**, then run `test_arrow_gems`, `test_arrow_combos` and `test_hero_gems`.
- [ ] **Step 5: Commit** `git commit -m "M5b Task 8d: ศรเพลิง (200% + burn 20%/s 3 s + r32 blast; ice/lightning gem replaces the fire)"`

---

### Task 8e: 4-slot skill bar: touch buttons, keys 1–4, skill panel, save key

The touch arc round the shoot button holds exactly 4 skill buttons at r24 (30° apart on a 97 px circle). A 5th at 210° would sit at y≈350, past the screen edge, and 5 buttons at 22.5° would overlap (chord 38 px < 48 px). `docs/skills.md` already says "ใส่ปุ่มสกิลได้ 4 ช่อง". A Lv10 hero has 5 active skills (D1), so the 4 buttons become a bar the player assigns.

**Files:**
- Modify: `project.godot` `[input]` (add `skill_3` = key 3, `skill_4` = key 4)
- Modify: `scripts/ui/touch_buttons.gd:59-62` (`skill3` → action `skill_3`, `skill4` → action `skill_4`; new `set_icon(name, path)`)
- Modify: `scripts/ui/hud.gd:630-640, 645-660` (loop over the 4 bar slots: icon, `Lv%d` lock note, MP note, cooldown; `_skill_numbers` per bar id)
- Modify: `scripts/hero/hero.gd` (`bar: Array` of 4; `_physics_process` maps `skill_N` → `try_skill(bar[N-1])`; `assign_bar(slot, id) -> String`; `signal bar_changed`)
- Modify: `scripts/ui/skill_panel.gd` (a `ปุ่ม N` / `—` badge on each unlocked row; a tap cycles 1→2→3→4→— and swaps with the skill already in that slot; touch size ≥ `IconButton.MIN_TOUCH`)
- Modify: `scripts/rules/save_game.gd` (`bar` key: `new_state`, `_bar_ok`, `_state_ok`, load default), `scripts/dev/test_ground.gd` (save / load `bar`; `bar_changed` → `save_now()`)
- Test: `tests/test_skill_bar.gd` (new), `tests/test_save_hardening.gd`, `touch_check`

**Interfaces:**
- `Skills.default_bar(level: int) -> Array`: the first 4 unlocked ids in `active_ids()` order, padded with `""`. Lv10 → `["piercing","spread","arrow_rain","thorn_trap"]`; ศรเพลิง is swapped in from the panel (D1).
- `Hero.assign_bar(slot: int, id: String) -> String`: `""` on success; `"ยังไม่ปลด"` for a locked skill; an id already in another slot swaps; `""` as id empties the slot. When the level rises, empty slots fill with newly unlocked skills.
- Save key `"bar"`: optional. If present it is an Array of exactly 4 Strings, each `""` or an id in `Skills.active_ids()` unlocked at the save's level, with no non-empty repeats. Anything else fails the whole save (the same Q3 a rule as `combos`). The signature covers it. `VERSION` stays 4 (B14/B15 reasoning, as in Task 10). A missing key loads as `default_bar(level)`.

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_default_bar_by_level():     # Lv1 ["piercing","","",""]; Lv3 [+spread]; Lv7 [+arrow_rain]; Lv10 ["piercing","spread","arrow_rain","thorn_trap"]
func test_assign_swaps():             # Lv10: assign_bar(3, "fire_arrow") → bar[3] == "fire_arrow"; then assign_bar(0, "fire_arrow") → bar == ["fire_arrow","spread","arrow_rain","piercing"]
func test_assign_locked_refused():    # Lv9: assign_bar(3, "fire_arrow") == "ยังไม่ปลด"; bar unchanged
func test_keys_follow_bar():          # action skill_4 pressed with bar[3] == "fire_arrow" → hero state "shoot" drawing fire_arrow
func test_touch_has_four_skill_actions(): # TouchButtons: skill1..skill4 → actions skill_1..skill_4; positions unchanged (landscape and portrait)
func test_hud_button_states():        # Lv6: skill3 disabled, note "Lv7"; Lv10 with mp 13: skill4 (thorn_trap, MP 12) enabled, note "MP 12"; skill3 (rain, MP 18) dim
func test_hud_icon_follows_bar():     # assign fire_arrow to slot 4 → skill4 icon path == Skills.icon("fire_arrow")
func test_bar_round_trip():           # save at Lv10 with bar ["fire_arrow","spread","arrow_rain","piercing"] → load equal
func test_bad_bar_refuses_save():     # signed: ["piercing","piercing","",""], ["nope","","",""], ["fire_arrow","","",""] at level 9, 3 entries, [1,"","",""], "piercing" → new_state() + .bad.json
func test_old_save_gets_default_bar():# test_save_hardening.FIXTURE_V4 (no "bar") loads; bar == default_bar(level)
func test_save_with_all_skills_under_max_bytes(): # max state: gems on all 5 skills, all 16 combos (Task 10), bar → text size ≤ save.max_bytes
```

- [ ] **Step 2: Run and check it fails.** **Step 3: Implement.** **Step 4: Run and check it passes**, then run `test_hud_icons`, `touch_check`, the portrait tests, `test_save_hardening` and `test_skill_panel`.
- [ ] **Step 5: Commit** `git commit -m "M5b Task 8e: 4-slot skill bar (touch + keys 1-4 + panel assign, range-checked save key)"`

---

### Task 9: Area recipes on the real area skills (คลื่นกระแทก, อัคนีทะลวงพิภพ, ฝนดาวไฟ, เพลิงระเบิด, อาณาเขตพราน, ทุ่งเพลิง)

Runs after Tasks 8a–8d, on the real skills. ศรเพลิง carries the arrow-side recipes. ห่าศร and กับดักหนาม carry the zone recipes, and ห่าศร / ศรเพลิง carry เพลิงระเบิด. Tier-3 tests build with `SkillBuild.of(id, 19, …)` (skill Lv10 = 3 slots for กับดัก / ศรเพลิง; ห่าศร reaches it at char Lv16): the pure build ignores the phase-1 cap (D8). The temporary `test_fire_arrow` skill is not needed.

**Files:**
- Modify: `scripts/arrow.gd` (pierce-through and first-hit combo blast triggers), `scripts/rules/gem_combo.gd`, `scripts/skills/arrow_rain.gd`, `scripts/skills/thorn_trap.gd` (zone and radius hooks)
- Test: `tests/test_arrow_combos.gd`, `tests/test_gem_combo.gd`, `tests/test_area_skills.gd`

**Interfaces:**
- Produces: `GemCombo.area_radius_mult(b: Dictionary) -> float` (`b.area_mult` + `area_radius_bonus` when the combo has it); `GemCombo.zone_mods(id: String) -> Dictionary` `{"slow": float, "taken": float, "burn": bool}` (`{}` for non-zone recipes). Arrow: `blast_on_pierce` fires when a primary arrow passes through a target, `blast_on_hit` on its first hit (both on top of ศรเพลิง's own r32 blast: owner ②, rows read literally).
- ArrowRain and ThornTrap use `area_radius_mult(b)` for their radius and call `t.apply_zone(mods.slow, mods.taken, 0.25)` each step for monsters inside (a rain for its duration, a spent trap for `root_secs`). With `mods.burn` / `burn_all`, every target inside burns (0.2 × the last hit, or the tick's damage for rain).

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_shockwave_r32_80pct_excludes_struck():   # fire_arrow [pierce, expand] Lv10: passing through A makes a blast at A: B at 31 px hit with mult ≈ arrow_mult × 0.80, A not hit twice by it, C at 33 px not hit
func test_earth_piercer_r40_100pct_burns():        # fire_arrow (char Lv19) [pierce, expand, element fire]: B at 39 px hit ×1.00 and burning; one blast per pierced target; no shockwave (replaced)
func test_meteor_rain_r40_80pct_per_arrow():       # fire_arrow (char Lv19) [split, element fire, expand]: each of 3 arrows' first hit blasts r40 ×0.80 including the struck target; 3 arrows → 3 meteor blasts
func test_fire_burst_radius():                     # area_radius_mult for [element fire, expand] Lv1 ≈ 1.0 + 0.30 + 0.20; [expand] alone ≈ 1.30
func test_zone_mods():                             # zone_mods("hunter_zone") == {slow 0.30, taken 0.10, burn false}; hellfield {0.30, 0.20, true}; fire_fan → {}
func test_hunter_zone_on_rain():                   # arrow_rain [expand, extend]: dummies inside: speed ≈ 0.7, taken ≈ 1.10 while the rain lasts; outside: none
func test_hellfield_on_rain():                     # arrow_rain (char Lv16) [expand, extend, element fire]: zone 0.30 / 0.20 and every target inside burning
func test_hunter_zone_on_trap():                   # thorn_trap [expand, extend]: the rooted dummy is in a zone (taken ≈ 1.10) for root_secs (2.6 s)
func test_fire_burst_rain_radius():                # arrow_rain [element fire, expand]: radius ≈ 96 (dummy at 95 px hit), all hit targets burning
func test_fire_burst_fire_arrow():                 # fire_arrow [element fire, expand]: own blast radius ≈ 48, all blast targets burning
func test_area_recipes_formable_in_phase1():       # hero Lv10 sockets: arrow_rain [expand, extend] → hunter_zone; arrow_rain [element fire, expand] → fire_burst; fire_arrow [pierce, expand] → shockwave (the 3 tier-2 area recipes form at the cap)
```

- [ ] **Step 2: Run and check it fails.** **Step 3: Implement.** **Step 4: Run and check it passes**, then run `test_area_skills` and `test_arrow_gems`.
- [ ] **Step 5: Commit** `git commit -m "M5b Task 9: area recipes on ห่าศร / กับดักหนาม / ศรเพลิง (blasts + zones)"`

---

### Task 10: Discovered recipes: hero, signed save field, load

**Files:**
- Modify: `scripts/hero/hero.gd` (`combos_found`, `combo_found` signal, check after `socket`/`unsocket`, `after_load`), `scripts/rules/save_game.gd` (`new_state`, `_combos_ok`, `_state_ok`, `load_or_new` normalise), `scripts/dev/test_ground.gd:147-152, 598` (save and load)
- Modify: `tests/test_save_hardening.gd` (the max-state builder includes all 16 ids and stays ≤ `save.max_bytes`; Task 8e's size test adds gems on all 5 skills and the `bar` key on top)
- Test: `tests/test_save_combos.gd`

**Interfaces:**
- Consumes: `GemCombo.ids`, `GemCombo.resolve`, `Hero.return_closed_gems` (Task 1)
- Produces: `Hero.combos_found: Array` (ids, in discovery order); `signal combo_found(id: String, name: String)`; `Hero.after_load(found: Array) -> void` (sets the list, runs `return_closed_gems()`, then adds recipes the open sockets form without emitting); `SaveGame._combos_ok(c) -> bool`; save key `"combos"`

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_combos_round_trip():               # save {... "combos": ["fire_fan", "garuda"]} → load_or_new().combos == ["fire_fan", "garuda"]
func test_old_v4_save_loads_and_marks_silently(): # test_save_hardening.FIXTURE_V4 (no "combos") loads, combos == []; a hero with [split, fire] sockets → after_load([]) emits no combo_found and combos_found == ["fire_fan"]
func test_bad_combos_refuse_save():          # each signed with signature(): ["nope"], ["fire_fan","fire_fan"], [1], "fire_fan", {"a":1} → load returns new_state() and a .bad.json exists
func test_signature_covers_combos():         # write a good save, edit "fire_fan"→"garuda" in the text without re-signing → refused
func test_new_state_has_empty_combos():      # SaveGame.new_state().combos == []
func test_first_combo_announces_once():      # hero Lv1: socket split, socket fire → one combo_found("fire_fan", "ศรพัดเพลิง"); unsocket fire, socket it again → no second emit
func test_three_gem_announces_advanced():    # Lv10 with fire_fan found: socket multiply → combo_found("brahmastra", "พัดเพลิงพรหมาสตร์")
func test_save_still_under_max_bytes():      # max state from test_save_hardening + all 16 ids → text size ≤ save.max_bytes
func test_closed_slot_combo_never_discovered_on_load(): # (Task 3 review) hero Lv1 loading sockets piercing [split, homing, fire] (fire in closed slot 3, bag full so it stays):
                                            # after_load([]) → combos_found == [] (split+fire would be fire_fan only with slot 3 open), no combo_found emit; same with a free bag (fire goes back to the bag)
```

- [ ] **Step 2: Run and check it fails** (`TEST_ONLY=test_save_combos`).
- [ ] **Step 3: Implement.** `_combos_ok`: an Array; every element is a `TYPE_STRING` in `GemCombo.ids()`; no repeats. `_state_ok` checks `_combos_ok(d.get("combos", []))`. Load sets `d["combos"]` to an Array of String. VERSION stays 4. The reason, written as a comment at `VERSION`: an optional key doesn't make any old save out of range (B14), and bumping the version would make an older cached build refuse the save (B15). test_ground saves `"combos": hero.combos_found` and calls `hero.after_load(state.get("combos", []))` right after `hero.inventory.from_dict(...)`. `combo_found` triggers `save_now()` (it already listens to `gems_changed`).
- [ ] **Step 4: Run and check it passes.** Run `TEST_ONLY=test_save_combos`, then `TEST_ONLY=test_save_hardening` (FIXTURE_V4 must still load unchanged).
- [ ] **Step 5: Commit** `git commit -m "M5b Task 10: discovered combos in the signed save (range-checked, v4 kept)"`

---

### Task 11: Skill panel live text: name above icon, description and numbers, gold frames

**Files:**
- Create: `scripts/rules/skill_text.gd`
- Modify: `scripts/ui/skill_panel.gd` (row build :250-280, `refresh` :355-390, `_previews` :182-205)
- Test: `tests/test_skill_text.gd`, `tests/test_skill_panel_combos.gd`

**Interfaces:**
- Consumes: `SkillBuild.of`, `GemCombo.recipe`, `Hero.open_gems`
- Produces: `SkillText.title(skill_id: String, b: Dictionary) -> String`; `SkillText.describe(skill_id: String, b: Dictionary) -> String`; `SkillText.numbers(skill_id: String, b: Dictionary, before := {}) -> Array` of `{"text": String, "kind": "up"|"down"|"plain"}` (damage up or MP down → `up`, damage down or MP up → `down`); `SkillPanel.row_view(skill_id: String) -> Dictionary` `{"title", "title_color": Color, "desc", "numbers": Array, "gold_slots": Array, "tier": int}`. While a bag gem is selected, every unlocked skill it fits shows the preview build (same slot choice as `_previews`), with `before` = the current build.

- [ ] **Step 1: Write the failing tests** (spec §5, piercing at skill Lv10 = char Lv10, gem Lv1, no options, element_dmg 0)

```gdscript
func test_text_one_gem():   # title == "ศรทะลวง"; describe == "ยิงลูกศร 3 แนว ทะลุทุกตัวในแนว"; numbers texts == ["แนวละ 157%", "MP 11.2"]
func test_text_two_gems():  # [split, fire]: title == "ศรทะลวง · ศรพัดเพลิง";
                            # describe == "ยิงศรไฟ 3 แนว ทะลุทุกตัว ติดไหม้ 20%/วิ 3 วิ และทิ้งทางไฟ 2 วิ";
                            # numbers(b2, b1) == [{"text":"แนวละ 172% (+10%)","kind":"up"}, {"text":"MP 14.6","kind":"down"}]
func test_text_three_gems():# [split, fire, multiply]: title == "ศรทะลวง · พัดเพลิงพรหมาสตร์";
                            # describe == "ยิงศรพรหมาสตร์ 3 แนว ทะลุทุกตัว ทางไฟ 3 วิ ไหม้ 30%/วิ ปลายแนวระเบิดไฟ";
                            # numbers(b3, b2) texts == ["แนวละ 233% (+35%)", "ระเบิด 50%", "MP 21.8"], kinds [up, plain, down]
func test_every_recipe_has_text():   # for every recipe formable on any of the 5 active skills: title contains the recipe name; describe != ""
func test_area_skill_text():        # Lv10, no gems: describe("arrow_rain") == "ห่าศรตกเป็นวง r64 นาน 3 วิ ทิกละ 46%"; describe("thorn_trap") == "วางกับดักไกลสุด 160px ตรึง 2 วิ" with numbers ["150%", "MP 12"];
                                    # describe("fire_arrow") == "ยิงศรไฟ ไหม้ 20%/วิ 3 วิ ระเบิดวง r32"; with an ice gem the line says "ศรน้ำแข็ง" and has no ไหม้ (D7)
func test_row_gold_only_recipe_slots(): # hero Lv10 [split, fire, leech]: row_view.gold_slots == [0, 1], tier 2, title_color == SkillPanel.GOLD; no combo → gold_slots [], title_color == SkillPanel.TEXT
func test_preview_shows_delta():     # [split] socketed, fire gem selected in the bag: row_view("piercing").title == "ศรทะลวง · ศรพัดเพลิง", numbers[0] == {"แนวละ 172% (+10%)", "up"}, numbers[-1].kind == "down"
func test_preview_full_slots_breaks_combo(): # Lv1 [split, fire] (2/2), homing selected → preview replaces slot 1 (index 0): title == "ศรทะลวง", gold_slots == []
func test_title_above_icon():        # in the built row, the title Label's global y < the skill icon's global y (built in a tree at 640×360)
func test_closed_slot_gem_never_gold(): # (Task 3 review) hero Lv1, piercing [split, homing, fire] with fire stuck in closed slot 3 (bag full):
                                    # row_view title == "ศรทะลวง" (no combo name), title_color == SkillPanel.TEXT, gold_slots == [], no gold frame on any slot incl. index 2;
                                    # same while previewing a gem that would only form a combo with the closed-slot gem
# tests/test_gem_combo.gd: widen test_every_combo_reader_uses_open_gems (Task 3 review): in every file that calls SkillBuild.of / GemCombo.resolve,
# also flag any `skill_gems[` or `skill_gems.get(` read, except inside an allow-list of functions that manage the sockets themselves
# (hero.gd: open_gems, return_closed_gems, socket, unsocket, set_skill_gems; skill_panel.gd: only a function that draws closed slots
# as closed, each listed in the test with its reason). Today skill_panel.gd reads hero.skill_gems at :120, :142, :151, :376: move them to
# hero.open_gems (or the allow-list) in this task, so the guard passes.
```

- [ ] **Step 2: Run and check it fails.**
- [ ] **Step 3: Implement.** Each row becomes a VBox: title Label (gold when there is a combo, plus a modulate-pulse tween at tier 3: "ตัวทองประกาย"), then an HBox with icon, desc + numbers (`RichTextLabel` using UP/DOWN colours) and slots. Slots in `combo.slots` use `UiKit.style_cell(c, GOLD, ...)`; tier 3 adds a looping border-brightness tween ("กรอบทองมีแสงวิ่ง"). Numbers are formatted with `Gear._trim(snappedf(x, 0.1))` for MP and integer percent for damage. Deltas are `round((after/before − 1) × 100)` and shown only when `before` is given and the delta ≠ 0.
- [ ] **Step 4: Run and check it passes.** Run both new files plus `test_skill_panel`, `touch_check` and the portrait layout tests (the row grew taller).
- [ ] **Step 5: Commit** `git commit -m "M5b Task 11: live skill text (name above icon, green/red deltas, gold combo slots)"`

---

### Task 12: Discovery toast and the recipe book (สมุดสูตร)

**Files:**
- Modify: `scripts/ui/skill_panel.gd`
- Test: `tests/test_skill_panel_combos.gd`

**Interfaces:**
- Consumes: `Hero.combo_found`, `Hero.combos_found`, `GemCombo.recipes`, `GemCombo.describe`, `GemCombo.key_name`
- Produces: `SkillPanel.toast_text() -> String`; `SkillPanel.open_book()`, `close_book()`, `is_book_open() -> bool`; `SkillPanel.book_rows() -> Array` of `{"id", "tier", "name", "gems", "effect", "found": bool}`

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_toast_on_first_combo():   # panel open, socket split + fire → toast_text() == "ค้นพบท่าผสม! ศรพัดเพลิง", visible; hidden after HUD.TOAST_TIME (1.5 s); Sfx "toast" requested
func test_no_toast_when_known():    # fire_fan already in combos_found → socketing it again leaves toast_text() == ""
func test_book_rows():              # 16 rows in data order; found fire_fan row: name "ศรพัดเพลิง", gems "แยกศร + ธาตุไฟ" (via key_name), effect == GemCombo.describe("fire_fan");
                                    # unfound tier-2 row: name "???", gems "? + ?", effect ""; unfound tier-3: gems "? + ? + ?"
func test_book_blocks_taps_below(): # book open: a tap where a gem slot lies under the book changes no socket (risks.md B9); the book root has mouse_filter STOP
func test_book_closes_with_panel(): # close() → is_book_open() false; reopening the panel shows the skill rows
```

- [ ] **Step 2: Run and check it fails.**
- [ ] **Step 3: Implement.** Put a `สมุดสูตร` button in the panel header next to ✕ (touch size ≥ `IconButton.MIN_TOUCH`). The book is a full-panel overlay with a ScrollContainer of 16 rows (an icon pair per row: the gem icons for found rows, a dim "?" cell otherwise) and its own ✕. The toast is a Label on the panel's root, above the book, at the panel's top centre.
- [ ] **Step 4: Run and check it passes.**
- [ ] **Step 5: Commit** `git commit -m "M5b Task 12: ค้นพบท่าผสม! toast + สมุดสูตร recipe book"`

---

### Task 13: Docs, risks, screenshots, acceptance

**Files:**
- Modify: `docs/gems.md` (new §8 "ท่าผสม" short summary pointing to the spec; slot table already done in Task 1), `docs/risks.md` (new rows below), `docs/pixellab-budget.md` ("M5b gem combos and area-skill effects: 0 gen"; the area-skill icons and trap sprite, 30 gen, are already logged), `docs/skills.md` (a dated note under rows 36/42/53 with the owner's D1–D8 answers)
- Create: `tests/screenshots_m5b_combos.gd` → `docs/preview/m5b/`

risks.md rows:
- **S10 🟠:** combos are decided on the player's device (damage, freeze, MP refund). The discovered list is in the signed save, range-checked and cosmetic. Online play needs a server to decide this (S1).
- **B25 🟢:** the MP refund is capped 6 / 9 per press. Burn and trail kills count (owner "นับทุกแบบ") through the cast of the press that applied them, so they share that press's cap.
- **B26 🟢:** a freeze cancels an attack windup, and bosses freeze (owner). Watch boss fights for freeze-lock feel.
- **B27 🟠:** the 3 two-gem area recipes form in phase 1 (ห่าศร from Lv7, กับดักหนาม / ศรเพลิง at Lv10). The 3 three-gem area recipes need skill Lv10 (ห่าศร char Lv16, กับดัก / ศรเพลิง Lv19), so they stay ??? in the book until the level cap rises (owner D8).
- **B28 🟢:** the trap cap (2) is enforced in `TrapSet` and `Hero.try_skill`, not the touch UI. An armed trap ignores rooted monsters, so two traps on one spot cannot give 300% + a 4 s root. Rains and traps are cleared on warp, room change and death (B20).
- **B29 🟢:** the skill bar's `bar` save key is optional and range-checked (4 entries, unlocked ids, no repeats, signed, VERSION 4). Traps, rains and cooldowns are never saved.

- [ ] **Step 1: Write the screenshot script.** Header comment gives the run command `xvfb-run -a godot --path . --rendering-driver opengl3 --script tests/screenshots_m5b_combos.gd`. Outputs: `skill_panel_2gem.png` (Lv10 piercing [split, fire], gold frames, live text), `skill_panel_3gem.png` (brahmastra), `skill_panel_preview.png` (fire gem selected over [split]: green +10%, red MP), `combo_toast.png`, `recipe_book.png` (2 found, the rest ???), `fx_fire_trail.png`, `fx_brahmastra_blast.png`, `fx_thunder_hop.png`, `fx_frost_freeze.png`, `fx_garuda_mark.png`, `fx_bloodthirst_kill.png` (test ground seed 7, room c1r0, 1280×720, plus an ×3 crop for each FX), `skill_panel_portrait_3gem.png`, and for the area skills `area_rain.png`, `area_trap.png` (armed + triggered with a rooted monster), `area_fire_arrow_blast.png`, `area_hunter_zone.png`, `skill_panel_5_skills.png` and `hud_bar_lv10.png` (landscape + portrait, ศรเพลิง on button 4). The PR notes for each area image whether the icon / trap art is the owner's pick or the placeholder.
- [ ] **Step 2: Run the full suite.** `godot --headless --path . --script tests/run_tests.gd` → `RESULT passed=N failed=0`. Record N in the PR body.
- [ ] **Step 3: Run the screenshots and look at every image.** Check the Thai text renders (no tofu), the name sits above the icon, the frames are gold, the deltas are green/red, the book shows ???, each effect is visible on a monster, the rain circle and trap sit on the ground under the monsters (Y-sort), and the 4 HUD skill buttons show the right icons and lock notes.
- [ ] **Step 4: Web export and draft PR (coordinator).** `godot --headless --path . --export-release "Web" build/web/index.html` succeeds. Draft PR `m5b/gem-combos` → main with test counts, the screenshot list, the risks rows and the Thai owner summary.
- [ ] **Step 5: Commit** `git commit -m "M5b Task 13: combos docs, risks, budget, acceptance screenshots"`

---

## Self-review notes (done)

- **Spec coverage:** all 8 two-gem recipes and 8 three-gem recipes are covered by Tasks 2 and 5–9 (the 6 area recipes on the real area skills in Task 9). The 3 area skills follow docs/skills.md rows 36/42/53 and gems.md §2 (Tasks 8a–8d); owner D1 (both open at Lv10, assignable buttons) is 8a + 8e, D2 aiming is 8b `area_point`, D3 root is 8c, D4 trap life and radius is 8a + 8c, D5 blast is 8d, D6 extend is 8a, D7 element replacement is 8a + 8d (`test_ice_gem_replaces_burn`, `test_lightning_gem_replaces_burn`), D8 is Task 9 + B27. "Burn/trail kills count, capped" (owner 2026-11-09) is Global Constraints + Task 8 (`test_burn_kill_counts_and_shares_cap`) + B25. The slot rule plus the owner's 2026-11-09 addendum is Task 1. The MP rule is in Task 3 (`test_combo_adds_no_mp`). §5 live text is Task 11. Toast and book are Task 12. The effect reuse with 0 gen is Task 5 plus Task 13's budget line. Boss freeze is Tasks 4 and 7. The MP caps are Tasks 3 and 8. The save is Task 10. The docs (gems.md §3, m3a spec, panel text, test_gem, sim) are Task 1.
- **Not implemented, on purpose:** the spec row's "บอสช้าลง 60%" (overridden by the owner); the Lv10 job choice (owner D1: later milestone); joystick or hold-to-place aiming (D2).
- **Plan decisions to show the owner (not numbers):** gear `element_dmg` also applies to ศรเพลิง's own fire (8a); at most one hit sound and one `chain_zap` FX per rain tick (8b); fire-arrow tints for ice / lightning gems (8d); the panel's `ปุ่ม N` badge cycles on tap (8e); the Task 11 area-skill lines are Claude's wording.
- **Type check:** `ComboCast` (Task 3) is used in Tasks 5, 8, 8b and 8c (via `Hero.hit_source`). `SkillHit` (8b) is used in 8b, 8c and Task 9. `area_mult` / `dur_mult` (8a) feed `GemCombo.area_radius_mult` (Task 9). `apply_root` (8c) is separate from Task 4's `apply_freeze`; both make `speed_mult()` 0. `Skills.active_ids` / `icon` / `display_name` (8a) are used in 8e and Task 11. The optional `cast` argument on `apply_status("burn")` / `apply_trail` (Task 8) defaults to null, so Task 4 / 5 call sites stay valid. `combo` / `extra_bounces` build keys (Task 3) are used in Tasks 5–9 and 11. `Hero.open_gems` (Task 1) is used in Task 11. `return_closed_gems` (Task 1) is used in Task 10's `after_load`.
