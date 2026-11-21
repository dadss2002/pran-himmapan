extends RefCounted
## Big map Task 2 (docs/superpowers/plans/2026-11-21-big-map-game.md): BigWorld reads data/bigmap/world.json
## (baked by tools/bigmap/bake_world.py) as pure rules: the 8 px walk grid, route finding, packs by home,
## zone level, the arena disc, and the read-only stones/chests/arena/props. Facts below are the bake test's
## (tools/bigmap/test_bake.py); levels and ids are read from world.json, never typed in as literals.

const WORLD := "res://data/bigmap/world.json"

var tree: SceneTree
var _w: BigWorld = null
var _raw: Dictionary = {}

func setup(t: SceneTree) -> void:
	tree = t

func _world() -> BigWorld:
	if _w == null: _w = BigWorld.open(WORLD)
	return _w

func _data() -> Dictionary:
	if _raw.is_empty():
		var f := FileAccess.open(WORLD, FileAccess.READ)
		_raw = JSON.parse_string(f.get_as_text())
	return _raw

static func _v(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))

## Centre of 32 px tile (x, y).
static func _tile(x: int, y: int) -> Vector2:
	return Vector2(x * 32 + 16, y * 32 + 16)

func test_big_world_opens() -> String:
	var w := _world()
	if w == null: return "BigWorld.open(%s) returned null" % WORLD
	if w.size_px() != Vector2(4096, 4096): return "size_px %s, want 4096x4096" % w.size_px()
	if w.cell != 8 or w.cols != 512 or w.rows != 512: return "walk grid %d px %dx%d, want 8 px 512x512" % [w.cell, w.cols, w.rows]
	if BigWorld.open("res://data/bigmap/no_such_world.json") != null: return "a missing file must give null"
	return ""

func test_big_world_frozen_ids_match_world_json() -> String:
	var d := _data()
	var stones: Array = []
	for s in d.stones: stones.append(String(s.id))
	var chests: Array = []
	for c in d.chests: chests.append(String(c.id))
	if stones != BigWorld.STONE_IDS: return "world.json stones %s != BigWorld.STONE_IDS %s" % [stones, BigWorld.STONE_IDS]
	if chests != BigWorld.CHEST_IDS: return "world.json chests %s != BigWorld.CHEST_IDS %s" % [chests, BigWorld.CHEST_IDS]
	if BigWorld.STONE_IDS != ["w1", "w2", "w3"] or BigWorld.CHEST_IDS != ["c4", "c11", "c12"]:
		return "frozen id constants changed: %s %s" % [BigWorld.STONE_IDS, BigWorld.CHEST_IDS]
	return ""

func test_big_world_blocked_at_matches_bake() -> String:
	var w := _world()
	if w.blocked_at(_tile(57, 57)): return "bridge cell (57,57) blocked"
	if not w.blocked_at(_tile(59, 40)): return "water cell (59,40) open"
	if not w.blocked_at(_tile(56, 40)): return "forest cell (56,40) open"
	if w.blocked_at(w.start()): return "start %s blocked" % w.start()
	for p in w.props():
		var deck = p.get("deck")
		if deck == null: continue
		var mid := Vector2(deck[0] + deck[2] / 2.0, deck[1] + deck[3] / 2.0)
		if w.blocked_at(mid): return "bridge %s deck centre %s blocked" % [p.name, mid]
	for q in [Vector2(-1, 100), Vector2(100, -0.5), Vector2(4096, 100), Vector2(100, 4096), Vector2(NAN, 10), Vector2(INF, 10)]:
		if not w.blocked_at(q): return "outside the map %s must be blocked" % q
	if not w.cell_blocked(-1, 0) or not w.cell_blocked(0, 512): return "cells outside the grid must be blocked"
	if not w.blocked_at(Vector2(4, 4)): return "map edge cell must be blocked"
	# same bit as the raw base64 (bit i = y*512+x is (byte i>>3 >> (i&7)) & 1)
	var raw := Marshalls.base64_to_raw(String(_data().walk))
	for c in [Vector2i(0, 0), Vector2i(58, 460), Vector2i(236, 160), Vector2i(511, 511), Vector2i(300, 300), Vector2i(57 * 4, 57 * 4)]:
		var i: int = c.y * 512 + c.x
		var want := ((raw[i >> 3] >> (i & 7)) & 1) == 1
		if w.cell_blocked(c.x, c.y) != want: return "cell %s blocked=%s, raw bit says %s" % [c, w.cell_blocked(c.x, c.y), want]
	return ""

