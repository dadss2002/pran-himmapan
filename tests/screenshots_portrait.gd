extends SceneTree
## Phone screenshots, portrait and landscape:
## xvfb-run -a godot --path . --rendering-driver opengl3 --script tests/screenshots_portrait.gd
## Saves docs/preview/phone_<name>.png at the window size: a 2x phone (portrait 780x1688, landscape
## 1688x780), so text sharpness is what a real phone shows. Run with -s "-screen 0 1800x1800x24".
## Add `-- --touch` to show the touch controls.

const OUT := "res://docs/preview/"
const SAVE := "user://shots_phone_save.json"
var g: Node2D

func _initialize() -> void:
	_run()
	_watchdog()

func _watchdog() -> void:
	await create_timer(90.0).timeout
	print("watchdog: giving up")
	quit(1)

func _frames(n: int) -> void:
	for i in n: await process_frame

func _snap(name: String) -> void:
	await _frames(4)
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + "phone_%s.png" % name))
	print("saved phone_%s.png %s" % [name, img.get_size()])

func _size(w: int, h: int) -> void:
	DisplayServer.window_set_size(Vector2i(w, h))
	root.size = Vector2i(w, h)
	await _frames(6)

func _run() -> void:
	if FileAccess.file_exists(SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = SAVE
	root.add_child(g)
	await _frames(10)
	g.hero.set_physics_process(false)
	g.go_to("c0r1", "", false)
	await _frames(4)
	g.hero.global_position = Vector2(290, 240)
	for p in g.packs:
		p.set_physics_process(false)
	await _size(780, 1688)
	await _snap("portrait")
	g.hud.open_bag()
	await _snap("portrait_bag")
	g.hud.bag_panel.close()
	g.hud.open_skills()
	await _snap("portrait_skills")
	g.hud.skill_panel.close()
	await _size(1688, 780)
	await _snap("landscape")
	quit(0)
