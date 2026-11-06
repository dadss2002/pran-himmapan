# M2c Bag and Equip Implementation Plan

> **For agentic workers:** Implement this plan task-by-task, checking off each step. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wolves drop equipment with a rarity and random options. The player opens the bag, compares items and equips a bow, armor, ring and necklace. Stats change, and the bow in the hero's hands changes.

**Architecture:** Pure rule class `Gear` (rolls, option ranges, stat totals) on data in balance.json. Equipment lives in `Inventory` slots as unique items (never stacked) plus an `equipped` dict on the hero. `Hero.stats()` = level base + `Gear.totals(equipped)`. Bag screen is a Control overlay in the HUD; the game pauses while it is open. Save version 2 migrates version 1.

**Tech Stack:** Godot 4.5.1 GDScript, headless test runner (`tests/run_tests.gd`), xvfb screenshots, PixelLab vfx_workbench (free) for the ground beam.

**Spec:** `docs/superpowers/specs/2026-11-06-m2-design.md` (M2c row, §5.6, §6) and `docs/spec-numbers.md` §5–§6 (rarity, option ranges, gear main stats). Both owner-approved.

## Global Constraints
- All numbers in `data/balance.json` read through `Balance`; nothing new hard-coded.
- Rarity (spec-numbers §5): ธรรมดา เทา 60% 0 options · ดี เขียว 28% 1 · หายาก ฟ้า 9% 2 · มหากาพย์ ม่วง 2.7% 3 · ตำนาน ทอง 0.3% 4.
- Wolf drops equipment 6% (spec-numbers §5).
- Options at item Lv10 (spec-numbers §5), unique within one item: ATK +3–8% · คริ +2–5% · ดาเมจคริ +8–20% · ความเร็วยิง +4–10% · HP +20–60 · DEF +3–8 · ความเร็วเดิน +3–8% · คูลดาวน์สกิล −3–8% · ดาเมจธาตุ +5–12% · EXP +3–8% · ทอง +5–15% · MP +10–30 · ฟื้น MP +0.5–1.5/วิ.
- Lower item levels: range × (item level ÷ 10), never below 30% of the range (design §5.6).
- Gear main stats (spec-numbers §6): ธนูไม้ไผ่ Lv1 ATK+8 · ธนูเขาควาย Lv5 ATK+16 · ชุดพรานฝึกหัด Lv1 DEF+4 HP+20 · ชุดหนังหมาป่า Lv4 DEF+10 HP+40 · แหวน/สร้อย no main stat.
- Wolf equipment pool (design §5.6): ธนูไม้ไผ่ · ธนูเขาควาย · ชุดพรานฝึกหัด · ชุดหนังหมาป่า · แหวน · สร้อย.
- Armor on the body keeps the current look (design: no new visible armor in M2).
- Auto-save on equip (design §5.6). Keys I/B open the bag (design §6).
- No PixelLab generation without owner approval (owner 2026-11-06). Ring and necklace icons wait for approval; until then they use labeled placeholder icons.

**My choices, to confirm with the owner in the PR (not balance numbers):**
- The 6 pool items drop with equal chance (same rule the spec uses for gems).
- Item level: bows and armor = their required level; ring/necklace = the wolf's level. Ring/necklace can be worn from Lv1.
- Percent options round to 0.1%; HP, DEF and MP to whole numbers; MP regen to 0.1/s.
- "ดาเมจธาตุ" is stored and shown but has no effect until elements exist (no element in M2).
- The game pauses while the bag is open.
- Starting kit: ธนูไม้ไผ่ + ชุดพรานฝึกหัด, both ธรรมดา, equipped.

## Review Focus
1. Bag full when a gear drop is touched → item stays on the ground with "กระเป๋าเต็ม", same as M2b (test in Task 4).
2. Equip an item above the hero's level → refused with a red "ต้องเลเวล N" in the detail panel, nothing moves (Task 2 + Task 5).
3. Unequip with a full bag → refused, item stays worn (Task 2).
4. A version-1 save (M2b players) loads with the starting kit equipped and the bag intact (Task 2).
5. HP above the new max after removing HP gear → HP clamps to the new max, never shows 130/120 (Task 3).

---

### Task 1: Gear rules and data

