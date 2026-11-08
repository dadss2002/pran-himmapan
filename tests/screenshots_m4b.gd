extends SceneTree
## M4b/M4c exit markers screenshots:
## xvfb-run -a godot --path . --rendering-driver opengl3 --script tests/screenshots_m4b.gd
## The start room's north exit with the hero inside 48 px (ring, arrow, "→ ลานเสาหิน"), and the way
## into the arena from c2r0 (red label with the skull). Review 2026-11-08: the same exits on a phone
## held upright (780x1688) and sideways (1688x780) with the touch controls on - the labels clear of the
## HUD and the touch buttons.

const OUT := "res://docs/preview/m4b/"
const SAVE := "user://shots_m4b_save.json"
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
	img.save_png(ProjectSettings.globalize_path(OUT + name))
	print("saved ", name, " ", img.get_size())

func _frames(n: int) -> void:
	for i in n: await physics_frame

func _near(room: String, warp_id: String, off: Vector2) -> void:
	g.go_to(room, "", false)
	await _frames(2)
	for p in g.packs:
		p.set_physics_process(false)
		p.set_process(false)
	hero.global_position = g.rooms.warp_at(room, warp_id) + off
	hero.velocity = Vector2.ZERO
	await _frames(10)

func _run() -> void:
	seed(3)
	if FileAccess.file_exists(SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = SAVE
	root.add_child(g)
	await process_frame
	hero = g.hero
	hero.set_physics_process(false)
	await _frames(10)
	await _near("c1r1", "north", Vector2(0, 40))
	await _snap("m4b_exit_c1r1_north.png")
	await _near("c2r0", "east", Vector2(-40, 0))
	await _snap("m4b_exit_c2r0_arena.png")
	await _near("c1r1", "east", Vector2(-40, 0))
	await _snap("m4b_exit_c1r1_east.png")
	g.hud.touch_ui.visible = true
	for o in [[Vector2i(780, 1688), "portrait"], [Vector2i(1688, 780), "landscape"]]:
		DisplayServer.window_set_size(o[0])
		root.size = o[0]
		await _frames(6)
		await _near("c1r1", "north", Vector2(0, 40))
		await _snap("m4b_exit_%s_c1r1_north.png" % o[1])
		await _near("c1r2", "south", Vector2(0, -40))
		await _snap("m4b_exit_%s_c1r2_south.png" % o[1])
		await _near("c2r0", "east", Vector2(-40, 0))
		await _snap("m4b_exit_%s_c2r0_arena.png" % o[1])
		await _near("c1r1", "west", Vector2(40, 0))
		await _snap("m4b_exit_%s_c1r1_west.png" % o[1])
	quit(0)
