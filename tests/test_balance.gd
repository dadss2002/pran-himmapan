extends RefCounted
## Balance data tests: numbers must match docs/spec-numbers.md and the M2 design.

func test_hero_lv1():
	var h := Balance.hero(1)
	if h != {"hp": 120, "atk": 18, "def": 6}: return "hero lv1 %s" % h
	return ""

func test_wolf_levels():
	var w1 := Balance.wolf(1)
	var w5 := Balance.wolf(5)
	if w1 != {"hp": 40, "atk": 6, "def": 3, "exp": 13}: return "wolf lv1 %s" % w1
	if w5 != {"hp": 112, "atk": 14, "def": 7, "exp": 33}: return "wolf lv5 %s" % w5
	return ""

func test_dodge_switches_at_lv5():
	var d4 := Balance.dodge(4)
	var d5 := Balance.dodge(5)
	if d4.distance != 64.0 or d4.cooldown != 1.5 or d4.iframe != 0.2 or d4.duration != 0.25: return "lv4 %s" % d4
	if d5.distance != 96.0 or d5.iframe != 0.3 or d5.duration != 0.3 or d5.cooldown != 1.5: return "lv5 %s" % d5
	return ""

func test_missing_key_reports_path():
	if Balance.has("wolf.nope"): return "wolf.nope should not exist"
	if not Balance.has("wolf.run"): return "wolf.run should exist"
	return "" if Balance.num("wolf.run") == 140.0 else "wolf.run should be 140"

func test_packs_total_eleven():
	var n := 0
	for p in Balance.data()["packs"]: n += int(p["count"])
	return "" if n == 11 else "expected 11 wolves, got %d" % n
