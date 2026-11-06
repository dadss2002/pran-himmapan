extends SceneTree
## M3b real-render screenshots: xvfb-run -a godot --path . --rendering-driver opengl3 --script tests/screenshots_m3b.gd -- --touch

const OUT := "res://docs/preview/"
const SAVE := "user://shots_m3b_save.json"
var g: Node2D
var hero: Hero

func _initialize() -> void:
	_run()
	_watchdog()

func _watchdog() -> void:
	await create_timer(90.0).timeout
	print("watchdog: giving up")
	quit(1)

func _snap(name: String) -> void:
	for i in 3: await process_frame
	var img := root.get_texture().get_image()
	img.resize(img.get_width() * 2, img.get_height() * 2, Image.INTERPOLATE_NEAREST)
	img.save_png(ProjectSettings.globalize_path(OUT + name))
	print("saved ", name)

func _frames(n: int) -> void:
	for i in n: await physics_frame

func _at(p: Vector2) -> void:
	hero.global_position = p
	hero.velocity = Vector2.ZERO
	await _frames(4)

func _run() -> void:
	seed(3)
	if FileAccess.file_exists(SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = SAVE
	root.add_child(g)
	await process_frame
	hero = g.hero
	hero.set_physics_process(false)
	for p in g.packs: p.set_process(false)
	await _frames(10)
	await _at(g.layout.hero_spawn)
	await _snap("m3b_spawn_path.png")
	await _at(Vector2(560, 470))
	await _snap("m3b_pack_clearing.png")
	await _at(Vector2(420, 800))
	await _snap("m3b_pond.png")
	await _at(Vector2(960, 960))
	await _snap("m3b_bridge.png")
	await _at(Vector2(700, 680))             # just above the tree's feet: drawn behind its canopy
	await _snap("m3b_behind_tree.png")
	await _at(Vector2(960, 1110))
	await _snap("m3b_south_pack.png")
	# whole map: zoom the camera out
	var cam: Camera2D = hero.get_child(hero.get_child_count() - 1)
	g.hud.visible = false
	cam.limit_left = -2000; cam.limit_top = -2000; cam.limit_right = 4000; cam.limit_bottom = 4000
	cam.zoom = Vector2(1, 1) / 3.6
	await _at(Vector2(960, 640))
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + "m3b_overview.png"))
	print("saved m3b_overview.png")
	quit(0)
