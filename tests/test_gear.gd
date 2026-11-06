extends RefCounted
## Gear rules: rarity, random options, stat totals (spec-numbers §5–§6, M2 design §5.6).

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r

func test_rarity_rates_seeded():
	var rng := _rng(7)
	var n := 100000
	var c := {}
	for i in n:
		var k := Gear.roll_rarity(rng)
		c[k] = c.get(k, 0) + 1
	var want := {"common": 60.0, "good": 28.0, "rare": 9.0, "epic": 2.7, "legend": 0.3}
	for k in want:
		var got: float = 100.0 * c.get(k, 0) / n
		if absf(got - want[k]) > 0.5: return "%s %.2f%%, want %.1f%%" % [k, got, want[k]]
	return ""

func test_option_count_by_rarity():
	var rng := _rng(3)
	var want := {"common": 0, "good": 1, "rare": 2, "epic": 3, "legend": 4}
	for r in want:
		for i in 50:
			var it := Gear.roll_item("ring", 10, rng, r)
			if it.opts.size() != want[r]: return "%s has %d options" % [r, it.opts.size()]
			var keys := {}
			for o in it.opts:
				if keys.has(o.k): return "%s repeats option %s" % [r, o.k]
				keys[o.k] = true
	return ""

func test_option_range_scaling():
	var r10 := Gear.option_range("crit", 10)
	var r5 := Gear.option_range("crit", 5)
	var r1 := Gear.option_range("crit", 1)
	if not (r10.is_equal_approx(Vector2(0.02, 0.05))): return "Lv10 %s" % r10
	if not (r5.is_equal_approx(Vector2(0.01, 0.025))): return "Lv5 %s" % r5
	if not (r1.is_equal_approx(Vector2(0.006, 0.015))): return "Lv1 %s (30%% floor)" % r1
	return ""

func test_rolled_values_inside_range_and_rounded():
	var rng := _rng(11)
	for i in 300:
		var it := Gear.roll_item("necklace", 1 + i % 10, rng, "legend")
		for o in it.opts:
			var rg := Gear.option_range(o.k, it.level)
			if o.v < rg.x - 0.0011 or o.v > rg.y + 0.0011: return "%s %.4f outside %s at Lv%d" % [o.k, o.v, rg, it.level]
			if o.k in ["hp", "def", "mp"] and o.v != round(o.v): return "%s %.3f not whole" % [o.k, o.v]
	return ""

func test_item_level_and_req():
	var rng := _rng(1)
	var bow := Gear.roll_item("bow_buffalo_horn", 2, rng)
	var ring := Gear.roll_item("ring", 3, rng)
	if bow.level != 5 or Gear.req_level("bow_buffalo_horn") != 5: return "horn bow level %d" % bow.level
	if ring.level != 3 or Gear.req_level("ring") != 1: return "ring level %d req %d" % [ring.level, Gear.req_level("ring")]
	if Gear.slot_of("armor_wolf_leather") != "armor" or Gear.slot_of("necklace") != "necklace": return "slots"
	return ""

func test_totals_sum_main_and_options():
	var eq := {
		"bow": {"base": "bow_bamboo", "rarity": "common", "level": 1, "opts": []},
		"armor": {"base": "armor_trainee", "rarity": "good", "level": 1, "opts": [{"k": "hp", "v": 12}]},
		"ring": {"base": "ring", "rarity": "rare", "level": 4, "opts": [{"k": "crit", "v": 0.012}, {"k": "def", "v": 2}]},
		"necklace": null,
	}
	var t := Gear.totals(eq)
	if t.atk != 8 or t.def != 6 or t.hp != 32: return "main %s" % t
	if absf(t.crit - 0.012) > 1e-6 or t.atk_pct != 0.0: return "options %s" % t
	return ""
