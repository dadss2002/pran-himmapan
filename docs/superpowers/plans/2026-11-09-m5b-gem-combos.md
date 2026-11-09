# M5b Gem Combos (ท่าผสม 2 เม็ด + ท่าขั้นสูง 3 เม็ด) Implementation Plan

> **For agentic workers:** Implement this plan task-by-task, checking off each step. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two gems that form a recipe on one skill become a named combo (8 recipes), three become an advanced combo (8 recipes). Every skill gets 2 gem slots from unlock. The skill panel shows the combo live, a toast announces each first discovery, and a recipe book (สมุดสูตร) lists the recipes.

**Architecture:** Recipes and every number live in `data/balance.json` → `gem_combos.recipes`. A pure rules script (`GemCombo`) works out which recipe a skill's open sockets form. `SkillBuild` folds the stat-level parts into the build. A per-press ledger (`ComboCast`) enforces the per-cast caps and once-per-target rules. `Arrow` applies the on-hit effects. Monsters get freeze, mark, trail-burn and zone statuses in `StatusEffects`. The UI reads the same rules (`SkillText`) so the panel, the HUD and combat always agree. Discovered recipe ids go into the signed save as a new optional, range-checked key.

**Tech Stack:** Godot 4.5.1 (GDScript), headless test runner `tests/run_tests.gd`, xvfb + opengl3 screenshots, existing FX sheets in `assets/fx/manifest.json`.

**Spec:** `docs/superpowers/specs/2026-11-08-gem-combos.md` (Option A + "ตัวเลขเสนอ" §1–§5 + effect-reuse table; owner approval line 2026-11-08 and owner addendum 2026-11-09 at the end override earlier lines). Base gem rules: `docs/gems.md` (approved 2026-11-06). Numbers' source: `tools/gem_combo_sim.py`. Cheat rules: `docs/risks.md` S1/S5/B14/B15/B9.

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
- **Secondary hits** (plan decision): blasts, bolts, shockwaves, shatters and trail ticks are hits of the same press. They can crit with the arrow's crit chance, leech, and count kills for MP-on-kill (DoT ticks excepted: burn and trail kills give no MP). They never trigger combo effects themselves: no trail, bounce, bolt, blast, freeze count or mark from a secondary hit. Per-line effects (trail, line-end blast) belong to primary arrows only (the ones `Hero._release` fires).
- **Save (risks.md S5/B14/B15):** `SaveGame.VERSION` stays **4**. Add an optional `"combos"` key: an Array of unique known recipe id Strings. Anything else fails the whole save (Q3 a). The signature covers it. A missing key loads as `[]`.
- **Art:** 0 PixelLab gen. Effects reuse the manifest ids `piercing_trail, spread_burst, chain_zap, hit_spark, water_ripple, status_burn, status_frost, lock_on, warp_ring, crit_hit, pickup_pop`, recoloured through `modulate` only. Record "M5b: 0 gen" in `docs/pixellab-budget.md`.
- **Copy (verbatim):** toast `ค้นพบท่าผสม!`, book title `สมุดสูตร`, undiscovered `???`. Skill panel §5 strings: see Task 11. Colours: gains `#6ccf62` (SkillPanel.UP), losses / MP up `#ff9d8a` (SkillPanel.DOWN), combo name and frame `#edbb55` (SkillPanel.GOLD).
- Rules live in `scripts/rules/` with no scene access (risks.md §3, server-portable). Everything stays client-side (S1). The final report must say that online play will need a server to decide this.
- Owner reports are in Thai, short and factual (CLAUDE.md).

## Review Focus

1. **A save with sockets on a skill that has no numbers or is still locked** (e.g. `"arrow_rain": [expand gem]`, which `_skills_ok` accepts today, or 3 gems on piercing at char Lv1). `Skills.unlock_level("arrow_rain")` asserts on a missing key. Loading must not crash, and the gems must go back to the bag (or stay inert if the bag is full). → Task 1 `test_after_load_returns_gems_from_unknown_and_closed_slots`.
2. **Several touches on one target in one press** (3 split lines through a boss, bounce arrows, overlapping trails). A reasonable player expects one shatter, one freeze and one trail tick per second, not three. → Task 4 `test_trail_does_not_stack`, Task 7 `test_anodard_shatters_once_per_target_per_press`, Task 7 `test_frost_freezes_once_on_third_hit`.
3. **A freeze landing during an attack windup** (lunge_warn / bite / ring / throw), or on a dying monster. The attack must not go off while the monster is frozen, the warning must hide, and a dead monster ignores the freeze. → Task 4 `test_freeze_cancels_windup_and_holds`.
4. **Previewing a gem when every open slot is full** (the panel replaces slot 1), or a swap that breaks a combo. The live title, gold frames and deltas must match what socketing would really do. → Task 11 `test_preview_full_slots_breaks_combo`.
5. **The save's discovered list**: an old v4 save without the key must load and quietly mark combos that its sockets already form (no toast storm on load). Unknown ids, duplicates or non-strings must fail the save. → Task 10 `test_old_v4_save_loads_and_marks_silently`, `test_bad_combos_refuse_save`.

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

