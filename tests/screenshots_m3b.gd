extends SceneTree
## M3b painted-map screenshots: xvfb-run -a godot --path . --rendering-driver opengl3 --script tests/screenshots_m3b.gd -- --touch

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
	await _snap("m3b_spawn_plaza.png")
	await _at(g.layout.pack_homes[0] + Vector2(-90, 60))
	await _snap("m3b_ruins_pack.png")
	await _at(Vector2(410, 980))
	await _snap("m3b_pond_road.png")
	await _at(Vector2(1720, 230))
	await _snap("m3b_shrine.png")
	await _at(Vector2(380, 1300))
	await _snap("m3b_arena.png")
	await _at(g.layout.pack_homes[2] + Vector2(-80, 0))
	await _snap("m3b_south_pond_pack.png")
	# under the leaves: feet right at a canopy's lower edge north of the plaza
	await _at(g.layout.hero_spawn + Vector2(0, -150))
	await _snap("m3b_under_leaves.png")
	# whole map
	var cam: Camera2D = hero.get_child(hero.get_child_count() - 1)
	g.hud.visible = false
	cam.limit_left = -4000; cam.limit_top = -4000; cam.limit_right = 8000; cam.limit_bottom = 8000
	cam.zoom = Vector2(1, 1) / 4.3
	await _at(Vector2(1032, 768))
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + "m3b_overview.png"))
	print("saved m3b_overview.png")
	quit(0)
