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
	# MP is taken when the arrow leaves (5/14 s); before that the bar is already full.
	if r == "" and absf(h.mp - (50 - 8 + 6 * (1.0 - 5.0 / 14.0))) > 0.2: r = "mp %.1f, want 45.9 (50 - 8 at release + 6/s regen)" % h.mp
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
	h.mp = 10.0                          # regen filled it during the wait
	if r == "" and not h.try_potion("mp"): r = "mp potion after 10 s refused"
	h.inventory.remove("potion_hp", 4)
	_run(h, 10.05)
	if r == "" and h.try_potion("hp"): r = "no potions left but still drank"
	_done(h)
	return r

func test_cancelled_skill_costs_nothing():
	var h := _hero()
	var r := ""
	h.try_skill("piercing")
	_run(h, 0.1)
	h.receive_hit(1, 1.0, Vector2(-20, 0))       # bitten before the arrow leaves
	_run(h, 1.0)
	if _shots.size() != 0: r = "%d arrows after a cancelled skill" % _shots.size()
	elif h.skill_cooldown_left("piercing") > 0.0: r = "cooldown %.2f after a cancelled skill" % h.skill_cooldown_left("piercing")
	elif h.mp < 50.0 - 0.01: r = "mp %.1f, a cancelled skill must not cost MP" % h.mp
	_run(h, 1.0)
	h.try_skill("piercing")
	_run(h, 0.1)
	h.try_dodge(Vector2.RIGHT)
	_run(h, 1.0)
	if r == "" and (_shots.size() != 0 or h.skill_cooldown_left("piercing") > 0.0 or h.mp < 50.0 - 0.01): r = "roll cancel still cost (arrows %d, cd %.2f, mp %.1f)" % [_shots.size(), h.skill_cooldown_left("piercing"), h.mp]
	_done(h)
	return r

func test_skill_pressed_during_basic_shot_waits_and_fires():
	var h := _hero()
	var r := ""
	h.try_shoot()
	_run(h, 0.1)                                   # basic arrow not out yet
	if not h.try_skill("piercing"): r = "skill press during a basic shot was dropped"
	_run(h, 1.2)
	if r == "" and _shots.size() != 2: r = "%d arrows, want basic + piercing" % _shots.size()
	elif r == "" and (_shots[0].pierce or not _shots[1].pierce): r = "order: basic first, then piercing"
	# basic arrow out at 5/14 s, skill starts then and releases 5/14 s later
	elif r == "" and absf(h.mp - (50 - 8 + 6 * (1.3 - 10.0 / 14.0))) > 0.2: r = "mp %.1f, want 45.5" % h.mp
	_done(h)
	return r

func test_piercing_uses_its_own_range():
	var sk: Dictionary = Balance.data()["skills"]["piercing"]
	var old = sk["range"]
	sk["range"] = 300
	var h := _hero()
	h.facing = 2
	h.try_skill("piercing")
	_run(h, 0.5)
	var r := ""
	if _shots.size() != 1: r = "%d arrows" % _shots.size()
	elif absf(_shots[0].max_range - 300.0) > 0.01: r = "piercing range %.0f, want skills.piercing.range" % _shots[0].max_range
	sk["range"] = old
	_done(h)
	return r

func test_potion_refused_when_bar_full():
	var h := _hero()
	var r := ""
	if h.try_potion("hp") or h.inventory.count_of("potion_hp") != 5: r = "drank an HP potion at full HP"
	elif h.try_potion("mp") or h.inventory.count_of("potion_mp") != 3: r = "drank an MP potion at full MP"
	_done(h)
	return r
