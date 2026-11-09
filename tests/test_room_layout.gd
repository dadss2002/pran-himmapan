extends RefCounted
## M4d random Diablo-style layout (RoomLayout, spec docs/superpowers/specs/2026-11-08-m4d-random-layout.md):
## made fresh each session from a seed; c1r1 in the middle, e0 farthest on an east-facing exit, exits always
## match, every room reachable, at least one loop, dead ends without warps, fixed M4b layout as the fallback.

const TMP_SAVE := "user://test_layout_save.json"
const SEEDS := 200
const SIDE_DIR := {"north": Vector2i(0, -1), "south": Vector2i(0, 1), "east": Vector2i(1, 0), "west": Vector2i(-1, 0)}
const OPP := {"north": "south", "south": "north", "east": "west", "west": "east"}

var tree: SceneTree
var _table := {}

func setup(t: SceneTree) -> void:
	tree = t

func _rooms() -> Dictionary:
	if _table.is_empty(): _table = RoomSet.open().exit_table()
	return _table

func _ex(id: String) -> Array:
	return _rooms()[id].exits

## Rooms walked from c1r1 over `links` (written here, not RoomLayout's, so the tests check it independently).
func _walk(links: Array, skip := "") -> Dictionary:
	var dist := {"c1r1": 0}
	var todo := ["c1r1"]
	while not todo.is_empty():
		var id: String = todo.pop_front()
		for k in links:
			for h in [[k[0], k[2]], [k[2], k[0]]]:
				if h[0] == id and h[1] != skip and not dist.has(h[1]):
					dist[h[1]] = dist[id] + 1
					todo.append(h[1])
	return dist

func test_exit_table_from_rooms_json():
	var want := {"c1r1": "NEW", "c0r1": "NESW", "x1": "NESW", "x2": "NESW", "x3": "NESW", "c0r2": "NES",
		"c2r1": "NSW", "c0r0": "ES", "c0r3": "NW", "c1r2": "SW", "c1r3": "NE", "c2r0": "ES", "c2r2": "NE",
		"c1r0": "S", "c2r3": "W", "e0": "W"}
	var full := {"N": "north", "E": "east", "S": "south", "W": "west"}
	var t := _rooms()
	if t.size() != want.size(): return "%d rooms with exits (want %d)" % [t.size(), want.size()]
	for id in want:
		if not t.has(id): return "%s missing" % id
		var sides: Array = []
		for c in String(want[id]): sides.append(full[c])
		var got: Array = t[id].exits.duplicate()
		got.sort()
		sides.sort()
		if got != sides: return "%s exits %s (spec %s)" % [id, got, sides]
	var rs := RoomSet.open()
	var names := {"x1": "ทุ่งต้นไม้ตาย", "x2": "เนินหินกลางป่า", "x3": "สะพานไม้ข้ามลำธาร"}
	for id in names:
		if String(rs.room(id).get("name", "")) != names[id]: return "%s name '%s'" % [id, rs.room(id).get("name", "")]
	return ""

func test_start_in_middle_and_no_fallback():
	for s in SEEDS:
		var l := RoomLayout.generate(s, _rooms())
		if l.fallback: return "seed %d fell back to the fixed layout" % s
		if l.pos.get("c1r1") != Vector2i(3, 3): return "seed %d: c1r1 at %s" % [s, l.pos.get("c1r1")]
		for id in l.pos:
			var p: Vector2i = l.pos[id]
			if p.x < 0 or p.y < 0 or p.x > 6 or p.y > 6: return "seed %d: %s outside 7x7 at %s" % [s, id, p]
	return ""

## Every room used once, all reachable from c1r1 over the links.
func test_all_rooms_reachable():
	for s in SEEDS:
		var l := RoomLayout.generate(s, _rooms())
		if l.pos.size() != _rooms().size(): return "seed %d placed %d of %d rooms" % [s, l.pos.size(), _rooms().size()]
		var cells := {}
		for id in l.pos:
			if cells.has(l.pos[id]): return "seed %d: %s and %s share %s" % [s, id, cells[l.pos[id]], l.pos[id]]
			cells[l.pos[id]] = id
		var d := _walk(l.links)
		if d.size() != _rooms().size(): return "seed %d: only %d rooms reachable" % [s, d.size()]
	return ""

