extends RefCounted
## M5b Task 8a: the three area skills' data (ห่าศร / กับดักหนาม / ศรเพลิง, docs/skills.md approved 2026-11-06, combos
## spec D1–D8), the data-driven skill list, the area build keys, the icons, and the save rules at the edge of each
## unlock (Review Focus 8). Task 8b: ห่าศร itself (ArrowRain, SkillHit, Hero.area_point / hit_source; the tests after
## "# ---------- ห่าศร (Task 8b) ----------"). กับดักหนาม's cast is Task 8c: until then its press is refused.

const DT := 1.0 / 60.0
const TMP := "user://test_area_skills.json"
const ST := {"crit": 0.05, "element_dmg": 0.0, "skill_cd_cut": 0.0}
const ALL := ["piercing", "spread", "arrow_rain", "thorn_trap", "fire_arrow"]

var tree: SceneTree
func setup(t: SceneTree) -> void:
	tree = t

var _shots: Array = []

func _hero(level := 1) -> Hero:
	var h: Hero = load("res://scenes/hero.tscn").instantiate()
	h.setup_sprites()
	if level > 1: h.set_progress(level, 0)
	h.inventory.slots.clear()
	_shots = []
	h.shot.connect(func(a): _shots.append(a))
	return h

func _done(h: Hero) -> void:
	for a in _shots: if is_instance_valid(a): a.free()
	h.halt_areas()               # frees the rains not in a tree
	h.free()

func _g(type: String, element := "", level := 1) -> Dictionary:
	var g := {"type": type, "level": level, "exp": 0, "rarity": "common", "opts": []}
	if element != "": g["element"] = element
	return g

func _b(id: String, lv: int, gems := []) -> Dictionary:
	return SkillBuild.of(id, lv, gems, ST)

func _near(a, b: float, tol := 0.0005) -> bool:
	return absf(float(a) - b) <= tol

func _num(path: String) -> float:
	return Balance.num(path)

# ---------- data ----------

## Every number is the approved one (docs/skills.md rows ห่าศร / กับดักหนาม / ศรเพลิง; combos spec D1, D4, D5, D6).
func test_numbers_match_skills_md():
	var want := {
		"arrow_rain": {"unlock": 7, "mult": 0.4, "cooldown": 10, "mp": 18, "radius": 64, "duration": 3, "tick": 0.5, "range": 220},
		"thorn_trap": {"unlock": 10, "mult": 1.5, "cooldown": 8, "mp": 12, "range": 160, "root": 2, "max_traps": 2, "trigger_radius": 16},
		"fire_arrow": {"unlock": 10, "mult": 2.0, "cooldown": 6, "mp": 14, "range": 220, "blast_radius": 32, "blast_frac": 1.0},
	}
	for id in want:
		var row: Dictionary = Balance.data()["skills"].get(id, {})
		for k in want[id]:
			if not row.has(k) or not _near(row[k], float(want[id][k]), 1e-9): return "skills.%s.%s = %s, want %s" % [id, k, row.get(k), want[id][k]]
		# no number beyond the approved ones ("kind" is not a number)
		for k in row:
			if k != "kind" and not want[id].has(k): return "skills.%s.%s is not an approved number" % [id, k]
	if Skills.kind("arrow_rain") != "rain" or Skills.kind("thorn_trap") != "trap": return "kinds %s / %s" % [Skills.kind("arrow_rain"), Skills.kind("thorn_trap")]
	for id in ["piercing", "spread", "fire_arrow"]:
		if Skills.kind(id) != "arrows": return "%s kind %s, want arrows" % [id, Skills.kind(id)]
	if not _near(_num("elements.fire.burn_frac"), 0.2) or not _near(_num("elements.fire.tick"), 1.0) or not _near(_num("elements.fire.duration"), 3.0):
		return "elements.fire changed"
	if not _near(_num("skills.per_level_damage"), 0.05) or not _near(_num("skills.per_level_cooldown"), 0.01) or not _near(_num("skills.max_cooldown_cut"), 0.3):
		return "per-level scaling changed"
	return ""

## D1: both Lv10 skills open at Lv10 (no job system yet).
func test_d1_both_open_at_lv10():
	if Skills.unlock_level("thorn_trap") != 10 or Skills.unlock_level("fire_arrow") != 10: return "unlock levels"
	var h := _hero(9)
	var r := ""
	if h.gem_slots("thorn_trap") != 0 or h.gem_slots("fire_arrow") != 0: r = "Lv9: the Lv10 skills must have no slots"
	h.set_progress(10, 0)
	if r == "" and (h.gem_slots("thorn_trap") != 2 or h.gem_slots("fire_arrow") != 2): r = "Lv10: both skills open with 2 slots (%d / %d)" % [h.gem_slots("thorn_trap"), h.gem_slots("fire_arrow")]
	_done(h)
	return r

func test_active_ids_order():
	if Skills.active_ids() != ALL: return "active_ids %s" % [Skills.active_ids()]
	# data-driven: a skill added to the data shows up, ordered by unlock level, ties in data order
	var skills: Dictionary = Balance.data()["skills"]
	skills["zz_test"] = {"unlock": 3, "mult": 1.0, "cooldown": 1, "mp": 1}
	var got := Skills.active_ids()
	skills.erase("zz_test")
	if got != ["piercing", "spread", "zz_test", "arrow_rain", "thorn_trap", "fire_arrow"]: return "with a Lv3 skill added: %s" % [got]
	if Skills.active_ids() != ALL: return "test data not restored"
	return ""

func test_names_and_icons():
	var names := {"piercing": "ศรทะลวง", "spread": "ศรกระจาย", "arrow_rain": "ห่าศร", "thorn_trap": "กับดักหนาม", "fire_arrow": "ศรเพลิง"}
	for id in names:
		if Skills.display_name(id) != names[id]: return "%s is named %s" % [id, Skills.display_name(id)]
	return ""

func test_labels():
	var yes := [["expand", "thorn_trap"], ["extend", "thorn_trap"], ["split", "fire_arrow"], ["expand", "fire_arrow"], ["extend", "arrow_rain"], ["expand", "arrow_rain"],
		["multiply", "thorn_trap"], ["element", "arrow_rain"]]
	var no := [["split", "arrow_rain"], ["extend", "fire_arrow"], ["split", "thorn_trap"], ["homing", "thorn_trap"], ["ricochet", "arrow_rain"]]
	for p in yes:
		if not Gem.fits(p[0], p[1]): return "%s should fit %s" % p
	for p in no:
		if Gem.fits(p[0], p[1]): return "%s should not fit %s" % p
	if Balance.data()["skill_labels"]["arrow_rain"] != ["area", "dot"]: return "arrow_rain labels changed"
	return ""

# ---------- builds ----------

func test_rain_build_lv7_and_lv10():
	var b := _b("arrow_rain", 7)
	if b.kind != "rain" or not _near(b.arrow_mult, 0.4) or not _near(b.cooldown, 10.0) or int(b.ticks) != 6: return "Lv7 %s" % b
	if not _near(b.radius, 64.0) or not _near(b.duration, 3.0) or not _near(b.tick_every, 0.5) or not _near(b.cast_range, 220.0) or not _near(b.mp, 18.0): return "Lv7 area keys %s" % b
	if not _near(b.area_mult, 1.0) or not _near(b.dur_mult, 1.0): return "no gem: area_mult / dur_mult must be 1"
	b = _b("arrow_rain", 10)
	if not _near(b.arrow_mult, 0.46) or not _near(b.cooldown, 9.7) or int(b.ticks) != 6: return "Lv10 %s" % b
	return ""

## D6: extend 3 → 3.9 s = 7 whole ticks; spec §3: expand + extend = 28.1 MP.
func test_rain_expand_extend():
	var b := _b("arrow_rain", 7, [_g("expand")])
	if not _near(b.radius, 83.2) or not _near(b.mp, 23.4) or not _near(b.area_mult, 1.3) or int(b.ticks) != 6: return "expand %s" % b
	b = _b("arrow_rain", 7, [_g("extend")])
	if not _near(b.duration, 3.9) or int(b.ticks) != 7 or not _near(b.dur_mult, 1.3) or not _near(b.radius, 64.0): return "extend %s" % b
	b = _b("arrow_rain", 7, [_g("expand"), _g("extend")])
	if not _near(b.mp, 28.08) or not _near(b.radius, 83.2) or int(b.ticks) != 7: return "expand + extend %s" % b
	# whole ticks only, at every gem level (never a part tick, never a float-edge tick lost)
	for lv in range(1, Gem.cap() + 1):
		b = _b("arrow_rain", 7, [_g("extend", "", lv)])
		var dur := 3.0 * (1.3 + 0.01 * (lv - 1))
		if int(b.ticks) != int(floor(dur / 0.5 + 1e-6)): return "extend Lv%d: %d ticks for %.2f s" % [lv, b.ticks, dur]
	# the damage gems work on a rain too
	b = _b("arrow_rain", 7, [_g("multiply")])
	if not _near(b.arrow_mult, 0.4 * 1.35) or not _near(b.mp, 27.0): return "multiply %s" % b
	return ""

func test_trap_build():
	var b := _b("thorn_trap", 10)
	if b.kind != "trap" or not _near(b.arrow_mult, 1.5) or not _near(b.cooldown, 8.0) or not _near(b.mp, 12.0): return "Lv10 %s" % b
	if not _near(b.root_secs, 2.0) or not _near(b.trigger_radius, 16.0) or int(b.max_traps) != 2 or not _near(b.cast_range, 160.0): return "Lv10 trap keys %s" % b
	b = _b("thorn_trap", 10, [_g("extend")])
	if not _near(b.root_secs, 2.6) or not _near(b.trigger_radius, 16.0) or not _near(b.mp, 14.4): return "extend %s" % b
	b = _b("thorn_trap", 10, [_g("expand")])
	if not _near(b.trigger_radius, 20.8) or not _near(b.root_secs, 2.0) or int(b.max_traps) != 2: return "expand %s" % b
	return ""

