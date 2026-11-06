# M3a Gems in Skills + Enhancement Implementation Plan

> **For agentic workers:** Implement this plan task-by-task, checking off each step. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gems socket into skills and change how they fire (main effect grows with gem level; random skill-only options are fixed at drop), and bows/armor can be enhanced +1…+10 with ore and gold.

**Architecture:** Two new pure rule classes on balance.json data: `Gem` (rolls, level scaling, EXP) and `SkillBuild` (everything one skill does with its gems, used by Hero, HUD and the skill screen), plus `Enhance` (chances, costs, try). Arrows gain ricochet / homing / extra pierce / leech / element hooks; wolves get a small `StatusEffects` (burn, slow). UI: new `SkillPanel` (HUD "สกิล" button, key N) and `EnhancePanel` opened from the bag. Save version 3 migrates 1 and 2.

**Tech Stack:** Godot 4.5.1 GDScript, headless runner `tests/run_tests.gd`, xvfb screenshots + `tests/touch_check.gd`, PixelLab vfx_workbench (0 gen) for status effects.

**Spec:** `docs/superpowers/specs/2026-11-06-m3a-gems-enhance-design.md` (owner approved 2026-11-06) with `docs/gems.md`, `docs/spec-numbers.md` §5 §7, `docs/skills.md`.

## Global Constraints
- Every number in `data/balance.json`, read through `Balance`; none in code.
- 0 PixelLab generations. Effects only via vfx_workbench.
- Gem effect at Lv1 = table value; "+x per level" adds x per level above 1 (ทวีคูณ Lv3 = ×1.37). Gem level cap 20; EXP to next = 150 × g^1.7.
- Gem effects (Lv1 / per level / MP ×): แยกศร +2 arrows, every arrow 60% / +1% / ×1.4 · สะท้อน 1 bounce 80% (Lv10: 2) / +1% / ×1.3 · ทะลุ +2 pierce (Lv10: 3) / — / ×1.2 · ศรนำวิถี 90% / +0.5% / ×1.2 · ทวีคูณ ×1.35 / +1% / ×1.5 · ขยาย +30% / +1% / ×1.3 · ยืดเวลา +30% / +1% / ×1.2 · พิฆาต crit +15% / +0.5% / ×1.2 · ดูดเลือด 3% / +0.1% / ×1.2 · ธาตุ ×1.1 / +1% / ×1.3.
- Labels: ศรทะลวง and ศรกระจาย = ลูกศร. แยกศร/สะท้อน/ทะลุ/ศรนำวิถี = ลูกศร; ทวีคูณ/พิฆาต/ดูดเลือด/ธาตุ = ทุกสกิล; ขยาย = พื้นที่; ยืดเวลา = ต่อเนื่อง·กับดัก.
- Elements: ไฟ burn 20% of the hit's damage (after DEF) every 1 s for 3 s, no crit, re-hit restarts and keeps the higher value · น้ำแข็ง slow 40% for 3 s on walk/run/lunge, re-hit restarts · สายฟ้า chain to 1 nearest other enemy within 120 px at 80%. Element is rolled at drop. Gear option `element_dmg` now adds to the ×1.1.
- Split geometry: ศรทะลวง 3 lines 12° apart · ศรกระจาย 7 arrows over a 63° fan. Ricochet search ≤120 px; homing turns 180°/s, searches 220 px, range counts distance flown.
- Gem options (skill-only), Lv1 ranges: ดาเมจสกิลนี้ +3–8% · คูลดาวน์สกิลนี้ −3–8% · MP สกิลนี้ −4–10% · คริสกิลนี้ +2–5% · EXP ของเจมนี้ +10–25%; count by rarity 0/1/2/3/4 (gear rarity table); values are rolled once at drop and **never change with gem level** (owner 2026-11-06).
- Combine in one skill: MP = skill MP × Π gem MP × (1 − mp option); damage = skill mult × Π gem dmg × (1 + dmg option); crit = hero crit + พิฆาต + crit option; cooldown cut = level + gear + cd option, total ≤ 30%.
- Slots: skill level 1–9 → 1, 10+ → 2 (30 → 3, 50 → 4). Locked skill (level 0) takes no gem.
- Gem EXP: equipped gems gain the EXP the kill gave (after EXP%) × (1 + gem EXP option), also at character cap; death costs gems nothing.
- Enhance (spec-numbers §7): chance 100/95/90/85/75/60/50/40/32/25% · ore = target step · gold = 100 × step² · on fail: current plus ≤ 5 → only costs, ≥ 6 → −1 · main stat bonus +6%/step (+1…+6) then +10%/step (+7…+10) · bow and armor only · ATK/DEF float, HP rounded per item.
- Gems are single items `{id: "gem_<type>", count: 1, gem: {type, level, exp, rarity, opts, element?}}`; plain common Lv1 EXP-0 no-option no-element gems (old saves) stack and split one off when socketed.
- Save version 3; versions 1 and 2 load (stacked gems stay stacked, plus = 0, no sockets).
- Thai UI text; Kanit; touch targets reachable by real touch.

