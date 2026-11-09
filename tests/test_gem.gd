extends RefCounted
## Gem rules + SkillBuild (docs/gems.md, M3a design §5–§6).

const STATS := {"crit": 0.05, "skill_cd_cut": 0.0, "element_dmg": 0.0}

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r

func _gem(type: String, level := 1, opts: Array = [], element := "") -> Dictionary:
	var g := {"type": type, "level": level, "exp": 0, "rarity": "common", "opts": opts}
	if element != "": g["element"] = element
	return g

func test_gem_level_scaling():
	var r := ""
	for pair in [[1, 1.35], [3, 1.37], [20, 1.54]]:
		var v := Gem.effect(_gem("multiply", pair[0]))
		if absf(v - pair[1]) > 1e-6: r = "ทวีคูณ Lv%d = %.4f, want %.2f" % [pair[0], v, pair[1]]
	if r == "" and absf(Gem.effect(_gem("execute", 10)) - 0.195) > 1e-6: r = "พิฆาต Lv10 %.4f" % Gem.effect(_gem("execute", 10))
	return r

func test_gem_exp_curve():
	var r := ""
	for pair in [[1, 150], [5, 2314], [10, 7518]]:
		if Gem.exp_to_next(pair[0]) != pair[1]: r = "exp_to_next(%d) = %d, want %d" % [pair[0], Gem.exp_to_next(pair[0]), pair[1]]
	var g := _gem("split", 19)
	var ups := Gem.add_exp(g, 10_000_000)
	if r == "" and (g.level != 20 or ups != 1 or g.exp != 0): r = "cap: level %d ups %d exp %d" % [g.level, ups, g.exp]
	var g2 := _gem("split", 1)
	if r == "" and (Gem.add_exp(g2, 160) != 1 or g2.level != 2 or g2.exp != 10): r = "Lv1 +160 → Lv%d exp %d" % [g2.level, g2.exp]
	return r

func test_gem_options_fixed():
	var r := ""
	for lv in [1, 10, 20]:
		if absf(Gem.option(_gem("split", lv, [{"k": "cd_cut", "v": 0.06}]), "cd_cut") - 0.06) > 1e-6: r = "option changed at Lv%d" % lv
	var rng := _rng(5)
	for i in 200:
		var g := Gem.roll("split", rng, "legend")
		if g.opts.size() != 4: r = "legend gem has %d options" % g.opts.size()
		for o in g.opts:
			var d: Dictionary = Balance.data()["gem_options"][o.k]
			if o.v < float(d.min) - 1e-6 or o.v > float(d.max) + 1e-6: r = "%s %.4f outside %s–%s" % [o.k, o.v, d.min, d.max]
		if r != "": break
	return r

func test_roll_element_and_rarity():
	var rng := _rng(9)
	var seen := {}
	var r := ""
	for i in 300:
		var g := Gem.roll("element", rng)
		if not g.has("element"): return "element gem without an element"
		seen[g.element] = true
		if g.level != 1 or g.exp != 0: r = "new gem should be Lv1 EXP 0"
	if r == "" and seen.size() != 3: r = "elements seen %s" % [seen.keys()]
	if r == "" and Gem.roll("split", rng).has("element"): r = "split gem must not carry an element"
	return r

func test_fits_by_label():
	var r := ""
	for t in ["expand", "extend"]:
		if Gem.fits(t, "piercing") or Gem.fits(t, "spread"): r = "%s should fit no arrow skill" % t
	for t in ["multiply", "split", "element"]:
		if not (Gem.fits(t, "piercing") and Gem.fits(t, "spread")): r = "%s should fit both arrow skills" % t
	return r

## Owner 2026-11-08 (combos spec approval line): every skill has 2 slots from unlock, slot 3 at skill Lv10, slot 4
## at skill Lv50 (was 1/10/30/50).
func test_slots_by_level():
	var want := {0: 0, 1: 2, 9: 2, 10: 3, 49: 3, 50: 4}
	for lv in want:
		if Gem.slots_for(lv) != want[lv]: return "slots_for(%d) = %d, want %d" % [lv, Gem.slots_for(lv), want[lv]]
	return ""

## Owner 2026-11-09: socketed gems stay where they are. The rule change only opens slots, so no gem a player put in
## under the old rule [1, 10, 30, 50] is ever in a slot that is now closed.
func test_new_slot_rule_never_closes_a_slot():
	var old := [1, 10, 30, 50]
	for lv in range(0, 61):
		var n_old := 0
		for t in old: if lv >= t: n_old += 1
		if Gem.slots_for(lv) < n_old: return "skill Lv%d: %d < old %d" % [lv, Gem.slots_for(lv), n_old]
	return ""

func test_plain_gem():
	if not Gem.is_plain(_gem("split")): return "Lv1 common no-option gem should be plain"
	if Gem.is_plain(_gem("split", 2)): return "Lv2 gem is not plain"
	if Gem.is_plain(_gem("element", 1, [], "fire")): return "element gem is not plain"
	if Gem.is_plain(_gem("split", 1, [{"k": "crit", "v": 0.03}])): return "gem with options is not plain"
	return ""