## Every neighbouring pair: exit meets exit (and is linked), wall meets wall. Every link joins neighbours'
## facing exits.
func test_exits_match_every_neighbour():
	for s in SEEDS:
		var l := RoomLayout.generate(s, _rooms())
		var at := {}
		for id in l.pos: at[l.pos[id]] = id
		var linked := {}
		for k in l.links:
			if Vector2i(l.pos[k[0]]) + SIDE_DIR[k[1]] != Vector2i(l.pos[k[2]]): return "seed %d: link %s not between neighbours" % [s, k]
			if OPP[k[1]] != k[3]: return "seed %d: link %s sides do not face" % [s, k]
			if not (k[1] in _ex(k[0])) or not (k[3] in _ex(k[2])): return "seed %d: link %s on a wall" % [s, k]
			linked[k[0] + ":" + k[1]] = true
			linked[k[2] + ":" + k[3]] = true
		for id in l.pos:
			for side in SIDE_DIR:
				var n: Vector2i = l.pos[id] + SIDE_DIR[side]
				if not at.has(n): continue
				var mine: bool = side in _ex(id)
				var theirs: bool = OPP[side] in _ex(at[n])
				if mine != theirs: return "seed %d: %s %s (%s) meets %s (%s)" % [s, id, side, mine, at[n], theirs]
				if mine and not linked.has(id + ":" + side): return "seed %d: %s %s faces %s but is not linked" % [s, id, side, at[n]]
	return ""

func test_at_least_one_loop():
	for s in SEEDS:
		var l := RoomLayout.generate(s, _rooms())
		var loops: int = l.links.size() - l.pos.size() + 1
		if loops < 1: return "seed %d has %d loops" % [s, loops]
	return ""

## e0 hangs on exactly one east-facing exit, and that exit is the farthest (rooms walked from c1r1)
## among all open east-facing exits where e0 would fit.
func test_boss_farthest_east():
	for s in SEEDS:
		var l := RoomLayout.generate(s, _rooms())
		var into: Array = []
		for k in l.links:
			if k[0] == "e0" or k[2] == "e0": into.append(k)
		if into.size() != 1 or into[0][2] != "e0" or into[0][1] != "east": return "seed %d: e0 links %s" % [s, into]
		var rest: Array = []
		for k in l.links:
			if k != into[0]: rest.append(k)
		var d := _walk(rest)
		var at := {}
		for id in l.pos:
			if id != "e0": at[l.pos[id]] = id
		var far := -1
		for id in at.values():
			if not ("east" in _ex(id)): continue
			var c: Vector2i = l.pos[id] + Vector2i(1, 0)
			if c.x > 6 or at.has(c): continue
			var ok := true
			for side in ["north", "south", "east"]:   # e0 has walls there: no neighbour exit may face it
				var n: Vector2i = c + SIDE_DIR[side]
				if at.has(n) and OPP[side] in _ex(at[n]): ok = false
			if ok: far = maxi(far, int(d[id]) + 1)
		var got := int(d[into[0][0]]) + 1
		if got != far: return "seed %d: e0 %d rooms from c1r1, farthest east spot %d" % [s, got, far]
		for id in d:                       # and no room is farther from c1r1 than e0 ("e0 อยู่ไกลสุดเสมอ")
			if int(d[id]) > got: return "seed %d: %s is %d rooms away, e0 only %d" % [s, id, d[id], got]
	return ""

func test_same_seed_same_layout():
	var differ := 0
	for s in 20:
		var a := RoomLayout.generate(s, _rooms())
		var b := RoomLayout.generate(s, _rooms())
		if a != b: return "seed %d gave two layouts" % s
		if a.pos != RoomLayout.generate(s + 1000, _rooms()).pos: differ += 1
	return "" if differ >= 18 else "only %d of 20 seed pairs differ" % differ

