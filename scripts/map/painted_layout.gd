class_name PaintedLayout
extends RefCounted
## One painted forest room as data (a room of res://data/rooms.json, built by RoomSet.layout):
## PixelLab scene chunks, an 8 px blocked grid, leaf overlays, spawn and pack homes.
## Pure rules, no scene access: what blocks, and whether places can reach each other on foot.

## Free cells a body needs around its feet cell (x: ±1, y: -2..0): the hero's 20×16 feet box sits at
## y-14..y+2, so it can touch three rows.
const CLEAR_X := 1
const CLEAR_UP := 2

var size := Vector2.ZERO
var cell := 8
var cols := 0
var rows := 0
var chunks: Array = []        # [{file, at: Vector2}]
var overlays: Array = []      # [{file, at: Vector2}]
var fx: Array = []            # [{id, at: Vector2}]
var hero_spawn := Vector2.ZERO
var pack_homes: Array = []    # [Vector2]
var from_room := false          # built from one room: packs are checked against its own homes only
var _blocked := PackedByteArray()

static func open(path: String) -> PaintedLayout:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return null
	return from_dict(JSON.parse_string(f.get_as_text()))

static func _v(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))

## Either the old whole-map dict or one room of data/rooms.json (image/overlay/spawn/pack_home/
## monsters; size and cell are copied in by RoomSet).
static func from_dict(d: Dictionary) -> PaintedLayout:
	var l := PaintedLayout.new()
	if d.has("image"):
		l.from_room = true
		d = d.duplicate()
		d["chunks"] = [{"file": d.image, "at": [0, 0]}]
		d["overlays"] = [{"file": d.overlay, "at": [0, 0]}] if d.get("overlay") != null else []
		d["hero_spawn"] = d.get("spawn", [0, 0])
		d["pack_homes"] = [d.pack_home] if d.get("pack_home") != null else []
	l.size = _v(d.size)
	l.cell = int(d.get("cell", 8))
	var grid: Array = d.blocked
	l.rows = grid.size()
	l.cols = String(grid[0]).length() if l.rows > 0 else 0
	l._blocked.resize(l.cols * l.rows)
	for y in l.rows:
		var row := String(grid[y])
		for x in l.cols:
			l._blocked[y * l.cols + x] = 1 if row[x] == "#" else 0
	for c in d.get("chunks", []): l.chunks.append({"file": String(c.file), "at": _v(c.at)})
	for c in d.get("overlays", []): l.overlays.append({"file": String(c.file), "at": _v(c.at)})
	for c in d.get("fx", []): l.fx.append({"id": String(c.id), "at": _v(c.at)})
	l.hero_spawn = _v(d.hero_spawn)
	for h in d.get("pack_homes", []): l.pack_homes.append(_v(h))
	return l

func size_px() -> Vector2:
	return size

func cell_blocked(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= cols or y >= rows: return true
	return _blocked[y * cols + x] == 1

func blocked_at(p: Vector2) -> bool:
	if p.x < 0 or p.y < 0 or p.x >= size.x or p.y >= size.y: return true
	return cell_blocked(int(p.x) / cell, int(p.y) / cell)

## Room for a hero-sized body with its feet in cell x, y.
func roomy(x: int, y: int) -> bool:
	for dy in range(-CLEAR_UP, 1):
		for dx in range(-CLEAR_X, CLEAR_X + 1):
			if cell_blocked(x + dx, y + dy): return false
	return true

## Whether a hero-sized body can walk from a to b (4-way flood over roomy cells).
func reachable(a: Vector2, b: Vector2) -> bool:
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

## A walk grid for route finding: a cell is solid unless a hero-sized body fits with its feet there.
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

## The points a pack's wolves spawn on (same ring WolfPack.spawn uses).
static func ring(home: Vector2, count: int) -> Array:
	var out := []
	for i in count:
		out.append(home + Vector2(Balance.num("wolf.pack_ring"), 0).rotated(TAU * i / count) * Vector2(1, 0.7))
	return out

## Every problem with this layout; empty means it is playable.
func validate() -> Array[String]:
	var errs: Array[String] = []
	for c in chunks + overlays:
		if not ResourceLoader.exists(c.file): errs.append("missing %s" % c.file)
	if blocked_at(hero_spawn): errs.append("hero spawn blocked")
	var packs: Array = Balance.data().get("packs", [])
	if from_room: return errs
	if pack_homes.size() != packs.size(): errs.append("%d pack homes for %d packs" % [pack_homes.size(), packs.size()])
	for i in mini(pack_homes.size(), packs.size()):
		for q in ring(pack_homes[i], int(packs[i].count)):
			if blocked_at(q): errs.append("pack %d spawn %s blocked" % [i, q])
		if not reachable(hero_spawn, pack_homes[i]): errs.append("pack %d home %s cannot be walked to from the spawn" % [i, pack_homes[i]])
	return errs
