extends SceneTree
## Skill · gem screen, action button beside the selected gem's name (owner 2026-11-08, same fix as the bag):
## xvfb-run -a godot --path . --rendering-driver opengl3 --script tests/screenshots_skill_action.gd
## Saves docs/preview/m4b/skill_action_{portrait,portrait_iphone,landscape}.png (780x1688 / 1688x780; the
## iPhone shot forces iPhone Safari, so the bottom 64 px stay free). A socketed gem is selected (ถอดเจม).

const OUT := "res://docs/preview/m4b/"
const SAVE := "user://shots_skill_action_save.json"
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
	img.save_png(ProjectSettings.globalize_path(OUT + "skill_action_%s.png" % name))
	print("saved skill_action_%s.png %s" % [name, img.get_size()])

func _size(w: int, h: int) -> void:
	DisplayServer.window_set_size(Vector2i(w, h))
	root.size = Vector2i(w, h)
	await _frames(6)

## Opens the screen and selects the gem in ศรทะลวง's first slot; the panel refits by itself.
func _open() -> void:
	g.hud.skill_panel.close()
	g.hud.open_skills()
	g.hud.skill_panel.press_slot("piercing", 0)
	await _frames(2)

func _run() -> void:
	if FileAccess.file_exists(SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = SAVE
	root.add_child(g)
	await _frames(10)
	g.hero.set_physics_process(false)
	for p in g.packs: p.set_physics_process(false)
	g.hero.set_progress(10, 0)
	var inv: Inventory = g.hero.inventory
	inv.add_gem({"type": "split", "level": 3, "exp": 20, "rarity": "good", "opts": [{"k": "mp_cut", "v": 0.05}, {"k": "crit", "v": 0.03}]})
	g.hero.socket("piercing", 0, inv.slots.size() - 1)
	inv.add_gem({"type": "pierce", "level": 1, "exp": 0, "rarity": "common", "opts": []})
	await _size(780, 1688)
	await _open()
	await _snap("portrait")
	ScreenFit.ios_override = 1
	ScreenFit.standalone_override = 0
	await _open()
	await _snap("portrait_iphone")
	ScreenFit.ios_override = -1
	ScreenFit.standalone_override = -1
	await _size(1688, 780)
	await _open()
	await _snap("landscape")
	if FileAccess.file_exists(SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	quit(0)