## D7: the arrow's own fire with no element gem (no ×1.1); a fire gem keeps one burn (×1.1); ice / lightning replace it.
func test_fire_arrow_build():
	var b := _b("fire_arrow", 10)
	if b.kind != "arrows" or int(b.arrows) != 1 or b.pierce_all or not _near(b.arrow_mult, 2.0) or not _near(b.blast_radius, 32.0) or not _near(b.blast_frac, 1.0): return "no gem %s" % b
	if b.element != "fire" or not _near(b.element_mult, 1.0) or not _near(b.mp, 14.0) or not _near(b.cooldown, 6.0): return "no gem: own fire %s" % b
	if not b.combo.is_empty(): return "the arrow's own fire formed %s" % b.combo
	b = _b("fire_arrow", 10, [_g("element", "fire")])
	if b.element != "fire" or not _near(b.arrow_mult, 2.2) or not _near(b.mp, 18.2) or not _near(b.element_mult, 1.1): return "fire gem %s" % b
	b = _b("fire_arrow", 10, [_g("element", "ice")])
	if b.element != "ice" or not _near(b.arrow_mult, 2.2): return "ice gem %s" % b
	b = _b("fire_arrow", 10, [_g("element", "lightning")])
	if b.element != "lightning" or not _near(b.arrow_mult, 2.2): return "lightning gem %s" % b
	b = _b("fire_arrow", 10, [_g("pierce"), _g("expand")])
	if not _near(b.mp, 21.84) or not _near(b.blast_radius, 41.6) or int(b.pierce_extra) != 2 or b.element != "fire": return "pierce + expand %s" % b
	b = _b("fire_arrow", 10, [_g("element", "fire"), _g("expand")])
	if not _near(b.mp, 23.66): return "fire + expand MP %s" % b.mp
	# gear element damage counts for the arrow's own fire (plan decision: it is elemental damage)
	b = SkillBuild.of("fire_arrow", 10, [], {"crit": 0.05, "element_dmg": 0.1, "skill_cd_cut": 0.0})
	if not _near(b.arrow_mult, 2.2) or not _near(b.element_mult, 1.1): return "element_dmg 10%% on the own fire: %s" % b
	# the split gem fans it like ศรทะลวง (ฝนดาวไฟ: 3 arrows)
	b = _b("fire_arrow", 10, [_g("split")])
	if int(b.arrows) != 3 or not _near(b.fan_deg, 24.0): return "split %s" % b
	return ""

func test_fire_arrow_own_fire_not_a_key():
	if GemCombo.resolve("fire_arrow", [_g("split")]) != {}: return "ศรพัดเพลิง without a fire gem"
	if GemCombo.resolve("fire_arrow", [_g("expand")]) != {}: return "ศรเพลิงระเบิด without a fire gem"
	if String(GemCombo.resolve("fire_arrow", [_g("split"), _g("element", "fire")]).get("id", "")) != "fire_fan": return "a real fire gem must still form the recipe"
	return ""

## ศรทะลวง / ศรกระจาย builds as they were before this task (dumped from ccdc0d6), with the new keys at their neutral values.
const GOLD_KEYS := ["mp", "dmg_mult", "arrow_mult", "crit", "cooldown", "arrows", "lines", "fan_deg", "pierce_extra", "bounces", "bounce_mult", "leech", "element_mult", "extra_bounces"]
const GOLD := '[["piercing",1,0,8.0,1.0,1.8,0.05,4.0,1.0,1.0,0.0,0.0,0.0,0.0,0.0,1.0,0.0,1,0,"",""],["piercing",1,1,11.2,1.0,1.08,0.08,4.0,3.0,3.0,24.0,0.0,0.0,0.0,0.0,1.0,0.0,1,0,"",""],["piercing",1,2,14.56,1.1,1.188,0.11,4.0,3.0,3.0,24.0,0.0,0.0,0.0,0.0,1.1,0.0,1,0,"fire","fire_fan"],["piercing",1,3,13.52,1.1,1.98,0.11,4.0,1.0,1.0,0.0,0.0,1.0,0.8,0.0,1.1,1.0,1,0,"lightning","thunder_hop"],["piercing",1,4,11.52,1.0,1.8,0.41,4.0,1.0,1.0,0.0,0.0,0.0,0.0,0.0,1.0,0.0,1,1,"","hawk_eye"],["piercing",1,5,14.4,1.35,2.43,0.11,4.0,1.0,1.0,0.0,0.0,0.0,0.0,0.06,1.0,0.0,1,0,"","bloodthirst"],["piercing",1,6,9.6,1.0,1.8,0.08,4.0,1.0,1.0,0.0,2.0,0.0,0.0,0.0,1.0,0.0,1,0,"",""],["piercing",1,7,21.84,1.485,1.6038,0.14,4.0,3.0,3.0,24.0,0.0,0.0,0.0,0.0,1.1,0.0,1,0,"ice","frost_shard"],["piercing",1,8,8.0,1.0,1.8,0.05,4.0,1.0,1.0,0.0,0.0,0.0,0.0,0.0,1.0,0.0,1,0,"",""],["piercing",3,0,8.0,1.0,1.98,0.05,3.92,1.0,1.0,0.0,0.0,0.0,0.0,0.0,1.0,0.0,1,0,"",""],["piercing",3,1,11.2,1.0,1.188,0.08,3.92,3.0,3.0,24.0,0.0,0.0,0.0,0.0,1.0,0.0,1,0,"",""],["piercing",3,2,14.56,1.1,1.3068,0.11,3.92,3.0,3.0,24.0,0.0,0.0,0.0,0.0,1.1,0.0,1,0,"fire","fire_fan"],["piercing",3,3,13.52,1.1,2.178,0.11,3.92,1.0,1.0,0.0,0.0,1.0,0.8,0.0,1.1,1.0,1,0,"lightning","thunder_hop"],["piercing",3,4,11.52,1.0,1.98,0.41,3.92,1.0,1.0,0.0,0.0,0.0,0.0,0.0,1.0,0.0,1,1,"","hawk_eye"],["piercing",3,5,14.4,1.35,2.673,0.11,3.92,1.0,1.0,0.0,0.0,0.0,0.0,0.06,1.0,0.0,1,0,"","bloodthirst"],["piercing",3,6,9.6,1.0,1.98,0.08,3.92,1.0,1.0,0.0,2.0,0.0,0.0,0.0,1.0,0.0,1,0,"",""],["piercing",3,7,21.84,1.485,1.76418,0.14,3.92,3.0,3.0,24.0,0.0,0.0,0.0,0.0,1.1,0.0,1,0,"ice","frost_shard"],["piercing",3,8,8.0,1.0,1.98,0.05,3.92,1.0,1.0,0.0,0.0,0.0,0.0,0.0,1.0,0.0,1,0,"",""],["piercing",5,0,8.0,1.0,2.16,0.05,3.84,1.0,1.0,0.0,0.0,0.0,0.0,0.0,1.0,0.0,1,0,"",""],["piercing",5,1,11.2,1.0,1.296,0.08,3.84,3.0,3.0,24.0,0.0,0.0,0.0,0.0,1.0,0.0,1,0,"",""],["piercing",5,2,14.56,1.1,1.4256,0.11,3.84,3.0,3.0,24.0,0.0,0.0,0.0,0.0,1.1,0.0,1,0,"fire","fire_fan"],["piercing",5,3,13.52,1.1,2.376,0.11,3.84,1.0,1.0,0.0,0.0,1.0,0.8,0.0,1.1,1.0,1,0,"lightning","thunder_hop"],["piercing",5,4,11.52,1.0,2.16,0.41,3.84,1.0,1.0,0.0,0.0,0.0,0.0,0.0,1.0,0.0,1,1,"","hawk_eye"],["piercing",5,5,14.4,1.35,2.916,0.11,3.84,1.0,1.0,0.0,0.0,0.0,0.0,0.06,1.0,0.0,1,0,"","bloodthirst"],["piercing",5,6,9.6,1.0,2.16,0.08,3.84,1.0,1.0,0.0,2.0,0.0,0.0,0.0,1.0,0.0,1,0,"",""],["piercing",5,7,21.84,1.485,1.92456,0.14,3.84,3.0,3.0,24.0,0.0,0.0,0.0,0.0,1.1,0.0,1,0,"ice","frost_shard"],["piercing",5,8,8.0,1.0,2.16,0.05,3.84,1.0,1.0,0.0,0.0,0.0,0.0,0.0,1.0,0.0,1,0,"",""],["piercing",10,0,8.0,1.0,2.61,0.05,3.64,1.0,1.0,0.0,0.0,0.0,0.0,0.0,1.0,0.0,1,0,"",""],["piercing",10,1,11.2,1.0,1.566,0.08,3.64,3.0,3.0,24.0,0.0,0.0,0.0,0.0,1.0,0.0,1,0,"",""],["piercing",10,2,14.56,1.1,1.7226,0.11,3.64,3.0,3.0,24.0,0.0,0.0,0.0,0.0,1.1,0.0,1,0,"fire","fire_fan"],["piercing",10,3,13.52,1.1,2.871,0.11,3.64,1.0,1.0,0.0,0.0,1.0,0.8,0.0,1.1,1.0,1,0,"lightning","thunder_hop"],["piercing",10,4,11.52,1.0,2.61,0.41,3.64,1.0,1.0,0.0,0.0,0.0,0.0,0.0,1.0,0.0,1,1,"","hawk_eye"],["piercing",10,5,14.4,1.35,3.5235,0.11,3.64,1.0,1.0,0.0,0.0,0.0,0.0,0.06,1.0,0.0,1,0,"","bloodthirst"],["piercing",10,6,9.6,1.0,2.61,0.08,3.64,1.0,1.0,0.0,2.0,0.0,0.0,0.0,1.0,0.0,1,0,"",""],["piercing",10,7,21.84,1.485,2.32551,0.14,3.64,3.0,3.0,24.0,0.0,0.0,0.0,0.0,1.1,0.0,1,0,"ice","frost_shard"],["piercing",10,8,8.0,1.0,2.61,0.05,3.64,1.0,1.0,0.0,0.0,0.0,0.0,0.0,1.0,0.0,1,0,"",""],["spread",3,0,12.0,1.0,0.7,0.05,6.0,5.0,1.0,45.0,0.0,0.0,0.0,0.0,1.0,0.0,0,0,"",""],["spread",3,1,16.8,1.0,0.42,0.08,6.0,7.0,3.0,63.0,0.0,0.0,0.0,0.0,1.0,0.0,0,0,"",""],["spread",3,2,21.84,1.1,0.462,0.11,6.0,7.0,3.0,63.0,0.0,0.0,0.0,0.0,1.1,0.0,0,0,"fire","fire_fan"],["spread",3,3,20.28,1.1,0.77,0.11,6.0,5.0,1.0,45.0,0.0,1.0,0.8,0.0,1.1,1.0,0,0,"lightning","thunder_hop"],["spread",3,4,17.28,1.0,0.7,0.41,6.0,5.0,1.0,45.0,0.0,0.0,0.0,0.0,1.0,0.0,0,1,"","hawk_eye"],["spread",3,5,21.6,1.35,0.945,0.11,6.0,5.0,1.0,45.0,0.0,0.0,0.0,0.06,1.0,0.0,0,0,"","bloodthirst"],["spread",3,6,14.4,1.0,0.7,0.08,6.0,5.0,1.0,45.0,2.0,0.0,0.0,0.0,1.0,0.0,0,0,"",""],["spread",3,7,32.76,1.485,0.6237,0.14,6.0,7.0,3.0,63.0,0.0,0.0,0.0,0.0,1.1,0.0,0,0,"ice","frost_shard"],["spread",3,8,12.0,1.0,0.7,0.05,6.0,5.0,1.0,45.0,0.0,0.0,0.0,0.0,1.0,0.0,0,0,"",""],["spread",5,0,12.0,1.0,0.77,0.05,5.88,5.0,1.0,45.0,0.0,0.0,0.0,0.0,1.0,0.0,0,0,"",""],["spread",5,1,16.8,1.0,0.462,0.08,5.88,7.0,3.0,63.0,0.0,0.0,0.0,0.0,1.0,0.0,0,0,"",""],["spread",5,2,21.84,1.1,0.5082,0.11,5.88,7.0,3.0,63.0,0.0,0.0,0.0,0.0,1.1,0.0,0,0,"fire","fire_fan"],["spread",5,3,20.28,1.1,0.847,0.11,5.88,5.0,1.0,45.0,0.0,1.0,0.8,0.0,1.1,1.0,0,0,"lightning","thunder_hop"],["spread",5,4,17.28,1.0,0.77,0.41,5.88,5.0,1.0,45.0,0.0,0.0,0.0,0.0,1.0,0.0,0,1,"","hawk_eye"],["spread",5,5,21.6,1.35,1.0395,0.11,5.88,5.0,1.0,45.0,0.0,0.0,0.0,0.06,1.0,0.0,0,0,"","bloodthirst"],["spread",5,6,14.4,1.0,0.77,0.08,5.88,5.0,1.0,45.0,2.0,0.0,0.0,0.0,1.0,0.0,0,0,"",""],["spread",5,7,32.76,1.485,0.68607,0.14,5.88,7.0,3.0,63.0,0.0,0.0,0.0,0.0,1.1,0.0,0,0,"ice","frost_shard"],["spread",5,8,12.0,1.0,0.77,0.05,5.88,5.0,1.0,45.0,0.0,0.0,0.0,0.0,1.0,0.0,0,0,"",""],["spread",10,0,12.0,1.0,0.945,0.05,5.58,5.0,1.0,45.0,0.0,0.0,0.0,0.0,1.0,0.0,0,0,"",""],["spread",10,1,16.8,1.0,0.567,0.08,5.58,7.0,3.0,63.0,0.0,0.0,0.0,0.0,1.0,0.0,0,0,"",""],["spread",10,2,21.84,1.1,0.6237,0.11,5.58,7.0,3.0,63.0,0.0,0.0,0.0,0.0,1.1,0.0,0,0,"fire","fire_fan"],["spread",10,3,20.28,1.1,1.0395,0.11,5.58,5.0,1.0,45.0,0.0,1.0,0.8,0.0,1.1,1.0,0,0,"lightning","thunder_hop"],["spread",10,4,17.28,1.0,0.945,0.41,5.58,5.0,1.0,45.0,0.0,0.0,0.0,0.0,1.0,0.0,0,1,"","hawk_eye"],["spread",10,5,21.6,1.35,1.27575,0.11,5.58,5.0,1.0,45.0,0.0,0.0,0.0,0.06,1.0,0.0,0,0,"","bloodthirst"],["spread",10,6,14.4,1.0,0.945,0.08,5.58,5.0,1.0,45.0,2.0,0.0,0.0,0.0,1.0,0.0,0,0,"",""],["spread",10,7,32.76,1.485,0.842,0.14,5.58,7.0,3.0,63.0,0.0,0.0,0.0,0.0,1.1,0.0,0,0,"ice","frost_shard"],["spread",10,8,12.0,1.0,0.945,0.05,5.58,5.0,1.0,45.0,0.0,0.0,0.0,0.0,1.0,0.0,0,0,"",""]]'

