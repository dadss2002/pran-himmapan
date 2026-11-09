extends SceneTree
## Task 5 waypoints: the stone in its room (c2r0 "ปรางค์ร้าง", the hero beside it, sideways phone), and the travel
## list open on the c1r1 stone with all four stones unlocked (c1r1 marked "ที่นี่") on a phone held upright
## (780x1688) and sideways (1688x780; also a small phone sideways, 1334x750 = a 640 x 360 view, where the list
## takes one column to keep clear of the hero), touch controls on:
## xvfb-run -a -s "-screen 0 1800x1800x24" godot --path . --rendering-driver opengl3 --script tests/screenshots_m4b_waypoints.gd

const OUT := "res://docs/preview/m4b/"
const SAVE := "user://shots_m4b_waypoints_save.json"
const SETTINGS := "user://shots_m4b_waypoints_settings.json"
var g: Node2D

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

func _clean() -> void:
	for f in [SAVE, SETTINGS]:
		if FileAccess.file_exists(f): DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

func _quiet() -> void:
	for p in g.packs:
		p.calm = 1000.0
		p.set_physics_process(false)
		p.set_process(false)

func _orient(size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	root.size = size
	for i in 6: await physics_frame

func _run() -> void:
	_clean()
	g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = SAVE
	g.settings_path = SETTINGS
	g.layout_seed = 7
	root.add_child(g)
	await process_frame
	g.hud.touch_ui.visible = true
	for id in g.waypoints.ids: g.waypoints.unlock(id)
	# the stone in its room: c2r0, the hero a little left of it (off the stone, so no list)
	await _orient(Vector2i(1688, 780))
	g.go_to("c2r0", "", false)
	_quiet()
	g.hero.global_position = g.rooms.waypoint_landing("c2r0") + Vector2(-44, 6)
	for i in 30: await physics_frame        # the glow breathes up
	g.hud.toast.visible = false
	await _snap("waypoint_room.png")
	# the list on the c1r1 stone, upright and sideways
	g.go_to("c1r1", "", false)
	_quiet()
	for o in [[Vector2i(780, 1688), "portrait"], [Vector2i(1688, 780), "landscape"], [Vector2i(1334, 750), "landscape_small"]]:
		await _orient(o[0])
		g.hud.close_waypoints()
		g.hero.global_position = g.rooms.waypoint_landing("c1r1") + Vector2(0, 40)
		for i in 3: await physics_frame
		g.hero.global_position = g.rooms.waypoint_landing("c1r1")
		for i in 6: await physics_frame
		g.hud.toast.visible = false
		g.hud.layout(root.get_visible_rect().size)
		print("list open: ", g.hud.waypoints_open(), " at ", g.hud.waypoint_list.get_global_rect(), " columns ",
			g.hud.waypoint_list.grid.columns, " hero ", g.hero_screen_rect())
		await _snap("waypoint_list_%s.png" % o[1])
	_clean()
	quit(0)
