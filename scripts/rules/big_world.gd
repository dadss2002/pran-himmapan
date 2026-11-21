class_name BigWorld
extends RefCounted
## The one 4096 x 4096 big map as data (data/bigmap/world.json, baked by tools/bigmap/bake_world.py; its `_doc`
## key describes every field). Pure rules, no scene access: the 8 px walk grid, route finding, monster packs by
## home, zone level, the boss arena disc, and read-only start / stones / chests / arena / props / zones.
## Stands in for PaintedLayout where hero, monsters and loot take a `layout`: same size / cell / cols / rows /
## hero_spawn fields and size_px / cell_blocked / blocked_at / roomy / reachable / make_nav with the same
## signatures and the same hero-sized body rule (PaintedLayout.CLEAR_X / CLEAR_UP).

## Frozen ids (saves use them). The game keeps these sets in code and never widens them from world.json (a
## modded data file must not add waypoints or chests); tests check world.json carries exactly these ids.
const STONE_IDS := ["w1", "w2", "w3"]
const CHEST_IDS := ["c4", "c11", "c12"]

var size := Vector2.ZERO
var cell := 8
var cols := 0
var rows := 0
var hero_spawn := Vector2.ZERO     # = start(); the field PaintedLayout callers read
var _blocked := PackedByteArray()  # cols*rows, 1 = blocked (decoded once from the base64 bits)
var _stones: Array = []            # [{id, at: Vector2}]
var _chests: Array = []            # [{id, at: Vector2, kind, level}]
var _packs: Array = []             # [{id, kind, level, count, at: Vector2, home: Vector2, elite}]
var _pack_by_id: Dictionary = {}   # id -> index into _packs
var _arena: Dictionary = {}        # {centre: Vector2, radius, rect: Rect2, gate: Vector2, pack: {kind, level, count, at: Vector2, elite}}
var _props: Array = []             # as in world.json
var _zones: Array = []             # as in world.json

## The baked big map, or null when the file is missing or malformed.
static func open(path := "res://data/bigmap/world.json") -> BigWorld:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return null
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY: return null
	return from_dict(d)

static func _v(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))

## Builds from the parsed world.json; null when the walk grid does not match size / cell.
static func from_dict(d: Dictionary) -> BigWorld:
	var w := BigWorld.new()
	w.size = _v(d.size)
	w.cell = int(d.get("cell", 8))
	w.cols = int(w.size.x) / w.cell
	w.rows = int(w.size.y) / w.cell
	var n := w.cols * w.rows
	var bits := Marshalls.base64_to_raw(String(d.get("walk", "")))
	if n <= 0 or bits.size() != (n + 7) / 8: return null
	w._blocked.resize(n)
	for i in n:
		w._blocked[i] = (bits[i >> 3] >> (i & 7)) & 1
	w.hero_spawn = _v(d.start)
	for s in d.get("stones", []): w._stones.append({"id": String(s.id), "at": _v(s.at)})
	for c in d.get("chests", []):
		w._chests.append({"id": String(c.id), "at": _v(c.at), "kind": String(c.kind), "level": int(c.level)})
	for p in d.get("packs", []):
		w._pack_by_id[String(p.id)] = w._packs.size()
		w._packs.append({"id": String(p.id), "kind": String(p.kind), "level": int(p.level), "count": int(p.count),
			"at": _v(p.at), "home": _v(p.get("home", p.at)), "elite": bool(p.get("elite", false))})
	var a: Dictionary = d.get("arena", {})
	if not a.is_empty():
		var r: Array = a.rect
		var bp: Dictionary = a.pack
		w._arena = {"centre": _v(a.centre), "radius": float(a.radius),
			"rect": Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])), "gate": _v(a.gate),
			"pack": {"kind": String(bp.kind), "level": int(bp.level), "count": int(bp.count), "at": _v(bp.at),
				"elite": bool(bp.get("elite", false))}}
	w._props = d.get("props", []).duplicate(true)
	w._zones = d.get("zones", []).duplicate(true)
	return w

# ---- the layout PaintedLayout callers use -------------------------------------------------------------------