Task order puts what phase 1 can use first (piercing/spread recipes). Area recipes (Task 9) are built generically but no in-game skill can form them yet (see open question Q3).

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

- [ ] **Step 1: Write the failing tests**

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

- [ ] **Step 2: Run them and check they fail**

Run: `TEST_ONLY=test_gem godot --headless --path . --script tests/run_tests.gd` and `TEST_ONLY=test_hero_gems ...`
Expected: FAIL `slots_for(1) = 1, want 2`; `return_closed_gems` not found.

- [ ] **Step 3: Implement**

`gem_slots: [1, 1, 10, 50]`. Add `Skills.exists(id) -> bool` (= `Balance.has("skills.%s.unlock" % id)`). In `Hero.gem_slots`, return 0 when the skill does not exist. Add `Hero.open_gems`, and have `build()` use it. `return_closed_gems()` walks every skill in `skill_gems` from the highest index down. For each gem at an index ≥ `gem_slots(id)` it calls `inventory.add_gem(g)`. On success it sets that socket to null; on failure it leaves the gem there. It emits `gems_changed` if anything moved. `_skills_ok` keeps a per-skill set of gem types and returns false on a repeat. The game can't produce one, so no real save is lost (B14). The panel text becomes `"ช่องเจม: 2 ช่องตั้งแต่ปลดสกิล · ช่องที่ 3 ที่เลเวลสกิล %d · ช่องที่ 4 ที่เลเวลสกิล %d · ถอดเจมฟรี เจมเก็บ EXP ไว้"`, filled from `gem_slots[2]` and `gem_slots[3]`. Update docs/gems.md §3 to the 1/1/10/50 table, and replace its phase-1 note with "ศรทะลวงได้ 3 ช่องที่ตัวละคร Lv10 · สกิลอื่น 2 ช่อง". In the sim, `slots(L, s)` becomes `0 if sl < 1 else 2 + (sl >= 10) + (sl >= 50)`.

- [ ] **Step 4: Run them and check they pass.** The same commands give `failed=0`. Then run the full suite to catch any other test that assumed 1 slot at Lv1 (`test_skill_panel`, `touch_check`). Fix those assertions to the new rule only.

- [ ] **Step 5: Commit**

```bash
git add data/balance.json scripts/hero/skills.gd scripts/hero/hero.gd scripts/ui/skill_panel.gd scripts/rules/save_game.gd tests/test_gem.gd tests/test_hero_gems.gd tests/test_save_hardening.gd docs/gems.md docs/superpowers/specs/2026-11-06-m3a-gems-enhance-design.md tools/gem_combo_sim.py
git commit -m "M5b Task 1: 2 gem slots from unlock (slot 3 at skill Lv10), closed-slot gems back to the bag"
```

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

- [ ] **Step 1: Write the failing tests**

