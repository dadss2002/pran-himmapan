extends RefCounted
## EXP curve, kill EXP, level-ups, death penalty, loot rolls (spec-numbers §3, §5; gems.md §6).

func test_exp_curve():
	var got := [Progression.exp_to_next(1), Progression.exp_to_next(2), Progression.exp_to_next(9)]
	return "" if got == [47, 168, 3201] else "curve %s" % [got]

func test_kill_exp_low_level_penalty():
	var a := Progression.kill_exp(13, 1, 7)
	var b := Progression.kill_exp(13, 1, 6)
	return "" if a == 4 and b == 13 else "penalty: vs lv7 %d (want 4), vs lv6 %d (want 13)" % [a, b]

func test_multi_level_and_cap():
	var r := Progression.add_exp(1, 0, 1000)
	if r != {"level": 4, "exp": 425, "levels_gained": 3}: return "1000 at L1 -> %s" % r
	r = Progression.add_exp(9, 3000, 5000)
	if r.level != 10 or r.exp != 0 or r.levels_gained != 1: return "L9+5000 -> %s" % r
	r = Progression.add_exp(10, 0, 50)
	if r.level != 10 or r.exp != 0 or r.levels_gained != 0: return "cap -> %s" % r
	return ""

func test_death_penalty_never_negative():
	var got := [Progression.after_death(3, 0), Progression.after_death(3, 100), Progression.after_death(3, 10)]
	return "" if got == [0, 82, 0] else "after death %s, want [0, 82, 0]" % [got]

func test_mp_by_level():
	return "" if Balance.mp(1) == 50 and Balance.mp(10) == 95 else "mp %d / %d" % [Balance.mp(1), Balance.mp(10)]

func test_loot_rates_seeded():
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var n := 10000
	var ore := 0
	var gem := 0
	for i in n:
		var drops := Loot.roll("wolf", 1, rng)
		var gold := 0
		for d in drops:
			if d.id == "gold": gold = d.count
			elif d.id == "ore_himmapan": ore += 1
			elif String(d.id).begins_with("gem_"):
				gem += 1
				if not Balance.data()["gems"].has(String(d.id).trim_prefix("gem_")): return "unknown gem %s" % d.id
		if gold < 4 or gold > 7: return "gold %d outside 4..7 at lv1" % gold
	var ore_p := float(ore) / n
	var gem_p := float(gem) / n
	if ore_p < 0.23 or ore_p > 0.27: return "ore rate %.3f" % ore_p
	if gem_p < 0.007 or gem_p > 0.013: return "gem rate %.4f" % gem_p
	return ""
