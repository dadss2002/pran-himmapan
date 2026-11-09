extends RefCounted
## M5b Task 2: gem combo recipes (balance.json gem_combos) + the GemCombo resolver.
## Numbers: docs/superpowers/specs/2026-11-08-gem-combos.md §1 / §2 at gem Lv1 (owner approval 2026-11-08).
## Owner 2026-11-09: one combo per skill (higher tier first, then recipe-book order); combo values do not
## grow with gem level; 3-gem rows read literally (no unlisted base effects).

## leech_add (owner 2026-11-09, Task 2 review): "ดูดเลือด ×2 (3% → 6%)" / "ดูดเลือด 6%" = the leech gem's own
## leech (grows with its level) + a flat 3 %, not ×2.
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
const ORDER := ["fire_fan", "thunder_hop", "hawk_eye", "bloodthirst", "frost_shard", "brahmastra", "thousand_bolts", "garuda",
	"anodard", "rahu", "shockwave", "hunter_zone", "fire_burst", "hellfield", "earth_piercer", "meteor_rain"]
## Row keys that are not numbers: everything else in a row must be a SPEC number (3-gem rows read literally).
const META := ["id", "tier", "name", "gems", "bases", "fx"]
## The label sets skills have or will have (docs/gems.md §2): ศรทะลวง/ศรกระจาย, ห่าศร, กับดักหนาม, ศรเพลิง.
const LABEL_SETS := [["arrow"], ["area", "dot"], ["trap", "area"], ["arrow", "area"]]

func _g(type: String, element := "", level := 1) -> Dictionary:
	var g := {"type": type, "level": level, "exp": 0, "rarity": "common", "opts": []}
	if element != "": g["element"] = element
	return g

## A gem for a recipe key ("fire" → an element gem).
func _k(key: String, level := 1) -> Dictionary:
	if key in ["fire", "ice", "lightning"]: return _g("element", key, level)
	return _g(key, "", level)

func _keys(keys: Array) -> Array:
	var out: Array = []
	for k in keys: out.append(_k(k))
	return out

## Temporary skills with the given labels (removed by _drop_skills).
func _add_skills(sets: Array) -> Array:
	var ids: Array = []
	for i in sets.size():
		var id := "test_combo_%d" % i
		Balance.data()["skill_labels"][id] = sets[i]
		ids.append(id)
	Balance.clear_cache()
	return ids

func _drop_skills(ids: Array) -> void:
	for id in ids: Balance.data()["skill_labels"].erase(id)
	Balance.clear_cache()

func test_recipes_match_spec():
	if GemCombo.ids() != ORDER: return "ids %s, want %s" % [GemCombo.ids(), ORDER]
	if GemCombo.recipes().size() != 16: return "%d recipes" % GemCombo.recipes().size()
	for id in ORDER:
		var row := GemCombo.recipe(id)
		var want: Dictionary = SPEC[id]
		if row.is_empty(): return "%s missing" % id
		if String(row.id) != id: return "%s: id %s" % [id, row.id]
		for key in want:
			if not row.has(key): return "%s: no %s" % [id, key]
			var v = want[key]
			match typeof(v):
				TYPE_FLOAT, TYPE_INT:
					if not is_equal_approx(float(row[key]), float(v)): return "%s.%s = %s, spec %s" % [id, key, row[key], v]
					if not is_equal_approx(GemCombo.p(id, key), float(v)): return "p(%s, %s) = %s" % [id, key, GemCombo.p(id, key)]
				_:
					if row[key] != v: return "%s.%s = %s, spec %s" % [id, key, row[key], v]
		for key in row:   # nothing that the spec row does not say (3-gem rows read literally, owner 2026-11-09 ②)
			if key not in META and not want.has(key): return "%s has unlisted key %s" % [id, key]
		if int(row.tier) == 2 and row.has("bases"): return "%s: a tier-2 row has bases" % id
	if GemCombo.p("fire_fan", "nope", 7.5) != 7.5: return "p default"
	if not GemCombo.recipe("nope").is_empty(): return "unknown recipe should be {}"
	return ""