func test_build_split_piercing():
	var b := SkillBuild.of("piercing", 1, [_gem("split")], STATS)
	var r := ""
	if b.arrows != 3 or absf(b.fan_deg - 24.0) > 1e-6: r = "arrows %d fan %.1f, want 3 / 24" % [b.arrows, b.fan_deg]
	elif absf(b.arrow_mult - 1.8 * 0.6) > 1e-6: r = "arrow mult %.4f, want 1.08" % b.arrow_mult
	elif absf(b.mp - 11.2) > 1e-6: r = "MP %.3f, want 11.2" % b.mp
	elif not b.pierce_all: r = "piercing must still pierce all"
	return r

func test_build_split_spread():
	var b := SkillBuild.of("spread", 3, [_gem("split")], STATS)
	var r := ""
	if b.arrows != 7 or absf(b.fan_deg - 63.0) > 1e-6: r = "arrows %d fan %.1f, want 7 / 63" % [b.arrows, b.fan_deg]
	elif absf(b.arrow_mult - 0.7 * 0.6) > 1e-6: r = "arrow mult %.4f, want 0.42" % b.arrow_mult
	elif absf(b.mp - 16.8) > 1e-6: r = "MP %.3f, want 16.8" % b.mp
	return r

func test_build_example_from_gems_md():
	var b := SkillBuild.of("piercing", 10, [_gem("split"), _gem("multiply")], STATS)
	var lv_mult := Skills.damage_mult("piercing", 10)
	var r := ""
	if absf(b.arrow_mult - lv_mult * 0.81) > 1e-6: r = "arrow mult %.4f, want %.4f (81%% each)" % [b.arrow_mult, lv_mult * 0.81]
	elif absf(b.mp - 16.8) > 1e-6: r = "MP %.3f, want 8 × 1.4 × 1.5 = 16.8" % b.mp
	return r

func test_build_options_and_cooldown_cap():
	var opts := [{"k": "cd_cut", "v": 0.08}, {"k": "mp_cut", "v": 0.10}, {"k": "dmg_pct", "v": 0.05}]
	var stats := {"crit": 0.05, "skill_cd_cut": 0.25, "element_dmg": 0.0}
	var b := SkillBuild.of("piercing", 10, [_gem("multiply", 1, opts)], stats)
	var r := ""
	if absf(b.cooldown - 4.0 * 0.7) > 1e-6: r = "cooldown %.3f, total cut must cap at 30%%" % b.cooldown
	elif absf(b.mp - 8 * 1.5 * 0.9) > 1e-6: r = "MP %.3f, want 10.8" % b.mp
	elif absf(b.arrow_mult - Skills.damage_mult("piercing", 10) * 1.35 * 1.05) > 1e-6: r = "damage %.4f" % b.arrow_mult
	return r

func test_build_crit_ricochet_pierce_homing_leech_element():
	var gems := [_gem("execute", 1, [{"k": "crit", "v": 0.03}]), _gem("ricochet", 10)]
	var b := SkillBuild.of("piercing", 10, gems, STATS)
	var r := ""
	if absf(b.crit - (0.05 + Gem.effect(gems[0]) + 0.03)) > 1e-6: r = "crit %.4f" % b.crit
	elif b.bounces != 2 or absf(b.bounce_mult - 0.89) > 1e-6: r = "ricochet Lv10: bounces %d mult %.3f, want 2 / 0.89" % [b.bounces, b.bounce_mult]
	var b2 := SkillBuild.of("spread", 10, [_gem("pierce", 10), _gem("homing")], STATS)
	if r == "" and (b2.pierce_extra != 3 or not b2.homing): r = "pierce Lv10 extra %d homing %s" % [b2.pierce_extra, b2.homing]
	elif r == "" and absf(b2.arrow_mult - Skills.damage_mult("spread", 10) * 0.9) > 1e-6: r = "homing should be 90%% damage"
	var b3 := SkillBuild.of("piercing", 1, [_gem("element", 1, [], "ice")], {"crit": 0.05, "skill_cd_cut": 0.0, "element_dmg": 0.05})
	if r == "" and (b3.element != "ice" or absf(b3.arrow_mult - 1.8 * 1.15) > 1e-6): r = "element %s mult %.4f, want ice / 1.8 × (1.1 + 0.05)" % [b3.element, b3.arrow_mult]
	var b4 := SkillBuild.of("piercing", 1, [_gem("leech", 11)], STATS)
	if r == "" and absf(b4.leech - 0.04) > 1e-6: r = "leech Lv11 %.4f, want 0.04" % b4.leech
	return r

func test_build_ignores_gems_that_do_not_fit():
	var b := SkillBuild.of("piercing", 1, [_gem("expand"), null], STATS)
	return "" if absf(b.mp - 8.0) < 1e-6 and b.arrows == 1 else "unfit/empty gems changed the build: %s" % b

func test_plain_element_text():
	var t := Gem.describe_effect({"type": "element", "level": 1, "exp": 0, "rarity": "common", "opts": []})
	return "" if t.contains("สุ่ม") else "plain element gem text '%s' should say the element is rolled" % t