**Files:**
- Modify: `data/balance.json` (sections `rarity`, `options`, `option_floor`, `gear` items with `slot`/`level`, `loot.wolf.gear`, `gear_pool.wolf`)
- Create: `scripts/rules/gear.gd`
- Test: `tests/test_gear.gd`

**Interfaces:**
- Produces: `Gear.roll_rarity(rng) -> String` (`"common"|"good"|"rare"|"epic"|"legend"`); `Gear.roll_item(base: String, source_level: int, rng) -> Dictionary` = `{base, rarity, level, opts: [{k, v}]}`; `Gear.option_range(k: String, item_level: int) -> Vector2`; `Gear.totals(equipped: Dictionary) -> Dictionary` with keys `atk, def, hp, atk_pct, crit, crit_dmg, atk_speed, move_speed, skill_cd, element_dmg, exp_pct, gold_pct, mp, mp_regen`; `Gear.slot_of(base) -> String`, `Gear.req_level(base) -> int`, `Gear.rarity_color(rarity) -> Color`, `Gear.display_name(base) -> String`, `Gear.describe_option(opt) -> String`.

- [x] **Step 1: Write the failing tests**
  `test_rarity_rates_seeded` (100 000 rolls, each within ±0.5 pp of 60/28/9/2.7/0.3) · `test_option_count_by_rarity` (0/1/2/3/4, keys unique) · `test_option_range_scaling` (crit at Lv10 = 0.02–0.05; Lv5 = 0.01–0.025; Lv1 = 0.006–0.015 from the 30% floor) · `test_rolled_values_inside_range_and_rounded` · `test_totals_sum_main_and_options` (bamboo bow + trainee armor = atk 8, def 4, hp 20).
- [x] **Step 2: Run** `$G --headless --path . --script tests/run_tests.gd` → the new tests fail (no `Gear`).
- [x] **Step 3: Implement** the balance sections and `gear.gd`.
- [x] **Step 4: Run** → all pass.
- [x] **Step 5: Commit** `M2c: gear rules (rarity, options, totals)`.

### Task 2: Items in the bag, equipping, save v2

**Files:**
- Modify: `scripts/rules/inventory.gd`, `scripts/rules/save_game.gd`, `scripts/hero/hero.gd`
- Test: `tests/test_inventory.gd`, `tests/test_equip.gd`

**Interfaces:**
- Consumes: `Gear.*` from Task 1.
- Produces: `Inventory.add_item(item: Dictionary) -> bool` (needs a free slot; never stacks); slot shape `{id: base, count: 1, item: {...}}`; `Inventory.take_slot(i) -> Dictionary`; `Hero.equipped: Dictionary` (`bow, armor, ring, necklace` → item or null); `Hero.equip(slot_index: int) -> String` ("" = ok, otherwise the Thai reason); `Hero.unequip(slot: String) -> String`; signal `Hero.gear_changed`. Save state adds `equipped`; `SaveGame.VERSION = 2`; v1 files migrate (`equipped` = starting kit) instead of `.bad.json`.

- [ ] **Step 1: Write the failing tests**
  `test_items_never_stack` · `test_equip_swaps_with_bag` (old item goes to the same slot) · `test_equip_refused_above_level` ("ต้องเลเวล 5", nothing moved) · `test_unequip_refused_when_bag_full` · `test_save_v2_roundtrip_with_items` · `test_v1_save_migrates_to_start_kit` · `test_bad_item_in_save_starts_fresh`.
- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement.** Equip/unequip emit `gear_changed`; the hero re-applies stats.
- [ ] **Step 4: Run** → pass, earlier 105 still pass.
- [ ] **Step 5: Commit** `M2c: items in bag, equip/unequip, save v2`.

### Task 3: Stats from gear, bow in hand

**Files:**
- Modify: `scripts/rules/balance.gd` (`hero()` drops the fixed gear; `hero_base()`), `scripts/hero/hero.gd`, `scripts/rules/combat.gd`, `scripts/hero/skills.gd`, `scripts/hero/bow_layer.gd`, `scripts/dev/test_ground.gd`
- Test: `tests/test_balance.gd`, `tests/test_equip.gd`

**Interfaces:**
- Produces: `Hero.stats()` = `{hp, atk, def, mp, crit, crit_mult, shot_cd, walk, skill_cd_cut, mp_regen, exp_mult, gold_mult}`; `Combat.roll_damage(atk, mult, def, can_crit, crit_chance := -1.0, crit_mult := -1.0)`; `Skills.cooldown(id, level, extra_cut := 0.0)` (total cut still capped at `skills.max_cooldown_cut`); `BowLayer.set_bow(base: String)`.

