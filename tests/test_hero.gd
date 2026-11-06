extends RefCounted
## Hero scene tests. Each returns "" on success or a failure message.

const MANIFEST := "res://assets/hero/manifest.json"

func _hero() -> Hero:
	return load("res://scenes/hero.tscn").instantiate()

func test_manifest_complete():
	var sf := SpriteSet.build(MANIFEST)
	var want := {"idle": 4, "walk": 8, "shoot": 9, "roll": 8, "death": 7}
	var count := 0
	for anim in want:
		for d in Combat.DIRS:
			var name: String = "%s_%s" % [anim, d]
			if not sf.has_animation(name): return "missing animation " + name
			if sf.get_frame_count(name) != want[anim]:
				return "%s has %d frames, expected %d" % [name, sf.get_frame_count(name), want[anim]]
			count += 1
	if sf.get_animation_loop("shoot_east"): return "shoot must not loop"
	if not sf.get_animation_loop("walk_east"): return "walk must loop"
	if sf.get_animation_loop("roll_east") or sf.get_animation_loop("death_east"): return "roll/death must not loop"
	return "" if count == 40 else "expected 40 animations, got %d" % count

func test_anchor_puts_feet_on_origin():
	var a := SpriteSet.anchor(MANIFEST, "walk")
	return "" if a == Vector2(32, 54) else "walk anchor should be (32,54), got %s" % a

func test_shot_cooldown():
	var h := _combat_hero()
	if not h.try_shoot(): return "first shot should fire"
	if h.try_shoot(): return "second shot within 0.8 s must be refused"
	h.step(0.5, Vector2.ZERO)
	if h.try_shoot(): return "still on cooldown after 0.5 s"
	h.step(0.31, Vector2.ZERO)
	var ok := h.try_shoot()
	_cleanup(h)
	return "" if ok else "shot should fire again after 0.81 s"

func test_walk_speed_and_facing():
	var h := _hero()
	h.setup_sprites()
	h.step(1.0, Vector2(1, 0))
	var res := ""
	if h.state != "walk": res = "state should be walk, got " + h.state
	elif absf(h.velocity.length() - Balance.num("hero.walk")) > 0.01: res = "speed %.2f != 110" % h.velocity.length()
	elif h.facing != 2: res = "moving right should face 2 east, got %d" % h.facing
	else:
		h.step(0.1, Vector2.ZERO)
		if h.state != "idle": res = "no input should go idle, got " + h.state
		elif h.facing != 2: res = "facing must be kept when idle, got %d" % h.facing
	h.free()
	return res

func test_diagonal_not_faster():
	var h := _hero()
	h.setup_sprites()
	h.step(0.1, Vector2(1, -1))
	var sp := h.velocity.length()
	h.free()
	return "" if absf(sp - Balance.num("hero.walk")) < 0.01 else "diagonal speed %.2f should be 110" % sp

func test_no_walking_while_shooting():
	var h := _hero()
	h.setup_sprites()
	h.try_shoot()
	h.step(0.1, Vector2(1, 0))
	var res := "" if h.state == "shoot" and h.velocity == Vector2.ZERO else "shooting should lock movement (state=%s v=%s)" % [h.state, h.velocity]
	h.free()
	return res

func test_bow_layer_order():
	# walking/idle: bow on the back -> behind the body when facing the camera (south), on top when facing away (north)
	# shooting: bow in front of the body, except when aiming away from the camera
	var b := BowLayer.new()
	var r := ""
	if b.draws_in_front("walk", 0): r = "walk south: bow on back must be behind body"
	elif not b.draws_in_front("walk", 4): r = "walk north: bow on back must be on top"
	elif not b.draws_in_front("shoot", 0): r = "shoot south: bow must be in front"
	elif b.draws_in_front("shoot", 4): r = "shoot north: bow must be behind body"
	elif not b.draws_in_front("shoot", 3): r = "shoot north-east: bow held out to the side must be visible"
	b.free()
	return r

func test_bow_aims_along_facing():
	var b := BowLayer.new()
	b.apply("shoot", 2)
	var east := b.rotation
	b.apply("shoot", 0)
	var south := b.rotation
	b.free()
	if absf(east) > 0.001: return "aiming east should have rotation 0, got %f" % east
	return "" if absf(south - PI / 2.0) < 0.001 else "aiming south should be PI/2, got %f" % south