```gdscript
# tests/test_gem_combo.gd
const SPEC := {   # spec §1 and §2 at gem Lv1, verbatim
	"fire_fan":      {"tier": 2, "name": "ศรพัดเพลิง", "gems": ["split", "fire"], "trail_secs": 2.0, "trail_frac": 0.20},
	"thunder_hop":   {"tier": 2, "name": "ศรอสนีกระโดด", "gems": ["ricochet", "lightning"], "extra_bounces": 1, "bolts": 1, "bolt_frac": 0.50},
	"hawk_eye":      {"tier": 2, "name": "ศรตาเหยี่ยว", "gems": ["homing", "execute"], "homing_full": 1, "crit_bonus": 0.15, "mark_secs": 4.0, "mark_taken": 0.20},
	"bloodthirst":   {"tier": 2, "name": "ศรกระหายเลือด", "gems": ["leech", "multiply"], "leech_mult": 2.0, "kill_heal_frac": 0.03, "kill_mp": 2, "kill_mp_cap": 6},
	"frost_shard":   {"tier": 2, "name": "ศรเกล็ดน้ำแข็ง", "gems": ["ice", "split"], "freeze_hits": 3, "freeze_secs": 1.0, "freeze_lock_secs": 5.0, "bonus_vs_chilled": 0.25},
	"shockwave":     {"tier": 2, "name": "ศรคลื่นกระแทก", "gems": ["pierce", "expand"], "blast_on_pierce": 1, "blast_radius": 32, "blast_frac": 0.80},
	"hunter_zone":   {"tier": 2, "name": "อาณาเขตพราน", "gems": ["expand", "extend"], "zone_slow": 0.30, "zone_taken": 0.10},
	"fire_burst":    {"tier": 2, "name": "ศรเพลิงระเบิด", "gems": ["fire", "expand"], "area_radius_bonus": 0.20, "burn_all": 1},
	"brahmastra":    {"tier": 3, "name": "พัดเพลิงพรหมาสตร์", "gems": ["split", "fire", "multiply"], "bases": ["fire_fan"], "trail_secs": 3.0, "trail_frac": 0.30, "blast_on_line_end": 1, "blast_radius": 32, "blast_frac": 0.50},
	"thousand_bolts":{"tier": 3, "name": "ศรอสนีพันสาย", "gems": ["ricochet", "lightning", "split"], "bases": ["thunder_hop"], "bolts": 2, "bolt_frac": 0.50},
	"garuda":        {"tier": 3, "name": "ศรเนตรพญาครุฑ", "gems": ["homing", "execute", "multiply"], "bases": ["hawk_eye"], "homing_full": 1, "crit_bonus": 0.15, "mark_secs": 4.0, "mark_taken": 0.30, "sure_crit_marked": 1},
	"anodard":       {"tier": 3, "name": "ศรผลึกอโนดาต", "gems": ["ice", "split", "execute"], "bases": ["frost_shard"], "freeze_hits": 3, "freeze_secs": 1.0, "freeze_lock_secs": 5.0, "sure_crit_chilled": 1, "blast_on_chilled": 1, "blast_radius": 32, "blast_frac": 0.50},
	"rahu":          {"tier": 3, "name": "ศรราหูอมจันทร์", "gems": ["leech", "multiply", "execute"], "bases": ["bloodthirst"], "hp_min": 0.70, "hp_bonus": 0.30, "leech_mult": 2.0, "crit_heal_frac": 0.01, "kill_mp": 3, "kill_mp_cap": 9},
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

- [ ] **Step 2: Run and check it fails.** `TEST_ONLY=test_gem_combo ...` → FAIL, "GemCombo" not declared.

- [ ] **Step 3: Implement.** Add the `gem_combos` block with exactly the SPEC values and the fx rows from Task 5's table. Write `GemCombo` with the signatures above. `resolve` keeps only Dictionary gems that fit, maps them to keys, and picks the first tier-3 recipe in data order whose keys ⊆ the set. If there is none, it picks the first tier-2 recipe the same way. `slots` = indices of the gems whose keys are in the recipe. `describe` builds its text from the row's numbers: one `match` on id, with the sentences taken from the spec's ผลพิเศษ/ผล columns.

- [ ] **Step 4: Run and check it passes.** `TEST_ONLY=test_gem_combo` → `failed=0`. Also run `TEST_ONLY=test_balance` so the JSON still parses.

- [ ] **Step 5: Commit** `git commit -m "M5b Task 2: gem combo recipes (16) in balance.json + GemCombo resolver"`

---

### Task 3: SkillBuild combo stats and the ComboCast per-press ledger

**Files:**
- Modify: `scripts/rules/skill_build.gd`
- Create: `scripts/rules/combo_cast.gd`
- Test: `tests/test_combo_cast.gd`; add to `tests/test_skill_text.gd` later. Build tests go in `tests/test_gem_combo.gd` (section "build").

**Interfaces:**
- Consumes: `GemCombo.resolve`, `GemCombo.p`
- Produces:
  - `SkillBuild.of(...)` gains output keys `"combo": Dictionary` (the resolve result) and `"extra_bounces": int`. `crit` adds `crit_bonus`. `leech` is multiplied by `leech_mult`. With `homing_full`, homing does not multiply `per_arrow`. `mp` is unchanged by combos.
  - `class_name ComboCast extends RefCounted`: `func _init(id := "", hp_frac := 1.0)`, `var id: String`, `func dmg_bonus() -> float` (Rahu: `hp_bonus` if `hp_frac >= hp_min`, else 0), `func refund_mp(per_kill: int) -> int` (granted after the cap), `func count_hit(target_key: int) -> int` (returns the new count), `func once(tag: String, target_key: int) -> bool`

- [ ] **Step 1: Write the failing tests**

```gdscript
# build (char Lv10, gem Lv1, no options, hero_stats {"crit": 0.05, "element_dmg": 0.0, "skill_cd_cut": 0.0})
func test_build_spec_section5_numbers():  # piercing [split]: arrow_mult≈1.566 mp≈11.2 combo {} ; [split, fire]: 1.7226, 14.56, combo.id "fire_fan"; [split, fire, multiply]: 2.32551, 21.84, "brahmastra"
func test_combo_adds_no_mp():             # for every recipe formable on piercing: mp == 8 × Π gem mp multipliers (is_equal_approx)
func test_hawk_eye_homing_full_crit():    # [homing, execute] Lv1: arrow_mult ≈ Skills.damage_mult("piercing",1) (no ×0.9); crit ≈ 0.05+0.15+0.15
func test_homing_alone_keeps_penalty():   # [homing]: arrow_mult ≈ 1.8 × 0.9
func test_bloodthirst_doubles_leech():    # [leech, multiply] Lv1 leech ≈ 0.06; leech gem Lv5 → ≈ (0.03+0.004)×2
func test_thunder_hop_extra_bounce():     # [ricochet, lightning] extra_bounces == 1; [ricochet, lightning, split] (thousand_bolts) extra_bounces == 0
# tests/test_combo_cast.gd
func test_bloodthirst_refund_caps_at_6(): # c = ComboCast.new("bloodthirst"); [c.refund_mp(2) ×4] == [2,2,2,0]
func test_rahu_refund_caps_at_9():        # ComboCast.new("rahu"): refund_mp(3) ×4 == [3,3,3,0]
func test_no_combo_no_refund():           # ComboCast.new("").refund_mp(2) == 0; ComboCast.new("fire_fan").refund_mp(2) == 0
func test_once_per_target():              # once("shatter", 7) true, again false; once("shatter", 8) true; once("freeze", 7) true
func test_count_hit():                    # count_hit(5) → 1, 2, 3; count_hit(6) → 1
func test_rahu_hp_threshold():            # ComboCast.new("rahu", 0.70).dmg_bonus() ≈ 0.30; 0.69 → 0.0; ComboCast.new("garuda", 1.0) → 0.0
```

- [ ] **Step 2: Run and check they fail** (`TEST_ONLY=test_combo_cast`, `TEST_ONLY=test_gem_combo`).
- [ ] **Step 3: Implement** the changes and the class as listed. The refund cap comes from `GemCombo.p(id, "kill_mp_cap")`, and the per-kill amount from `p(id, "kill_mp")`. `refund_mp` takes the per-kill amount so Task 8 can pass it in.
- [ ] **Step 4: Run and check they pass.** Then run the full suite: `test_hero_gems`, `test_arrow_gems` and `test_skill_panel` must stay green, because a build without a combo is unchanged.
- [ ] **Step 5: Commit** `git commit -m "M5b Task 3: SkillBuild combo stats + ComboCast per-press ledger (MP-on-kill caps 6/9)"`

---

### Task 4: Monster statuses: freeze (with lock), mark, trail burn, zone

**Files:**
- Modify: `scripts/monsters/status_effects.gd`, `scripts/monsters/wolf.gd` (status API near :186, `receive_hit` :213, `tick_burn` :345, `step` :354, `status_tint` :298, `_update_status_fx` :290)
- Modify: `tests/dummy_enemy.gd`
- Test: `tests/test_status_combo.gd`

**Interfaces:**
- Produces on `StatusEffects`: `apply_freeze(secs: float, lock_secs: float) -> bool` (false while locked or already frozen); `is_frozen() -> bool`; `apply_mark(taken: float, secs: float)` (keeps the highest `taken` while active and refreshes the time); `is_marked() -> bool`; `apply_trail(per_tick: float, hold: float, source: Object)` (keeps the highest per_tick; burns while `hold` > 0; ticks every `elements.fire.tick`); `apply_zone(slow: float, taken: float, hold: float)`; `taken_mult() -> float` = (1 + mark) × (1 + zone_taken); `speed_mult()` = 0 when frozen, otherwise (1 − ice slow if slowed) × (1 − zone slow if in zone); `tick()` returns burn + trail damage; `clear()` clears everything.
- Produces on `Wolf` (and the same names on `tests/dummy_enemy.gd`): `apply_freeze(secs, lock_secs) -> bool`, `apply_mark(taken, secs)`, `apply_trail(raw_per_tick, hold, source)` (applies its own DEF: per_tick = raw × (1 − def/(def+100))), `apply_zone(slow, taken, hold)`, `is_frozen()`, `is_chilled()` (slowed or frozen), `is_marked()`. `receive_hit` multiplies `mult` by `status.taken_mult()`. Burn and trail ticks are multiplied by it too.

- [ ] **Step 1: Write the failing tests**

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

- [ ] **Step 2: Run and check it fails** (`TEST_ONLY=test_status_combo`).
- [ ] **Step 3: Implement.** In `Wolf.step`, after `_update_status_fx()`, a frozen monster gets `velocity = Vector2.ZERO` and the body animation paused; the step returns before the state `match` (cooldowns still tick). `apply_freeze` on a monster in an attack windup (any of `_fight_states()` other than chase) ends it: `_end_lunge()`, `_show_telegraph(false)`, state set to `"chase"`, and its attack cooldown is left as it was. Frost FX and tint show while frozen. `Monster.step` (monster.gd:148) gets no special case, since its windups go through `super.step`. Check ring and throw too, and cancel their telegraphs the same way.
- [ ] **Step 4: Run and check it passes.** Run `TEST_ONLY=test_status_combo`, then `test_monsters`, `test_elite` and the tint tests (`test_frost_tint_reads_as_ice_on_every_monster`) to catch regressions.
- [ ] **Step 5: Commit** `git commit -m "M5b Task 4: freeze (5 s lock, bosses too), mark, non-stacking trail burn, zone statuses"`

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
| fire_fan / brahmastra | trail → piercing_trail (#ff8a3d) + status_burn; brahmastra line_end → spread_burst (#ff8a3d) |
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

- [ ] **Step 1: Write the failing tests**

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

- [ ] **Step 2: Run and check it fails** (`TEST_ONLY=test_arrow_combos`).
- [ ] **Step 3: Implement.** A primary arrow whose `build.combo` has `trail_secs` creates one FireTrail at launch, calls `extend_to` every advance, and calls `finish()` in `_finish`/`halt`. `halt()` (warp) frees the trail immediately so no damage happens after the warp (B20). The trail damages targets within `t.hurt_radius()` (else `shot.arrow_hit_radius`) of the segment by calling `t.apply_trail(frac × atk × mult, 0.25, source)` each step. `blast_on_line_end` → `blast(position, r, frac, false)` once in `_finish`, primary arrows only. `_secondary_hit` calls `t.receive_hit(atk, mult × frac, at, crit_chance, crit_mult)` and then `_leech` and the kill hook from Task 8. It never calls `_after_hit`.
- [ ] **Step 4: Run and check it passes.** Run `TEST_ONLY=test_arrow_combos`, then `test_arrow_gems` and `test_hero_gems`.
- [ ] **Step 5: Commit** `git commit -m "M5b Task 5: combo FX reuse + fire trail and line-end blast (ศรพัดเพลิง, พรหมาสตร์)"`

---

### Task 6: Lightning combos (ศรอสนีกระโดด, ศรอสนีพันสาย)

**Files:**
- Modify: `scripts/arrow.gd` (`_spawn_bounce` :103-118, bounce event, `bolts`)
- Test: `tests/test_arrow_combos.gd`

**Interfaces:**
- Consumes: `build.extra_bounces`, `GemCombo.p(id, "bolts" / "bolt_frac")`, `Arrow._secondary_hit`, `ComboFx.play(..., "bounce", at)`
- Produces: `Arrow.bolts(from: Vector2, n: int, frac: float, skip: Array) -> int` (hits the n nearest distinct live targets within `elements.lightning.range`, skipping `skip`)

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_thunder_hop_two_bounces_on_piercing():  # piercing [ricochet, lightning] Lv1, dummies A (in line), B, C chained within 120 px:
                                                  # hit order A, B, C (gem's 1 bounce + 1 extra); without the combo (ricochet only) only A, B (existing rule)
func test_thunder_hop_bolt_per_bounce():          # dummy D near each bounce point (not A/B/C): D gets one hit per bounce with mult ≈ arrow_mult × bounce_mult^k × 0.50
func test_thousand_bolts_two_bolts_no_extra():    # [ricochet, lightning, split]: each line bounces once (no extra); each bounce bolts the 2 nearest distinct targets at 0.50
func test_bolt_without_target_is_safe():          # lone target: no error, bolts(...) == 0
func test_lightning_gem_chain_still_works():      # element lightning's own +1 target ×0.8 still happens on primary hits (gems keep working)
```

