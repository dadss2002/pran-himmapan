extends RefCounted
## Hero EXP / level-up / MP / death penalty.

var _ups: Array = []

func _hero() -> Hero:
	var h: Hero = load("res://scenes/hero.tscn").instantiate()
	h.setup_sprites()
	_ups = []
	h.leveled_up.connect(func(l): _ups.append(l))
	return h

func test_kill_gives_exp():
	var h := _hero()
	h.on_kill(13, 1)
	var r := "" if h.exp == 13 and h.level == 1 else "exp %d level %d" % [h.exp, h.level]
	h.free()
	return r

func test_level_up_heals_and_raises_stats():
	var h := _hero()
	h.health.take_hit(70, false)
	h.mp = 3.0
	h.gain_exp(47)
	var r := ""
	if h.level != 2 or h.exp != 0: r = "level %d exp %d" % [h.level, h.exp]
	elif h.health.max_hp != 132 or h.health.hp != 132: r = "hp %d/%d, want 132/132" % [h.health.hp, h.health.max_hp]
	elif int(h.mp) != 55 or h.max_mp() != 55: r = "mp %.1f/%d" % [h.mp, h.max_mp()]
	elif _ups != [2]: r = "leveled_up signals %s" % [_ups]
	h.free()
	return r

func test_multi_level_emits_each():
	var h := _hero()
	h.gain_exp(1000)
	var r := "" if _ups == [2, 3, 4] and h.level == 4 and h.exp == 425 else "ups %s level %d exp %d" % [_ups, h.level, h.exp]
	h.free()
	return r

func test_mp_regen_6_per_s():
	var h := _hero()
	h.mp = 10.0
	for i in 60: h.step(1.0 / 60.0, Vector2.ZERO)
	var r := "" if absf(h.mp - 16.0) < 0.05 else "mp %.2f after 1 s, want 16" % h.mp
	for i in 600: h.step(1.0 / 60.0, Vector2.ZERO)
	if r == "" and h.mp > h.max_mp(): r = "mp above max"
	h.free()
	return r

func test_death_costs_5_percent():
	var h := _hero()
	h.gain_exp(47 + 168 + 100)   # level 3 with 100 EXP
	var r := ""
	if h.level != 3 or h.exp != 100: r = "setup: level %d exp %d" % [h.level, h.exp]
	h.receive_hit(9999, 1.0, Vector2.ZERO)
	if r == "" and (h.exp != 82 or h.level != 3): r = "after death level %d exp %d, want 3 / 82" % [h.level, h.exp]
	h.free()
	return r

func test_hud_shows_exp_mp_gold():
	var h := _hero()
	var hud := Hud.new()
	hud.build()
	hud.bind(h)
	h.gain_exp(20)
	h.mp = 31.0
	h.inventory.add("gold", 57)
	hud.refresh()
	var r := ""
	if hud.mp_label.text != "MP 31 / 50": r = "mp label '%s'" % hud.mp_label.text
	elif absf(hud.exp_bar.value - 100.0 * 20 / 47) > 0.5: r = "exp bar %.1f" % hud.exp_bar.value
	elif hud.gold_label.text != "57": r = "gold label '%s'" % hud.gold_label.text
	h.gain_exp(100000)
	hud.refresh()
	if r == "" and (hud.exp_bar.value != 100.0 or hud.level_label.text != "Lv 10"): r = "at cap: bar %.1f label %s" % [hud.exp_bar.value, hud.level_label.text]
	hud.free(); h.free()
	return r

func test_no_exp_while_dead():
	var h := _hero()
	h.receive_hit(9999, 1.0, Vector2.ZERO)
	h.on_kill(50, 1)
	var r := "" if h.exp == 0 else "dead hero gained %d EXP" % h.exp
	h.free()
	return r
