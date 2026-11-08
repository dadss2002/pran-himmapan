extends SceneTree
## M4d Task 3d HUD icon buttons screenshots (skills, bag, map, settings; the settings panel open; the
## map's "เร็ว ๆ นี้" note) on a phone held upright (780x1688) and sideways (1688x780), touch controls on:
## xvfb-run -a godot --path . --rendering-driver opengl3 --script tests/screenshots_m4b_hud.gd

const OUT := "res://docs/preview/m4b/"
const SAVE := "user://shots_m4b_hud_save.json"
const SETTINGS := "user://shots_m4b_hud_settings.json"
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

func _run() -> void:
	for f in [SAVE, SETTINGS]:
		if FileAccess.file_exists(f): DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = SAVE
	g.layout_seed = 7
	root.add_child(g)
	await process_frame
	g.hud.settings_path = SETTINGS          # never write the player's settings file
	g.hero.set_physics_process(false)
	for p in g.packs:
		p.set_physics_process(false)
		p.set_process(false)
	g.hud.touch_ui.visible = true
	for o in [[Vector2i(780, 1688), "portrait"], [Vector2i(1688, 780), "landscape"]]:
		DisplayServer.window_set_size(o[0])
		root.size = o[0]
		for i in 6: await physics_frame
		g.hud.settings_panel.visible = false
		g.hud.toast.visible = false
		g.hud.layout(root.get_visible_rect().size)
		await _snap("m4b_hud_%s.png" % o[1])
		g.hud.toggle_settings()
		g.hud.open_map()
		await _snap("m4b_hud_%s_settings.png" % o[1])
		g.hud.toggle_settings()
	quit(0)