- [ ] **Step 2: Run and check it fails.**
- [ ] **Step 3: Implement.** On spawning a bounce arrow, the child gets `bounces = base_child + parent.build.extra_bounces` and `extra_bounces = 0`. This adds exactly +1 to each chain, piercing lines included. At every bounce event, `bolts(from, p("bolts"), p("bolt_frac"), [struck, next])` runs. A bolt is a secondary hit.
- [ ] **Step 4: Run and check it passes.** Run `test_arrow_combos` and `test_arrow_gems` (`test_piercing_bounces_only_from_first_target` must still pass for no-combo builds).
- [ ] **Step 5: Commit** `git commit -m "M5b Task 6: lightning combos (+1 bounce, bolts per bounce)"`

---

### Task 7: Mark and frost combos (ศรตาเหยี่ยว, ศรเนตรพญาครุฑ, ศรเกล็ดน้ำแข็ง, ศรผลึกอโนดาต)

**Files:**
- Modify: `scripts/arrow.gd` (`_combo_on_hit` and pre-hit mult/crit), `tests/dummy_enemy.gd` (record `crit_chance` per hit)
- Test: `tests/test_arrow_combos.gd`

**Interfaces:**
- Consumes: `ComboCast.count_hit`, `ComboCast.once`, the Wolf status API, `Arrow.blast`, `ComboFx.play`
- Produces: none new. Arrow behaviour only.

