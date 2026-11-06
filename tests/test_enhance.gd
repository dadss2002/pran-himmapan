extends RefCounted
## Enhancement +1…+10 (spec-numbers §7, M3a design §7).

func _item(base: String, plus := 0) -> Dictionary:
	return {"base": base, "rarity": "common", "level": Gear.req_level(base), "opts": [], "plus": plus}

func _inv(ore: int, gold: int) -> Inventory:
	var inv := Inventory.new()
	inv.slots.clear()
	inv.add("ore_himmapan", ore)
	inv.gold = gold
	return inv

func test_tables():
	var chance := [1.0, 0.95, 0.90, 0.85, 0.75, 0.60, 0.50, 0.40, 0.32, 0.25]
	for t in range(1, 11):
		if absf(Enhance.chance(t) - chance[t - 1]) > 1e-6: return "chance +%d = %.2f" % [t, Enhance.chance(t)]
		if Enhance.ore(t) != t: return "ore +%d = %d" % [t, Enhance.ore(t)]
		if Enhance.gold(t) != 100 * t * t: return "gold +%d = %d" % [t, Enhance.gold(t)]
	return ""

func test_bonus_curve():
	var want := {0: 0.0, 1: 0.06, 5: 0.30, 6: 0.36, 7: 0.46, 10: 0.76}
	for p in want:
		if absf(Enhance.bonus(p) - want[p]) > 1e-6: return "bonus(+%d) = %.3f, want %.2f" % [p, Enhance.bonus(p), want[p]]
	return ""

func test_fail_rules():
	var rng := RandomNumberGenerator.new()
	var a := _item("bow_buffalo_horn", 5)
	var inv := _inv(20, 100000)
	var res := Enhance.attempt(a, inv, rng, 0.99)      # 0.99 always fails from +2 up
	var r := ""
	if res.result != "fail" or a.plus != 5: r = "+5 → +6 fail: %s plus %d (should stay +5)" % [res.result, a.plus]
	elif inv.count_of("ore_himmapan") != 14 or inv.gold != 100000 - 3600: r = "costs not taken: ore %d gold %d" % [inv.count_of("ore_himmapan"), inv.gold]
	var b := _item("bow_buffalo_horn", 6)
	res = Enhance.attempt(b, inv, rng, 0.99)
	if r == "" and (res.result != "down" or b.plus != 5): r = "+6 → +7 fail: %s plus %d (should drop to +5)" % [res.result, b.plus]
	res = Enhance.attempt(b, inv, rng, 0.0)
	if r == "" and (res.result != "ok" or b.plus != 6): r = "success: %s plus %d" % [res.result, b.plus]
	return r

func test_not_enough_takes_nothing():
	var a := _item("bow_bamboo", 2)
	var inv := _inv(10, 500)               # +3 needs 900 gold
	var res := Enhance.attempt(a, inv, RandomNumberGenerator.new())
	var r := ""
	if res.result != "no_gold" or inv.gold != 500 or inv.count_of("ore_himmapan") != 10 or a.plus != 2: r = "no gold: %s" % [res]
	var inv2 := _inv(2, 5000)              # +3 needs 3 ore
	res = Enhance.attempt(a, inv2, RandomNumberGenerator.new())
	if r == "" and (res.result != "no_ore" or inv2.gold != 5000): r = "no ore: %s" % [res]
	var m := _item("bow_bamboo", 10)
	if r == "" and Enhance.attempt(m, _inv(99, 99999), RandomNumberGenerator.new()).result != "max": r = "+10 should be max"
	return r

func test_ring_cannot():
	var ring := {"base": "ring", "rarity": "rare", "level": 3, "opts": []}
	if Enhance.can(ring): return "ring should not be enhanceable"
	if not Enhance.can(_item("armor_trainee")): return "armor should be enhanceable"
	return "" if Enhance.attempt(ring, _inv(9, 9999), RandomNumberGenerator.new()).result == "cannot" else "ring attempt not refused"

func test_totals_with_plus():
	var eq := {"bow": _item("bow_buffalo_horn", 6), "armor": _item("armor_trainee", 1), "ring": null, "necklace": null}
	var t := Gear.totals(eq)
	var r := ""
	if absf(float(t.atk) - 21.76) > 1e-4: r = "horn bow +6 ATK %.3f, want 21.76" % float(t.atk)
	elif absf(float(t.def) - 4.24) > 1e-4: r = "trainee armor +1 DEF %.3f, want 4.24" % float(t.def)
	elif int(t.hp) != 21: r = "trainee armor +1 HP %s, want 21" % t.hp
	return r

func test_name_with_plus():
	if Gear.item_name(_item("bow_buffalo_horn", 6)) != "ธนูเขาควาย +6": return Gear.item_name(_item("bow_buffalo_horn", 6))
	if Gear.item_name(_item("ring")) != "แหวน": return "no plus should show no suffix"
	return ""
