extends SceneTree
## M2b real-render screenshots: xvfb-run -a godot --path . --rendering-driver opengl3 --script tests/screenshots_m2b.gd -- --touch

const OUT := "res://docs/preview/"
const SAVE := "user://shots_m2b_save.json"
var g: Node2D
var hero: Hero

func _initialize() -> void:
	_run()
	_watchdog()

func _watchdog() -> void:
	await create_timer(100.0).timeout
	print("watchdog: giving up")
	quit(1)

func _snap(name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.resize(img.get_width() * 2, img.get_height() * 2, Image.INTERPOLATE_NEAREST)
	img.save_png(ProjectSettings.globalize_path(OUT + name))
	print("saved ", name)

func _frames(n: int) -> void:
	for i in n: await physics_frame

func _until(cond: Callable, max_frames := 600) -> bool:
	for i in max_frames:
		if cond.call(): return true
		await physics_frame
	return false

func _pack(level: int) -> WolfPack:
	for p in g.packs:
		if p.level == level: return p
	return null

func _run() -> void:
	seed(7)
	Combat.rng.seed = 7
	if FileAccess.file_exists(SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = SAVE
	g.loot_rng.seed = 3
	root.add_child(g)
	await process_frame
	hero = g.hero
	await _frames(10)

	# piercing arrow through the Lv1 pack
	var p1 := _pack(1)
	hero.global_position = p1.home + Vector2(170, 0)
	await _until(func():
		for w in p1.wolves:
			if w.state == "chase": return true
		return false, 120)
	await _frames(10)
	hero.try_skill("piercing")
	await _frames(28)      # release frame is ~0.36 s in
	await _snap("m2b_piercing.png")

	# shoot until a wolf dies and loot pops out
	Input.action_press("attack")
	var dropped := await _until(func(): return g.drops.size() > 0, 900)
	Input.action_release("attack")
	hero.try_dodge(Vector2(0, 1))      # step out of the pack so the drops are visible
	await _frames(20)
	await _snap("m2b_loot_magnet.png")
	print("loot seen: ", dropped)
	Input.action_press("attack")
	await _until(func(): return hero.inventory.gold > 0, 300)
	Input.action_release("attack")
	await _frames(10)
	await _snap("m2b_hud_exp_mp.png")

	# level-up: top the bar up and finish a wolf
	hero.exp = Progression.exp_to_next(hero.level) - 1
	Input.action_press("attack")
	var lv := hero.level
	var up := await _until(func(): return hero.level > lv, 900)
	Input.action_release("attack")
	await _frames(8)
	await _snap("m2b_level_up.png")
	print("level up seen: ", up)

	# spread at Lv3 vs the Lv3 pack
	hero.set_progress(3, 0)
	var p3 := _pack(3)
	hero.global_position = p3.home + Vector2(190, 10)
	await _frames(40)
	hero.mp = hero.max_mp()
	var fired := hero.try_skill("spread")
	await _frames(26)
	await _snap("m2b_spread.png")
	print("spread fired: ", fired)

	# potion: take damage, drink
	hero.health.hp = int(hero.health.max_hp * 0.3)
	hero.global_position = Vector2(960, 640)
	await _frames(5)
	hero.try_potion("hp")
	await _frames(4)
	await _snap("m2b_potion.png")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	quit(0)
