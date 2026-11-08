extends RefCounted
## Touch controls + HUD. Uses the pure handle_* APIs so no input frames are needed (the second-finger panel
## test pushes touches into the root viewport).

var tree: SceneTree

func setup(t: SceneTree) -> void:
	tree = t

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
	if r == "" and j.center != j.idle_center(): r = "should go back to idle spot"
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
	b.handle_touch(5, b.center_of("skill2"), true)
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

func test_screen_dims_while_dead():
	var hero: Hero = load("res://scenes/hero.tscn").instantiate()
	hero.setup_sprites()
	var hud := Hud.new()
	hud.build()
	hud.bind(hero)
	var r := ""
	if hud.dim.color.a != 0.0: r = "dim before death"
	hero.receive_hit(9999, 1.0, Vector2.ZERO)
	hud.refresh()
	if r == "" and absf(hud.dim.color.a - Hud.DEAD_DIM) > 0.001: r = "screen not dimmed while dead"
	for i in 100: hero.step(1.0 / 60.0, Vector2.ZERO)
	hud.refresh()
	if r == "" and hud.dim.color.a != 0.0: r = "dim should clear after respawn"
	hud.free(); hero.free()
	return r

func test_two_fingers_on_shoot_release_one():
	var b := TouchButtons.new()
	b.build_default()
	var c: Vector2 = b.center_of("shoot")
	b.handle_touch(1, c, true)
	b.handle_touch(2, c + Vector2(5, 0), true)
	b.handle_touch(1, c, false)
	var r := "" if Input.is_action_pressed("attack") else "lifting one of two fingers released attack"
	b.handle_touch(2, c, false)
	if r == "" and Input.is_action_pressed("attack"): r = "attack held after both fingers lifted"
	b.free()
	return r

func test_focus_loss_releases_everything():
	var j := _joy()
	var b := TouchButtons.new()
	b.build_default()
	j.handle_touch(0, Vector2(150, 260), true)
	j.handle_drag(0, Vector2(190, 260))
	b.handle_touch(1, b.center_of("shoot"), true)
	j.release_all()
	b.release_all()
	var r := ""
	if j.active or j.vector != Vector2.ZERO: r = "joystick still active after focus loss"
	elif Input.is_action_pressed("attack"): r = "attack still held after focus loss"
	j.free(); b.free()
	return r

func test_buttons_follow_wide_screen():
	var b := TouchButtons.new()
	b.build_default()
	b.layout(Vector2(800, 360))
	var c: Vector2 = b.center_of("shoot")
	var r := "" if c == Vector2(744, 302) else "shoot at %s on an 800-wide screen, want (744, 302)" % c
	var j := TouchJoystick.new()
	j.view_size = Vector2(800, 360)
	j.handle_touch(0, Vector2(390, 250), true)
	if r == "" and not j.active: r = "joystick zone should grow with the screen (x 390 < 400)"
	b.free(); j.free()
	return r

func test_hud_unlocks_spread_at_lv3():
	var hero: Hero = load("res://scenes/hero.tscn").instantiate()
	hero.setup_sprites()
	var hud := Hud.new()
	hud.build()
	hud.bind(hero)
	var r := ""
	if hud.buttons.buttons["skill2"].enabled: r = "spread usable at Lv1"
	hero.set_progress(3, 0)
	hud.refresh()
	if r == "" and not hud.buttons.buttons["skill2"].enabled: r = "spread still locked at Lv3"
	if r == "" and hud.buttons.buttons["potion_hp"].note != "5": r = "potion count label '%s'" % hud.buttons.buttons["potion_hp"].note
	hud.free(); hero.free()
	return r

## A touch (finger `index`) at p (HUD px) pushed into the root viewport; `mouse` first sends the emulated mouse
## button Godot makes for the one finger it turns into the mouse (device DEVICE_ID_EMULATION).
func _touch(index: int, p: Vector2, pressed: bool, mouse := false) -> void:
	if mouse:
		var mm := InputEventMouseMotion.new()
		mm.device = InputEvent.DEVICE_ID_EMULATION
		mm.position = p
		mm.global_position = p
		tree.root.push_input(mm, true)
		var mb := InputEventMouseButton.new()
		mb.device = InputEvent.DEVICE_ID_EMULATION
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		mb.pressed = pressed
		mb.position = p
		mb.global_position = p
		tree.root.push_input(mb, true)
	var st := InputEventScreenTouch.new()
	st.index = index
	st.position = p
	st.pressed = pressed
	tree.root.push_input(st, true)

func _tap(index: int, c: Control, mouse := false) -> void:
	var p := c.get_global_rect().get_center()
	_touch(index, p, true, mouse)
	await tree.process_frame
	_touch(index, p, false, mouse)
	await tree.process_frame