- [ ] **Step 1: Write the failing tests**

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

- [ ] **Step 2: Run and check it fails.**
- [ ] **Step 3: Implement.** Before a primary or bounce arrow hit, the arrow checks: `sure_crit_marked` and the target is marked → crit_chance 1.0; `sure_crit_chilled` and the target is chilled → 1.0; `bonus_vs_chilled` and the target is chilled → mult × (1 + bonus). After the hit: `mark_secs` → `apply_mark(mark_taken, mark_secs)` plus ComboFx "mark"; `freeze_hits` → if `cast.count_hit(id) == freeze_hits`, call `apply_freeze(freeze_secs, freeze_lock_secs)` plus FX; `blast_on_chilled` and the target was chilled and `cast.once("shatter", id)` → `blast(t.hurt_point(), r, frac, false, t)`.
- [ ] **Step 4: Run and check it passes.**
- [ ] **Step 5: Commit** `git commit -m "M5b Task 7: mark (ตาเหยี่ยว/ครุฑ) and freeze (เกล็ดน้ำแข็ง/อโนดาต) combos"`

---

### Task 8: Sustain combos and MP-on-kill caps (ศรกระหายเลือด, ศรราหูอมจันทร์)

**Files:**
- Modify: `scripts/hero/hero.gd` (add hooks), `scripts/arrow.gd` (kill and crit detection in `_after_hit` and `_secondary_hit`), `tests/dummy_enemy.gd` (`die_on_hit`)
- Test: `tests/test_arrow_combos.gd`, `tests/test_hero_gems.gd`