## 0 tries, or rooms that can never make a valid layout (e0 with no west exit) → the fixed M4b layout.
func test_failure_falls_back_to_m4b_layout():
	var want: Array = []
	for k in [["c0r0:south", "c0r1:north"], ["c0r1:south", "c0r2:north"], ["c0r2:south", "c0r3:north"],
			["c0r1:east", "c1r1:west"], ["c1r0:south", "c1r1:north"], ["c1r1:east", "c2r1:west"],
			["c2r0:south", "c2r1:north"], ["c2r1:south", "c2r2:north"], ["c0r2:east", "c1r2:west"],
			["c1r2:south", "c1r3:north"], ["c1r3:east", "c2r3:west"], ["c2r0:east", "e0:west"]]:
		var a: PackedStringArray = k[0].split(":")
		var b: PackedStringArray = k[1].split(":")
		want.append([a[0], a[1], b[0], b[1]])
	var bad := _rooms().duplicate(true)
	bad["e0"] = {"exits": ["north"], "arena": true}
	for l in [RoomLayout.generate(7, _rooms(), 0), RoomLayout.generate(7, bad)]:
		if not l.fallback: return "no fallback flag"
		if l.links != want: return "fallback links %s" % [l.links]
		if l.pos.get("c1r1") != Vector2i(3, 3) or l.pos.get("e0") != Vector2i(5, 2): return "fallback places %s" % [l.pos]
	var rs := RoomSet.open()
	rs.use_layout(RoomLayout.generate(7, _rooms(), 0))
	var errs := rs.validate()
	if not errs.is_empty(): return "fallback layout: %s" % [errs.slice(0, 3)]
	if String(rs.warp("c1r1", "west").to) != "c0r1" or String(rs.warp("c2r0", "east").to) != "e0": return "fallback warps wrong"
	return ""

## A dead-end exit (no neighbour) has no warp; every linked exit has exactly one warp at its painted point.
func test_dead_ends_have_no_warp():
	var rs := RoomSet.open()
	var dead_seen := 0
	for s in 30:
		var l := RoomLayout.generate(s, rs.exit_table())
		rs.use_layout(l)
		var linked := {}
		for k in l.links:
			linked[k[0] + ":" + k[1]] = k[2] + ":" + k[3]
			linked[k[2] + ":" + k[3]] = k[0] + ":" + k[1]
		for id in rs.ids():
			var ws: Array = rs.room(id).warps
			var sides := {}
			for w in ws:
				var key := id + ":" + String(w.id)
				if not linked.has(key): return "seed %d: %s has a warp on a dead end" % [s, key]
				if linked[key] != String(w.to) + ":" + String(w.to_warp): return "seed %d: %s leads to %s:%s" % [s, key, w.to, w.to_warp]
				if Vector2(w.at[0], w.at[1]) != Vector2(rs.exit(id, String(w.id)).at[0], rs.exit(id, String(w.id)).at[1]): return "seed %d: %s warp off its exit point" % [s, key]
				sides[String(w.id)] = true
			for e in rs.exits(id):
				var key := id + ":" + String(e.id)
				if linked.has(key) and not sides.has(String(e.id)): return "seed %d: linked %s has no warp" % [s, key]
				if not linked.has(key): dead_seen += 1
	return "" if dead_seen > 0 else "no dead end seen in 30 seeds"

func test_validate_50_random_seeds():
	var rs := RoomSet.open()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in 50:
		var s := rng.randi()
		rs.use_layout(RoomLayout.generate(s, rs.exit_table()))
		var errs := rs.validate()
		if not errs.is_empty(): return "seed %d: %d problems, first %s" % [s, errs.size(), errs.slice(0, 3)]
	return ""

## Every painted exit point (even ones that are dead ends this session) stands on open ground that the
## room's spawn reaches, so any layout is playable.
func test_every_exit_point_open_and_reachable():
	var rs := RoomSet.open()
	for id in rs.ids():
		var l := rs.layout(id)
		for e in rs.exits(id):
			var p := Vector2(e.at[0], e.at[1])
			if not l.roomy(int(p.x) / l.cell, int(p.y) / l.cell): return "%s exit %s at %s not open ground" % [id, e.id, p]
			if not l.reachable(l.hero_spawn, p): return "%s exit %s unreachable from the spawn" % [id, e.id]
			var a := rs.arrival(id, String(e.id))
			if not l.reachable(a, l.hero_spawn): return "%s arrival %s cannot reach the spawn" % [id, e.id]
	return ""

func _ground(seed: int) -> Node2D:
	if FileAccess.file_exists(TMP_SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))
	var g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = TMP_SAVE
	g.layout_seed = seed
	tree.root.add_child(g)
	return g