## A few rows cross-checked against the spec's Thai wording itself (not the SPEC table above).
func test_spot_check_against_spec_text():
	var checks := [
		["fire_fan", "trail_secs", 2.0], ["fire_fan", "trail_frac", 0.20],          # "ทางไฟ ... 2 วิ ไหม้ 20% ของแรงลูกศร/วิ"
		["shockwave", "blast_radius", 32.0], ["shockwave", "blast_frac", 0.80],      # "วงกระแทก r32 แรง 80%"
		["bloodthirst", "kill_mp_cap", 6.0], ["rahu", "kill_mp_cap", 9.0],           # "สูงสุด 6 MP" / "สูงสุด 9"
		["rahu", "hp_min", 0.70], ["rahu", "hp_bonus", 0.30],                         # "HP ≥ 70%: สกิลนี้แรง +30%"
		["frost_shard", "freeze_lock_secs", 5.0], ["frost_shard", "bonus_vs_chilled", 0.25],
		["earth_piercer", "blast_radius", 40.0], ["earth_piercer", "blast_frac", 1.00],
		["garuda", "mark_taken", 0.30], ["hawk_eye", "mark_taken", 0.20],
	]
	for c in checks:
		if not is_equal_approx(GemCombo.p(c[0], c[1]), c[2]): return "%s.%s = %s, spec text says %s" % [c[0], c[1], GemCombo.p(c[0], c[1]), c[2]]
	# literal 3-gem rows (owner ②): no base-only effects carried over
	for pair in [["rahu", "kill_heal_frac"], ["anodard", "bonus_vs_chilled"], ["thousand_bolts", "extra_bounces"], ["hellfield", "area_radius_bonus"]]:
		if GemCombo.recipe(pair[0]).has(pair[1]): return "%s must not carry its base's %s" % pair
	return ""

func test_bases_are_subsets():
	for row in GemCombo.recipes():
		if int(row.tier) != 3: continue
		if row.get("bases", []).is_empty(): return "%s has no bases" % row.id
		for b in row.bases:
			var base := GemCombo.recipe(b)
			if base.is_empty() or int(base.tier) != 2: return "%s base %s is not a tier-2 recipe" % [row.id, b]
			for k in base.gems:
				if k not in row.gems: return "%s base %s gem %s not in %s" % [row.id, b, k, row.gems]
	return ""

func test_every_recipe_formable():
	var skills := _add_skills(LABEL_SETS)
	var r := ""
	for row in GemCombo.recipes():
		var ok := false
		for s in skills:
			var all := true
			for k in row.gems:
				if not Gem.fits(GemCombo.key_type(k), s): all = false
			if all: ok = true
		if not ok: r = "%s %s fits no skill label set" % [row.id, row.gems]
	_drop_skills(skills)
	return r

## Spec "กติกาเสริม": every 3-gem set that a skill can hold and that holds two 2-gem recipes is itself a 3-gem recipe.
func test_no_three_gem_collision():
	var skills := _add_skills(LABEL_SETS)
	var keys: Array = []
	for t in Gem.types():
		if t == "element": keys.append_array(["fire", "ice", "lightning"])
		else: keys.append(t)
	var tier3: Array = []
	var tier2: Array = []
	for row in GemCombo.recipes():
		var s: Array = row.gems.duplicate()
		s.sort()
		(tier3 if int(row.tier) == 3 else tier2).append(s)
	var r := ""
	var checked := 0
	for a in keys.size():
		for b in range(a + 1, keys.size()):
			for c in range(b + 1, keys.size()):
				var set3: Array = [keys[a], keys[b], keys[c]]
				var els := 0
				for k in set3: if k in ["fire", "ice", "lightning"]: els += 1
				if els > 1: continue
				var holdable := false      # some skill can socket all three
				for s in skills:
					var all := true
					for k in set3: if not Gem.fits(GemCombo.key_type(k), s): all = false
					if all: holdable = true
				if not holdable: continue
				var n2 := 0
				for t2 in tier2:
					if set3.has(t2[0]) and set3.has(t2[1]): n2 += 1
				if n2 < 2: continue
				checked += 1
				var sorted3 := set3.duplicate()
				sorted3.sort()
				if not tier3.has(sorted3): r = "%s holds %d tier-2 recipes but is no tier-3 recipe" % [set3, n2]
	_drop_skills(skills)
	if r == "" and checked != 3: r = "expected the 3 known overlap sets (meteor_rain, hellfield, earth_piercer), checked %d" % checked
	return r

