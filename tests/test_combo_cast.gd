extends RefCounted
## M5b Task 3: ComboCast, the per-press ledger (docs/superpowers/specs/2026-11-08-gem-combos.md, owner 2026-11-08:
## sustain combos refund MP on kill, at most 6 / 9 MP per press; owner 2026-11-09: burn / trail kills count too,
## through the ComboCast of the press that applied them, still under the same cap).

func test_bloodthirst_refund_caps_at_6():
	var c := ComboCast.new("bloodthirst")
	var got: Array = []
	for i in 4: got.append(c.refund_mp(2))
	return "" if got == [2, 2, 2, 0] else "got %s" % [got]

func test_rahu_refund_caps_at_9():
	var c := ComboCast.new("rahu")
	var got: Array = []
	for i in 4: got.append(c.refund_mp(3))
	return "" if got == [3, 3, 3, 0] else "got %s" % [got]

## A partial grant at the cap, and nonsense amounts give nothing.
func test_refund_partial_and_junk():
	var c := ComboCast.new("bloodthirst")
	var got := [c.refund_mp(5), c.refund_mp(5), c.refund_mp(5), c.refund_mp(-3), c.refund_mp(0)]
	if got != [5, 1, 0, 0, 0]: return "got %s, want [5, 1, 0, 0, 0]" % [got]
	return "" if c.mp_refunded() == 6 else "mp_refunded %d" % c.mp_refunded()

func test_no_combo_no_refund():
	if ComboCast.new("").refund_mp(2) != 0: return "no combo refunded"
	if ComboCast.new("fire_fan").refund_mp(2) != 0: return "fire_fan has no MP on kill"
	if ComboCast.new("nope").refund_mp(2) != 0: return "unknown id refunded"
	return ""

## The per-kill numbers are read from data once, at the press (no per-hit lookups later).
func test_numbers_copied_at_press():
	var c := ComboCast.new("rahu", 0.9)
	if c.kill_mp != 3 or c.kill_mp_cap != 9: return "rahu kill_mp %d cap %d" % [c.kill_mp, c.kill_mp_cap]
	if not is_equal_approx(c.crit_heal_frac, 0.01): return "rahu crit_heal_frac %s" % c.crit_heal_frac
	var b := ComboCast.new("bloodthirst")
	if b.kill_mp != 2 or b.kill_mp_cap != 6 or not is_equal_approx(b.kill_heal_frac, 0.03): return "bloodthirst %d %d %s" % [b.kill_mp, b.kill_mp_cap, b.kill_heal_frac]
	var row := GemCombo.recipe("bloodthirst")
	var old = row.kill_mp_cap
	row.kill_mp_cap = 99          # data changing after the press does not change this press's cap
	var r := "" if b.kill_mp_cap == 6 else "the ledger re-read data after the press"
	row.kill_mp_cap = old
	return r

func test_once_per_target():
	var c := ComboCast.new("anodard")
	var got := [c.once("shatter", 7), c.once("shatter", 7), c.once("shatter", 8), c.once("freeze", 7), c.once("freeze", 7)]
	return "" if got == [true, false, true, true, false] else "got %s" % [got]

func test_count_hit():
	var c := ComboCast.new("frost_shard")
	var got := [c.count_hit(5), c.count_hit(5), c.count_hit(5), c.count_hit(6)]
	return "" if got == [1, 2, 3, 1] else "got %s" % [got]

## Two presses never share a ledger: a second press gets its own cap, counts and once-tags.
func test_presses_are_separate():
	var a := ComboCast.new("bloodthirst")
	for i in 3: a.refund_mp(2)
	a.once("kill", 1)
	a.count_hit(1)
	var b := ComboCast.new("bloodthirst")
	if b.refund_mp(2) != 2 or not b.once("kill", 1) or b.count_hit(1) != 1: return "a new press inherited the old ledger"
	return "" if a.refund_mp(2) == 0 else "the old press's cap reopened"

func test_rahu_hp_threshold():
	if not is_equal_approx(ComboCast.new("rahu", 0.70).dmg_bonus(), 0.30): return "rahu at 70%% HP: %s" % ComboCast.new("rahu", 0.70).dmg_bonus()
	if not is_equal_approx(ComboCast.new("rahu", 1.0).dmg_bonus(), 0.30): return "rahu at full HP"
	if ComboCast.new("rahu", 0.69).dmg_bonus() != 0.0: return "rahu below 70%% HP: %s" % ComboCast.new("rahu", 0.69).dmg_bonus()
	if ComboCast.new("garuda", 1.0).dmg_bonus() != 0.0: return "garuda has no HP bonus"
	if ComboCast.new("", 1.0).dmg_bonus() != 0.0: return "no combo has no HP bonus"
	return ""

