extends RefCounted
## Forest rooms data (RoomSet): links, warps, reachability, arrivals, and that the hero can really
## walk every route without getting stuck.

const LINKS := [["c0r0:south", "c0r1:north"], ["c0r1:south", "c0r2:north"], ["c0r2:south", "c0r3:north"],
	["c0r1:east", "c1r1:west"], ["c1r0:south", "c1r1:north"], ["c1r1:east", "c2r1:west"],
	["c2r0:south", "c2r1:north"], ["c2r1:south", "c2r2:north"], ["c0r2:east", "c1r2:west"],
	["c1r2:south", "c1r3:north"], ["c1r3:east", "c2r3:west"],
	# M4b: e0 is the only arena (w1, w3, e2 removed; c0r1 west, c0r3 west, c2r2 east are dead ends)
	["e0:west", "c2r0:east"]]

var tree: SceneTree

func setup(t: SceneTree) -> void:
	tree = t

func test_rooms_data_valid():
	var rs := RoomSet.open()
	if rs == null: return "data/rooms.json missing"
	if rs.ids().size() != 13: return "%d rooms (12 map + arena e0)" % rs.ids().size()
	if rs.start != "c1r1": return "start %s" % rs.start
	var errs := rs.validate()
	return "" if errs.is_empty() else "%d problems, first: %s" % [errs.size(), errs.slice(0, 4)]

## M4b: each room has its own size, read from its picture (all 512x512 now; old rooms were 688x384).
func test_room_sizes_from_rooms_json():
	var rs := RoomSet.open()
	for id in rs.ids():
		var l := rs.layout(id)
		if l.size_px() != Vector2(512, 512): return "%s layout size %s (want 512x512)" % [id, l.size_px()]
		if l.cols * l.cell != 512 or l.rows * l.cell != 512: return "%s walk grid %dx%d cells" % [id, l.cols, l.rows]
		var tex: Texture2D = load(String(rs.room(id).image))
		if tex == null or Vector2(tex.get_size()) != l.size_px(): return "%s picture size differs from layout" % id
	return ""

## Pre-M4b data: a global 688x384 size and rooms without their own "size" still load at that size,
## and a warp arrival lands on ground a hero-sized body fits on.
func test_old_format_rooms_use_global_size():
	var rows: Array = []
	for y in 48:
		var row := ""
		for x in 86:
			row += "#" if x == 0 or y == 0 or x == 85 or y == 47 or (x >= 60 and x <= 64 and y >= 10 and y <= 40) else "."
		rows.append(row)
	var room := {"image": "res://assets/map/painted/raw/c1r1.png", "overlay": null, "blocked": rows, "fx": [],
		"monsters": [], "warps": [{"id": "east", "at": [676, 196], "to": "a", "to_warp": "west"},
		{"id": "west", "at": [12, 196], "to": "a", "to_warp": "east"}]}
	var rs := RoomSet.from_dict({"start": "a", "size": [688, 384], "cell": 8, "rooms": {"a": room}})
	var l := rs.layout("a")
	if l.size_px() != Vector2(688, 384): return "old room layout size %s (want 688x384)" % l.size_px()
	for w in ["east", "west"]:
		var p := rs.arrival("a", w)
		var c := Vector2i((p / 8.0).floor())
		if not l.roomy(c.x, c.y): return "arrival %s at %s is not open ground" % [w, p]
		var d := p.distance_to(rs.warp_at("a", w))
		if d <= RoomSet.REARM or d > 60.0: return "arrival %s %.0f px from its warp" % [w, d]
		# toward the 688x384 room's middle, not a 512x512 one's
		if absf(p.y - 196.0) > 12.0: return "arrival %s at %s drifts off the warp's row" % [w, p]
	if not l.roomy(int(l.hero_spawn.x) / 8, int(l.hero_spawn.y) / 8): return "spawn %s not open ground" % l.hero_spawn
	return ""

## Every room's spawn and every warp arrival stand on open ground (a hero-sized body fits) that
## reaches the room's warps.
func test_spawns_and_arrivals_on_open_ground():
	var rs := RoomSet.open()
	for id in rs.ids():
		var l := rs.layout(id)
		var pts := {"spawn": rs.spawn(id)}
		for w in rs.room(id).warps: pts["arrival " + String(w.id)] = rs.arrival(id, w.id)
		for k in pts:
			var p: Vector2 = pts[k]
			if not l.roomy(int(p.x) / l.cell, int(p.y) / l.cell): return "%s %s at %s is not open ground" % [id, k, p]
			for w in rs.room(id).warps:
				if not l.reachable(p, rs.warp_at(id, w.id)): return "%s %s cannot reach warp %s" % [id, k, w.id]
	return ""