func test_arrow_frees_after_range():
	var a: Arrow = load("res://scenes/arrow.tscn").instantiate()
	a.launch(Vector2(1, 0), 0.0)
	var steps := 0
	while not a.spent and steps < 1000:
		a.advance(1.0 / 60.0)
		steps += 1
	var travelled := a.travelled
	a.free()
	if steps >= 1000: return "arrow never finished"
	return "" if absf(travelled - Balance.num("shot.range")) < 0.01 else "arrow travelled %.1f, expected 220" % travelled

# ---- M2a combat ----
const DT := 1.0 / 60.0
var _shots: Array = []
var _respawns := 0

func _combat_hero() -> Hero:
	var h := _hero()
	h.setup_sprites()
	_shots = []
	_respawns = 0
	h.shot.connect(func(a): _shots.append(a))
	h.respawned.connect(func(): _respawns += 1)
	return h

func _run(h: Hero, seconds: float, input := Vector2.ZERO) -> void:
	var n := int(round(seconds / DT))
	for i in n: h.step(DT, input)

func _dummy(pos: Vector2) -> Node2D:
	var d: Node2D = load("res://tests/dummy_enemy.gd").new()
	d.position = pos
	return d

func _cleanup(h: Hero, extra: Array = []) -> void:
	for a in _shots: if is_instance_valid(a): a.free()
	for e in extra: if is_instance_valid(e): e.free()
	h.free()

func test_receive_hit_uses_def():
	Combat.rng.seed = 7
	var h := _combat_hero()
	h.position = Vector2(100, 100)
	var dealt := h.receive_hit(6, 1.0, Vector2(90, 100))
	var r := ""
	if dealt < 5 or dealt > 6: r = "damage %d not in 5..6" % dealt
	elif h.health.hp != 120 - dealt: r = "hp %d" % h.health.hp
	elif h.state != "hurt": r = "state %s != hurt" % h.state
	elif absf(h.position.x - 108.0) > 0.01: r = "knockback x %f != 108" % h.position.x
	_cleanup(h)
	return r

func test_hurt_iframe_0_5():
	var h := _combat_hero()
	h.receive_hit(6, 1.0, Vector2(-10, 0))
	_run(h, 0.3)
	var r := ""
	if h.receive_hit(6, 1.0, Vector2(-10, 0)) != 0: r = "hit at 0.3 s should be ignored"
	_run(h, 0.25)
	if r == "" and h.receive_hit(6, 1.0, Vector2(-10, 0)) <= 0: r = "hit at 0.55 s should land"
	_cleanup(h)
	return r

func test_roll_distance_lv1_and_lv5():
	var r := ""
	for lv in [1, 5]:
		var h := _combat_hero()
		h.level = lv
		var want: float = Balance.dodge(lv).distance
		if not h.try_dodge(Vector2.RIGHT): r = "lv%d roll refused" % lv
		_run(h, Balance.dodge(lv).duration)
		if r == "" and absf(h.position.x - want) > 1.0: r = "lv%d moved %f, want %f" % [lv, h.position.x, want]
		if r == "" and h.state == "roll": r = "lv%d still rolling after duration" % lv
		if r == "" and h.try_dodge(Vector2.RIGHT): r = "lv%d second roll inside 1.5 s accepted" % lv
		_run(h, 1.3)
		if r == "" and not h.try_dodge(Vector2.RIGHT): r = "lv%d roll after cooldown refused" % lv
		_cleanup(h)
		if r != "": return r
	return r

func test_roll_iframe_window():
	var h := _combat_hero()
	h.try_dodge(Vector2.RIGHT)
	_run(h, 0.1)
	var r := ""
	if h.receive_hit(6, 1.0, Vector2(-10, 0)) != 0: r = "hit at 0.1 s into roll should be ignored"
	_run(h, 0.12)
	if r == "" and h.receive_hit(6, 1.0, Vector2(-10, 0)) <= 0: r = "hit at 0.22 s (after 0.2 iframe) should land"
	_cleanup(h)
	return r

func test_roll_cancels_shot_no_arrow():
	var h := _combat_hero()
	h.try_shoot()
	_run(h, 2.0 / 14.0)          # frame 2 of the shot
	h.try_dodge(Vector2.LEFT)
	_run(h, 1.0)
	var r := "" if _shots.is_empty() else "roll before release still loosed %d arrow(s)" % _shots.size()
	_cleanup(h)
	return r