**Interfaces:**
- Consumes: `ComboCast.refund_mp`, `ComboCast.dmg_bonus`, `Hero.leech_heal(amount: float)`
- Produces: `Hero.on_combo_kill(cast: ComboCast) -> void` (heals `kill_heal_frac × max_hp` through `leech_heal`; `mp = minf(max_mp(), mp + cast.refund_mp(int(kill_mp)))`); `Hero.on_combo_crit(cast: ComboCast) -> void` (heals `crit_heal_frac × max_hp`). An arrow calls `on_combo_kill` when `amount > 0 and not t.is_alive()` after a direct or secondary hit (never from burn or trail ticks), and `on_combo_crit` on a crit hit.

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_bloodthirst_mp_cap_6_per_press():   # hero Lv10, mp 40, spread [leech, multiply] (MP 12 × 1.2 × 1.5 = 21.6), 5 die_on_hit dummies killed by the 5 arrows of one press: mp ≈ 40 − 21.6 + 6 (not +10)
func test_cap_resets_each_press():            # after the cooldown a second press kills 3 more: +6 again
func test_bloodthirst_kill_heals_3pct():      # hp = max_hp / 2, dummy deals amount 1 (normal leech stays < 1 HP): after one kill hp == max_hp / 2 + floor(0.03 × max_hp)
func test_rahu_mp_cap_9():                    # [leech, multiply, execute], 5 kills → +9
func test_rahu_bonus_only_at_70pct_hp():      # hp = 0.70 × max: arrow mult ≈ build.arrow_mult × 1.30; hp 0.69 × max: × 1.0 (checked at release)
func test_rahu_crit_heals_1pct():             # forced crit (crit_chance 1.0 via the dummy recording) heals 0.01 × max_hp
func test_refund_never_exceeds_max_mp():      # mp at max − 1, 3 kills → mp == max_mp()
func test_burn_kill_gives_no_mp():            # a monster killed by its burn tick after the press → mp unchanged
func test_bounce_and_bolt_kills_share_cap():  # [leech, multiply] + ricochet: kills by bounce arrows count toward the same 6
```

- [ ] **Step 2: Run and check it fails.**
- [ ] **Step 3: Implement.** `Hero._release` builds `ComboCast.new(b.combo.get("id", ""), float(health.hp) / health.max_hp)` once per press and shares it through `b["cast"]` (bounce arrows copy the build shallowly, so they share the same object). Rahu's `dmg_bonus()` is applied once to `b.arrow_mult` at release.
- [ ] **Step 4: Run and check it passes.**
- [ ] **Step 5: Commit** `git commit -m "M5b Task 8: sustain combos; MP on kill capped 6 / 9 per press"`

---

### Task 9: Area recipes built generically (คลื่นกระแทก, อัคนีทะลวงพิภพ, ฝนดาวไฟ, เพลิงระเบิด, อาณาเขตพราน, ทุ่งเพลิง)

No skill in the game has the `area` label with numbers yet (ห่าศร has labels only; กับดักหนาม and ศรเพลิง don't exist). This task builds the arrow-side and rule-side parts so the future area-skill task only has to call them. Tests use a temporary `test_fire_arrow` skill added to `Balance.data()` (`skills.test_fire_arrow = {unlock 1, mult 2.0, cooldown 6, mp 14}`, labels `["arrow","area"]`, `Balance.clear_cache()`, removed at the end).

**Files:**
- Modify: `scripts/arrow.gd` (pierce-through and first-hit blast triggers), `scripts/rules/gem_combo.gd`
- Test: `tests/test_arrow_combos.gd`, `tests/test_gem_combo.gd`

**Interfaces:**
- Produces: `GemCombo.area_radius_mult(b: Dictionary) -> float` (1 + expand effect + `area_radius_bonus` when the combo has it); `GemCombo.zone_mods(id: String) -> Dictionary` `{"slow": float, "taken": float, "burn": bool}` (`{}` for non-zone recipes). Arrow: `blast_on_pierce` fires when a primary arrow passes through a target, `blast_on_hit` on its first hit.
- Hook for the later area-skill task: ห่าศร/กับดัก call `t.apply_zone(mods.slow, mods.taken, hold)` for monsters inside, and use `area_radius_mult` for their radius.

- [ ] **Step 1: Write the failing tests**

```gdscript
func test_shockwave_r32_80pct_excludes_struck():   # test_fire_arrow [pierce, expand]: passing through A makes a blast at A: B at 31 px hit with mult ≈ arrow_mult × 0.80, A not hit twice, C at 33 px not hit
func test_earth_piercer_r40_100pct_burns():        # [pierce, expand, fire]: B at 39 px hit ×1.00 and burning; one blast per pierced target; no shockwave (replaced)
func test_meteor_rain_r40_80pct_per_arrow():       # [split, fire, expand]: each of 3 arrows' first hit blasts r40 ×0.80 including the struck target; 3 arrows → 3 blasts
func test_fire_burst_radius():                     # area_radius_mult for [fire, expand] Lv1 ≈ 1.0 + 0.30 + 0.20; [expand] alone ≈ 1.30
func test_zone_mods():                             # zone_mods("hunter_zone") == {slow 0.30, taken 0.10, burn false}; hellfield {0.30, 0.20, true}; fire_fan → {}
```

- [ ] **Step 2: Run and check it fails.** **Step 3: Implement.** **Step 4: Run and check it passes.**
- [ ] **Step 5: Commit** `git commit -m "M5b Task 9: area recipes (arrow blasts + zone rules) ready for area skills"`

---

### Task 10: Discovered recipes: hero, signed save field, load

**Files:**
- Modify: `scripts/hero/hero.gd` (`combos_found`, `combo_found` signal, check after `socket`/`unsocket`, `after_load`), `scripts/rules/save_game.gd` (`new_state`, `_combos_ok`, `_state_ok`, `load_or_new` normalise), `scripts/dev/test_ground.gd:147-152, 598` (save and load)
- Modify: `tests/test_save_hardening.gd` (the max-state builder includes all 16 ids and stays ≤ `save.max_bytes`)
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
func test_every_recipe_has_text():   # for every recipe formable on piercing or spread: title contains the recipe name; describe != ""
func test_row_gold_only_recipe_slots(): # hero Lv10 [split, fire, leech]: row_view.gold_slots == [0, 1], tier 2, title_color == SkillPanel.GOLD; no combo → gold_slots [], title_color == SkillPanel.TEXT
func test_preview_shows_delta():     # [split] socketed, fire gem selected in the bag: row_view("piercing").title == "ศรทะลวง · ศรพัดเพลิง", numbers[0] == {"แนวละ 172% (+10%)", "up"}, numbers[-1].kind == "down"
func test_preview_full_slots_breaks_combo(): # Lv1 [split, fire] (2/2), homing selected → preview replaces slot 1 (index 0): title == "ศรทะลวง", gold_slots == []
func test_title_above_icon():        # in the built row, the title Label's global y < the skill icon's global y (built in a tree at 640×360)
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
- Modify: `docs/gems.md` (new §8 "ท่าผสม" short summary pointing to the spec; slot table already done in Task 1), `docs/risks.md` (new rows below), `docs/pixellab-budget.md` ("M5b gem combos: 0 gen")
- Create: `tests/screenshots_m5b_combos.gd` → `docs/preview/m5b/`

risks.md rows:
- **S10 🟠:** combos are decided on the player's device (damage, freeze, MP refund). The discovered list is in the signed save, range-checked and cosmetic. Online play needs a server to decide this (S1).
- **B24 🟢:** the MP refund is capped 6 / 9 per press; burn/trail kills give none.
- **B25 🟢:** a freeze cancels an attack windup, and bosses freeze (owner). Watch boss fights for freeze-lock feel.
- **B26 🟠:** the 6 area recipes show as ??? until the area skills are built.

- [ ] **Step 1: Write the screenshot script.** Header comment gives the run command `xvfb-run -a godot --path . --rendering-driver opengl3 --script tests/screenshots_m5b_combos.gd`. Outputs: `skill_panel_2gem.png` (Lv10 piercing [split, fire], gold frames, live text), `skill_panel_3gem.png` (brahmastra), `skill_panel_preview.png` (fire gem selected over [split]: green +10%, red MP), `combo_toast.png`, `recipe_book.png` (2 found, the rest ???), `fx_fire_trail.png`, `fx_brahmastra_blast.png`, `fx_thunder_hop.png`, `fx_frost_freeze.png`, `fx_garuda_mark.png`, `fx_bloodthirst_kill.png` (test ground seed 7, room c1r0, 1280×720, plus an ×3 crop for each FX), and `skill_panel_portrait_3gem.png`.
- [ ] **Step 2: Run the full suite.** `godot --headless --path . --script tests/run_tests.gd` → `RESULT passed=N failed=0`. Record N in the PR body.
- [ ] **Step 3: Run the screenshots and look at every image.** Check the Thai text renders (no tofu), the name sits above the icon, the frames are gold, the deltas are green/red, the book shows ???, and each effect is visible on a monster.
- [ ] **Step 4: Web export and draft PR (coordinator).** `godot --headless --path . --export-release "Web" build/web/index.html` succeeds. Draft PR `m5b/gem-combos` → main with test counts, the screenshot list, the risks rows and the Thai owner summary.
- [ ] **Step 5: Commit** `git commit -m "M5b Task 13: combos docs, risks, budget, acceptance screenshots"`

---

## Self-review notes (done)

- **Spec coverage:** all 8 two-gem recipes and 8 three-gem recipes are covered by Tasks 2 and 5–9. The slot rule plus the owner's 2026-11-09 addendum is Task 1. The MP rule is in Task 3 (`test_combo_adds_no_mp`). §5 live text is Task 11. Toast and book are Task 12. The effect reuse with 0 gen is Task 5 plus Task 13's budget line. Boss freeze is Tasks 4 and 7. The MP caps are Tasks 3 and 8. The save is Task 10. The docs (gems.md §3, m3a spec, panel text, test_gem, sim) are Task 1.
- **Not implemented, on purpose:** the spec row's "บอสช้าลง 60%" (overridden by the owner), and in-game area skills (outside this spec; see Q3).
- **Type check:** `ComboCast` (Task 3) is used in Tasks 5 and 8. `combo` / `extra_bounces` build keys (Task 3) are used in Tasks 5–9 and 11. `Hero.open_gems` (Task 1) is used in Task 11. `return_closed_gems` (Task 1) is used in Task 10's `after_load`.
