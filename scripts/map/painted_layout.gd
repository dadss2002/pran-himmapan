class_name PaintedLayout
extends WalkGrid
## One painted forest room as data (a room of res://data/rooms.json, built by RoomSet.layout):
## PixelLab scene chunks, an 8 px blocked grid, leaf overlays, spawn and pack homes.
## Pure rules, no scene access. The walk rules (blocked_at, roomy, reachable, make_nav, CLEAR_X / CLEAR_UP,
## size / cell / cols / rows / hero_spawn) live in WalkGrid, shared with BigWorld.

var chunks: Array = []        # [{file, at: Vector2}]
var overlays: Array = []      # [{file, at: Vector2}]
var fx: Array = []            # [{id, at: Vector2}]
var pack_homes: Array = []    # [Vector2]
var from_room := false          # built from one room: packs are checked against its own homes only

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
	var r := grid.size()
	l._reset_cells(String(grid[0]).length() if r > 0 else 0, r)
	for y in l.rows:
		var row := String(grid[y])
		for x in l.cols:
			if row[x] == "#": l._mark(y * l.cols + x)
	for c in d.get("chunks", []): l.chunks.append({"file": String(c.file), "at": _v(c.at)})
	for c in d.get("overlays", []): l.overlays.append({"file": String(c.file), "at": _v(c.at)})
	for c in d.get("fx", []): l.fx.append({"id": String(c.id), "at": _v(c.at)})
	l.hero_spawn = _v(d.hero_spawn)
	for h in d.get("pack_homes", []): l.pack_homes.append(_v(h))
	return l

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