func test_gem_key_maps_elements():
	if GemCombo.gem_key(_g("element", "ice")) != "ice": return "ice element key %s" % GemCombo.gem_key(_g("element", "ice"))
	if GemCombo.gem_key(_g("element", "fire")) != "fire": return "fire key"
	if GemCombo.gem_key(_g("element", "lightning")) != "lightning": return "lightning key"
	if GemCombo.gem_key(_g("split")) != "split": return "split key"
	if GemCombo.gem_key(_g("element")) != "": return "an element gem with no element has no key"
	if GemCombo.key_name("fire") != "ธาตุไฟ": return "key_name(fire) %s" % GemCombo.key_name("fire")
	if GemCombo.key_name("ice") != "ธาตุน้ำแข็ง": return "key_name(ice) %s" % GemCombo.key_name("ice")
	if GemCombo.key_name("split") != "แยกศร": return "key_name(split) %s (book shows 'แยกศร + ธาตุไฟ')" % GemCombo.key_name("split")
	if GemCombo.key_type("lightning") != "element" or GemCombo.key_type("homing") != "homing": return "key_type"
	return ""

func test_resolve_two():
	var got := GemCombo.resolve("piercing", [_g("split"), _g("element", "fire")])
	var want := {"id": "fire_fan", "tier": 2, "name": "ศรพัดเพลิง", "slots": [0, 1]}
	return "" if got == want else "got %s" % got

func test_resolve_three_replaces_base():
	var got := GemCombo.resolve("piercing", _keys(["split", "fire", "multiply"]))
	if got.get("id", "") != "brahmastra" or int(got.get("tier", 0)) != 3 or got.get("slots", []) != [0, 1, 2]: return "got %s" % got
	if got.name != "พัดเพลิงพรหมาสตร์": return "name %s" % got.name
	return ""