func test_auto_aim_turns_and_fires_at_nearest():
	var h := _combat_hero()
	var far := _dummy(Vector2(100, 0))
	var near := _dummy(Vector2(0, -50))
	h.test_enemies = [far, near]
	h.try_shoot()
	var r := ""
	if h.facing != 4: r = "should face north (4), faces %d" % h.facing
	_run(h, 1.0)
	if r == "" and _shots.size() != 1: r = "expected 1 arrow, got %d" % _shots.size()
	if r == "" and _shots[0].dir.distance_to(Vector2(0, -1)) > 0.05: r = "arrow dir %s" % _shots[0].dir
	_cleanup(h, [far, near])
	return r

func test_target_freed_before_release():
	var h := _combat_hero()
	var t := _dummy(Vector2(120, 0))
	h.test_enemies = [t]
	h.try_shoot()
	_run(h, 3.0 / 14.0)
	t.free()
	_run(h, 1.0)
	var r := ""
	if _shots.size() != 1: r = "expected 1 arrow after target freed, got %d" % _shots.size()
	elif _shots[0].dir.distance_to(Vector2(1, 0)) > 0.1: r = "arrow should keep stored aim east, got %s" % _shots[0].dir
	_cleanup(h)
	return r

func test_arrow_hits_enemy():
	var a: Arrow = load("res://scenes/arrow.tscn").instantiate()
	var d1 := _dummy(Vector2(100, 14))
	var d2 := _dummy(Vector2(150, 14))
	a.position = Vector2.ZERO
	a.launch(Vector2.RIGHT, 18.0, [d1, d2])
	for i in 120: a.advance(DT)
	var r := ""
	if d1.hits.size() != 1: r = "first enemy hit %d times" % d1.hits.size()
	elif d1.hits[0][0] != 18.0: r = "atk passed %s" % d1.hits[0][0]
	elif d2.hits.size() != 0: r = "arrow must stop at first enemy"
	elif not a.spent: r = "arrow should be spent"
	a.free(); d1.free(); d2.free()
	return r

func test_death_and_respawn():
	var h := _combat_hero()
	h.spawn_point = Vector2(500, 300)
	h.position = Vector2(10, 10)
	h.health.take_hit(119, false)
	h.receive_hit(500, 1.0, Vector2.ZERO)
	var r := ""
	if h.state != "dead": r = "state %s != dead" % h.state
	elif not String(h.body.animation).begins_with("death_"): r = "dead hero plays %s, not the death clip" % h.body.animation
	_run(h, 0.5)
	if r == "" and not String(h.body.animation).begins_with("death_"): r = "death clip replaced by %s while dead" % h.body.animation
	_run(h, 0.95)
	if r == "" and _respawns != 0: r = "respawned too early"
	_run(h, 0.1)
	if r == "" and _respawns != 1: r = "respawned %d times" % _respawns
	if r == "" and h.position != Vector2(500, 300): r = "respawn at %s" % h.position
	if r == "" and h.health.hp != 120: r = "hp after respawn %d" % h.health.hp
	_cleanup(h)
	return r

func test_no_damage_while_dead_or_respawning():
	var h := _combat_hero()
	h.receive_hit(9999, 1.0, Vector2.ZERO)
	var r := ""
	if h.receive_hit(10, 1.0, Vector2.ZERO) != 0: r = "dead hero took damage"
	_run(h, 1.6)
	if r == "" and h.receive_hit(10, 1.0, Vector2.ZERO) != 0: r = "hit right after respawn should be ignored"
	_run(h, 1.7)
	if r == "" and h.receive_hit(10, 1.0, Vector2.ZERO) != 0: r = "hit 1.8 s after respawn should be ignored"
	_run(h, 0.3)
	if r == "" and h.receive_hit(10, 1.0, Vector2.ZERO) <= 0: r = "hit after 2 s should land"
	_cleanup(h)
	return r

func test_current_target_for_lock_ring():
	var h := _combat_hero()
	var a := _dummy(Vector2(150, 0))
	var b := _dummy(Vector2(0, 90))
	var c := _dummy(Vector2(400, 0))
	h.test_enemies = [a, b, c]
	var r := ""
	if h.current_target() != b: r = "nearest in range should be b"
	b.alive = false
	if r == "" and h.current_target() != a: r = "after b dies the ring should move to a"
	a.alive = false
	if r == "" and h.current_target() != null: r = "nothing in range -> no ring"
	_cleanup(h, [a, b, c])
	return r
