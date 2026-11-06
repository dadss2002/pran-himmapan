extends RefCounted
## Hero sockets gems; skills fire from SkillBuild (M3a design §5).

const DT := 1.0 / 60.0
var _shots: Array = []

func _hero(level := 1) -> Hero:
	var h: Hero = load("res://scenes/hero.tscn").instantiate()
	h.setup_sprites()
	if level > 1: h.set_progress(level, 0)
	h.inventory.slots.clear()
	_shots = []
	h.shot.connect(func(a): _shots.append(a))
	return h

func _g(type: String, extra := {}) -> Dictionary:
	var g := {"type": type, "level": 1, "exp": 0, "rarity": "good", "opts": [{"k": "crit", "v": 0.03}]}
	g.merge(extra, true)
	return g

func _run(h: Hero, s: float) -> void:
	for i in int(round(s / DT)): h.step(DT, Vector2.ZERO)

func _done(h: Hero) -> void:
	for a in _shots: if is_instance_valid(a): a.free()
	h.free()

func test_socket_swap_and_label():
	var h := _hero()
	h.inventory.add_gem(_g("expand"))
	h.inventory.add_gem(_g("split"))
	h.inventory.add_gem(_g("multiply"))
	var r := ""
	if h.socket("piercing", 0, 0) != "ป้ายไม่ตรง": r = "expand into piercing should be refused"
	elif h.socket("spread", 0, 1) != "ยังไม่ปลด": r = "spread is locked at Lv1"
	elif h.socket("piercing", 1, 1) != "ช่องยังไม่เปิด": r = "slot 2 opens at skill level 10"
	elif h.socket("piercing", 0, 1) != "" or h.skill_gems.piercing[0].type != "split": r = "split not socketed"
	elif h.inventory.slots.size() != 2: r = "split should leave the bag (%d slots)" % h.inventory.slots.size()
	elif h.socket("piercing", 0, 1) != "" or h.skill_gems.piercing[0].type != "multiply": r = "swap failed"
	elif h.inventory.slots.back().get("gem", {}).get("type", "") != "split": r = "swapped-out gem should be back in the bag"
	_done(h)
	return r

func test_unsocket_full_bag():
	var h := _hero()
	h.inventory.add_gem(_g("split"))
	h.socket("piercing", 0, 0)
	for i in 24: h.inventory.add("junk_%d" % i, 1)
	var r := ""
	if h.unsocket("piercing", 0) != "กระเป๋าเต็ม" or h.skill_gems.piercing[0] == null: r = "unsocket into a full bag must be refused"
	h.inventory.slots.pop_back()
	if r == "" and (h.unsocket("piercing", 0) != "" or h.skill_gems.piercing[0] != null): r = "unsocket failed with room"
	_done(h)
	return r

func test_piercing_with_split_fires_three():
	var h := _hero()
	h.facing = 2
	h.inventory.add_gem(_g("split"))
	h.socket("piercing", 0, 0)
	h.try_skill("piercing")
	_run(h, 0.6)
	var r := ""
	if _shots.size() != 3: r = "%d arrows, want 3" % _shots.size()
	else:
		var angles := []
		for a in _shots: angles.append(rad_to_deg(a.dir.angle()))
		angles.sort()
		if absf(angles[1] - angles[0] - 12.0) > 0.1 or absf(angles[2] - angles[1] - 12.0) > 0.1: r = "angles %s, want 12° apart" % [angles]
		elif absf(_shots[0].mult - 1.08) > 1e-4 or not _shots[0].pierce: r = "mult %.3f pierce %s" % [_shots[0].mult, _shots[0].pierce]
		elif absf(h.mp - (50.0 - 11.2 + 6.0 * (0.6 - 5.0 / 14.0))) > 0.2: r = "mp %.2f, want 11.2 spent" % h.mp
	_done(h)
	return r

func test_spread_with_split_fires_seven():
	var h := _hero(3)
	h.facing = 2
	h.inventory.add_gem(_g("split"))
	h.socket("spread", 0, 0)
	h.try_skill("spread")
	_run(h, 0.6)
	var r := ""
	if _shots.size() != 7: r = "%d arrows, want 7" % _shots.size()
	else:
		var lo := INF
		var hi := -INF
		for a in _shots:
			lo = minf(lo, rad_to_deg(a.dir.angle())); hi = maxf(hi, rad_to_deg(a.dir.angle()))
		if absf(hi - lo - 63.0) > 0.2: r = "fan %.1f°, want 63°" % (hi - lo)
	_done(h)
	return r

func test_mp_too_high_refused():
	var h := _hero(3)
	for t in ["split"]: h.inventory.add_gem(_g(t))
	h.socket("spread", 0, 0)                 # 12 × 1.4 = 16.8
	h.mp = 16.0
	var r := ""
	if h.try_skill("spread") or h.mp != 16.0: r = "fired or spent with 16 MP (cost 16.8)"
	elif absf(h.skill_mp("spread") - 16.8) > 1e-6: r = "skill_mp %.2f" % h.skill_mp("spread")
	_done(h)
	return r

func test_gem_exp_from_kill_and_at_cap():
	var h := _hero()
	h.inventory.add_gem(_g("split", {"opts": [{"k": "gem_exp", "v": 0.2}]}))
	h.socket("piercing", 0, 0)
	h.on_kill(100, 1)
	var g: Dictionary = h.skill_gems.piercing[0]
	var r := "" if g.exp == 120 else "gem exp %d, want 120 (100 × 1.2)" % g.exp
	h.set_progress(Progression.cap(), 0)
	h.on_kill(10, Progression.cap())
	if r == "" and g.exp != 132: r = "at the character cap the gem should still gain (exp %d, want 132)" % g.exp
	_done(h)
	return r

func test_hud_shows_real_mp_and_cooldown():
	var h := _hero(3)
	h.inventory.add_gem(_g("split"))
	h.socket("spread", 0, 0)
	h.mp = 14.0
	var hud := Hud.new()
	hud.build()
	hud.bind(h)
	hud.refresh()
	var r := "" if not hud.buttons.buttons["skill2"].enabled else "spread shown usable with 14 MP (needs 16.8)"
	hud.free()
	_done(h)
	return r
