extends RefCounted
## Hero scene tests. Each returns "" on success or a failure message.

const MANIFEST := "res://assets/hero/manifest.json"

func _hero() -> Hero:
	return load("res://scenes/hero.tscn").instantiate()

func test_manifest_complete():
	var sf := HeroSprites.build(MANIFEST)
	var want := {"idle": 4, "walk": 8, "shoot": 9}
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
	return "" if count == 24 else "expected 24 animations, got %d" % count

func test_anchor_puts_feet_on_origin():
	var a := HeroSprites.anchor(MANIFEST, "walk")
	return "" if a == Vector2(32, 54) else "walk anchor should be (32,54), got %s" % a

func test_shot_cooldown():
	var h := _hero()
	h.setup_sprites()
	if not h.try_shoot(): return "first shot should fire"
	if h.try_shoot(): return "second shot within 0.8 s must be refused"
	h.step(0.5, Vector2.ZERO)
	if h.try_shoot(): return "still on cooldown after 0.5 s"
	h.step(0.31, Vector2.ZERO)
	var ok := h.try_shoot()
	h.free()
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
	a.launch(Vector2(1, 0))
	var steps := 0
	while not a.spent and steps < 1000:
		a.advance(1.0 / 60.0)
		steps += 1
	var travelled := a.travelled
	a.free()
	if steps >= 1000: return "arrow never finished"
	return "" if absf(travelled - Balance.num("shot.range")) < 0.01 else "arrow travelled %.1f, expected 220" % travelled
