extends SceneTree
## Task 8 full map screenshots on a phone held sideways (1688x780) and upright (780x1688), touch controls on: seed 7,
## the hero walks from c1r1 towards the boss arena through up to 5 rooms (fog revealed along each walk, arrival to
## the next exit, so B11 shows only exits he passed near), then stands mid-room; the map is opened from the map
## button. Portrait: a room card is open (the first room tapped).
## xvfb-run -a godot --path . --rendering-driver opengl3 --script tests/screenshots_m4c_worldmap.gd

const OUT := "res://docs/preview/m4b/"
const SAVE := "user://shots_m4c_worldmap_save.json"
const SETTINGS := "user://shots_m4c_worldmap_settings.json"
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
	print("saved ", name, " ", img.get_size(), " drawn ", g.hud.world_map.drawn_ids(), " tile ", g.hud.world_map.tile)

## Shortest room path from `a` to `b` through this layout's warps.
func _route(a: String, b: String) -> Array:
	var prev := {a: ""}
	var q := [a]
	while not q.is_empty():
		var id: String = q.pop_front()
		if id == b: break
		for w in g.rooms.room(id).warps:
			if not prev.has(String(w.to)):
				prev[String(w.to)] = id
				q.append(String(w.to))
	var out := []
	var c := b
	while c != "":
		out.push_front(c)
		c = prev.get(c, "")
	return out

## Reveals the fog along a straight walk (room px).
func _walk_line(id: String, a: Vector2, b: Vector2) -> void:
	var n := int(a.distance_to(b) / 16.0) + 1
	for i in n + 1: g.fog.reveal(id, a.lerp(b, float(i) / n))

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
	g.hud.touch_ui.visible = true
	var route := _route("c1r1", "e0").slice(0, 5)
	print("route ", route)
	for i in route.size():
		var id: String = route[i]
		if i > 0:
			var via := ""
			for w in g.rooms.room(route[i - 1]).warps:
				if String(w.to) == id: via = String(w.to_warp)
			g.go_to(id, via, false)
		for p in g.packs:
			p.set_physics_process(false)
			p.set_process(false)
		var from: Vector2 = g.hero.global_position
		var mid: Vector2 = g.layout.size_px() / 2.0
		_walk_line(id, from, mid)
		if i + 1 < route.size():
			for w in g.rooms.room(id).warps:
				if String(w.to) == route[i + 1]: _walk_line(id, mid, Vector2(w.at[0], w.at[1]))
	# the hero also walked up to one exit into a room he has not entered: its "?" shows (B11: revealed exits only)
	var peek := false
	for id in route:
		for w in g.rooms.room(id).warps:
			if not peek and not g.fog.known(String(w.to)):
				_walk_line(id, Vector2(256, 256), Vector2(w.at[0], w.at[1]))
				peek = true
	g.go_to(route[route.size() - 2] if route.size() > 1 else "c1r1", "", false)   # stand in the room before the last
	g.hero.global_position = g.layout.size_px() / 2.0 + Vector2(20, 30)
	g.hero.facing = 3
	for o in [[Vector2i(1688, 780), "landscape", false], [Vector2i(780, 1688), "portrait", true]]:
		g.hud.close_map()
		DisplayServer.window_set_size(o[0])
		root.size = o[0]
		for i in 6: await process_frame
		g.hud.buttons.layout(root.get_visible_rect().size)
		g.hud.layout(root.get_visible_rect().size)
		await process_frame
		g.hud.open_map()
		if o[2]: g.hud.world_map.show_card(route[0])
		await _snap("worldmap_%s.png" % o[1])
	g.hud.close_map()
	quit(0)