func test_big_world_nav_start_to_gate() -> String:
	var w := _world()
	var nav := w.make_nav()
	if nav.region != Rect2i(0, 0, 512, 512) or nav.cell_size != Vector2(8, 8): return "nav region/cell %s %s" % [nav.region, nav.cell_size]
	var a := Vector2i(w.start() / 8.0)
	var gate: Vector2 = w.arena().gate
	var b := Vector2i(gate / 8.0)
	if nav.is_point_solid(a): return "start cell solid in nav"
	if nav.is_point_solid(b): return "gate cell solid in nav"
	var path := nav.get_id_path(a, b)
	if path.is_empty() or path[-1] != b: return "no nav path start %s -> gate %s" % [a, b]
	if not w.reachable(w.start(), gate): return "reachable(start, gate) false"
	if not w.roomy(a.x, a.y): return "start not roomy"
	return ""

func test_big_world_packs_near_start_low_level() -> String:
	var w := _world()
	var near := w.packs_near(w.start(), 500.0)
	if near.is_empty(): return "no pack within 500 px of the start"
	for id in near:
		var p := w.pack(id)
		if p.is_empty(): return "pack(%s) empty" % id
		if int(p.level) > 2: return "pack %s level %d near the start (want <= 2)" % [id, p.level]
		if p.home.distance_to(w.start()) > 500.0: return "pack %s home %s farther than 500" % [id, p.home]
	# every pack whose home is within 500 is listed (from the raw data)
	for q in _data().packs:
		var inside := _v(q.home).distance_to(w.start()) <= 500.0
		if inside != near.has(String(q.id)): return "pack %s inside=%s but listed=%s" % [q.id, inside, near.has(String(q.id))]
	if not w.pack("nope").is_empty(): return "unknown pack id must give {}"
	return ""

func test_big_world_zone_level_near_gate() -> String:
	var w := _world()
	var gate: Vector2 = w.arena().gate
	var best: Dictionary = {}
	var bd := INF
	for q in _data().packs:
		var dd := _v(q.home).distance_to(gate)
		if dd < bd:
			bd = dd
			best = q
	if w.zone_level(gate) != int(best.level): return "zone_level(gate) %d, nearest pack %s is Lv%d" % [w.zone_level(gate), best.id, best.level]
	var p0: Dictionary = _data().packs[0]
	if w.zone_level(_v(p0.home)) != int(p0.level): return "zone_level at %s's home %d != %d" % [p0.id, w.zone_level(_v(p0.home)), p0.level]
	return ""

func test_big_world_in_arena_is_the_disc() -> String:
	var w := _world()
	var a := w.arena()
	var c: Vector2 = a.centre
	var r: float = a.radius
	if not w.in_arena(c): return "centre %s not in arena" % c
	if w.in_arena(a.gate): return "gate %s counts as in arena" % a.gate
	if w.in_arena(c + Vector2(r + 8, 0)): return "one cell outside the disc (east) counts as in arena"
	if w.in_arena(c + Vector2(0, -(r + 8))): return "one cell outside the disc (north) counts as in arena"
	if not w.in_arena(c + Vector2(r - 8, 0)): return "one cell inside the disc edge not in arena"
	var rect: Rect2 = a.rect
	var corner := rect.position + Vector2(8, 8)
	if not rect.has_point(corner) or w.in_arena(corner): return "rect corner %s must be outside the disc" % corner
	return ""

func test_big_world_read_only_data() -> String:
	var w := _world()
	var d := _data()
	if w.start() != _v(d.start): return "start %s != %s" % [w.start(), d.start]
	if w.hero_spawn != w.start(): return "hero_spawn (layout stand-in) != start"
	if w.stones().size() != 3 or w.chests().size() != 3: return "stones/chests count"
	if w.stones()[1].id != "w2" or w.stones()[1].at != _v(d.stones[1].at): return "stone w2 %s" % w.stones()[1]
	if w.chests()[0].id != "c4" or w.chests()[0].kind != d.chests[0].kind or int(w.chests()[0].level) != int(d.chests[0].level):
		return "chest c4 %s" % w.chests()[0]
	if w.packs().size() != d.packs.size(): return "packs %d != %d" % [w.packs().size(), d.packs.size()]
	if w.props().size() != d.props.size(): return "props %d != %d" % [w.props().size(), d.props.size()]
	if w.arena().pack.kind != d.arena.pack.kind: return "arena pack kind"
	# callers get copies: changing them does not change the world
	w.stones()[0].id = "zz"
	w.packs()[0].level = 99
	w.arena().radius = 1.0
	w.props()[0].name = "zz"
	w.pack("p0").level = 99
	if w.stones()[0].id != "w1" or int(w.pack("p0").level) == 99 or w.arena().radius == 1.0 or w.props()[0].name == "zz":
		return "accessors must return copies"
	return ""