func _gold_sets() -> Array:
	var o := [{"k": "crit", "v": 0.03}]
	var g := func(t: String, el := "") -> Dictionary:
		var d := {"type": t, "level": 1, "exp": 0, "rarity": "good", "opts": o.duplicate(true)}
		if el != "": d["element"] = el
		return d
	return [[], [g.call("split")], [g.call("split"), g.call("element", "fire")], [g.call("ricochet"), g.call("element", "lightning")], [g.call("homing"), g.call("execute")],
		[g.call("leech"), g.call("multiply")], [g.call("pierce")], [g.call("split"), g.call("multiply"), g.call("element", "ice")], [g.call("expand"), g.call("extend")]]

func test_existing_builds_unchanged():
	var sets := _gold_sets()
	var rows: Array = JSON.parse_string(GOLD)
	if rows.size() != 63: return "golden rows %d" % rows.size()
	for row in rows:
		var id := String(row[0])
		var b := SkillBuild.of(id, int(row[1]), sets[int(row[2])], ST)
		var tag := "%s Lv%d set %d" % [id, int(row[1]), int(row[2])]
		for i in GOLD_KEYS.size():
			if not _near(b[GOLD_KEYS[i]], float(row[3 + i]), 0.00002): return "%s: %s = %s, was %s" % [tag, GOLD_KEYS[i], b[GOLD_KEYS[i]], row[3 + i]]
		var n := 3 + GOLD_KEYS.size()
		if b.pierce_all != (int(row[n]) == 1) or b.homing != (int(row[n + 1]) == 1): return "%s: pierce_all / homing changed" % tag
		if b.element != String(row[n + 2]) or String(b.combo.get("id", "")) != String(row[n + 3]): return "%s: element '%s' / combo '%s' changed" % [tag, b.element, b.combo.get("id", "")]
		# expand / extend do not fit an arrow skill: neutral
		if b.kind != "arrows" or not _near(b.area_mult, 1.0) or not _near(b.dur_mult, 1.0): return "%s: kind %s area %s dur %s" % [tag, b.kind, b.area_mult, b.dur_mult]
		for k in ["radius", "ticks", "trigger_radius", "root_secs", "blast_radius"]:
			if b.has(k): return "%s has the area key %s" % [tag, k]
	return ""

# ---------- icons / art ----------

func test_icon_fallback():
	if not Skills.icon("piercing").ends_with("piercing.png"): return "piercing icon %s" % Skills.icon("piercing")
	if not Skills.icon("no_such").ends_with("slot_empty.png"): return "unknown skill icon %s" % Skills.icon("no_such")
	for id in ALL:
		var p := Skills.icon(id)
		if not ResourceLoader.exists(p): return "%s icon %s cannot be loaded" % [id, p]
		# placeholder-tolerant: its own picture when the file is in the project, else the empty slot
		var own := "res://assets/skills/%s.png" % id
		if ResourceLoader.exists(own) != (p == own): return "%s icon %s (own file present: %s)" % [id, p, ResourceLoader.exists(own)]
	return ""

## The owner's picks (docs/art/area_skills/README.md: A2, B1, C3) are the installed files, pixel for pixel.
func test_owner_art_installed():
	var pairs := {
		"res://docs/art/area_skills/thorn_trap_icon.png": "res://assets/skills/thorn_trap.png",
		"res://docs/art/area_skills/fire_arrow_icon.png": "res://assets/skills/fire_arrow.png",
		"res://docs/art/area_skills/thorn_trap_ground.png": "res://assets/props/thorn_trap.png",
	}
	for src in pairs:
		if not FileAccess.file_exists(src): continue          # an exported game has no docs/
		var dst: String = pairs[src]
		if not FileAccess.file_exists(dst): return "%s not installed" % dst
		if FileAccess.get_md5(src) != FileAccess.get_md5(dst): return "%s is not the owner's pick %s" % [dst, src]
		var img := Image.load_from_file(ProjectSettings.globalize_path(dst))
		if img == null or img.get_size() != Vector2i(48, 48): return "%s is not 48×48" % dst
	return ""

# ---------- hero ----------

func test_hero_sockets_follow_the_skill_list():
	var h := _hero(10)
	var r := ""
	if h.skill_gems.keys() != ALL: r = "new hero sockets %s" % [h.skill_gems.keys()]
	h.set_skill_gems({"piercing": [_g("split")]})
	if r == "" and h.skill_gems.keys() != ALL: r = "after set_skill_gems %s" % [h.skill_gems.keys()]
	if r == "" and h.open_gems("arrow_rain") != [null, null]: r = "arrow_rain open gems %s" % [h.open_gems("arrow_rain")]
	_done(h)
	return r