## Review Focus
1. A burning wolf dies from the burn tick → EXP, gem EXP and loot are credited exactly once (Task 5).
2. A gemmed skill costs more MP than the hero has, or more than max MP → refused, nothing spent, HUD and skill screen show the real cost (Task 4).
3. Ricochet / chain / homing with no other enemy in range, or the target freed mid-flight → no error; ricochet and chain simply don't happen, homing flies straight (Task 5).
4. Enhancing the bow or armor that is being worn → stats, HP clamp and bow name update at once and the game saves (Task 7).
5. Removing a gem with a full bag, or loading a v2 save holding 24 stacked slots → refused / still loads with nothing lost (Tasks 3 and 6).

---

### Task 1: Gem and SkillBuild rules

**Files:**
- Modify: `data/balance.json` (sections `gem_effects`, `gem_options`, `gem_option_growth`, `gem_exp`, `gem_slots`, `skill_labels`, `split`, `ricochet`, `homing`, `elements`)
- Create: `scripts/rules/gem.gd`, `scripts/rules/skill_build.gd`
- Test: `tests/test_gem.gd`

**Interfaces:**
- Produces: `Gem.roll(type: String, rng, rarity := "") -> Dictionary` (level 1, exp 0, opts, element for "element") · `Gem.effect(gem: Dictionary) -> float` (main value at its level) · `Gem.mp_mult(type) -> float` · `Gem.option(gem, key) -> float` (the rolled value; 0 if absent) · `Gem.exp_to_next(level) -> int` · `Gem.add_exp(gem, amount) -> int` (levels gained, caps at 20) · `Gem.fits(type, skill_id) -> bool` · `Gem.slots_for(skill_level) -> int` · `Gem.is_plain(gem) -> bool`.
- Produces: `SkillBuild.of(skill_id: String, char_level: int, gems: Array, hero_stats: Dictionary) -> Dictionary` with `mp: float, dmg_mult: float, crit: float, cooldown: float, arrows: int, fan_deg: float, arrow_mult: float, pierce_all: bool, pierce_extra: int, bounces: int, bounce_mult: float, homing: bool, homing_mult: float, leech: float, element: String, element_mult: float`.

