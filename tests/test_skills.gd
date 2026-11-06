extends RefCounted
## ศรทะลวง / ศรกระจาย / potions (skills.md §1, gems.md §2, spec-numbers §10).

const DT := 1.0 / 60.0
var _shots: Array = []

func _hero(level := 1) -> Hero:
	var h: Hero = load("res://scenes/hero.tscn").instantiate()
	h.setup_sprites()
	if level > 1: h.set_progress(level, 0)
	_shots = []
	h.shot.connect(func(a): _shots.append(a))
	return h

func _run(h: Hero, s: float) -> void:
	for i in int(round(s / DT)): h.step(DT, Vector2.ZERO)

func _dummy(pos: Vector2) -> Node2D:
	var d: Node2D = load("res://tests/dummy_enemy.gd").new()
	d.position = pos
	return d

func _done(h: Hero, extra: Array = []) -> void:
	for a in _shots: if is_instance_valid(a): a.free()
	for e in extra: if is_instance_valid(e): e.free()
	h.free()

func test_piercing_arrow_hits_every_enemy_in_line():
	var ds := [_dummy(Vector2(60, 14)), _dummy(Vector2(120, 14)), _dummy(Vector2(180, 14))]
	var a: Arrow = load("res://scenes/arrow.tscn").instantiate()
	a.launch(Vector2.RIGHT, 18.0, ds, 1.8, true)
	for i in 60: a.advance(DT)
	var r := ""
	for d in ds:
		if d.hits.size() != 1: r = "enemy at %s hit %d times" % [d.position, d.hits.size()]
		elif absf(d.hits[0][1] - 1.8) > 0.001: r = "mult %s, want 1.8" % d.hits[0][1]
	a.free()
	for d in ds: d.free()
	return r

func test_piercing_skill_fires_one_piercing_arrow():
	var h := _hero()
	var r := ""
	if not h.try_skill("piercing"): r = "piercing refused at Lv1"
	_run(h, 1.0)
	if r == "" and _shots.size() != 1: r = "%d arrows, want 1" % _shots.size()
	elif r == "" and (not _shots[0].pierce or absf(_shots[0].mult - 1.8) > 0.001): r = "pierce %s mult %s" % [_shots[0].pierce, _shots[0].mult]
	if r == "" and absf(h.mp - (50 - 8 + 6 * 1.0)) > 0.2: r = "mp %.1f, want 48 (50 - 8 + 6/s regen)" % h.mp
	_done(h)
	return r

func test_spread_five_arrows_45deg():
	var h := _hero(3)
	h.facing = 2   # east, no enemies: fan centred on east
	var r := ""
	if not h.try_skill("spread"): r = "spread refused at Lv3"
	_run(h, 1.0)
	if r == "" and _shots.size() != 5: r = "%d arrows, want 5" % _shots.size()
	if r == "":
		var angles := []
		for a in _shots: angles.append(snappedf(rad_to_deg(a.dir.angle()), 0.01))
		angles.sort()
		if angles != [-22.5, -11.25, 0.0, 11.25, 22.5]: r = "fan angles %s" % [angles]
		for a in _shots:
			if absf(a.mult - 0.7) > 0.001: r = "spread arrow mult %s" % a.mult
	_done(h)
	return r

func test_spread_locked_before_lv3():
	var h := _hero(2)
	var r := "" if not h.try_skill("spread") else "spread must be locked below Lv3"
	_done(h)
	return r

func test_skill_scaling():
	var m := Skills.damage_mult("piercing", 5)
	var c := Skills.cooldown("piercing", 5)
	var c_cap := Skills.cooldown("piercing", 99)
	if absf(m - 2.16) > 0.0001: return "mult at L5 %.4f, want 2.16" % m
	if absf(c - 3.84) > 0.0001: return "cooldown at L5 %.3f, want 3.84" % c
	return "" if absf(c_cap - 2.8) < 0.0001 else "cooldown cut should stop at -30%% (2.8 s), got %.3f" % c_cap

func test_skill_refused_keeps_mp():
	var h := _hero()
	var r := ""
	h.mp = 7.0
	if h.try_skill("piercing") or h.mp != 7.0: r = "low MP: fired or spent (mp %.1f)" % h.mp
	h.mp = 50.0
	if r == "" and not h.try_skill("piercing"): r = "should fire with 50 MP"
	_run(h, 1.0)
	var mp := h.mp
	if r == "" and (h.try_skill("piercing") or h.mp != mp): r = "on cooldown: fired or spent"
	_run(h, 4.0)
	h.try_dodge(Vector2.RIGHT)
	mp = h.mp
	if r == "" and (h.try_skill("piercing") or h.mp != mp): r = "while rolling: fired or spent"
	_run(h, 1.0)
	h.receive_hit(9999, 1.0, Vector2.ZERO)
	mp = h.mp
	if r == "" and (h.try_skill("piercing") or h.mp != mp): r = "while dead: fired or spent"
	_done(h)
	return r

func test_potion_shared_cooldown():
	var h := _hero()
	h.health.take_hit(100, false)        # 20 / 120
	h.mp = 10.0
	var r := ""
	if not h.try_potion("hp"): r = "hp potion refused"
	elif h.health.hp != 68: r = "hp %d after potion, want 68 (+40%% of 120)" % h.health.hp
	elif h.inventory.count_of("potion_hp") != 4: r = "hp potions left %d" % h.inventory.count_of("potion_hp")
	if r == "" and h.try_potion("mp"): r = "mp potion inside the shared 10 s cooldown"
	_run(h, 10.05)
	if r == "" and not h.try_potion("mp"): r = "mp potion after 10 s refused"
	h.inventory.remove("potion_hp", 4)
	_run(h, 10.05)
	if r == "" and h.try_potion("hp"): r = "no potions left but still drank"
	_done(h)
	return r