func size_px() -> Vector2:
	return size

func cell_blocked(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= cols or y >= rows: return true
	return _blocked[y * cols + x] == 1

## Outside the map (or not a finite point) counts as blocked.
func blocked_at(p: Vector2) -> bool:
	if not p.is_finite(): return true
	if p.x < 0 or p.y < 0 or p.x >= size.x or p.y >= size.y: return true
	return cell_blocked(int(p.x) / cell, int(p.y) / cell)

## Room for a hero-sized body with its feet in cell x, y (PaintedLayout.roomy).
func roomy(x: int, y: int) -> bool:
	for dy in range(-PaintedLayout.CLEAR_UP, 1):
		for dx in range(-PaintedLayout.CLEAR_X, PaintedLayout.CLEAR_X + 1):
			if cell_blocked(x + dx, y + dy): return false
	return true

## Whether a hero-sized body can walk from a to b (4-way flood over roomy cells, PaintedLayout.reachable).
func reachable(a: Vector2, b: Vector2) -> bool:
	if blocked_at(a) or blocked_at(b): return false
	var start := Vector2i(int(a.x) / cell, int(a.y) / cell)
	var goal := Vector2i(int(b.x) / cell, int(b.y) / cell)
	if not roomy(start.x, start.y) or not roomy(goal.x, goal.y): return false
	var seen := PackedByteArray()
	seen.resize(cols * rows)
	var queue: Array[Vector2i] = [start]
	seen[start.y * cols + start.x] = 1
	var i := 0
	while i < queue.size():
		var c := queue[i]
		i += 1
		if c == goal: return true
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + o
			if n.x < 0 or n.y < 0 or n.x >= cols or n.y >= rows: continue
			if seen[n.y * cols + n.x] == 1 or not roomy(n.x, n.y): continue
			seen[n.y * cols + n.x] = 1
			queue.append(n)
	return false

## A walk grid for route finding (same settings as PaintedLayout.make_nav): a cell is solid unless a
## hero-sized body fits with its feet there.
func make_nav() -> AStarGrid2D:
	var g := AStarGrid2D.new()
	g.region = Rect2i(0, 0, cols, rows)
	g.cell_size = Vector2(cell, cell)
	g.offset = Vector2(cell, cell) / 2.0
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.update()
	for y in rows:
		for x in cols:
			if not roomy(x, y): g.set_point_solid(Vector2i(x, y))
	return g

# ---- packs, zones, arena -------------------------------------------------------------------------------------

## Ids of the packs whose home is within r px of p (distance <= r), in world.json order.
func packs_near(p: Vector2, r: float) -> Array[String]:
	var out: Array[String] = []
	for q in _packs:
		if q.home.distance_to(p) <= r: out.append(q.id)
	return out

## A copy of pack id ({id, kind, level, count, at, home, elite}), or {} if there is no such pack.
func pack(id: String) -> Dictionary:
	if not _pack_by_id.has(id): return {}
	return _packs[_pack_by_id[id]].duplicate(true)

## Level of the pack whose home is nearest p (first in world.json order on a tie); 0 with no packs.
## The boss arena's pack is not a layout pack and never counts.
func zone_level(p: Vector2) -> int:
	var best := 0
	var bd := INF
	for q in _packs:
		var dd: float = q.home.distance_squared_to(p)
		if dd < bd:
			bd = dd
			best = q.level
	return best

## Whether p is inside the arena's fight disc (centre / radius, edge included); the rect is only its bounds.
func in_arena(p: Vector2) -> bool:
	if _arena.is_empty() or not p.is_finite(): return false
	return p.distance_to(_arena.centre) <= _arena.radius

# ---- read-only data (copies) ---------------------------------------------------------------------------------

func start() -> Vector2:
	return hero_spawn

func stones() -> Array:
	return _stones.duplicate(true)

func chests() -> Array:
	return _chests.duplicate(true)

func packs() -> Array:
	return _packs.duplicate(true)

func arena() -> Dictionary:
	return _arena.duplicate(true)

func props() -> Array:
	return _props.duplicate(true)

func zones() -> Array:
	return _zones.duplicate(true)
