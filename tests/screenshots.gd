extends SceneTree
## Real-render screenshots (not headless):
## xvfb-run -a godot --path . --rendering-driver opengl3 --script tests/screenshots.gd -- --touch
## Writes docs/preview/m2a_*.png at 2x. Waits on physics frames (real time), not render frames.

const OUT := "res://docs/preview/"
var g: Node2D
var hero: Hero

func _initialize() -> void:
	_run()
	_watchdog()

func _watchdog() -> void:
	await create_timer(80.0).timeout
	print("watchdog: giving up")
	quit(1)

func _snap(name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.resize(img.get_width() * 2, img.get_height() * 2, Image.INTERPOLATE_NEAREST)
	var path := ProjectSettings.globalize_path(OUT + name)
	img.save_png(path)
	print("saved ", path)

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _wait_until(cond: Callable, max_frames := 600) -> bool:
	for i in max_frames:
		if cond.call(): return true
		await physics_frame
	return false

func _pack(level: int) -> WolfPack:
	for p in g.packs:
		if p.level == level: return p
	return null

const SHOT_SAVE := "user://shots_m2a_save.json"

func _run() -> void:
	seed(4)
	Combat.rng.seed = 4
	g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = SHOT_SAVE          # never touch the player's real save
	if FileAccess.file_exists(SHOT_SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(SHOT_SAVE))
	root.add_child(g)
	await process_frame          # _ready runs once the main loop starts
	hero = g.hero
	await _frames(20)
	await _snap("m2a_hud_touch.png")

	# joystick dragged up-right: hero walks
	var joy: TouchJoystick = g.hud.joystick
	joy.handle_touch(0, Vector2(120, 250), true)
	joy.handle_drag(0, Vector2(150, 225))
	await _frames(20)
	await _snap("m2a_joystick_drag.png")
	joy.handle_touch(0, Vector2(150, 225), false)

	# walk into the Lv1 pack and wait for a lunge warning
	var p1 := _pack(1)
	hero.global_position = p1.home + Vector2(150, 40)
	var warned := await _wait_until(func():
		for w in p1.wolves:
			if w.state == "lunge_warn": return true
		return false)
	await _frames(12)
	await _snap("m2a_lunge_warning.png")
	print("lunge warning seen: ", warned)

	# roll out of the lunge
	hero.try_dodge(Vector2(0, 1))
	await _frames(6)
	await _snap("m2a_roll.png")

	# shoot the pack: damage numbers + hit sparks
	Input.action_press("attack")
	var hit := await _wait_until(func():
		for c in g.get_children():
			if c is DamageNumber and c.modulate.a > 0.6: return true
		return false, 400)
	await _frames(2)
	await _snap("m2a_hit_numbers.png")
	print("damage number seen: ", hit)

	# keep shooting until a wolf dies
	var died := await _wait_until(func():
		for w in p1.wolves:
			if w.state == "dead" and w.body.modulate.a > 0.5: return true
		return false, 900)
	await _frames(36)   # let the fall-over clip finish before the fade
	await _snap("m2a_wolf_death.png")
	print("wolf death seen: ", died)
	Input.action_release("attack")

	# hero death: drop HP and let the pack finish it
	hero.health.hp = 1
	var p5 := _pack(5)
	hero.global_position = p5.home + Vector2(30, 0)
	var dead := await _wait_until(func(): return hero.state == "dead", 600)
	await _frames(25)
	await _snap("m2a_hero_death.png")
	print("hero death seen: ", dead)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SHOT_SAVE))
	quit(0)
