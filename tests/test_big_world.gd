extends RefCounted
## Big map Task 2 (docs/superpowers/plans/2026-11-21-big-map-game.md): BigWorld reads data/bigmap/world.json
## (baked by tools/bigmap/bake_world.py) as pure rules: the 8 px walk grid, route finding, packs by home,
## zone level, the arena disc, the ground tiles, and the read-only stones/chests/arena/props. Facts below are the
## bake test's (tools/bigmap/test_bake.py); levels and ids are read from world.json, never typed in as literals.
## BigWorld and PaintedLayout share WalkGrid: a drift test runs one small grid through both and a naive check.

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
	if w.tile != 32 or w.props_dir != String(_data().props_dir): return "tile %d props_dir %s" % [w.tile, w.props_dir]
	if w.atlas() != {"file": String(_data().atlas.file), "cols": int(_data().atlas.cols), "count": int(_data().atlas.count)}:
		return "atlas %s" % w.atlas()
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
	# every cell = the raw base64 bit (bit i = y*512+x is (byte i>>3 >> (i&7)) & 1)
	var raw := Marshalls.base64_to_raw(String(_data().walk))
	for y in 512:
		for x in 512:
			var i: int = y * 512 + x
			var want := ((raw[i >> 3] >> (i & 7)) & 1) == 1
			if w.cell_blocked(x, y) != want: return "cell (%d,%d) blocked=%s, raw bit says %s" % [x, y, not want, want]
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
	var a := w.arena()
	# owner rule (2026-11-21): the boss arena is the zone before it + 1
	if w.zone_level(a.gate) + 1 != int(a.pack.level):
		return "zone_level(gate) %d + 1 != arena pack Lv%d" % [w.zone_level(a.gate), a.pack.level]
	var gate: Vector2 = a.gate
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

func test_big_world_ground_and_flip() -> String:
	var w := _world()
	var g := w.ground()
	var f := w.flip()
	if g.size() != 16384 or f.size() != 16384: return "ground %d / flip %d entries, want 16384" % [g.size(), f.size()]
	var count: int = w.atlas().count
	for i in g.size():
		if g[i] < 0 or g[i] >= count: return "ground[%d] = %d outside the atlas (%d tiles)" % [i, g[i], count]
		if f[i] > 3: return "flip[%d] = %d" % [i, f[i]]
	var d := _data()
	for i in [0, 75, 8000, 16383]:
		if g[i] != int(d.ground[i]) or f[i] != int(d.flip[i]): return "ground/flip[%d] differ from world.json" % i
	g[0] = 999
	if w.ground()[0] == 999: return "ground() must return a copy"
	return ""

func test_big_world_points_open_and_roomy() -> String:
	var w := _world()
	var pts := {"start": w.start()}
	for s in w.stones(): pts["stone " + s.id] = s.at
	for c in w.chests(): pts["chest " + c.id] = c.at
	for p in w.packs(): pts["pack %s home" % p.id] = p.home
	for k in pts:
		var p: Vector2 = pts[k]
		if w.blocked_at(p): return "%s %s blocked" % [k, p]
		if not w.roomy(int(p.x) / 8, int(p.y) / 8): return "%s %s not roomy" % [k, p]
	return ""

func test_big_world_cheap_getters() -> String:
	var w := _world()
	var a := w.arena()
	if w.arena_centre() != a.centre or w.arena_radius() != a.radius: return "arena_centre/radius"
	if w.pack_home("p1") != w.pack("p1").home: return "pack_home(p1)"
	if w.pack_home("nope") != Vector2.INF: return "pack_home(unknown) must be INF"
	if w.stone_at("w3") != _v(_data().stones[2].at): return "stone_at(w3)"
	if w.stone_at("w9") != Vector2.INF: return "stone_at(unknown) must be INF"
	return ""

# ---- synthetic worlds ----------------------------------------------------------------------------------------