## The game's own rule (Hero.socket): nothing on a locked skill, one gem of a type per skill, labels must fit; builds
## read the open sockets.
func test_socket_rules_on_new_skills():
	var h := _hero(9)
	h.inventory.add_gem(_g("multiply"))
	h.inventory.add_gem(_g("element", "fire"))
	h.inventory.add_gem(_g("element", "ice"))
	h.inventory.add_gem(_g("extend"))
	var r := ""
	if h.socket("fire_arrow", 0, 0) != "ยังไม่ปลด" or h.socket("thorn_trap", 0, 0) != "ยังไม่ปลด": r = "Lv9: the Lv10 skills must refuse gems"
	elif h.socket("no_such_skill", 0, 0) != "ยังไม่ปลด": r = "an unknown skill must refuse gems"
	h.set_progress(10, 0)
	if r == "":
		if h.socket("fire_arrow", 0, 1) != "": r = "Lv10: fire gem into ศรเพลิง refused"
		elif h.socket("fire_arrow", 1, 1) != "เจมชนิดนี้ใส่ในสกิลนี้แล้ว": r = "a second element gem on one skill must be refused"
		elif h.socket("fire_arrow", 0, 2) != "ป้ายไม่ตรง": r = "extend does not fit ศรเพลิง"
		elif h.socket("thorn_trap", 0, 2) != "": r = "extend into กับดักหนาม refused"
		elif h.socket("fire_arrow", 2, 0) != "ช่องยังไม่เปิด": r = "slot 3 of a skill at skill Lv1 is closed"
		elif not _near(h.build("fire_arrow").mp, 18.2) or not _near(h.build("thorn_trap").root_secs, 2.6): r = "builds do not read the sockets"
	if r == "":
		# a gem left in a closed slot is inert (open_gems), also on the new skills
		h.skill_gems["thorn_trap"] = [null, null, _g("expand")]
		if not _near(h.build("thorn_trap").trigger_radius, 16.0) or not _near(h.build("thorn_trap").mp, 12.0): r = "a closed-slot gem changed the trap build"
	_done(h)
	return r

## Until Tasks 8b / 8c build them, a rain / trap press must do nothing at all: no arrow, no MP, no cooldown.
func test_non_arrow_skill_press_is_refused():
	for id in ["thorn_trap"]:      # ห่าศร casts since Task 8b (test_rain_costs_and_cooldown)
		var h := _hero(10)
		h.facing = 2
		var mp0: float = h.mp
		var r := ""
		if h.try_skill(id): r = "%s: try_skill returned true" % id
		for i in 90: h.step(DT, Vector2.ZERO)
		if r == "":
			if not _shots.is_empty(): r = "%s fired %d arrow(s)" % [id, _shots.size()]
			elif h.mp < mp0: r = "%s spent MP (%.1f → %.1f)" % [id, mp0, h.mp]
			elif h.skill_cooldown_left(id) > 0.0: r = "%s went on cooldown" % id
			elif h.state == "shoot": r = "%s left the hero drawing the bow" % id
		if r == "":
			# also when it is pressed during a basic shot (the queued path)
			h.try_shoot()
			if h.try_skill(id): r = "%s queued during a basic shot" % id
			for i in 90: h.step(DT, Vector2.ZERO)
			if r == "" and (_shots.size() != 1 or h.skill_cooldown_left(id) > 0.0 or h.mp < mp0): r = "%s ran after the basic shot (%d arrows)" % [id, _shots.size()]
		_done(h)
		if r != "": return r
	# an id with no numbers is refused too (no crash)
	var h2 := _hero(10)
	var bad := h2.try_skill("no_such_skill")
	_done(h2)
	return "an unknown skill id was accepted" if bad else ""

## ศรเพลิง is an arrow skill: its press already goes through the arrow path (one arrow, MP 14, CD 6, the arrow's own
## fire burns on a hit). Its r32 blast comes with Task 8d.
func test_fire_arrow_press_fires_one_burning_arrow():
	var h := _hero(10)
	h.facing = 2
	var mp0: float = h.mp
	var r := ""
	if not h.try_skill("fire_arrow"): r = "Lv10 press refused"
	for i in 36: h.step(DT, Vector2.ZERO)
	var after := 0.6 - 5.0 / 14.0          # time since the arrow left
	if r == "":
		if _shots.size() != 1: r = "%d arrows, want 1" % _shots.size()
		elif _shots[0].pierce or absf(_shots[0].mult - 2.0) > 1e-4: r = "arrow mult %.3f pierce %s, want 2.0 / false" % [_shots[0].mult, _shots[0].pierce]
		elif String(_shots[0].build.get("element", "")) != "fire": r = "the arrow does not carry its own fire"
		elif absf(h.mp - (mp0 - 14.0 + float(h.stats().mp_regen) * after)) > 0.3: r = "MP %.2f → %.2f, want 14 spent" % [mp0, h.mp]
		elif absf(h.skill_cooldown_left("fire_arrow") - (6.0 - after)) > 0.05: r = "cooldown %.2f, want 6" % h.skill_cooldown_left("fire_arrow")
	_done(h)
	# locked at Lv9
	var h9 := _hero(9)
	if r == "" and h9.try_skill("fire_arrow"): r = "ศรเพลิง usable at Lv9"
	if r == "" and h9.try_skill("thorn_trap"): r = "กับดักหนาม usable at Lv9"
	_done(h9)
	return r

# ---------- skill screen ----------

func _labels(n: Node, out: Array) -> Array:
	if n is Label: out.append(n.text)
	for c in n.get_children(): _labels(c, out)
	return out

func test_panel_lists_five():
	var h := _hero(10)
	var p := SkillPanel.new()
	p.build()
	p.open(h)
	var r := ""
	if p._rows.keys() != ALL: r = "rows %s" % [p._rows.keys()]
	else:
		var texts := _labels(p, [])
		var at := -1
		for id in ALL:
			var i := texts.find(Skills.display_name(id))
			if i <= at: r = "%s row missing or out of order (%d after %d)" % [id, i, at]
			at = i
			if r == "" and p._rows[id].slots.get_child_count() != (3 if id == "piercing" else 2): r = "%s shows %d slots at Lv10" % [id, p._rows[id].slots.get_child_count()]
			if r == "" and String(p._rows[id].sub.text).begins_with("ปลดที่"): r = "%s shown locked at Lv10" % id
		for t in texts:
			if "รอบถัดไป" in t: r = "the old 'coming later' row is still there: %s" % t
		if r == "" and not String(p._rows["thorn_trap"].sub.text).contains("MP 12") : r = "trap row text %s" % p._rows["thorn_trap"].sub.text
	p.free(); h.free()
	if r != "": return r
	h = _hero(6)
	p = SkillPanel.new()
	p.build()
	p.open(h)
	if p._rows["arrow_rain"].sub.text != "ปลดที่ Lv7": r = "Lv6 arrow_rain row: %s" % p._rows["arrow_rain"].sub.text
	elif p._rows["fire_arrow"].sub.text != "ปลดที่ Lv10" or p._rows["thorn_trap"].sub.text != "ปลดที่ Lv10": r = "Lv6 Lv10-skill rows"
	else:
		for c in p._rows["arrow_rain"].slots.get_children():
			if not (c as Button).disabled: r = "a locked skill's slot can be pressed"
	# a gem for a locked skill: dim, with the unlock level in its preview
	if r == "":
		h.inventory.add_gem(_g("extend"))
		p.select_gem(0)
		if p.cell_usable(0): r = "extend is usable at Lv6"
		else:
			var lines := []
			for l in p.gem_detail().lines: lines.append(l.text)
			if not lines.has("ห่าศร: ปลดที่ Lv7") or not lines.has("กับดักหนาม: ปลดที่ Lv10"): r = "preview %s" % [lines]
	p.free(); h.free()
	return r

## All 5 rows are on screen without scrolling at 640×360, and every row can be reached (shown or scrollable) in portrait.
func test_panel_five_rows_fit():
	var w := tree.root
	var size0 := w.size
	var scale0 := w.content_scale_size
	var h := _hero(10)
	var p := SkillPanel.new()
	p.build()
	w.add_child(p)
	await tree.process_frame
	var fails := []
	for o in [Vector2i(1280, 720), Vector2i(1334, 750), Vector2i(1688, 780), Vector2i(750, 1334), Vector2i(780, 1688)]:
		DisplayServer.window_set_size(o)
		w.size = o
		w.content_scale_size = ScreenFit.base_for(o)
		for i in 3: await tree.process_frame
		p.open(h)
		for i in 3: await tree.process_frame
		var view := Rect2(Vector2.ZERO, w.get_visible_rect().size)
		var area := p._scroll.get_global_rect()
		if not view.grow(0.5).encloses(p._panel.get_global_rect()): fails.append("%s: panel %s off screen %s" % [o, p._panel.get_global_rect(), view])
		var hidden := 0
		for id in ALL:
			var row: Control = p._rows[id].row
			if not area.grow(1.5).encloses(row.get_global_rect()): hidden += 1      # row heights are fractional (41.8 px)
		var bar := p._scroll.get_v_scroll_bar()
		var can_scroll := bar.max_value > bar.page + 0.5
		if o.x > o.y and hidden > 0: fails.append("%s: %d row(s) need scrolling in landscape" % [o, hidden])
		if hidden > 0 and not can_scroll: fails.append("%s: %d row(s) cut off and no scrolling" % [o, hidden])
		if area.size.y * p._panel.scale.y < 2.0 * 40.0: fails.append("%s: the skill list is only %.0f px tall" % [o, area.size.y * p._panel.scale.y])
		p.close()
	tree.paused = false
	DisplayServer.window_set_size(size0)
	w.size = size0
	w.content_scale_size = scale0
	p.queue_free()
	h.free()
	await tree.process_frame
	return "; ".join(fails)

# ---------- save rules (docs/risks.md S5; Review Focus 8) ----------

func _bads() -> Array:
	var out := []
	for n in SaveGame.BAD_KEEP: out.append(SaveGame.bad_path(TMP, n))
	return out

func _clean() -> void:
	for p in [TMP, TMP + ".tmp", SaveGame.marker_path(TMP)] + _bads():
		if FileAccess.file_exists(p): DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

func _write_text(t: String) -> void:
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string(t)
	f.close()

