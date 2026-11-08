extends SceneTree
## Task 7 corner minimap screenshots on a phone held sideways (1688x780) and upright (780x1688), touch controls on:
## the start room partly revealed (a walk from the arrival), the hero mid-room; then the hero by the room's top-right
## corner, under the minimap, which fades to 30 %.
## xvfb-run -a godot --path . --rendering-driver opengl3 --script tests/screenshots_m4c_minimap.gd

const OUT := "res://docs/preview/m4b/"
const SAVE := "user://shots_m4c_minimap_save.json"
const SETTINGS := "user://shots_m4c_minimap_settings.json"
## The walk that reveals part of c1r1 (room px): from the arrival north along the path, then east.
const WALK := [Vector2(260, 372), Vector2(260, 320), Vector2(255, 270), Vector2(250, 220), Vector2(260, 170),
	Vector2(300, 150), Vector2(350, 150), Vector2(400, 160), Vector2(330, 165)]
var g: Node2D

func _initialize() -> void:
	_run()
	_watchdog()

func _watchdog() -> void:
	await create_timer(120.0).timeout
	print("watchdog: giving up")
	quit(1)

func _snap(name: String) -> void:
	for i in 3: await process_frame
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + name))
	print("saved ", name, " ", img.get_size(), " minimap opacity %.2f" % g.hud.minimap.modulate.a)

func _place(p: Vector2) -> void:
	g.hero.global_position = p
	g.hero.reset_physics_interpolation()
	for i in 3: await physics_frame
	await create_timer(MiniMap.FADE_TIME + 0.2).timeout

func _run() -> void:
	for f in [SAVE, SETTINGS]:
		if FileAccess.file_exists(f): DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = SAVE
	g.settings_path = SETTINGS
	g.layout_seed = 7
	root.add_child(g)
	await process_frame
	g.hero.set_physics_process(false)
	for p in g.packs:
		p.set_physics_process(false)
		p.set_process(false)
	g.hud.touch_ui.visible = true
	for p in WALK: g.fog.reveal(g.room_id, p)
	for o in [[Vector2i(1688, 780), "landscape", Vector2(482, 96)], [Vector2i(780, 1688), "portrait", Vector2(482, 130)]]:
		DisplayServer.window_set_size(o[0])
		root.size = o[0]
		for i in 6: await physics_frame
		g.hud.layout(root.get_visible_rect().size)
		await _place(WALK[WALK.size() - 1])
		g.hero.facing = 3                       # north-east
		await _snap("minimap_%s.png" % o[1])
		await _place(o[2])
		var hs: Rect2 = g.hero_screen_rect()
		print("hero on screen %s, minimap %s" % [hs, g.hud.minimap.get_global_rect()])
		await _snap("minimap_%s_faded.png" % o[1])
	quit(0)