## A real session: start in c1r1, follow the warps along a shortest route to e0 (the hero steps on each
## ring and the fade runs); every room arrived in is the one the layout says, and each exit label names it.
func test_session_walks_c1r1_to_e0():
	for s in [3, 11, 58]:
		var g := _ground(s)
		await tree.physics_frame
		var r := ""
		if g.room_id != "c1r1": r = "seed %d: session starts in %s" % [s, g.room_id]
		var l := RoomLayout.generate(s, g.rooms.exit_table())
		if r == "" and g.rooms.active != l: r = "seed %d: the session does not use its seed's layout" % s
		var d := _walk_from(l.links, "e0")      # rooms left to walk to e0
		var steps := 0
		while r == "" and g.room_id != "e0" and steps < 20:
			steps += 1
			var here: String = g.room_id
			var next: Dictionary = {}
			for w in g.rooms.room(here).warps:
				if int(d.get(String(w.to), 99)) == int(d[here]) - 1: next = w
			if next.is_empty():
				r = "seed %d: no warp onward from %s" % [s, here]
				break
			for wn in g.warps:
				var want := "→ " + String(g.rooms.room(wn.to_room).name)
				if wn.label.get_node("Text").text != want: r = "seed %d: %s %s label '%s' but leads to %s" % [s, here, wn.warp_id, wn.label.get_node("Text").text, wn.to_room]
				elif wn.to_arena != (wn.to_room == "e0"): r = "seed %d: %s %s arena mark wrong" % [s, here, wn.warp_id]
			if r != "": break
			for p in g.packs: p.process_mode = Node.PROCESS_MODE_DISABLED
			g.hero.set_physics_process(false)
			g.hero.health.setup(100000)
			g.hero.global_position = g.rooms.warp_at(here, String(next.id))
			for i in 90:
				await tree.physics_frame
				if g.room_id != here and not g.warping: break
			if g.room_id != String(next.to): r = "seed %d: %s %s took us to %s, not %s" % [s, here, next.id, g.room_id, next.to]
			elif g.hero.global_position != g.rooms.arrival(g.room_id, String(next.to_warp)): r = "seed %d: arrived at %s, not the %s arrival" % [s, g.hero.global_position, next.to_warp]
		if r == "" and g.room_id != "e0": r = "seed %d: never reached e0 (in %s)" % [s, g.room_id]
		if r == "" and steps != int(d["c1r1"]): r = "seed %d: %d warps to e0, layout says %d" % [s, steps, d["c1r1"]]
		g.queue_free()
		await tree.process_frame
		if r != "": return r
	return ""

func _walk_from(links: Array, from: String) -> Dictionary:
	var dist := {from: 0}
	var todo := [from]
	while not todo.is_empty():
		var id: String = todo.pop_front()
		for k in links:
			for h in [[k[0], k[2]], [k[2], k[0]]]:
				if h[0] == id and not dist.has(h[1]):
					dist[h[1]] = dist[id] + 1
					todo.append(h[1])
	return dist

## Two sessions without a fixed seed get their own random layouts; the saved room is not used (always
## c1r1), and the save stays loadable with the session's seed in it.
func test_new_session_new_layout_and_start_in_c1r1():
	var g1 := _ground(-1)
	await tree.physics_frame
	g1.go_to("c1r0", "", false)
	var seed1: int = g1.session_seed
	var pos1: Dictionary = g1.rooms.active.pos
	g1.queue_free()
	await tree.process_frame
	var st := SaveGame.load_or_new(TMP_SAVE)
	var r := ""
	if String(st.get("room", "")) != "c1r0": r = "save did not keep working (room %s)" % st.get("room", "")
	elif int(st.get("seed", -1)) != seed1: r = "save seed %s, session %d" % [st.get("seed"), seed1]
	var g2 = load("res://scenes/test_ground.tscn").instantiate()
	g2.save_path = TMP_SAVE                         # keep the save made in c1r0
	tree.root.add_child(g2)
	await tree.physics_frame
	if r == "" and g2.room_id != "c1r1": r = "second session started in %s" % g2.room_id
	elif r == "" and g2.hero.global_position != g2.rooms.spawn("c1r1"): r = "hero not at the c1r1 spawn"
	elif r == "" and g2.session_seed == seed1: r = "same seed twice (%d)" % seed1
	elif r == "" and g2.rooms.active.pos == pos1: r = "same layout twice"
	elif r == "" and g2.rooms.active.fallback: r = "session fell back"
	g2.queue_free()
	await tree.process_frame
	return r