## A file signed with the game's key but never range-checked: what someone who read the key out of the game can make.
func _write_signed(st: Dictionary) -> void:
	var d = JSON.parse_string(JSON.stringify(st))
	d["version"] = SaveGame.VERSION
	d["sig"] = SaveGame.signature(d)
	_write_text(JSON.stringify(d))

func _state(level: int, skills: Dictionary) -> Dictionary:
	var st := SaveGame.new_state()
	st.level = level
	st.skills = skills
	return st

func _sg(type: String, element := "") -> Dictionary:
	var g := {"type": type, "level": 2, "exp": 5, "rarity": "good", "opts": [{"k": "crit", "v": 0.02}]}
	if element != "": g["element"] = element
	return g

## "" when the loader and save() agree with `want` (true = accepted): a hand-signed file loads / is thrown away
## (kept as .bad.json, new game), and save() writes / refuses the same state.
func _both(name: String, st: Dictionary, want: bool) -> String:
	_clean()
	_write_signed(st)
	var s := SaveGame.load_or_new(TMP)
	var loaded: bool = not FileAccess.file_exists(SaveGame.bad_path(TMP, 0)) and int(s.level) == int(st.level)
	var thrown: bool = FileAccess.file_exists(SaveGame.bad_path(TMP, 0)) and not FileAccess.file_exists(TMP) and int(s.level) == 1 and s.skills.is_empty()
	_clean()
	var written := SaveGame.save(st, TMP)
	var on_disk := FileAccess.file_exists(TMP)
	_clean()
	if want and not loaded: return "should load: %s" % name
	if not want and not thrown: return "should be refused whole and kept as .bad.json: %s" % name
	if written != want or on_disk != want: return "save() %s what the loader %s: %s" % ["wrote" if written else "refused", "accepts" if want else "refuses", name]
	return ""

func test_save_gems_on_new_skills():
	var cases := [
		["ศรเพลิง gem at Lv9", _state(9, {"fire_arrow": [_sg("multiply")]}), false],
		["ศรเพลิง gem at Lv10", _state(10, {"fire_arrow": [_sg("multiply")]}), true],
		["กับดักหนาม gem at Lv9", _state(9, {"thorn_trap": [_sg("extend")]}), false],
		["กับดักหนาม gem at Lv9 in slot 2", _state(9, {"thorn_trap": [null, _sg("expand")]}), false],
		["กับดักหนาม gems at Lv10", _state(10, {"thorn_trap": [_sg("extend"), _sg("expand")]}), true],
		["ห่าศร gem at Lv6", _state(6, {"arrow_rain": [_sg("expand")]}), false],
		["ห่าศร gems at Lv7", _state(7, {"arrow_rain": [_sg("expand"), _sg("extend")]}), true],
		["empty sockets on locked skills (what a Lv1 hero saves)", _state(1, {"piercing": [], "spread": [], "arrow_rain": [], "thorn_trap": [], "fire_arrow": []}), true],
		["null sockets on locked skills", _state(1, {"thorn_trap": [null, null], "fire_arrow": [null]}), true],
		["two element gems on ศรเพลิง", _state(10, {"fire_arrow": [_sg("element", "fire"), _sg("element", "ice")]}), false],
		["two expand gems on กับดักหนาม", _state(10, {"thorn_trap": [_sg("expand"), _sg("expand")]}), false],
		["expand, null, expand on ห่าศร", _state(10, {"arrow_rain": [_sg("expand"), null, _sg("expand")]}), false],
		["split does not fit ห่าศร", _state(10, {"arrow_rain": [_sg("split")]}), false],
		["extend does not fit ศรเพลิง", _state(10, {"fire_arrow": [_sg("extend")]}), false],
		["homing does not fit กับดักหนาม", _state(10, {"thorn_trap": [_sg("homing")]}), false],
		["5 sockets on ศรเพลิง", _state(10, {"fire_arrow": [null, null, null, null, null]}), false],
		["a gem over the level cap on กับดักหนาม", _state(10, {"thorn_trap": [{"type": "expand", "level": Gem.cap() + 1, "exp": 0, "rarity": "good", "opts": []}]}), false],
		["an unknown skill id", _state(10, {"poison_shot": []}), false],
		["the same type on two skills, one of each per skill", _state(10, {"fire_arrow": [_sg("element", "ice"), _sg("split")], "thorn_trap": [_sg("element", "fire"), _sg("expand")],
			"arrow_rain": [_sg("element", "lightning"), _sg("expand")]}), true],
		# hand-made (slot 3 is closed at skill Lv1) but kept: owner 2026-11-09 "never lost"; the hero returns it to the bag
		["a gem in a closed slot of an unlocked skill", _state(10, {"fire_arrow": [_sg("multiply"), _sg("split"), _sg("execute")]}), true],
	]
	for c in cases:
		var r := _both(c[0], c[1], c[2])
		if r != "": return r
	return ""

## A tampered save (gems on a skill the character has not unlocked, signed by someone who has the key) is refused
## whole and kept, never overwritten: .bad.json, then .bad.1.json. Changing one character of a good save does the same.
func test_tampered_new_skill_save_is_kept_as_bad():
	_clean()
	var r := ""
	var cheat := _state(9, {"fire_arrow": [_sg("multiply"), _sg("element", "fire")]})
	_write_signed(cheat)
	var text1 := FileAccess.get_file_as_string(TMP)
	var s := SaveGame.load_or_new(TMP)
	if int(s.level) != 1 or not s.skills.is_empty(): r = "the tampered save was loaded: %s" % s
	elif FileAccess.file_exists(TMP): r = "the refused file is still in place"
	elif FileAccess.get_file_as_string(SaveGame.bad_path(TMP, 0)) != text1: r = "the refused save was not kept as .bad.json"
	if r == "":
		# a good Lv10 save with gems on ศรเพลิง, then the level edited down / one character changed: the signature fails
		var good := _state(10, {"fire_arrow": [_sg("multiply")]})
		if not SaveGame.save(good, TMP): r = "a good Lv10 save was not written"
		else:
			var text2 := FileAccess.get_file_as_string(TMP).replace("\"multiply\"", "\"execute\"")
			_write_text(text2)
			s = SaveGame.load_or_new(TMP)
			if int(s.level) != 1: r = "an edited gem type loaded"
			elif FileAccess.get_file_as_string(SaveGame.bad_path(TMP, 1)) != text2: r = "the second refused save was not kept as .bad.1.json"
			elif FileAccess.get_file_as_string(SaveGame.bad_path(TMP, 0)) != text1: r = "the first refused copy was overwritten"
	_clean()
	return r

## An old v4 save from before the area skills (no arrow_rain / thorn_trap / fire_arrow keys) still loads; the hero
## gets empty sockets for the new skills and what he saves next loads back.
func test_old_v4_save_without_the_new_skills_loads():
	_clean()
	_write_text(load("res://tests/test_save_hardening.gd").FIXTURE_V4)
	var s := SaveGame.load_or_new(TMP)
	var r := ""
	if FileAccess.file_exists(SaveGame.bad_path(TMP, 0)): r = "the 2026-11-09 save was refused"
	elif int(s.level) != 7 or s.skills.keys() != ["piercing"] or String(s.skills.piercing[0].type) != "multiply": r = "loaded %s" % [s.skills]
	var h := _hero(7)
	if r == "":
		h.set_skill_gems(s.skills)
		if h.skill_gems.keys() != ALL: r = "hero sockets %s" % [h.skill_gems.keys()]
		elif String(h.skill_gems.piercing[0].type) != "multiply" or int(h.skill_gems.piercing[0].level) != 2: r = "the socketed gem changed: %s" % [h.skill_gems.piercing]
		elif h.return_closed_gems() != 0: r = "a legal old gem was moved to the bag"
	if r == "":
		# the game saves only the skills that hold a gem: no key an older build does not know (risks.md B15)
		if h.sockets_to_save().keys() != ["piercing"]: r = "sockets_to_save %s, want only piercing" % [h.sockets_to_save().keys()]
	if r == "":
		s["skills"] = h.sockets_to_save()
		if not SaveGame.save(s, TMP): r = "the next save was not written"
		else:
			var s2 := SaveGame.load_or_new(TMP)
			if FileAccess.file_exists(SaveGame.bad_path(TMP, 0)) or int(s2.level) != 7 or s2.skills.keys() != ["piercing"]: r = "the next save did not load back: %s" % [s2.skills]
			elif String(s2.skills.piercing[0].type) != "multiply": r = "gem lost in the round trip"
			else:
				h.set_skill_gems(s2.skills)
				if h.skill_gems.keys() != ALL: r = "sockets after the round trip %s" % [h.skill_gems.keys()]
	if r == "":
		# every key also loads (a save written with all 5), and a hero with no gems saves no skill key at all
		s["skills"] = h.skill_gems
		if not SaveGame.save(s, TMP) or FileAccess.file_exists(SaveGame.bad_path(TMP, 0)) or int(SaveGame.load_or_new(TMP).level) != 7: r = "a save with all 5 skill keys did not load"
		h.set_skill_gems({})
		if r == "" and not h.sockets_to_save().is_empty(): r = "an empty hero saves %s" % [h.sockets_to_save()]
		h.set_skill_gems({"thorn_trap": [null, {"type": "expand", "level": 1, "exp": 0, "rarity": "common", "opts": []}]})
		if r == "" and (h.sockets_to_save().keys() != ["thorn_trap"] or h.sockets_to_save().thorn_trap[0] != null): r = "a gem in slot 2 must keep its slot: %s" % [h.sockets_to_save()]
	h.free()
	_clean()
	return r

## The biggest save (every skill, every slot, cap gems) still fits save.max_bytes with the three new skills in it.
func test_full_sockets_on_five_skills_fit_the_size_limit():
	var sk := {}
	for id in ALL:
		sk[id] = []
		var fit := []
		for t in Gem.types():
			if Gem.fits(String(t), id): fit.append(String(t))
		if fit.size() < Balance.data()["gem_slots"].size(): return "%s has only %d fitting gem types for %d slots" % [id, fit.size(), Balance.data()["gem_slots"].size()]
		for i in Balance.data()["gem_slots"].size():
			var opts := []
			for k in ["dmg_pct", "cd_cut", "mp_cut", "crit"]: opts.append({"k": k, "v": float(Balance.data()["gem_options"][k].max)})
			var g := {"type": fit[i], "level": Gem.cap(), "exp": 0, "rarity": "legend", "opts": opts}
			if fit[i] == "element": g["element"] = "lightning"
			sk[id].append(g)
	return _both("every slot of all 5 skills at the level cap", _state(Progression.cap(), sk), true)