- [x] **Step 1: Failing tests** `test_gem_level_scaling` (ทวีคูณ Lv1 1.35, Lv3 1.37, Lv20 1.54) · `test_gem_exp_curve` (Lv1 150, Lv5 2314, Lv10 7518; cap 20) · `test_gem_options_fixed` (cd option 0.06 stays 0.06 at Lv10 and Lv20; roll stays in 0.03–0.08) · `test_fits_by_label` (ขยาย fits neither arrow skill; ทวีคูณ fits both) · `test_slots_by_level` (1→1, 9→1, 10→2) · `test_build_split_piercing` (arrows 3, fan 24°, each 0.6 × 1.8; MP 8×1.4 = 11.2) · `test_build_split_spread` (arrows 7, fan 63°, each 0.7×0.6) · `test_build_example_from_gems_md` (piercing + แยกศร + ทวีคูณ: arrow mult 1.8×0.81, MP 16.8) · `test_build_cooldown_cap` (cut never > 30% with level+gear+option) · `test_build_crit_adds`.
- [x] **Step 2: Run** `$G --headless --path . --script tests/run_tests.gd` → new tests fail.
- [x] **Step 3: Implement** data + `gem.gd` + `skill_build.gd` (pure, no scene access).
- [x] **Step 4: Run** → pass, existing 143 still pass.
- [x] **Step 5: Commit** `M3a Task 1: gem and skill-build rules`.

### Task 2: Enhancement rules and gear stats with plus

**Files:**
- Modify: `data/balance.json` (`enhance`: `chance[10]`, `gold_base` 100, `safe_max` 5, `bonus_low` 0.06, `bonus_low_until` 6, `bonus_high` 0.10, `max` 10), `scripts/rules/gear.gd`
- Create: `scripts/rules/enhance.gd`
- Test: `tests/test_enhance.gd`

**Interfaces:**
- Produces: `Enhance.chance(target: int) -> float` · `Enhance.ore(target) -> int` · `Enhance.gold(target) -> int` · `Enhance.bonus(plus: int) -> float` (+5 → 0.30, +6 → 0.36, +7 → 0.46, +10 → 0.76) · `Enhance.can(item: Dictionary) -> bool` (bow/armor, plus < 10) · `Enhance.attempt(item: Dictionary, inv: Inventory, rng) -> Dictionary` `{result: "ok"|"fail"|"down"|"no_ore"|"no_gold"|"max"|"cannot", plus: int}` (mutates item.plus and inventory) · `Gear.totals` applies `(1 + Enhance.bonus(plus))` to atk/def (float) and hp (rounded per item) · `Gear.item_name(item) -> String` ("ธนูเขาควาย +6").

- [x] **Step 1: Failing tests** `test_tables` (chances and costs for +1…+10) · `test_bonus_curve` · `test_fail_rules` (seeded: plus 5 fail → 5; plus 6 fail → 5; costs taken either way) · `test_not_enough_takes_nothing` · `test_ring_cannot` · `test_totals_with_plus` (trainee armor +1: def 4.24, hp 21; horn bow +6: atk 21.76) · `test_name_with_plus`.
- [x] **Step 2: Run** → fail.
- [x] **Step 3: Implement.**
- [x] **Step 4: Run** → pass (existing gear tests still pass; ATK/DEF stay floats).
- [x] **Step 5: Commit** `M3a Task 2: enhancement rules and plus on gear`.

### Task 3: Gems in the bag, drops, save v3

**Files:**
- Modify: `scripts/rules/inventory.gd`, `scripts/rules/loot.gd`, `scripts/rules/save_game.gd`
- Test: `tests/test_inventory.gd`, `tests/test_progression.gd`

**Interfaces:**
- Consumes: `Gem.roll`, `Gem.is_plain`.
- Produces: `Inventory.add_gem(gem: Dictionary) -> bool` (plain gems stack on `gem_<type>` stacks without data, others take a slot) · `Inventory.take_gem(index: int) -> Dictionary` (splits one off a plain stack) · `Loot.roll` gem entries carry `gem` data · state key `skills: {piercing: [gem|null, …], spread: [...]}` · item `plus` kept by `clean_item` · `SaveGame.VERSION = 3`.