## A small grid (cols x rows of 8 px cells, '#' blocked) used by the drift test and the broken-dict tests.
const GRID := [
	"################",
	"#......#.......#",
	"#......#.......#",
	"#..##..#...#...#",
	"#..##......#...#",
	"#..........#...#",
	"#.....######...#",
	"#..............#",
	"#..............#",
	"#..............#",
	"#.........#....#",
	"################"]

static func _bits_of(grid: Array) -> PackedByteArray:
	var cols := String(grid[0]).length()
	var b := PackedByteArray()
	b.resize((cols * grid.size() + 7) / 8)
	for y in grid.size():
		for x in cols:
			if String(grid[y])[x] == "#":
				var i := y * cols + x
				b[i >> 3] |= 1 << (i & 7)
	return b

## A valid world.json-shaped dict for GRID (128 x 96 px, tile 32 -> 4 x 3 ground tiles).
static func _small() -> Dictionary:
	return {"size": [128, 96], "tile": 32, "cell": 8,
		"atlas": {"file": "res://x.png", "cols": 2, "count": 2}, "props_dir": "res://p",
		"ground": [0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1], "flip": [0, 1, 2, 3, 0, 0, 0, 0, 0, 0, 0, 0],
		"walk": Marshalls.raw_to_base64(_bits_of(GRID)), "props": [], "zones": [],
		"start": [20, 60],
		"stones": [{"id": "w1", "at": [20, 60]}, {"id": "x9", "at": [30, 60]}, {"id": "w1", "at": [40, 60]}],
		"chests": [{"id": "c4", "at": [90, 60], "kind": "wolf", "level": 1}, {"id": "c99", "at": [90, 70], "kind": "wolf", "level": 1}],
		"packs": [{"id": "p0", "kind": "wolf", "level": 1, "count": 3, "at": [100, 40], "home": [100, 44], "elite": false}],
		"arena": {"centre": [60, 30], "radius": 20, "rect": [40, 10, 40, 40], "gate": [60, 60],
			"pack": {"kind": "boar", "level": 2, "count": 1, "at": [60, 30], "elite": true}}}

## The hero-sized body rule written out plainly (cells x-1..x+1, y-2..y all open).
static func _naive_roomy(grid: Array, x: int, y: int) -> bool:
	for dy in range(-2, 1):
		for dx in range(-1, 2):
			var cx := x + dx
			var cy := y + dy
			if cy < 0 or cy >= grid.size() or cx < 0 or cx >= String(grid[0]).length(): return false
			if String(grid[cy])[cx] == "#": return false
	return true

func test_walk_grid_no_drift_painted_vs_big() -> String:
	var b := BigWorld.from_dict(_small())
	var l := PaintedLayout.from_dict({"size": [128, 96], "cell": 8, "blocked": GRID, "hero_spawn": [20, 60]})
	if b == null or l == null: return "synthetic world/layout did not build"
	var any_b: Object = b
	if not (any_b is WalkGrid and l is WalkGrid) or any_b is PaintedLayout: return "both must extend WalkGrid, BigWorld not PaintedLayout"
	if PaintedLayout.CLEAR_X != 1 or PaintedLayout.CLEAR_UP != 2 or BigWorld.CLEAR_X != 1: return "CLEAR_X/CLEAR_UP not resolvable"
	if b.cols != l.cols or b.rows != l.rows or b.size_px() != l.size_px(): return "grid shape differs"
	for y in range(-1, 13):
		for x in range(-1, 17):
			if b.cell_blocked(x, y) != l.cell_blocked(x, y): return "cell_blocked (%d,%d) differs" % [x, y]
			var want := _naive_roomy(GRID, x, y)
			if b.roomy(x, y) != want or l.roomy(x, y) != want: return "roomy (%d,%d): big %s painted %s want %s" % [x, y, b.roomy(x, y), l.roomy(x, y), want]
	var nb := b.make_nav()
	var nl := l.make_nav()
	for y in 12:
		for x in 16:
			var want := not _naive_roomy(GRID, x, y)
			if nb.is_point_solid(Vector2i(x, y)) != want or nl.is_point_solid(Vector2i(x, y)) != want: return "nav solid (%d,%d) differs" % [x, y]
	if nb.get_id_path(Vector2i(2, 4), Vector2i(13, 10)) != nl.get_id_path(Vector2i(2, 4), Vector2i(13, 10)): return "nav paths differ"
	var pairs := [[Vector2(20, 60), Vector2(110, 80)], [Vector2(20, 60), Vector2(70, 20)], [Vector2(20, 60), Vector2(36, 36)],
		[Vector2(20, 60), Vector2(-5, 60)], [Vector2(20, 60), Vector2(200, 60)], [Vector2(20, 60), Vector2(20, 4)]]
	for pr in pairs:
		if b.reachable(pr[0], pr[1]) != l.reachable(pr[0], pr[1]): return "reachable %s differs" % [pr]
	if not b.reachable(Vector2(20, 60), Vector2(110, 80)): return "open ground must be reachable"
	if b.reachable(Vector2(20, 60), Vector2(20, 4)): return "a wall cell must not be reachable"
	return ""