# ---------- ห่าศร (Task 8b) ----------

const RAIN := "arrow_rain"
var _made: Array = []

func _dummy(feet: Vector2) -> Node2D:
	var d: Node2D = load("res://tests/dummy_enemy.gd").new()
	d.position = feet
	_made.append(d)
	return d

func _free_made() -> void:
	for d in _made: if is_instance_valid(d): d.free()
	_made = []

## A rain of hero h's build (its gems, its ledger) at `center`, not in a tree: stepped by the test.
func _rain(h: Hero, center: Vector2, targets: Array) -> ArrowRain:
	h.test_enemies = targets
	var b := h.build(RAIN)
	b["cast"] = ComboCast.from_build(b, 1.0)
	var rain := ArrowRain.new()
	rain.setup(center, b, h.hit_source(b), targets)
	_made.append(rain)
	return rain

## Presses ห่าศร for real (try_skill, the bow animation, the release) and returns the rain it laid (null: none).
func _press(h: Hero, targets: Array) -> ArrowRain:
	h.test_enemies = targets
	if not h.try_skill(RAIN): return null
	for i in 40:
		h.step(DT, Vector2.ZERO)
		if not h.rains.is_empty(): return h.rains[0]
	return null

## Steps the rain to `secs` after its cast; returns the time of every hit on d, to 1/60 s.
func _run(rain: ArrowRain, secs: float, d: Node2D = null) -> Array:
	var times: Array = []
	var n: int = d.hits.size() if d != null else 0
	if not is_instance_valid(rain): return times
	for i in int(ceil((secs - rain.time()) / DT - 1e-6)):       # a rain that is over no longer counts time
		if not is_instance_valid(rain) or rain.done: break
		rain.step(DT)
		if d != null and d.hits.size() > n:
			n = d.hits.size()
			times.append(snappedf(rain.time(), 0.01))
	return times

func _sockets(h: Hero, gems: Array) -> void:
	h.set_skill_gems({RAIN: gems})

## docs/skills.md: r64, 3 s, a tick of 40 % every 0.5 s. Feet within 64 px are hit, at 0.5, 1.0 ... 3.0 s and never
## before 0.5 s; feet at 65 px never; after the last tick the rain is over and hits nothing more.
func test_rain_six_ticks_r64():
	var h := _hero(7)
	var d_in := _dummy(Vector2(63, 0))
	var d_out := _dummy(Vector2(65, 0))
	var d_diag := _dummy(Vector2(-45, 45))       # 63.6 px
	var d_far := _dummy(Vector2(-46, 46))        # 65.05 px
	var d_up := _dummy(Vector2(0, -63.9))        # a true circle: as far up as sideways
	var all := [d_in, d_out, d_diag, d_far, d_up]
	var rain := _rain(h, Vector2.ZERO, all)
	var r := ""
	for i in 29: rain.step(DT)
	if not d_in.hits.is_empty(): r = "a hit before 0.5 s (t = %.3f)" % rain.time()
	var times := _run(rain, 3.2, d_in) if r == "" else []
	if r == "":
		if times != [0.5, 1.0, 1.5, 2.0, 2.5, 3.0]: r = "hit times %s, want 0.5 .. 3.0" % [times]
		elif d_diag.hits.size() != 6 or d_up.hits.size() != 6: r = "inside the circle: %d / %d hits, want 6 each" % [d_diag.hits.size(), d_up.hits.size()]
		elif not d_out.hits.is_empty() or not d_far.hits.is_empty(): r = "a monster outside r64 was hit (%d / %d)" % [d_out.hits.size(), d_far.hits.size()]
		elif rain.ticks_done != 6 or not rain.done: r = "ticks_done %d done %s, want 6 / true" % [rain.ticks_done, rain.done]
		else:
			for hit in d_in.hits:
				if not _near(hit[1], 0.4) or hit[2] != Vector2.ZERO or not _near(hit[0], float(h.stats().atk)): r = "hit %s, want ATK %.1f × 0.4 from the centre" % [hit, h.stats().atk]
	if r == "":
		for i in 120: rain.step(DT)
		if d_in.hits.size() != 6: r = "the rain hit after its last tick (%d hits)" % d_in.hits.size()
	_free_made()
	_done(h)
	return r

## D6: the extend gem makes it 3.9 s: 7 whole ticks, the last at 3.5 s, then it is over. In a tree it then frees itself.
func test_rain_extend_seven_ticks():
	var h := _hero(7)
	_sockets(h, [_g("extend")])
	var d := _dummy(Vector2(10, 0))
	var rain := _rain(h, Vector2.ZERO, [d])
	var times := _run(rain, 3.45, d)
	var r := ""
	if times.size() != 6 or rain.done: r = "at 3.45 s: %d hits, done %s; want 6, still falling" % [times.size(), rain.done]
	times += _run(rain, 4.2, d)
	if r == "" and (times.size() != 7 or times[6] != 3.5): r = "hit times %s, want 7 with the last at 3.5" % [times]
	if r == "" and not rain.done: r = "not over after its 7th tick"
	_free_made()
	_done(h)
	if r != "": return r
	# in a tree: over after the last tick, gone after its short fade
	var world := Node2D.new()
	tree.root.add_child(world)
	var h2 := _hero(7)
	var d2 := _dummy(Vector2(10, 0))
	world.add_child(d2)
	var rain2 := _rain(h2, Vector2.ZERO, [d2])
	world.add_child(rain2)
	rain2.set_physics_process(false)
	_run(rain2, 3.05, d2)
	if not rain2.done or d2.hits.size() != 6: r = "in a tree: done %s after %d hits" % [rain2.done, d2.hits.size()]
	for i in 30:
		if is_instance_valid(rain2) and not rain2.is_queued_for_deletion(): rain2.step(DT)
	if r == "" and not rain2.is_queued_for_deletion(): r = "in a tree the rain did not free itself after its last tick"
	_made.erase(d2)
	_made.erase(rain2)
	world.free()
	_free_made()
	_done(h2)
	return r

func test_rain_expand_radius():
	var h := _hero(7)
	_sockets(h, [_g("expand")])
	var d_in := _dummy(Vector2(83, 0))
	var d_out := _dummy(Vector2(84, 0))
	var rain := _rain(h, Vector2.ZERO, [d_in, d_out])
	_run(rain, 0.6)
	var r := ""
	if not _near(rain.radius, 83.2): r = "radius %.2f, want 83.2" % rain.radius
	elif d_in.hits.size() != 1: r = "83 px with the expand gem: %d hits, want 1" % d_in.hits.size()
	elif not d_out.hits.is_empty(): r = "84 px was hit (radius 83.2)"
	_free_made()
	_done(h)
	return r

## D2: the rain lands on the feet of the nearest live monster within 220 px, else on the hero's own feet.
func test_rain_target_point():
	var cases := [
		["one at 200 px", [Vector2(200, 0)], [], Vector2(200, 0)],
		["one at 230 px", [Vector2(230, 0)], [], Vector2(30, 40)],
		["nearest of two", [Vector2(180, 40), Vector2(-90, 40)], [], Vector2(-90, 40)],
		["a dead one is skipped", [Vector2(60, 40), Vector2(150, 40)], [0], Vector2(150, 40)],
		["no monster", [], [], Vector2(30, 40)],
	]
	for c in cases:
		var h := _hero(7)
		h.position = Vector2(30, 40) if c[0] != "one at 200 px" and c[0] != "one at 230 px" else Vector2.ZERO
		var want: Vector2 = c[3] if h.position != Vector2.ZERO or c[0] == "one at 200 px" else Vector2.ZERO
		var ds: Array = []
		for p in c[1]: ds.append(_dummy(p))
		for i in c[2]: ds[i].alive = false
		var rain := _press(h, ds)
		var r := ""
		if rain == null: r = "%s: no rain was laid" % c[0]
		elif rain.center != want: r = "%s: centre %s, want %s" % [c[0], rain.center, want]
		elif h.area_point(220.0) != want and c[2].is_empty(): r = "%s: area_point %s" % [c[0], h.area_point(220.0)]
		elif not _shots.is_empty(): r = "%s: the press fired %d arrow(s)" % [c[0], _shots.size()]
		_done(h)
		_free_made()
		if r != "": return r
	return ""

## MP 18, cooldown 10 × (1 − 3 %) at Lv10 (skill Lv4); refused on cooldown, without the MP, and before Lv7.
func test_rain_costs_and_cooldown():
	var h := _hero(10)
	var mp0: float = h.mp
	var r := ""
	if not h.try_skill(RAIN): r = "Lv10 press refused"
	for i in 36: h.step(DT, Vector2.ZERO)
	var after := 0.6 - 5.0 / 14.0
	if r == "":
		if h.rains.size() != 1: r = "%d rains, want 1" % h.rains.size()
		elif absf(h.mp - (mp0 - 18.0 + float(h.stats().mp_regen) * after)) > 0.3: r = "MP %.2f → %.2f, want 18 spent" % [mp0, h.mp]
		elif absf(h.skill_cooldown_left(RAIN) - (9.7 - after)) > 0.05: r = "cooldown %.2f, want 9.7" % h.skill_cooldown_left(RAIN)
		elif h.try_skill(RAIN): r = "a second press during the cooldown was accepted"
		elif not _shots.is_empty(): r = "the rain press fired an arrow"
	_done(h)
	if r != "": return r
	var poor := _hero(10)
	poor.mp = 17.0
	if poor.try_skill(RAIN): r = "pressed with 17 MP (needs 18)"
	_done(poor)
	var low := _hero(6)
	if r == "" and low.try_skill(RAIN): r = "ห่าศร usable at Lv6"
	_done(low)
	return r