- [x] **Step 1: Failing tests** `test_rolled_gems_take_own_slot` · `test_plain_gems_stack_and_split` · `test_gem_drop_has_data` (seeded: rarity, opts count by rarity, element for gem_element) · `test_save_v3_roundtrip` (gem level/exp/opts, sockets, plus) · `test_v2_save_migrates` (24 stacked slots incl. gem stacks load; plus 0; sockets empty) · `test_v1_save_still_migrates` · `test_bad_gem_rejected` (unknown type, level 21, duplicate option, plus 11).
- [x] **Step 2: Run** → fail.
- [x] **Step 3: Implement.**
- [x] **Step 4: Run** → pass.
- [x] **Step 5: Commit** `M3a Task 3: gems as items, gem drops, save v3`.

### Task 4: Hero uses gems

**Files:**
- Modify: `scripts/hero/hero.gd`, `scripts/dev/test_ground.gd`, `scripts/ui/hud.gd`
- Test: `tests/test_hero_gems.gd`

**Interfaces:**
- Consumes: `SkillBuild.of`, `Gem.add_exp`, `Inventory.take_gem/add_gem`.
- Produces: `Hero.skill_gems: Dictionary` (skill → Array) · `Hero.socket(skill_id, slot: int, bag_index: int) -> String` ("" or reason; swaps) · `Hero.unsocket(skill_id, slot) -> String` ("กระเป๋าเต็ม") · `Hero.build(skill_id) -> Dictionary` (SkillBuild for current level/gear) · `Hero.skill_mp(skill_id) -> float` · signal `gems_changed` · kill EXP also feeds equipped gems (`gem_leveled(gem)` signal).

- [x] **Step 1: Failing tests** `test_socket_swap_and_label` (ขยาย refused "ป้ายไม่ตรง"; locked spread refused "ยังไม่ปลด") · `test_unsocket_full_bag` · `test_piercing_with_split_fires_three` (3 arrows, 12° apart, mult 1.08, MP 11.2) · `test_spread_with_split_fires_seven` · `test_mp_too_high_refused` (cost > mp: refused, nothing spent) · `test_gem_exp_from_kill_and_at_cap` · `test_hud_shows_real_mp`.
- [x] **Step 2: Run** → fail.
- [x] **Step 3: Implement**; `_release` reads `build(skill)` for arrows, fan, multipliers; MP/cooldown at release as today.
- [x] **Step 4: Run** → pass.
- [x] **Step 5: Commit** `M3a Task 4: hero sockets gems, skills fire from SkillBuild`.

### Task 5: Arrow behaviours and monster status

**Files:**
- Modify: `scripts/arrow.gd`, `scripts/monsters/wolf.gd`, `scripts/dev/test_ground.gd`, `assets/fx/manifest.json`
- Create: `scripts/monsters/status_effects.gd`, `assets/fx/status_burn.png`, `status_frost.png`, `chain_zap.png` (vfx_workbench, 0 gen)
- Test: `tests/test_arrow_gems.gd`, `tests/test_status.gd`

**Interfaces:**
- Consumes: SkillBuild fields from Task 1.
- Produces: `Arrow.configure(build: Dictionary)` (pierce_extra, bounces, bounce_mult, homing, leech, element, element_mult) · signal `Arrow.dealt(amount: int)` (for leech) · `StatusEffects.apply_burn(per_tick: float)`, `apply_slow()`, `tick(delta) -> int` (burn damage this frame), `speed_mult() -> float` · `Wolf.status: StatusEffects`; `Wolf._move` scales by `status.speed_mult()`; burn damage goes through `health.take_hit` so death and kill credit use the existing path.

- [x] **Step 1: Failing tests** `test_pierce_extra_hits_three_then_stops` · `test_ricochet_once_80` · `test_ricochet_no_target_no_error` · `test_homing_turns_and_retargets` (target freed mid-flight → flies on) · `test_leech_heals_3pct_with_carry` · `test_burn_ticks_and_refresh` · `test_slow_40_on_chase_and_lunge` · `test_chain_120px_80pct` · `test_burn_kill_credited_once` (in test_ground: one EXP grant, one loot roll).
- [x] **Step 2: Run** → fail.
- [x] **Step 3: Implement**; effects from vfx_workbench (`burn_status`, `freeze_status`, `zap_hit`), strip like item_glint.
- [x] **Step 4: Run** → pass.
- [x] **Step 5: Commit** `M3a Task 5: ricochet, homing, pierce, leech, burn/slow/chain`.