## Owner report 2026-11-08 (second finger): with the thumb still down (the finger Godot turns into the mouse),
## another finger's taps work on the bag (tab, close), the ตีบวก window under it is not pressed through, and on
## the skill · gem screen (close); a one-finger tap (emulated mouse) presses a button exactly once.
func test_second_finger_on_bag_and_skill_panels():
	var hero: Hero = load("res://scenes/hero.tscn").instantiate()
	hero.setup_sprites()
	hero.set_progress(5, 0)
	var hud := Hud.new()
	tree.root.add_child(hud)
	await tree.process_frame
	hud.bind(hero)
	await tree.process_frame
	var thumb := Vector2(60, 300)
	var r := ""
	_touch(0, thumb, true, true)                       # the thumb: Godot's mouse finger
	hud.open_bag()
	for i in 2: await tree.process_frame
	var bag := hud.bag_panel
	if not bag.is_open(): r = "setup: bag not open"
	if r == "":
		var presses := [0]
		(bag._tab_buttons[2] as Button).pressed.connect(func(): presses[0] += 1)
		await _tap(1, bag._tab_buttons[2])
		if bag.tab != 2 or presses[0] != 1: r = "second finger on tab 2: tab %d, pressed %d times" % [bag.tab, presses[0]]
	if r == "":
		await _tap(1, bag._close_button)
		if bag.is_open() or tree.paused: r = "second finger on ✕ did not close the bag"
	_touch(0, thumb, false, true)                      # thumb up
	await tree.process_frame
	if r == "":
		hud.open_bag()
		for i in 2: await tree.process_frame
		var presses := [0]
		(bag._tab_buttons[1] as Button).pressed.connect(func(): presses[0] += 1)
		await _tap(0, bag._tab_buttons[1], true)       # one finger alone: the GUI presses it, nothing more
		if bag.tab != 1 or presses[0] != 1: r = "one-finger tap on tab 1: tab %d, pressed %d times (want once)" % [bag.tab, presses[0]]
	if r == "":
		_touch(0, thumb, true, true)
		hero.inventory.add("ore_himmapan", 5)
		hero.inventory.gold = 5000
		bag.select_worn("bow")
		bag.press_enhance()
		await tree.process_frame
		var ep := bag.enhance_panel
		if not ep.is_open(): r = "setup: ตีบวก window not open"
		else:
			# any bag button outside the window (under its dim) must not be pressed by another finger
			var under: Button = null
			var stack: Array = [bag._root]
			while not stack.is_empty() and under == null:
				var n: Node = stack.pop_back()
				if n is Button and n.is_visible_in_tree() and not n.disabled and not ep._panel.get_global_rect().intersects(n.get_global_rect()):
					under = n
				stack.append_array(n.get_children())
			if under == null: r = "setup: no bag button outside the ตีบวก window"
			else:
				var hits := [0]
				under.pressed.connect(func(): hits[0] += 1)
				await _tap(1, under)
				if hits[0] != 0 or not ep.is_open(): r = "a second finger pressed the bag's %s through the ตีบวก window" % under.name
			if r == "":
				await _tap(1, ep._close_button)
				if ep.is_open(): r = "second finger on the ตีบวก ✕ did not close it"
		_touch(0, thumb, false, true)
		await tree.process_frame
	if bag.is_open(): bag.close()
	if r == "":
		_touch(0, thumb, true, true)
		hud.open_skills()
		for i in 2: await tree.process_frame
		var sp := hud.skill_panel
		if not sp.is_open(): r = "setup: skill screen not open"
		else:
			await _tap(1, sp._close_button)
			if sp.is_open() or tree.paused: r = "second finger on the skill screen's ✕ did not close it"
		_touch(0, thumb, false, true)
		await tree.process_frame
	if hud.skill_panel.is_open(): hud.skill_panel.close()
	tree.paused = false
	hud.queue_free()
	hero.queue_free()
	for i in 2: await tree.process_frame
	return r

## Review I1/M2 (2026-11-09): an iOS touchcancel (a call, a system gesture) over a button is not a tap, and a finger
## held on a button while the panel shut (or was covered) does not press it after the panel opens again.
func test_touch_taps_cancel_and_shut_panel():
	var root := Control.new()
	tree.root.add_child(root)
	var b := Button.new()
	b.position = Vector2(100, 100)
	b.size = Vector2(80, 44)
	root.add_child(b)
	await tree.process_frame
	var presses := [0]
	b.pressed.connect(func(): presses[0] += 1)
	var t := TouchTaps.new()
	var at := b.get_global_rect().get_center()
	var mk := func(i: int, p: Vector2, down: bool, cancel := false) -> InputEventScreenTouch:
		var st := InputEventScreenTouch.new()
		st.index = i
		st.position = p
		st.pressed = down
		st.canceled = cancel
		return st
	var emu := InputEventMouseButton.new()
	emu.device = InputEvent.DEVICE_ID_EMULATION
	emu.pressed = true
	var r := ""
	t.feed(emu, root, TouchTaps.EVERYWHERE)                       # the thumb is Godot's mouse finger
	t.feed(mk.call(0, Vector2(5, 5), true), root, TouchTaps.EVERYWHERE)
	t.feed(mk.call(1, at, true), root, TouchTaps.EVERYWHERE)
	t.feed(mk.call(1, at, false, true), root, TouchTaps.EVERYWHERE)  # touchcancel over the button
	if presses[0] != 0: r = "a cancelled touch pressed the button %d times" % presses[0]
	if r == "":
		t.feed(mk.call(1, at, true), root, TouchTaps.EVERYWHERE)
		t.feed(mk.call(2, Vector2(300, 300), true), root, TouchTaps.EVERYWHERE, false)   # panel shut meanwhile
		t.feed(mk.call(1, at, false), root, TouchTaps.EVERYWHERE)    # reopened, finger 1 lifts
		if presses[0] != 0: r = "a finger held across a shut panel pressed the button on reopen"
	if r == "":
		t.feed(mk.call(1, at, true), root, TouchTaps.EVERYWHERE)
		t.reset()                                                      # close() forgets fingers
		t.feed(mk.call(1, at, false), root, TouchTaps.EVERYWHERE)
		if presses[0] != 0: r = "a finger held across close() pressed the button"
	if r == "":
		t.feed(mk.call(1, at, true), root, TouchTaps.EVERYWHERE)
		t.feed(mk.call(1, at, false), root, TouchTaps.EVERYWHERE)    # a real second-finger tap still works
		if presses[0] != 1: r = "a normal second-finger tap pressed %d times (want 1)" % presses[0]
	root.queue_free()
	await tree.process_frame
	return r