func test_links_are_pairs():
	var rs := RoomSet.open()
	var want := {}
	for l in LINKS:
		want[l[0] + ">" + l[1]] = true
		want[l[1] + ">" + l[0]] = true
	var got := {}
	for id in rs.ids():
		for w in rs.room(id).warps: got["%s:%s>%s:%s" % [id, w.id, w.to, w.to_warp]] = true
	for k in want:
		if not got.has(k): return "missing link %s" % k
	for k in got:
		if not want.has(k): return "extra link %s" % k
	return ""

func test_every_room_reachable_from_start():
	var rs := RoomSet.open()
	var seen := {rs.start: true}
	var todo := [rs.start]
	while not todo.is_empty():
		var id: String = todo.pop_back()
		for w in rs.room(id).warps:
			if not seen.has(String(w.to)):
				seen[String(w.to)] = true
				todo.append(String(w.to))
	return "" if seen.size() == 13 else "only %d rooms reachable: %s" % [seen.size(), seen.keys()]

func test_warps_connected_in_room():
	var rs := RoomSet.open()
	for id in rs.ids():
		var l := rs.layout(id)
		var ws: Array = rs.room(id).warps
		for a in ws:
			for b in ws:
				if not l.reachable(rs.warp_at(id, a.id), rs.warp_at(id, b.id)):
					return "%s: %s cannot reach %s" % [id, a.id, b.id]
	return ""

func test_arrival_clear_of_warp():
	var rs := RoomSet.open()
	for id in rs.ids():
		var l := rs.layout(id)
		for w in rs.room(id).warps:
			var p := rs.arrival(id, w.id)
			var d := p.distance_to(rs.warp_at(id, w.id))
			if l.blocked_at(p): return "%s %s arrival blocked" % [id, w.id]
			if d <= RoomSet.REARM or d > 60.0: return "%s %s arrival %.0f px from the warp" % [id, w.id, d]
	return ""

func test_no_stray_specks():
	var rs := RoomSet.open()
	for id in rs.ids():
		var l := rs.layout(id)
		# a walkable cell with no walkable 4-neighbour is a speck the smoothing should have removed
		for y in range(1, l.rows - 1):
			for x in range(1, l.cols - 1):
				if l.cell_blocked(x, y): continue
				if l.cell_blocked(x + 1, y) and l.cell_blocked(x - 1, y) and l.cell_blocked(x, y + 1) and l.cell_blocked(x, y - 1):
					return "%s: lone walkable cell at %d,%d" % [id, x, y]
	return ""

## The hero (real physics, real feet shape) follows the walk route from the spawn to every warp and
## between every pair of warps, in every room; it must get there in time and never stay stuck.
func test_hero_walks_every_route():
	var rs := RoomSet.open()
	var hero: Hero = load("res://scenes/hero.tscn").instantiate()
	var speed := Balance.num("hero.walk")
	var fails := []
	for id in rs.ids():
		var root := Node2D.new()
		tree.root.add_child(root)
		var l := rs.layout(id)
		var m := PaintedMap.new()
		root.add_child(m)
		m.build(l)
		var h: Hero = load("res://scenes/hero.tscn").instantiate()
		root.add_child(h)
		h.set_physics_process(false)
		var nav := l.make_nav()
		var points := [l.hero_spawn]
		for w in rs.room(id).warps: points.append(rs.warp_at(id, w.id))
		for a in points:
			for b in points:
				if a == b: continue
				h.global_position = a
				await tree.physics_frame
				var path := nav.get_point_path(Vector2i((a / 8.0).floor()), Vector2i((b / 8.0).floor()))
				var length := 0.0
				for i in range(1, path.size()): length += path[i].distance_to(path[i - 1])
				var frames := int((length / speed * 1.6 + 1.0) * 60.0)
				var k := 1
				for f in frames:
					while k < path.size() - 1 and h.global_position.distance_to(path[k]) < 6.0: k += 1
					var target: Vector2 = path[mini(k, path.size() - 1)] if not path.is_empty() else b
					var dir := target - h.global_position
					if h.global_position.distance_to(b) < 12.0: break
					h.step(1.0 / 60.0, dir.normalized() if dir.length() > 1.0 else Vector2.ZERO)
					await tree.physics_frame
				if h.global_position.distance_to(b) >= 12.0:
					fails.append("%s %s->%s stopped at %s" % [id, a, b, h.global_position])
		root.queue_free()
		await tree.process_frame
	hero.free()
	return "" if fails.is_empty() else "%d routes failed, e.g. %s" % [fails.size(), fails.slice(0, 3)]