### Task 6: Skill screen

**Files:**
- Create: `scripts/ui/skill_panel.gd`
- Modify: `scripts/ui/hud.gd` (button "สกิล" left of "กระเป๋า"), `project.godot` (action `skills`: N), `tests/touch_check.gd`
- Test: `tests/test_skill_panel.gd`

**Interfaces:**
- Consumes: `Hero.socket/unsocket/build/skill_gems`, `Gem.*`.
- Produces: `SkillPanel.open(hero)`, `close()`, `select_gem(bag_index)`, `press_slot(skill_id, slot) -> String`, `gem_detail() -> Dictionary` (name, sub, exp_frac, effect, lines with per-skill preview "MP 8 → 11.2"), pauses like BagPanel; HUD `open_skills()` releases touch first.

- [x] **Step 1: Failing tests** `test_open_pauses` · `test_preview_lines` (แยกศร shows both skills and MP 8 → 11.2, 12 → 16.8) · `test_unusable_gem_dimmed_and_explained` · `test_press_slot_sockets_and_swaps` · `test_full_bag_refusal_shown`.
- [x] **Step 2: Run** → fail.
- [x] **Step 3: Implement** to the approved sketch (artboard "หน้าสกิล · เจม").
- [x] **Step 4: Run** → pass; `xvfb-run … tests/touch_check.gd` → TOUCH PASS including open skills, pick gem, tap slot.
- [x] **Step 5: Commit** `M3a Task 6: skill and gem screen`.

### Task 7: Enhance window in the bag

**Files:**
- Create: `scripts/ui/enhance_panel.gd`
- Modify: `scripts/ui/bag_panel.gd` (button "ตีบวก" for bow/armor, worn or in bag; names with "+N"; gem/ore texts), `data/items.json`
- Test: `tests/test_enhance_panel.gd`

**Interfaces:**
- Consumes: `Enhance.*`, `Gear.item_name`, `Hero.gear_changed`.
- Produces: `EnhancePanel.open(hero, item_ref: Dictionary)` (`{"worn": slot}` or `{"bag": index}`), `detail() -> Dictionary` (title, stat_before, stat_after, chance, ore, gold, enough flags, warn text, safe), `press() -> String`.

- [x] **Step 1: Failing tests** `test_safe_and_risky_warnings` (+2→+3 safe text; +6→+7 "ลดเหลือ +5") · `test_not_enough_disables` · `test_worn_item_updates_stats_and_saves` · `test_ring_has_no_button`.
- [x] **Step 2: Run** → fail.
- [x] **Step 3: Implement** to the approved sketch (artboard "ตีบวก").
- [x] **Step 4: Run** → pass; touch check adds tap ตีบวก.
- [x] **Step 5: Commit** `M3a Task 7: enhance window`.

### Task 8: Screenshots, verification, PR, review

**Files:**
- Create: `tests/screenshots_m3a.gd`, `docs/preview/m3a_*.png`
- Modify: this plan (checkboxes), `docs/pixellab-budget.md` (0 gen lines for the effects)

- [x] **Step 1:** Shots: skill screen with a socketed gem · piercing + แยกศร three lines · burn / frost / chain on wolves · enhance safe and risky · bag name with +N. Look at each.
- [x] **Step 2:** `python3 tools/test_assets.py` PASS · full suite 0 failed · `touch_check.gd` PASS · M2a/M2b/M2c/M3a screenshot scripts rc=0.
- [x] **Step 3:** Push `m3a/gems-enhance`, draft PR to `main` with commands, SHA, counts, tagged Thai summary.
- [x] **Step 4:** Fresh reviewer on the branch; fix findings with regression tests; report to the owner in Thai with group tags.