## Area ticks are primary hits: each rolls the build's crit chance and leeches (3 % of the tick's damage).
func test_rain_ticks_crit_and_leech():
	var h := _hero(7)
	_sockets(h, [_g("leech"), _g("execute")])
	var b := h.build(RAIN)
	var d := _dummy(Vector2(5, 0))
	d.deal = 100
	h.health.hp = 10
	var rain := _rain(h, Vector2.ZERO, [d])
	_run(rain, 3.1)
	var r := ""
	if d.hits.size() != 6: r = "%d hits" % d.hits.size()
	elif h.health.hp != 10 + 18: r = "HP 10 → %d, want +18 (3 %% of 6 × 100)" % h.health.hp
	elif not _near(b.crit, 0.05 + 0.15): r = "build crit %.3f, want 0.20 with the execute gem" % b.crit
	else:
		for c in d.crit_chances:
			if not _near(c, float(b.crit)): r = "a tick rolled crit chance %.3f, want the build's %.3f" % [c, b.crit]
	_free_made()
	_done(h)
	return r

## Review Focus 6: a rain's kills go through the one kill hook with the press's ONE ledger: ศรกระหายเลือด (leech +
## multiply) refunds 2 MP a kill, at most 6 a press: 4 kills = +6, not +8; each kill heals 3 % of max HP.
func test_rain_kill_counts_for_sustain():
	var h := _hero(7)
	_sockets(h, [_g("leech"), _g("multiply")])
	var ds: Array = []
	for i in 4:
		var d := _dummy(Vector2(-30 + 20 * i, 10))
		d.die_on_hit = true
		ds.append(d)
	var late := _dummy(Vector2(0, -30))          # dies on the last tick: the same ledger, the cap is already spent
	ds.append(late)
	var rain := _press(h, ds)
	var r := ""
	if rain == null:
		_free_made()
		_done(h)
		return "no rain"
	var cast: ComboCast = rain.src.cast
	if cast == null or cast.id != "bloodthirst": r = "the rain's ledger is %s, want the press's bloodthirst" % [cast.id if cast else "null"]
	h.mp = 0.0
	h.health.hp = 1
	_run(rain, 0.6)
	var heal := 4 * int(floor(0.03 * h.health.max_hp + 1e-6))
	if r == "":
		if not _near(h.mp, 6.0): r = "4 kills in one tick: MP +%.2f, want +6 (the cap), not +8" % h.mp
		elif absf(h.health.hp - 1 - heal) > 4 + 1: r = "HP 1 → %d, want about +%d (3 %% a kill; + leech)" % [h.health.hp, heal]
	if r == "":
		late.die_on_hit = true
		_run(rain, 3.1)
		if late.alive: r = "the late monster did not die"
		elif not _near(h.mp, 6.0): r = "a kill on a later tick paid again: MP %.2f (one cap per press)" % h.mp
		elif not _near(cast.mp_refunded(), 6.0): r = "ledger refunded %.2f" % cast.mp_refunded()
	_free_made()
	_done(h)
	return r

## The element gem's status lands on every monster a tick hits: fire burns (20 % of that tick, the press's ledger),
## ice slows; lightning chains once per monster hit to the nearest other one within 120 px at × 0.8 (also outside
## the circle), and the chained hit chains no further.
func test_rain_fire_gem_burns_all():
	var h := _hero(7)
	_sockets(h, [_g("element", "fire")])
	var ds := [_dummy(Vector2(-40, 0)), _dummy(Vector2(0, 30)), _dummy(Vector2(50, -10))]
	for d in ds: d.deal = 50
	var out := _dummy(Vector2(120, 0))
	var rain := _rain(h, Vector2.ZERO, ds + [out])
	_run(rain, 0.6)
	var r := ""
	for d in ds:
		if not d.status.is_burning(): r = "a monster hit by the first tick is not burning"
		elif not _near(d.status.burn_per_tick, 10.0): r = "burn %.2f a tick, want 20 %% of the 50 dealt" % d.status.burn_per_tick
		elif d.status.burn_cast != rain.src.cast or rain.src.cast == null: r = "the burn does not carry the press's ledger"
		elif not _near(d.hits[0][1], 0.4 * 1.1): r = "tick mult %.3f, want 0.44 with the fire gem" % d.hits[0][1]
	if r == "" and (out.status.is_burning() or not out.hits.is_empty()): r = "a monster outside the circle was hit / burnt"
	_free_made()
	_done(h)
	if r != "": return r
	var hi := _hero(7)
	_sockets(hi, [_g("element", "ice")])
	var di := _dummy(Vector2(10, 0))
	var ri := _rain(hi, Vector2.ZERO, [di])
	_run(ri, 0.6)
	if not di.status.is_slowed() or di.status.is_burning(): r = "ice gem: slowed %s burning %s" % [di.status.is_slowed(), di.status.is_burning()]
	_free_made()
	_done(hi)
	if r != "": return r
	var hl := _hero(7)
	_sockets(hl, [_g("element", "lightning")])
	var a := _dummy(Vector2(60, 0))
	var far := _dummy(Vector2(150, 0))            # outside the circle, 90 px from a
	var rl := _rain(hl, Vector2.ZERO, [a, far])
	_run(rl, 0.6)
	if a.hits.size() != 1: r = "lightning: the monster in the circle took %d hits, want 1 (nothing chains back)" % a.hits.size()
	elif far.hits.size() != 1 or not _near(far.hits[0][1], 0.4 * 1.1 * 0.8): r = "lightning chain: %s, want one hit of 0.352" % [far.hits]
	_free_made()
	_done(hl)
	return r

## Review Focus 7 (B20): a rain never outlives a warp, the hero's death or the room: no further hit, the node goes.
func test_rain_freed_on_warp():
	for how in ["warp", "death"]:
		var h := _hero(7)
		var d := _dummy(Vector2(40, 0))
		var rain := _press(h, [d])
		if rain == null:
			_done(h)
			_free_made()
			return "no rain"
		_run(rain, 0.6)
		var r := ""
		if d.hits.size() != 1: r = "%d hits after the first tick" % d.hits.size()
		if how == "warp": h.begin_warp()
		else: h.health.take_hit(999999, false)
		if r == "":
			if is_instance_valid(rain): r = "%s: the rain is still there" % how
			elif not h.rains.is_empty(): r = "%s: the hero still lists a rain" % how
		_done(h)
		_free_made()
		if r != "": return r
	# in a tree (the world): halted at once, freed by the tree, and it hits nothing in between
	var world := Node2D.new()
	tree.root.add_child(world)
	var h2 := _hero(7)
	world.add_child(h2)
	h2.set_physics_process(false)
	var d2 := _dummy(Vector2(40, 0))
	d2.add_to_group("enemies")                   # in a tree the hero reads the group
	world.add_child(d2)
	var rain2 := _press(h2, [d2])
	var r2 := ""
	if rain2 == null or rain2.get_parent() != world: r2 = "in a tree the rain is not the hero's sibling"
	else:
		rain2.set_physics_process(false)
		_run(rain2, 0.6)
		h2.begin_warp()
		var n: int = d2.hits.size()
		for i in 120: rain2.step(DT)
		if not rain2.done or not rain2.is_queued_for_deletion(): r2 = "in a tree: done %s, queued %s after the warp" % [rain2.done, rain2.is_queued_for_deletion()]
		elif d2.hits.size() != n or n != 1: r2 = "hits after the warp: %d → %d" % [n, d2.hits.size()]
	_made.erase(d2)
	_shots = []
	world.free()
	_free_made()
	return r2

## Two rains of one hero never overlap: even with the extend gem at the gem level cap the rain is over before the
## shortest cooldown the skill can have (10 s × (1 − the 30 % cut cap)).
func test_rain_not_overlapping():
	var top := _b(RAIN, 99, [_g("extend", "", 20)])
	var capped := _b(RAIN, 99, [_g("extend", "", Gem.cap())])
	var shortest := _num("skills.arrow_rain.cooldown") * (1.0 - _num("skills.max_cooldown_cut"))
	if not _near(top.duration, 4.47): return "extend Lv20: duration %.3f, want 4.47" % top.duration
	if float(capped.duration) + ArrowRain.FADE >= shortest: return "extend at the gem cap: %.2f s ≥ the shortest cooldown %.2f s" % [capped.duration, shortest]
	if float(capped.ticks) * float(capped.tick_every) > float(capped.duration) + 1e-6: return "the last tick is after the duration"
	return ""

## Area ticks never produce the arrow-only combo effects, whatever numbers the build carries: no mark, no freeze (and
## no freeze count), no fire trail. (No recipe with them fits ห่าศร's labels today; this guards the shared SkillHit.)
func test_rain_no_arrow_only_effects():
	var h := _hero(7)
	var d := _dummy(Vector2(5, 0))
	var rain := _rain(h, Vector2.ZERO, [d])
	rain.src.build["combo_p"] = {"mark_secs": 4.0, "mark_taken": 0.3, "freeze_hits": 1.0, "freeze_secs": 1.0, "freeze_lock_secs": 5.0,
		"trail_secs": 2.0, "trail_frac": 0.2, "blast_on_chilled": 1.0, "blast_radius": 32.0, "blast_frac": 0.5, "bolts": 2.0, "bolt_frac": 0.5}
	var trails := FireTrail.made
	var other := _dummy(Vector2(20, 0))
	other.position = Vector2(100, 0)              # outside: a bolt / shatter would reach it
	rain.targets = [d, other]
	_run(rain, 3.1)
	var r := ""
	if d.hits.size() != 6: r = "%d hits" % d.hits.size()
	elif d.is_marked() or d.freezes != 0 or d.is_frozen(): r = "a rain tick marked / froze (marked %s, freezes %d)" % [d.is_marked(), d.freezes]
	elif FireTrail.made != trails: r = "a rain laid a fire trail"
	elif not other.hits.is_empty(): r = "a rain tick reached a monster outside the circle (%d hits)" % other.hits.size()
	_free_made()
	_done(h)
	return r