## Risk guard: a sustain press can never refund more MP than it costs, even with every gem rolled at the best
## MP-cut option and a 4th gem in slot 4 (lowest-MP fourth gem). Covers every skill with numbers.
func test_refund_cap_below_press_cost():
	var best_cut := float(Balance.data()["gem_options"]["mp_cut"]["max"])
	var cheapest := 99.0
	for t in Gem.types(): cheapest = minf(cheapest, Gem.mp_mult(t))
	for skill in Balance.data()["skills"]:
		if typeof(Balance.data()["skills"][skill]) != TYPE_DICTIONARY or not Skills.exists(skill): continue
		for id in ["bloodthirst", "rahu"]:
			var keys: Array = GemCombo.recipe(id).gems
			var fits := true
			for k in keys: if not Gem.fits(GemCombo.key_type(String(k)), skill): fits = false
			if not fits: continue
			var gems: Array = []
			for k in keys: gems.append({"type": k, "level": 20, "exp": 0, "rarity": "legend", "opts": [{"k": "mp_cut", "v": best_cut}]})
			var b := SkillBuild.of(skill, 60, gems, {"crit": 0.05, "element_dmg": 0.0, "skill_cd_cut": 0.0})
			if String(b.combo.get("id", "")) != id: return "%s did not form on %s" % [id, skill]
			# a 4th gem with the best MP cut: cost ≥ this press × cheapest mult × (1 − cut) / (1 − 0)
			var worst := float(b.mp) / (1.0 - best_cut * keys.size()) * cheapest * (1.0 - best_cut * (keys.size() + 1))
			var cap := int(GemCombo.p(id, "kill_mp_cap"))
			if float(b.mp) <= cap or worst <= cap: return "%s on %s costs %s MP (4 gems: %s) but can refund %d" % [id, skill, b.mp, worst, cap]
	return ""

## Task 3 review M4: refund_kill() grants this press's own kill_mp (copied at the press), under the same cap.
func test_refund_kill_uses_stored_kill_mp():
	var b := ComboCast.new("bloodthirst")
	var r := ComboCast.new("rahu")
	var got := [[], []]
	for i in 4:
		got[0].append(b.refund_kill())
		got[1].append(r.refund_kill())
	if got != [[2, 2, 2, 0], [3, 3, 3, 0]]: return "refund_kill got %s, want [[2,2,2,0],[3,3,3,0]]" % [got]
	if ComboCast.new("").refund_kill() != 0 or ComboCast.new("garuda").refund_kill() != 0: return "a combo with no MP on kill refunded"
	var mixed := ComboCast.new("bloodthirst")         # refund_mp (kept for callers) and refund_kill share one cap
	return "" if [mixed.refund_mp(5), mixed.refund_kill(), mixed.refund_kill()] == [5, 1, 0] else "refund_mp and refund_kill do not share the cap"

## Task 3 review M5: a press's ledger is built from the build's combo_p (one source for the press's numbers), so a
## hit and the ledger can never disagree; a build with no combo gives an empty ledger.
func test_from_build_reads_combo_p():
	var stats := {"crit": 0.05, "element_dmg": 0.0, "skill_cd_cut": 0.0}
	var gems := [{"type": "leech", "level": 1, "exp": 0}, {"type": "multiply", "level": 1, "exp": 0}, {"type": "execute", "level": 1, "exp": 0}]
	var b := SkillBuild.of("piercing", 10, gems, stats)
	b.combo_p.kill_mp_cap = 4.0                       # the build's copy is the source, not balance.json
	var c := ComboCast.from_build(b, 0.8)
	if c.id != "rahu": return "from_build id %s" % c.id
	if c.kill_mp != 3 or c.kill_mp_cap != 4: return "from_build kill_mp %d cap %d (want 3 / the build's 4)" % [c.kill_mp, c.kill_mp_cap]
	if not is_equal_approx(c.dmg_bonus(), 0.30): return "from_build HP bonus %s at 80 %% HP" % c.dmg_bonus()
	if not is_equal_approx(ComboCast.from_build(b, 0.5).dmg_bonus(), 0.0): return "from_build HP bonus below 70 %"
	if [c.refund_kill(), c.refund_kill()] != [3, 1]: return "from_build cap not the build's"
	var none := ComboCast.from_build(SkillBuild.of("piercing", 10, [], stats), 1.0)
	if none.id != "" or none.refund_kill() != 0 or none.dmg_bonus() != 0.0: return "no-combo build gave a ledger with effects"
	var junk := ComboCast.from_build({}, 1.0)
	return "" if junk.id == "" and junk.refund_kill() == 0 else "a junk build gave a ledger with effects"

## Task 3 review M3: once() keys by tag then target id (no "tag:id" string built per call).
func test_once_keys_by_tag_then_target():
	var c := ComboCast.new("anodard")
	c.once("shatter", 7)
	c.once("shatter", 8)
	c.once("freeze", 7)
	if c._once.size() != 2 or not (c._once.get("shatter", {}) as Dictionary).has(7) or not (c._once.get("freeze", {}) as Dictionary).has(7): return "once table %s" % [c._once]
	var src := FileAccess.get_file_as_string("res://scripts/rules/combo_cast.gd")
	var body := src.substr(src.find("func once("))
	body = body.substr(0, body.find("\nfunc ", 1)) if body.find("\nfunc ", 1) > 0 else body
	return "" if not ("%" in body or "str(" in body or "String(" in body) else "once() still builds a string per call"
