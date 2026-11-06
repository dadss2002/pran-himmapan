extends RefCounted
## Touch controls + HUD. Uses the pure handle_* APIs so no input frames are needed.

func _joy() -> TouchJoystick:
	var j := TouchJoystick.new()
	j.view_size = Vector2(640, 360)
	j.reset()
	return j

func test_joystick_follows_finger():
	var j := _joy()
	j.handle_touch(0, Vector2(200, 250), true)
	var r := ""
	if not j.active: r = "should be active"
	elif j.center != Vector2(200, 250): r = "centre %s should be under the finger" % j.center
	elif absf(j.alpha() - TouchJoystick.ACTIVE_ALPHA) > 0.001: r = "alpha %f" % j.alpha()
	j.handle_touch(0, Vector2(200, 250), false)
	if r == "" and (j.active or j.vector != Vector2.ZERO): r = "release should stop"
	if r == "" and absf(j.alpha() - TouchJoystick.IDLE_ALPHA) > 0.001: r = "idle alpha %f" % j.alpha()
	if r == "" and j.center != TouchJoystick.IDLE_CENTER: r = "should go back to idle spot"
	j.free()
	return r

func test_joystick_vector_and_clamp():
	var j := _joy()
	j.handle_touch(0, Vector2(200, 250), true)
	j.handle_drag(0, Vector2(230, 250))
	var r := ""
	if j.vector.distance_to(Vector2(1, 0)) > 0.001: r = "vector %s != (1,0)" % j.vector
	j.handle_drag(0, Vector2(330, 250))   # 130 px right: ring follows, knob stays on the rim
	if r == "" and absf(j.knob.distance_to(j.center) - TouchJoystick.RADIUS) > 0.01: r = "knob not on rim"
	if r == "" and j.knob != Vector2(330, 250): r = "knob should stay under the finger, at %s" % j.knob
	if r == "" and j.center != Vector2(330 - TouchJoystick.RADIUS, 250): r = "ring should follow, centre %s" % j.center
	j.handle_drag(0, Vector2(202, 251))   # back inside the deadzone of the moved ring? no: far left now
	if r == "" and j.vector.x >= 0: r = "dragging back left should point left"
	j.free()
	return r

func test_right_half_touch_ignored():
	var j := _joy()
	j.handle_touch(3, Vector2(500, 250), true)
	var r := "" if not j.active else "a touch on the right half grabbed the joystick"
	j.handle_touch(4, Vector2(200, 30), true)
	if r == "" and j.active: r = "a touch on the top status bar grabbed the joystick"
	j.free()
	return r

func test_multitouch_joystick_and_shoot():
	var j := _joy()
	var b := TouchButtons.new()
	b.build_default()
	j.handle_touch(0, Vector2(150, 260), true)
	j.handle_drag(0, Vector2(190, 260))
	var shoot: Vector2 = b.center_of("shoot")
	j.handle_touch(1, shoot, true)          # the joystick sees every touch first
	b.handle_touch(1, shoot, true)
	var r := ""
	if j.vector.distance_to(Vector2(1, 0)) > 0.001: r = "joystick changed by the second finger: %s" % j.vector
	elif not Input.is_action_pressed("attack"): r = "shoot button did not press attack"
	b.handle_touch(1, shoot, false)
	if r == "" and Input.is_action_pressed("attack"): r = "attack still held after release"
	var dodge: Vector2 = b.center_of("dodge")
	b.handle_touch(2, dodge, true)
	if r == "" and not Input.is_action_pressed("dodge"): r = "dodge button did not press dodge"
	b.handle_touch(2, dodge, false)
	j.free(); b.free()
	return r

func test_locked_buttons_do_nothing():
	var b := TouchButtons.new()
	b.build_default()
	b.handle_touch(5, b.center_of("skill1"), true)
	var r := "" if b.pressed_names().is_empty() else "locked skill button reacted"
	b.free()
	return r

func test_hud_hp_text():
	var hero: Hero = load("res://scenes/hero.tscn").instantiate()
	hero.setup_sprites()
	var hud := Hud.new()
	hud.build()
	hud.bind(hero)
	hero.health.take_hit(6, false)
	hud.refresh()
	var t := hud.hp_label.text
	hud.free(); hero.free()
	return "" if t == "HP 114 / 120" else "label '%s'" % t