class LoudDummy extends "res://tests/dummy_enemy.gd":
	func receive_hit(atk: float, mult: float, from: Vector2, crit_chance := -1.0, crit_mult := -1.0) -> int:
		Sfx.play("arrow_hit", position)           # as Wolf.receive_hit
		return super.receive_hit(atk, mult, from, crit_chance, crit_mult)

## Plan decision: one hit sound per rain tick, however many monsters it hits (5 here: 6 sounds in 3 s, not 30), and
## the hit sounds are back on after every tick.
func test_rain_one_hit_sound_per_tick():
	Sfx.reset()
	var h := _hero(7)
	var ds: Array = []
	for i in 5:
		var d := LoudDummy.new()
		d.position = Vector2(-40 + 20 * i, 0)
		_made.append(d)
		ds.append(d)
	var rain := _rain(h, Vector2.ZERO, ds)
	var asked := 0
	var played := 0
	var r := ""
	for i in 190:
		Sfx.fake_now = i * DT
		Sfx.requested.clear()
		Sfx.started.clear()
		rain.step(DT)
		asked += Sfx.requested.filter(func(e): return e.id == "arrow_hit").size()
		played += Sfx.started.filter(func(e): return e.id == "arrow_hit").size()
		if Sfx.hit_quiet: r = "hit sounds left switched off after a step"
	if r == "":
		if asked != 30: r = "%d hits asked for a sound, want 30 (5 monsters × 6 ticks)" % asked
		elif played != 6: r = "%d hit sounds started, want 6 (one a tick)" % played
		elif not Sfx.play("arrow_hit"): r = "a hit sound after the rain did not play"
	Sfx.reset()
	_free_made()
	_done(h)
	return r

## The area marker (the real hit circle and the yantra) is never shed by the PerfSaver; only the falling arrows are.
func test_rain_marker_stays_with_perf_saver():
	var world := Node2D.new()
	tree.root.add_child(world)
	var h := _hero(7)
	var rain := _rain(h, Vector2(50, 50), [])
	world.add_child(rain)
	rain.set_physics_process(false)
	_made.erase(rain)
	var r := ""
	var was := PerfSaver.active
	for on in [false, true]:
		PerfSaver.active = on
		for i in 20: rain.step(DT)               # 0.33 s / 0.67 s: arrows of the next tick are in the air
		if rain._ring == null or not rain._ring.visible or not rain._ring.is_playing(): r = "saver %s: the yantra is not shown" % on
		elif not rain.visible or rain.modulate.a < 1.0: r = "saver %s: the marker is hidden / faded" % on
		elif on and rain.arrows_now() != 0: r = "saver on: %d falling arrows drawn (decoration)" % rain.arrows_now()
		elif not on and rain.arrows_now() == 0: r = "saver off: no falling arrow at %.2f s" % rain.time()
	PerfSaver.active = was
	if r == "" and PerfSaver.decorative(ArrowRain.RING_FX): r = "the marker's effect is listed as decoration"
	var wide: float = rain._ring.scale.x * rain._ring._cell.x
	if r == "" and (wide > 128.0 or wide < 0.85 * 128.0 or fmod(rain._ring.scale.x * 2.0, 1.0) != 0.0): r = "the yantra is %.1f px wide (× %.2f), want an even scale just inside the circle's 128" % [wide, rain._ring.scale.x]
	if r == "" and not _near(ArrowRain.ring_scale(83.2, 58.0), 2.5): r = "the yantra's scale at r83.2 is %.2f, want 2.5" % ArrowRain.ring_scale(83.2, 58.0)
	if r == "" and FxSprite.make_frames(ArrowRain.RING_FX) != rain._ring.sprite_frames: r = "the yantra does not use the shared FxSprite frames"
	world.free()
	_done(h)
	return r

## Game vs tools/gem_combo_sim.py (cast('rain', ...): one hit of 2.4 × skill level, × gems; pack: 5 monsters, 6 with
## the expand gem; lightning + 0.8 a hit), per press in ATK units with crit off (the sim multiplies both sides by the
## same crit factor). Equal for: no gem, multiply, expand, lightning. Different by rule, measured here so a change shows:
## - extend: the sim says × 1.3; the game deals whole ticks (owner D6: 3.9 s = 7 ticks) = × 7/6 (−10 %).
## - fire gem: the sim burns 60 % of the whole 240 %; the game burns 20 % of a TICK per second, not stacking, from the
##   first tick to 3 s after the last = 5 burn ticks = +16.7 % (plan Task 8b: burn = 0.2 × the tick's amount).
func test_rain_press_matches_sim():
	var lv := 10
	var lvl := 1.0 + 0.05 * (lv - 7)
	var cases := [      # name, gems, monsters in the circle, sim total, game / sim
		["no gem, single", [], 1, 2.4 * lvl, 1.0],
		["no gem, pack", [], 5, 2.4 * lvl * 5, 1.0],
		["multiply, pack", [_g("multiply")], 5, 2.4 * lvl * 1.35 * 5, 1.0],
		["expand, pack of 6", [_g("expand")], 6, 2.4 * lvl * 6, 1.0],
		["lightning, pack", [_g("element", "lightning")], 5, 2.4 * lvl * 1.1 * 5 * 1.8, 1.0],
		["extend, single", [_g("extend")], 1, 2.4 * lvl * 1.3, (7.0 / 6.0) / 1.3],
	]
	for c in cases:
		var h := _hero(lv)
		_sockets(h, c[1])
		var ds: Array = []
		for i in int(c[2]): ds.append(_dummy(Vector2(-50 + 20 * i, 0)))
		var rain := _rain(h, Vector2.ZERO, ds)
		_run(rain, 4.0)
		var total := 0.0
		for d in ds:
			for hit in d.hits: total += float(hit[1])
		_free_made()
		_done(h)
		if absf(total / float(c[3]) - float(c[4])) > 0.005: return "%s: game %.3f vs sim %.3f = × %.3f, want × %.3f" % [c[0], total, c[3], total / float(c[3]), c[4]]
	# the fire gem's burn on one monster: 5 burn ticks of 20 % of a tick
	var hf := _hero(lv)
	_sockets(hf, [_g("element", "fire")])
	var d := _dummy(Vector2(5, 0))
	d.deal = 1000
	d.hp = 100000000
	var rain := _rain(hf, Vector2.ZERO, [d])
	var burnt := 0
	for i in int(8.0 / DT):
		if is_instance_valid(rain) and not rain.done: rain.step(DT)
		burnt += d.tick_status(DT)
	var r := ""
	if d.hits.size() != 6: r = "fire: %d hits" % d.hits.size()
	elif burnt != 1000: r = "fire gem burn: %d for 6 ticks of 1000, want 1000 (5 burn ticks of 200; the sim's 60 %% would be 3600)" % burnt
	_free_made()
	_done(hf)
	return r

## In the game (TestGround, real monsters): a real press lays the rain in the world on the locked monster's feet and
## its ticks hurt real monsters; the warp's dark ends it at once, and the room change (go_to, also without a warp)
## leaves no rain behind and none in the hero's list (Review Focus 7, B20).
func test_rain_in_game_hits_and_goes_with_the_room():
	if FileAccess.file_exists(TMP): DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	var g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = TMP
	g.layout_seed = 1
	tree.root.add_child(g)
	await tree.process_frame
	await tree.process_frame
	g.go_to("c1r0", "", false)
	var h: Hero = g.hero
	h.set_physics_process(false)
	h.set_progress(7, 0)
	var wolves: Array = []
	for p in g.packs:
		p.process_mode = Node.PROCESS_MODE_DISABLED
		for w in p.wolves: wolves.append(w)
	var r := "" if not g.warps.is_empty() and not wolves.is_empty() else "setup: no warp / monster in c1r0"
	var rains := func() -> Array: return g.world.get_children().filter(func(c): return c is ArrowRain and not c.is_queued_for_deletion())
	if r == "":
		for x in wolves: x.health.setup(100000)
		h.global_position = wolves[0].global_position + Vector2(-100, 0)
		var w: Wolf = h.target_within(220.0)         # the monster the press locks on to (D2)
		var hp0: int = w.hp if w != null else 0
		if w == null: r = "setup: no monster within 220 px"
		if not h.try_skill(RAIN): r = "press refused"
		for i in 30: h.step(DT, Vector2.ZERO)
		var laid: Array = rains.call()
		if r == "" and (laid.size() != 1 or h.rains.size() != 1): r = "%d rains in the world, %d in the hero's list; want 1 / 1" % [laid.size(), h.rains.size()]
		if r == "":
			var rain: ArrowRain = laid[0]
			if rain.center.distance_to(w.global_position) > 0.5: r = "the rain is at %s, want the locked monster's feet %s" % [rain.center, w.global_position]
			for i in 40: await tree.physics_frame                 # past the first tick (0.5 s)
			if r == "" and (rain.ticks_done < 1 or w.hp >= hp0): r = "after %d tick(s) the monster under the rain has %d / %d HP" % [rain.ticks_done, w.hp, hp0]
			g.warp_through(g.warps[0])
			g._fade_tween.pause()
			if r == "" and not rain.done: r = "the rain still falls during the warp's dark"
			if r == "" and not h.rains.is_empty(): r = "the hero still lists the rain during the warp"
			g._fade_tween.custom_step(g.FADE_OUT + 0.01)
			await tree.process_frame
			if r == "" and not rains.call().is_empty(): r = "an old-room rain is left in %s" % g.room_id
	if r == "":
		# a room change with no warp before it (go_to): the same
		h.end_warp()
		h.mp = h.max_mp()
		h._skill_cd.clear()
		h.state = "idle"
		if not h.try_skill(RAIN): r = "second press refused"
		for i in 30: h.step(DT, Vector2.ZERO)
		if r == "" and rains.call().size() != 1: r = "no rain after the second press"
		g.go_to("c1r0", "", false)
		if r == "" and (not rains.call().is_empty() or not h.rains.is_empty()): r = "go_to left a rain (%d in the world, %d listed)" % [rains.call().size(), h.rains.size()]
	g.queue_free()
	await tree.process_frame
	if FileAccess.file_exists(TMP): DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	return r