- [ ] **Step 1: Write the failing tests**
  `test_hero_lv1` keeps 120/18/6 with the starting kit · `test_each_option_changes_its_stat` (one item per option key: ATK%, crit, crit dmg, shot cooldown, HP, DEF, walk speed, skill cooldown, EXP, gold, MP, MP regen) · `test_hp_clamps_when_gear_removed` · `test_bow_layer_shows_equipped_bow`.
- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement.** Gold bonus applies to the gold count rolled in `test_ground._on_wolf_died`; EXP bonus in `Hero.on_kill`.
- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `M2c: gear stats and bow in hand`.

### Task 4: Equipment drops on the ground

**Files:**
- Modify: `scripts/rules/loot.gd`, `scripts/loot/loot_drop.gd`, `scripts/dev/test_ground.gd`
- Create: `assets/fx/rarity_beam.png` (vfx_workbench, 0 gen), placeholder icons `assets/items/ring_placeholder.png`, `necklace_placeholder.png` (labeled PLACEHOLDER in docs/art-style.md)
- Test: `tests/test_loot_drop.gd`, `tests/test_progression.gd`

**Interfaces:**
- Produces: `Loot.roll()` may add `{id: base, count: 1, item: {...}}` (6%, pool uniform); `LootDrop.make_item(item)`; `LootDrop.beam` (FxSprite, rare and above, tinted to the rarity color); pickup calls `inv.add_item`.

- [ ] **Step 1: Write the failing tests**
  `test_gear_drop_rate_seeded` (≈6%, pool uniform) · `test_beam_only_rare_and_up` · `test_gear_pickup_needs_free_slot` (bag full → stays, notice) · `test_icon_for_gear`.
- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement**; make the beam with vfx_workbench (`heal_column` or `sky_beam`, recoloured), export, strip with the same steps as item_glint.
- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `M2c: equipment drops with rarity beam`.

### Task 5: Bag screen

**Files:**
- Create: `scripts/ui/bag_panel.gd`
- Modify: `scripts/ui/hud.gd` (enable the กระเป๋า button), `project.godot` (action `bag`: I, B)
- Test: `tests/test_bag_panel.gd`

**Interfaces:**
- Consumes: `Hero.equip/unequip/equipped/inventory`, `Gear.describe_option/rarity_color/display_name`.
- Produces: `BagPanel.open(hero)`, `close()`, `select(index)`, `selected_detail() -> Dictionary` (lines for the UI, used by tests), `press_equip()`. Layout follows the approved mockup: 4 equipment slots on the left, 6×4 grid, detail panel with name in rarity color, main stat, options, compare with the worn item (+green / −red), button สวมใส่ / ถอด, gold, close ✕.

- [ ] **Step 1: Write the failing tests**
  `test_open_pauses_and_close_resumes` · `test_select_shows_compare` (bow ATK+16 over ATK+8 → "+8" green) · `test_equip_from_panel_updates_slots_and_saves` · `test_level_lock_shown_red`.
- [ ] **Step 2: Run** → fail.
- [ ] **Step 3: Implement**; touch-sized cells (≥ 28 px in the 640×360 view).
- [ ] **Step 4: Run** → pass.
- [ ] **Step 5: Commit** `M2c: bag screen`.

### Task 6: Screenshots, verification, PR

**Files:**
- Create: `tests/screenshots_m2c.gd`, `docs/preview/m2c_*.png`
- Modify: this plan (checkboxes), `docs/pixellab-budget.md` (0 gen; ring/necklace waiting)

- [ ] **Step 1:** Screenshots: gear drop with beam · bag open with compare · after equipping ธนูเขาควาย (bow in hand changed) · level-lock message. Look at every image.
- [ ] **Step 2:** `python3 tools/test_assets.py` → PASS; full suite → 0 failed; M2a/M2b screenshot scripts → rc=0.
- [ ] **Step 3:** Commit, push `m2c/bag`, draft PR with base `m2b/loot`: commands, SHA, counts, my-choices list, waiting-for-approval list.
- [ ] **Step 4:** Fresh reviewer on the branch; fix findings; report to the owner in Thai.