func test_big_world_skips_unknown_ids() -> String:
	var b := BigWorld.from_dict(_small())
	if b == null: return "synthetic world did not build"
	var s := []
	for x in b.stones(): s.append(x.id)
	var c := []
	for x in b.chests(): c.append(x.id)
	if s != ["w1"]: return "stones %s, want [w1] (x9 unknown, second w1 repeated)" % [s]
	if c != ["c4"]: return "chests %s, want [c4] (c99 unknown)" % [c]
	return ""

func test_big_world_broken_dicts_give_null() -> String:
	var cases := {
		"no size": func(d): d.erase("size"),
		"size text": func(d): d.size = "128x96",
		"cell 0": func(d): d.cell = 0,
		"cell text": func(d): d.cell = "8",
		"walk short": func(d): d.walk = Marshalls.raw_to_base64(PackedByteArray([0, 0, 0])),
		"walk not base64": func(d): d.walk = "!".repeat(String(d.walk).length()),
		"walk missing": func(d): d.erase("walk"),
		"no start": func(d): d.erase("start"),
		"start one number": func(d): d.start = [3],
		"no arena": func(d): d.erase("arena"),
		"arena no centre": func(d): d.arena.erase("centre"),
		"arena radius text": func(d): d.arena.radius = "20",
		"arena no pack": func(d): d.arena.erase("pack"),
		"arena rect short": func(d): d.arena.rect = [1, 2],
		"ground index past atlas": func(d): d.ground[3] = 2,
		"ground too short": func(d): d.ground.pop_back(),
		"flip 4": func(d): d.flip[0] = 4,
		"no atlas": func(d): d.erase("atlas"),
		"pack no kind": func(d): d.packs[0].erase("kind"),
		"pack id repeated": func(d): d.packs.append(d.packs[0].duplicate()),
		"stone not a dict": func(d): d.stones.append("w2"),
		"props not array": func(d): d.props = {},
		"props_dir not res": func(d): d.props_dir = "/etc",
		"props_dir user": func(d): d.props_dir = "user://p",
		"props_dir text res inside": func(d): d.props_dir = "../res://p",
		"atlas file not res": func(d): d.atlas.file = "/tmp/x.png",
	}
	for k in cases:
		var d := _small()
		cases[k].call(d)
		if BigWorld.from_dict(d) != null: return "%s: from_dict must give null" % k
	var real: Dictionary = _data().duplicate()
	real.walk = String(real.walk).substr(0, String(real.walk).length() - 4)
	if BigWorld.from_dict(real) != null: return "world.json with a short walk must give null"
	if BigWorld.from_dict(_small()) == null: return "the unbroken synthetic world must build"
	return ""
