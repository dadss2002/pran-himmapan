extends SceneTree
## M4b/M4c Task 9 acceptance screenshots on a phone held sideways (1688x780) and upright (780x1688), touch
## controls on, seed 7. The hero walks the layout's warps from c1r1 (start) towards the e0 arena (fog revealed
## along each walk, as in screenshots_m4c_worldmap.gd); three rooms are shot where he arrives: c1r1, the first
## forest room on the way, and e0. Then the minimap (cropped and enlarged x3 from the room shot of the last room)
## and the full map (opened from the map button) in each orientation.
## xvfb-run -a godot --path . --rendering-driver opengl3 --script tests/screenshots_m4_acceptance.gd
## Out: docs/preview/m4b/acceptance_<room>_<landscape|portrait>.png, acceptance_minimap_*.png, acceptance_worldmap_*.png

const OUT := "res://docs/preview/m4b/"
const SAVE := "user://shots_m4_acceptance_save.json"
const SETTINGS := "user://shots_m4_acceptance_settings.json"
const SHAPES := [[Vector2i(1688, 780), "landscape"], [Vector2i(780, 1688), "portrait"]]
var g: Node2D

func _initialize() -> void:
	_run()
	_watchdog()

func _watchdog() -> void:
	await create_timer(240.0).timeout
	print("watchdog: giving up")
	quit(1)

func _snap(name: String) -> Image:
	for i in 4: await process_frame
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + name))
	print("saved ", name, " ", img.get_size(), " room ", g.room_id, " hero ", g.hero.global_position)
	return img

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
	if not prev.has(b): return []
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

func _still() -> void:
	for p in g.packs:
		p.set_physics_process(false)
		p.set_process(false)

func _shape(size: Vector2i) -> void:
	g.hud.close_map()
	DisplayServer.window_set_size(size)
	root.size = size
	for i in 6: await process_frame
	g.hud.buttons.layout(root.get_visible_rect().size)
	g.hud.layout(root.get_visible_rect().size)
	await process_frame

## Enters `id` from `from` (by the warp joining them; "" = the room's spawn), reveals the walk to the middle.
func _enter(from: String, id: String) -> void:
	var via := ""
	if from != "":
		for w in g.rooms.room(from).warps:
			if String(w.to) == id: via = String(w.to_warp)
	g.go_to(id, via, false)
	_still()
	_walk_line(id, g.hero.global_position, g.layout.size_px() / 2.0)

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
	var route := _route("c1r1", "e0")
	print("route ", route)
	if route.is_empty():
		print("e0 not reachable in this layout")
		quit(1)
		return
	# the rooms to shoot: the start, the first forest room after it, the arena
	var shots := ["c1r1", route[1] if route.size() > 2 else "", "e0"]
	var prev := ""
	for i in route.size():
		var id: String = route[i]
		await _enter(prev, id)
		if i + 1 < route.size():
			for w in g.rooms.room(id).warps:
				if String(w.to) == route[i + 1]: _walk_line(id, g.layout.size_px() / 2.0, Vector2(w.at[0], w.at[1]))
		if id in shots and id != "":
			var arrive: Vector2 = g.hero.global_position
			for s in SHAPES:
				await _shape(s[0])
				g.hero.global_position = arrive
				g.hero.facing = 0
				var img: Image = await _snap("acceptance_%s_%s.png" % [id, s[1]])
				if id == "e0":     # the minimap, cropped from this shot (window px) and enlarged x3
					var k: float = float(img.get_width()) / root.get_visible_rect().size.x
					var r: Rect2 = g.hud.minimap.get_global_rect().grow(6.0)
					var px := Rect2i(Vector2i(r.position * k), Vector2i(r.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
					var crop := img.get_region(px)
					crop.resize(crop.get_width() * 3, crop.get_height() * 3, Image.INTERPOLATE_NEAREST)
					crop.save_png(ProjectSettings.globalize_path(OUT + "acceptance_minimap_%s.png" % s[1]))
					print("saved acceptance_minimap_%s.png %s from %s" % [s[1], crop.get_size(), px])
		prev = id
	for s in SHAPES:
		await _shape(s[0])
		g.hud.map_button.pressed.emit()
		await _snap("acceptance_worldmap_%s.png" % s[1])
		print("  map drawn ", g.hud.world_map.drawn_ids(), " tile ", g.hud.world_map.tile)
	g.hud.close_map()
	for f in [SAVE, SETTINGS]:
		if FileAccess.file_exists(f): DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	quit(0)