func test_resolve_order_and_nulls():
	var got := GemCombo.resolve("piercing", [null, _k("fire"), _k("split")])
	if got.get("id", "") != "fire_fan" or got.get("slots", []) != [1, 2]: return "null first: %s" % got
	var perms := [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
	var keys := ["split", "fire", "multiply"]
	for p in perms:
		var gems: Array = []
		for i in p: gems.append(_k(keys[i]))
		var r := GemCombo.resolve("piercing", gems)
		if r.get("id", "") != "brahmastra" or r.get("slots", []) != [0, 1, 2]: return "order %s: %s" % [p, r]
	return ""

func test_resolve_ignores_unfit_and_junk():
	if not GemCombo.resolve("piercing", _keys(["expand", "extend"])).is_empty(): return "expand + extend do not fit piercing (no area label)"
	if not GemCombo.resolve("piercing", [{}, "x", 3]).is_empty(): return "junk formed a combo"
	if not GemCombo.resolve("piercing", [_k("split")]).is_empty(): return "one gem formed a combo"
	if not GemCombo.resolve("piercing", []).is_empty(): return "no gems formed a combo"
	if not GemCombo.resolve("no_such_skill", _keys(["split", "fire"])).is_empty(): return "an unknown skill formed a combo"
	if not GemCombo.resolve("piercing", [_k("split"), _g("element")]).is_empty(): return "an element gem with no element formed fire_fan"
	if not GemCombo.resolve("piercing", [_k("split"), _k("ice")]).get("id", "") == "frost_shard": return "ice + split should form frost_shard"
	return ""

func test_resolve_extra_gem_keeps_combo():
	var got := GemCombo.resolve("piercing", _keys(["split", "fire", "leech"]))
	if got.get("id", "") != "fire_fan" or got.get("slots", []) != [0, 1]: return "got %s" % got
	got = GemCombo.resolve("piercing", _keys(["leech", "split", "fire"]))
	return "" if got.get("slots", []) == [1, 2] else "slots %s" % [got.get("slots", [])]

## Owner 2026-11-09: one combo per skill: the higher tier first, then recipe-book order (4 slots at skill Lv50).
func test_four_gems_one_combo():
	var got := GemCombo.resolve("piercing", _keys(["homing", "execute", "multiply", "leech"]))   # garuda and rahu are both tier 3
	if got.get("id", "") != "garuda" or int(got.get("tier", 0)) != 3 or got.get("slots", []) != [0, 1, 2]: return "homing+execute+multiply+leech: %s" % got
	got = GemCombo.resolve("piercing", _keys(["leech", "multiply", "execute", "homing"]))
	if got.get("id", "") != "garuda" or got.get("slots", []) != [1, 2, 3]: return "reordered: %s" % got
	var skills := _add_skills([["arrow", "area"]])      # ศรเพลิง-like: earth_piercer and meteor_rain both tier 3
	got = GemCombo.resolve(skills[0], _keys(["split", "fire", "expand", "pierce"]))
	var r := ""
	if got.get("id", "") != "earth_piercer" or got.get("slots", []) != [1, 2, 3]: r = "split+fire+expand+pierce: %s (earth_piercer comes before meteor_rain in the book)" % got
	if r == "":
		got = GemCombo.resolve(skills[0], _keys(["split", "fire", "expand", "leech"]))   # meteor_rain beats fire_fan / fire_burst
		if got.get("id", "") != "meteor_rain": r = "split+fire+expand+leech: %s" % got
	if r == "":
		got = GemCombo.resolve(skills[0], _keys(["pierce", "expand", "leech", "multiply"]))   # two tier-2s: book order
		if got.get("id", "") != "bloodthirst" or got.get("slots", []) != [2, 3]: r = "two tier-2 candidates should pick the earlier book row: %s" % got
	_drop_skills(skills)
	return r

## Owner 2026-11-09 Q2: combo values do not grow with gem level.
func test_combo_flat_at_any_gem_level():
	var lo := GemCombo.resolve("piercing", [_k("split", 1), _k("fire", 1)])
	var hi := GemCombo.resolve("piercing", [_k("split", 20), _k("fire", 15)])
	if lo != hi: return "Lv1 %s vs Lv20 %s" % [lo, hi]
	return "" if not GemCombo.describe("fire_fan").is_empty() else "describe empty"

## Review note: every reader goes through hero.open_gems(): a gem in a closed slot never forms a combo.
func test_closed_slot_gem_never_forms_a_combo():
	var h: Hero = load("res://scenes/hero.tscn").instantiate()
	h.setup_sprites()
	h.inventory.slots.clear()
	var i := 0
	while h.inventory.slots.size() < int(Balance.num("bag.slots")):     # full bag (as test_hero_gems._full_bag)
		h.inventory.add("junk_%d" % i, 1)
		i += 1
	# char Lv1: piercing has 2 open slots; fire sits in slot 3 (closed) and the bag is full, so it stays socketed
	h.set_skill_gems({"piercing": [_k("split"), null, _k("fire")], "spread": [_k("split"), _k("fire")]})
	h.return_closed_gems()
	var r := ""
	if h.skill_gems.piercing.size() < 3 or h.skill_gems.piercing[2] == null: r = "setup: the closed-slot gem should stay (bag full)"
	elif GemCombo.resolve("piercing", h.skill_gems.piercing).get("id", "") != "fire_fan": r = "setup: the raw sockets should form fire_fan"
	elif not GemCombo.resolve("piercing", h.open_gems("piercing")).is_empty(): r = "a closed-slot gem formed a combo: %s" % GemCombo.resolve("piercing", h.open_gems("piercing"))
	elif not GemCombo.resolve("spread", h.open_gems("spread")).is_empty(): r = "spread is locked at char Lv1 (no open slots): no combo"
	if r == "":
		h.set_progress(10, 0)      # piercing skill Lv10: slot 3 opens → the same sockets now form fire_fan
		if GemCombo.resolve("piercing", h.open_gems("piercing")).get("slots", []) != [0, 2]: r = "after slot 3 opens: %s" % GemCombo.resolve("piercing", h.open_gems("piercing"))
	h.free()
	return r

func test_describe_has_numbers():
	var d := GemCombo.describe("fire_fan")
	if not ("2 วิ" in d and "20%" in d): return "fire_fan: %s" % d
	d = GemCombo.describe("rahu")
	if not ("70%" in d and "9" in d and "30%" in d): return "rahu: %s" % d
	if not ("+3%" in d) or "×" in d: return "rahu leech is a flat +3 %% (owner 2026-11-09), not ×: %s" % d
	d = GemCombo.describe("bloodthirst")
	if not ("+3%" in d) or "×" in d: return "bloodthirst leech is a flat +3 %% (owner 2026-11-09), not ×: %s" % d
	d = GemCombo.describe("shockwave")
	if not ("r32" in d and "80%" in d): return "shockwave: %s" % d
	d = GemCombo.describe("frost_shard")
	if "บอส" in d: return "frost_shard must not promise a boss slow (owner: bosses freeze like others): %s" % d
	for id in GemCombo.ids():
		if GemCombo.describe(id) == "": return "%s has no text" % id
	return "" if GemCombo.describe("nope") == "" else "unknown id should describe as ''"

# ---------- build (M5b Task 3): SkillBuild combo stats ----------
## char Lv10, gem Lv1, no options (spec §5 example row).
const STATS := {"crit": 0.05, "element_dmg": 0.0, "skill_cd_cut": 0.0}

func _b(keys: Array, char_level := 10, gem_level := 1, skill := "piercing") -> Dictionary:
	var gems: Array = []
	for k in keys: gems.append(_k(k, gem_level))
	return SkillBuild.of(skill, char_level, gems, STATS)

## Recipes whose gems all fit `skill`.
func _formable_on(skill: String) -> Array:
	var out: Array = []
	for row in GemCombo.recipes():
		var all := true
		for k in row.gems: if not Gem.fits(GemCombo.key_type(String(k)), skill): all = false
		if all: out.append(row)
	return out

func test_build_spec_section5_numbers():
	var rows := [[["split"], 1.566, 11.2, ""], [["split", "fire"], 1.7226, 14.56, "fire_fan"], [["split", "fire", "multiply"], 2.32551, 21.84, "brahmastra"]]
	for r in rows:
		var b := _b(r[0])
		if not is_equal_approx(float(b.arrow_mult), r[1]): return "%s arrow_mult %s, spec %s" % [r[0], b.arrow_mult, r[1]]
		if not is_equal_approx(float(b.mp), r[2]): return "%s mp %s, spec %s" % [r[0], b.mp, r[2]]
		if String(b.combo.get("id", "")) != r[3]: return "%s combo %s, want '%s'" % [r[0], b.combo, r[3]]
	return ""

## The build carries the resolve result unchanged, and a copy of the recipe's numbers (read once per press).
func test_build_carries_combo_and_numbers():
	var b := _b(["split", "fire"])
	if b.combo != GemCombo.resolve("piercing", [_k("split"), _k("fire")]): return "combo %s is not the resolve result" % b.combo
	if not is_equal_approx(float(b.combo_p.get("trail_frac", 0.0)), 0.20) or not is_equal_approx(float(b.combo_p.get("trail_secs", 0.0)), 2.0): return "combo_p %s" % b.combo_p
	for k in b.combo_p:
		if k in META: return "combo_p holds the non-number %s" % k
		if typeof(b.combo_p[k]) != TYPE_FLOAT: return "combo_p.%s is not a float" % k
	var none := _b(["split"])
	if not none.combo.is_empty() or not none.combo_p.is_empty() or int(none.extra_bounces) != 0: return "no combo: %s %s %s" % [none.combo, none.combo_p, none.extra_bounces]
	# a copy: changing it never changes the data
	b.combo_p.trail_frac = 9.0
	return "" if is_equal_approx(GemCombo.p("fire_fan", "trail_frac"), 0.20) else "combo_p is not a copy"

func test_combo_adds_no_mp():
	var n := 0
	for row in _formable_on("piercing"):
		var want := Skills.mp_cost("piercing")
		for k in row.gems: want *= Gem.mp_mult(GemCombo.key_type(String(k)))
		var b := _b(row.gems)
		if String(b.combo.get("id", "")) != String(row.id): return "%s did not form (%s)" % [row.id, b.combo]
		if not is_equal_approx(float(b.mp), want): return "%s mp %s, want %s (no combo MP multiplier)" % [row.id, b.mp, want]
		n += 1
	return "" if n == 10 else "expected the 10 arrow recipes on piercing, got %d" % n

func test_hawk_eye_homing_full_crit():
	for id in ["hawk_eye", "garuda"]:
		var keys: Array = GemCombo.recipe(id).gems
		var b := _b(keys)
		var want_mult := Skills.damage_mult("piercing", 10) * (Gem.effect(_k("multiply")) if "multiply" in keys else 1.0)
		if not is_equal_approx(float(b.arrow_mult), want_mult): return "%s arrow_mult %s, want %s (no homing ×0.9)" % [id, b.arrow_mult, want_mult]
		if not is_equal_approx(float(b.crit), 0.05 + 0.15 + 0.15): return "%s crit %s, want 0.35" % [id, b.crit]
		if not b.homing: return "%s lost homing" % id
	return ""

func test_homing_alone_keeps_penalty():
	var b := _b(["homing"], 1)
	if not is_equal_approx(float(b.arrow_mult), 1.8 * 0.9): return "homing alone %s, want 1.62" % b.arrow_mult
	b = _b(["homing", "multiply"], 1)          # homing + a gem that forms no combo: penalty stays
	return "" if is_equal_approx(float(b.arrow_mult), 1.8 * 0.9 * 1.35) and b.combo.is_empty() else "homing+multiply %s %s" % [b.arrow_mult, b.combo]

## Owner 2026-11-09: the combo leech is the leech gem's own leech + a flat 3 % (not ×2).
func test_sustain_leech_is_gem_plus_flat_three():
	var cases := [[["leech", "multiply"], 1, 0.06], [["leech", "multiply"], 5, 0.034 + 0.03], [["leech", "multiply"], 20, 0.079],
		[["leech", "multiply", "execute"], 1, 0.06], [["leech", "multiply", "execute"], 20, 0.079], [["leech"], 1, 0.03], [["leech"], 20, 0.049]]
	for c in cases:
		var b := _b(c[0], 10, c[1])
		if not is_equal_approx(float(b.leech), c[2]): return "%s gem Lv%d leech %s, want %s" % [c[0], c[1], b.leech, c[2]]
	return ""

func test_thunder_hop_extra_bounce():
	var b := _b(["ricochet", "lightning"])
	if String(b.combo.get("id", "")) != "thunder_hop" or int(b.extra_bounces) != 1: return "thunder_hop %s extra %s" % [b.combo, b.extra_bounces]
	if int(b.bounces) != 1: return "the ricochet gem's own bounce stays separate: %s" % b.bounces
	b = _b(["ricochet", "lightning", "split"])
	if String(b.combo.get("id", "")) != "thousand_bolts" or int(b.extra_bounces) != 0: return "thousand_bolts (row read literally) %s extra %s" % [b.combo, b.extra_bounces]
	return ""

## Owner 2026-11-09 Q2 at the build level: from gem Lv1 to Lv20 only the gems' own effects grow.
## Every build number with a combo minus the same build's number without the combo part must not change.
func test_combo_values_flat_at_any_gem_level_in_build():
	for row in _formable_on("piercing"):
		var lo := _b(row.gems, 10, 1)
		var hi := _b(row.gems, 10, 20)
		var id := String(row.id)
		if lo.combo_p != hi.combo_p: return "%s combo numbers moved with gem level: %s vs %s" % [id, lo.combo_p, hi.combo_p]
		if int(lo.extra_bounces) != int(hi.extra_bounces): return "%s extra_bounces moved" % id
		for lv in [1, 20]:
			var b := lo if lv == 1 else hi
			var own_crit := 0.05
			var own_leech := 0.0
			for k in row.gems:
				if k == "execute": own_crit += Gem.effect(_k("execute", lv))
				if k == "leech": own_leech += Gem.effect(_k("leech", lv))
			if not is_equal_approx(float(b.crit) - own_crit, GemCombo.p(id, "crit_bonus")): return "%s Lv%d crit %s: combo part %s, want flat %s" % [id, lv, b.crit, float(b.crit) - own_crit, GemCombo.p(id, "crit_bonus")]
			if not is_equal_approx(float(b.leech) - own_leech, GemCombo.p(id, "leech_add")): return "%s Lv%d leech %s: combo part %s, want flat %s" % [id, lv, b.leech, float(b.leech) - own_leech, GemCombo.p(id, "leech_add")]
	return ""

## Every reader of sockets goes through hero.open_gems(): a closed-slot gem never forms a combo in the build.
func test_hero_build_reads_open_slots_only():
	var h: Hero = load("res://scenes/hero.tscn").instantiate()
	h.setup_sprites()
	h.inventory.slots.clear()
	var i := 0
	while h.inventory.slots.size() < int(Balance.num("bag.slots")):
		h.inventory.add("junk_%d" % i, 1)
		i += 1
	h.set_skill_gems({"piercing": [_k("homing"), null, _k("execute")]})
	h.return_closed_gems()      # bag full: execute stays in closed slot 3
	var r := ""
	var b := h.build("piercing")
	if h.skill_gems.piercing[2] == null: r = "setup: execute should stay socketed"
	elif not b.combo.is_empty() or not b.combo_p.is_empty(): r = "closed-slot gem formed %s" % b.combo
	elif not is_equal_approx(float(b.crit), float(h.stats().crit)): r = "closed-slot execute/crit_bonus counted: %s" % b.crit
	if r == "":
		h.set_progress(10, 0)
		b = h.build("piercing")
		if String(b.combo.get("id", "")) != "hawk_eye": r = "slot 3 open at skill Lv10: %s" % b.combo
	h.free()
	return r

## Source guard: outside scripts/rules, every SkillBuild.of / GemCombo.resolve call is fed from open_gems, never
## from skill_gems directly (a gem in a closed slot must stay inert).
func test_every_combo_reader_uses_open_gems():
	var files: Array = []
	var stack := ["res://scripts"]
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		if dir_path.ends_with("/rules"): continue
		var d := DirAccess.open(dir_path)
		for sub in d.get_directories(): stack.append(dir_path + "/" + sub)
		for f in d.get_files(): if f.ends_with(".gd"): files.append(dir_path + "/" + f)
	var callers := 0
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		if not ("SkillBuild.of(" in text or "GemCombo.resolve(" in text): continue
		callers += 1
		if not "open_gems(" in text: return "%s calls SkillBuild.of / GemCombo.resolve without open_gems()" % path
		var n := 0
		for line in text.split("\n"):
			n += 1
			if ("SkillBuild.of(" in line or "GemCombo.resolve(" in line) and "skill_gems" in line: return "%s:%d reads skill_gems directly: %s" % [path, n, line.strip_edges()]
	return "" if callers >= 2 else "expected hero.gd and skill_panel.gd as callers, found %d" % callers

## The id → row cache: same rows as the data, and it follows a test that swaps the recipe list.
func test_recipe_lookup_cache():
	if not is_same(GemCombo.recipe("rahu"), GemCombo.recipes()[9]): return "recipe() should return the data row itself"
	var old: Array = Balance.data()["gem_combos"]["recipes"]
	Balance.data()["gem_combos"]["recipes"] = [{"id": "only", "tier": 2, "name": "x", "gems": ["split", "fire"], "trail_frac": 0.5}]
	Balance.clear_cache()
	var r := ""
	if not is_equal_approx(GemCombo.p("only", "trail_frac"), 0.5) or not GemCombo.recipe("fire_fan").is_empty(): r = "cache did not follow the new list"
	Balance.data()["gem_combos"]["recipes"] = old
	Balance.clear_cache()
	if r == "" and not is_equal_approx(GemCombo.p("fire_fan", "trail_frac"), 0.20): r = "cache did not come back"
	return r
