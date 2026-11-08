extends SceneTree
## M4d addendum 4 before/after shots: the whole room (512x512 world view, same camera) with its monsters on
## their spawn points, for a forest room next to c1r1, x2 and e0 (layout seed 7). Works on the code before
## Task 3e too (run it from a worktree of the earlier commit with PILES_TAG=before):
## PILES_TAG=after PILES_OUT=/abs/dir xvfb-run -a godot --path . --rendering-driver opengl3 --script tests/screenshots_m4b_piles.gd
## Also writes <out>/piles_<tag>.json: per room the monsters' positions and homes (for the sheet's circles).

var g: Node2D

func _initialize() -> void:
	_run()
	_watchdog()

func _watchdog() -> void:
	await create_timer(120.0).timeout
	print("watchdog: giving up")
	quit(1)

func _run() -> void:
	var tag := OS.get_environment("PILES_TAG")
	var out := OS.get_environment("PILES_OUT")
	if tag == "": tag = "after"
	if out == "": out = ProjectSettings.globalize_path("res://docs/preview/m4b")
	Wolf.elites_enabled = false
	var save := "user://shots_piles_save.json"
	if FileAccess.file_exists(save): DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = save
	g.settings_path = "user://shots_piles_settings.json"
	g.layout_seed = 7
	root.add_child(g)
	await process_frame
	g.hero.set_physics_process(false)
	g.hud.visible = false
	var near := ""
	for k in g.rooms.active.links:
		for half in [[k[0], k[2]], [k[2], k[0]]]:
			if half[0] == "c1r1" and String(half[1]).begins_with("c") and (near == "" or String(half[1]) < near): near = half[1]
	var dump := {}
	for id in [near, "x2", "e0"]:
		g.go_to(id, "", false)
		for p in g.packs:
			p.set_physics_process(false)
			p.set_process(false)
		g.hero.visible = false
		g.world_vp.size = Vector2i(g.layout.size_px())
		for i in 4: await process_frame
		var img: Image = g.world_vp.get_texture().get_image()
		var name := "piles_%s_%s.png" % [tag, id]
		img.save_png(out.path_join(name))
		print("saved ", name, " ", img.get_size())
		var mons := []
		for p in g.packs:
			for w in p.wolves:
				mons.append({"kind": p.kind, "pos": [w.position.x, w.position.y], "home": [w.home.x, w.home.y], "pack": g.packs.find(p)})
		dump[id] = mons
	var f := FileAccess.open(out.path_join("piles_%s.json" % tag), FileAccess.WRITE)
	f.store_string(JSON.stringify({"rooms": [near, "x2", "e0"], "monsters": dump}))
	f.close()
	quit(0)
