extends RefCounted
## M3k frame rate (owner 2026-11-07: "ทำให้มากกว่า 60fps"): the effect saver, physics
## interpolation for 120 Hz screens, and the 2x canvas cap for phones.

var tree: SceneTree

func setup(t: SceneTree) -> void:
	tree = t

func _feed(s: PerfSaver, seconds: float, fps: float) -> bool:
	var changed := false
	var n := int(round(seconds * 60.0))
	for i in n:
		if s.step(1.0 / 60.0, fps): changed = true
	return changed

func test_saver_waits_for_a_steady_drop():
	var s := PerfSaver.new()
	_feed(s, 2.5, 40.0)
	if s.on: return "on after 2.5 s under 57 (want 3 s)"
	_feed(s, 0.2, 60.0)                  # recovered: the count starts again
	_feed(s, 2.5, 40.0)
	if s.on: return "a short recovery did not reset the count"
	_feed(s, 0.6, 40.0)
	if not s.on: return "still off after 3.1 s under 57"
	_feed(s, 30.0, 58.0)                 # 58 is not good enough to leave
	if not s.on: return "left the saver at 58 fps"
	_feed(s, 9.0, 60.0)
	if not s.on: return "left after 9 s at 60 (want 10 s)"
	_feed(s, 1.2, 60.0)
	if s.on: return "still on after 10 s at 60 fps"
	return ""

func test_saver_keeps_gameplay_effects():
	for f in ["roll_dust", "pickup_pop"]:
		if not PerfSaver.decorative(f): return "%s should be skipped by the saver" % f
	for f in ["hit_spark", "level_up", "spread_burst", "water_ripple"]:
		if PerfSaver.decorative(f): return "%s must not be skipped as a one-shot" % f
	return ""

func _ground() -> Node:
	var g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = "user://test_m3k_save.json"
	if FileAccess.file_exists(g.save_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(g.save_path))
	tree.root.add_child(g)
	await tree.process_frame
	await tree.process_frame
	return g

func test_saver_hides_ripples_and_dust_and_tells_the_meter():
	var g = await _ground()
	var r := ""
	g.go_to("c0r2", "", false)
	var fx: Array = g.forest.fx_nodes
	if fx.is_empty(): r = "c0r2 should have a pond ripple"
	else:
		g.saver.on = true
		g.apply_saver()
		var before: int = g.stage.get_child_count()
		g._fx("roll_dust", g.hero.global_position)
		if fx[0].visible or fx[0].is_playing(): r = "ripple still showing with the saver on"
		elif g.stage.get_child_count() != before: r = "roll dust drawn with the saver on"
		elif not g.hud.fps_text(60).ends_with("ประหยัด"): r = "meter does not say ประหยัด: %s" % g.hud.fps_text(60)
		else:
			g._fx("hit_spark", g.hero.global_position)
			if g.stage.get_child_count() != before + 1: r = "hit spark skipped by the saver"
			else:
				g.go_to("c1r3", "", false)          # a new room keeps the saver's choice
				if g.forest.fx_nodes.is_empty() or g.forest.fx_nodes[0].visible: r = "new room shows ripples with the saver on"
				else:
					g.saver.on = false
					g.apply_saver()
					if not g.forest.fx_nodes[0].visible or not g.forest.fx_nodes[0].is_playing(): r = "ripple not back after the saver"
					elif g.hud.fps_text(60).contains("ประหยัด"): r = "meter still says ประหยัด"
	g.queue_free()
	await tree.process_frame
	return r

func test_world_is_interpolated_and_ui_is_not():
	if not ProjectSettings.get_setting("physics/common/physics_interpolation", false): return "physics interpolation is off"
	var g = await _ground()
	var r := ""
	if not g.hero.is_physics_interpolated(): r = "hero not interpolated"
	elif g.packs.size() > 0 and g.packs[0].wolves.size() > 0 and not g.packs[0].wolves[0].is_physics_interpolated(): r = "monsters not interpolated"
	elif g.hud.is_physics_interpolated(): r = "HUD is interpolated (it moves in _process)"
	elif g.overlay.is_physics_interpolated(): r = "damage text layer is interpolated"
	g.queue_free()
	await tree.process_frame
	return r

func test_web_canvas_capped_at_2x_on_phones():
	var cfg := FileAccess.open("res://export_presets.cfg", FileAccess.READ).get_as_text()
	var line := ""
	for l in cfg.split("\n"):
		if l.begins_with("html/head_include="): line = l
	if line == "": return "no head include in the Web preset"
	for want in ["devicePixelRatio", "d>2", "return 2;", "iPhone"]:
		if not line.contains(want): return "head include is missing %s" % want
	return ""
