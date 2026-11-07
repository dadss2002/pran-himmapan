extends RefCounted
## Ghost wolf + pack AI, stepped manually at 60 Hz with a real Hero (out of tree).

const DT := 1.0 / 60.0

func _hero(pos: Vector2) -> Hero:
	var h: Hero = load("res://scenes/hero.tscn").instantiate()
	h.setup_sprites()
	h.position = pos
	return h

func _pack(level: int, count: int, home := Vector2.ZERO) -> WolfPack:
	var p := WolfPack.new()
	p.level = level
	p.count = count
	p.home = home
	p.spawn()
	return p

## Put wolf i of the pack at pos and every other wolf far away and dead-quiet.
func _solo(p: WolfPack, pos: Vector2) -> Wolf:
	var w: Wolf = p.wolves[0]
	w.position = pos
	for k in range(1, p.wolves.size()):
		p.wolves[k].position = Vector2(-5000, -5000)
		p.wolves[k].home = Vector2(-5000, -5000)
	return w

func _run(p: WolfPack, h: Hero, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		if h: h.step(DT, Vector2.ZERO)
		p.step_all(DT, h)

func _done(p: WolfPack, h: Hero) -> void:
	p.free()
	if h: h.free()

func test_stats_from_level():
	var p := _pack(3, 1)
	var w: Wolf = p.wolves[0]
	var r := ""
	# lv3 76/10/5 x M3g horde -> 38/8/5
	if w.health.max_hp != 38 or w.stats().atk != 8 or w.stats().def != 5: r = "lv3 stats %s hp %d" % [w.stats(), w.health.max_hp]
	_done(p, null)
	return r

func test_aggro_at_160_alerts_pack():
	var p := _pack(1, 4)
	var h := _hero(Vector2(150, 0))
	p.wolves[0].position = Vector2.ZERO
	for k in range(1, 4): p.wolves[k].position = Vector2(-60, 0)   # 210 px from the hero
	_run(p, h, DT)
	var r := ""
	for w in p.wolves:
		if w.state != "chase": r = "wolf in state %s, all should chase" % w.state
	_done(p, h)
	return r

func test_chase_speed_100():
	var p := _pack(1, 1)
	var w := _solo(p, Vector2.ZERO)
	var h := _hero(Vector2(155, 0))
	_run(p, h, DT)            # alert
	var x0 := w.position.x
	h.position = Vector2(600, 0)  # far: plain running (out of lunge range)
	p.home = Vector2(200, 0); w.home = Vector2(200, 0)   # keep inside the leash
	_run(p, h, 0.25)
	var speed := (w.position.x - x0) / 0.25
	_done(p, h)
	return "" if absf(speed - 100.0) < 3.0 else "speed %.1f != 100 (M3i: slower than the hero's 110)" % speed

func test_bite_after_windup():
	Combat.rng.seed = 3
	var p := _pack(1, 1)
	var w := _solo(p, Vector2.ZERO)
	var h := _hero(Vector2(20, 0))
	_run(p, h, 0.3)
	var r := ""
	if w.state != "bite": r = "state %s, expected bite" % w.state
	elif h.health.hp != 120: r = "damage landed before the 0.35 s windup"
	_run(p, h, 0.1)
	var lost := 120 - h.health.hp
	if r == "" and (lost < 5 or lost > 6): r = "bite did %d, expected 5-6" % lost
	_run(p, h, 1.0)          # hero still in iframes/hurt; next bite not before 1.2 s
	if r == "" and 120 - h.health.hp != lost: r = "second bite before the 1.2 s cooldown"
	_done(p, h)
	return r

func test_lunge_warns_then_dashes():
	Combat.rng.seed = 5
	var p := _pack(1, 1)
	var w := _solo(p, Vector2.ZERO)
	var h := _hero(Vector2(100, 0))
	_run(p, h, DT)
	var r := ""
	if w.state != "lunge_warn": r = "state %s, expected lunge_warn" % w.state
	elif not w.telegraph_visible(): r = "warning circle not shown"
	_run(p, h, 0.55)
	if r == "" and (w.state != "lunge_warn" or w.position != Vector2.ZERO): r = "wolf must hold still for 0.6 s (M3i)"
	if r == "" and h.health.hp != 120: r = "hit during the warning"
	_run(p, h, 0.05 + 0.4 + DT)
	var lost := 120 - h.health.hp
	if r == "" and absf(w.position.x - 100.0) > 1.5: r = "lunge travelled %.1f, want 100 (M3i)" % w.position.x
	var hit: float = w.stats().atk * 1.5                     # x1.5 lunge, minus a little for the hero's DEF and the roll
	if r == "" and (lost < int(hit) - 1 or lost > int(ceil(hit))): r = "lunge did %d, expected about %.1f (x1.5)" % [lost, hit]
	_done(p, h)
	return r

func test_one_lunge_per_pack():
	var p := _pack(1, 2)
	var h := _hero(Vector2(100, 0))
	p.wolves[0].position = Vector2(0, 0)
	p.wolves[1].position = Vector2(0, 20)
	_run(p, h, DT)
	var warns := 0
	for w in p.wolves:
		if w.state == "lunge_warn": warns += 1
	_done(p, h)
	return "" if warns == 1 else "%d wolves warned at once" % warns

func test_roll_dodges_lunge():
	var p := _pack(1, 1)
	var w := _solo(p, Vector2.ZERO)
	var h := _hero(Vector2(100, 0))
	_run(p, h, 0.5)
	h.try_dodge(Vector2(0, 1))   # roll out of the line as the warning ends
	_run(p, h, 0.5)
	var r := "" if h.health.hp == 120 else "rolled hero still took %d" % (120 - h.health.hp)
	_done(p, h)
	return r

func test_leash_returns_and_heals():
	var p := _pack(1, 1)
	var w := _solo(p, Vector2.ZERO)
	var h := _hero(Vector2(150, 0))
	_run(p, h, DT)
	w.health.take_hit(10, false)
	w.position = Vector2(330, 0)
	h.position = Vector2(700, 0)
	_run(p, h, DT)
	var r := ""
	if w.state != "return": r = "state %s, expected return" % w.state
	elif w.health.hp != w.health.max_hp: r = "not healed on return"
	_run(p, h, 4.0)                          # 330 px home at run 100 (M3i)
	if r == "" and w.state != "idle": r = "should be idle at home, is %s" % w.state
	_done(p, h)
	return r

func test_pack_returns_when_hero_dies():
	var p := _pack(1, 3)
	var h := _hero(Vector2(40, 0))
	_run(p, h, DT)
	h.receive_hit(9999, 1.0, Vector2.ZERO)
	_run(p, h, DT)
	var r := ""
	for w in p.wolves:
		if w.state != "return": r = "wolf state %s after hero died" % w.state
	_done(p, h)
	return r

func test_hit_knockback_and_windup_not_interrupted():
	Combat.rng.seed = 9
	var p := _pack(1, 1)
	var w := _solo(p, Vector2.ZERO)
	var r := ""
	w.receive_hit(5, 1.0, Vector2(-10, 0))
	if absf(w.position.x - 6.0) > 0.01: r = "idle wolf knocked %.2f, want 6" % w.position.x
	var h := _hero(Vector2(26, 0))
	_run(p, h, DT)
	if r == "" and w.state != "bite": r = "expected bite windup, got %s" % w.state
	var x := w.position.x
	w.receive_hit(5, 1.0, Vector2(40, 0))
	if r == "" and w.position.x != x: r = "windup wolf must not be knocked back"
	_run(p, h, 0.36)
	if r == "" and h.health.hp == 120: r = "bite should still land"
	_done(p, h)
	return r

func test_death_and_respawn_9s():
	var p := _pack(1, 1)
	var w := _solo(p, Vector2(30, 0))
	w.receive_hit(9999, 1.0, Vector2.ZERO)
	var r := ""
	if w.is_alive() or w.state != "dead": r = "wolf should be dead"
	_run(p, null, 8.9)
	if r == "" and w.is_alive(): r = "respawned too early"
	_run(p, null, 0.2)
	if r == "" and not w.is_alive(): r = "not respawned after 9 s (M3g)"
	if r == "" and w.health.hp != 20: r = "respawn hp %d" % w.health.hp
	if r == "" and w.position.distance_to(p.home) > 40: r = "respawned away from home at %s" % w.position
	_done(p, null)
	return r
