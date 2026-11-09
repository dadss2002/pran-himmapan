extends SceneTree
## Bag action button beside the item name (owner 2026-11-08 "กดสวมใส่ไม่ได้"):
## xvfb-run -a godot --path . --rendering-driver opengl3 --script tests/screenshots_bag_action.gd
## Saves docs/preview/m4b/bag_action_{portrait,portrait_iphone,landscape}.png.

const OUT := "res://docs/preview/m4b/"
const SAVE := "user://shots_bag_action_save.json"
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
	img.save_png(ProjectSettings.globalize_path(OUT + "bag_action_%s.png" % name))
	print("saved bag_action_%s.png %s" % [name, img.get_size()])

func _size(w: int, h: int) -> void:
	DisplayServer.window_set_size(Vector2i(w, h))
	root.size = Vector2i(w, h)
	await _frames(6)

func _open() -> void:
	g.hud.bag_panel.close()
	g.hud.open_bag()
	g.hud.bag_panel.select(g.hero.inventory.slots.size() - 1)
	await _frames(2)

func _run() -> void:
	if FileAccess.file_exists(SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = SAVE
	root.add_child(g)
	await _frames(10)
	g.hero.set_physics_process(false)
	for p in g.packs: p.set_physics_process(false)
	g.hero.set_progress(5, 0)
	g.hero.inventory.add_item({"base": "bow_buffalo_horn", "rarity": "good", "level": 5, "opts": [{"k": "atk_speed", "v": 0.06}, {"k": "crit", "v": 0.009}]})
	await _size(780, 1688)
	await _open()
	await _snap("portrait")
	ScreenFit.ios_override = 1          # iPhone Safari: the panel refits by itself (refresh), no manual layout
	ScreenFit.standalone_override = 0
	await _open()
	await _snap("portrait_iphone")
	ScreenFit.ios_override = -1
	ScreenFit.standalone_override = -1
	await _size(1688, 780)
	await _open()
	await _snap("landscape")
	quit(0)
