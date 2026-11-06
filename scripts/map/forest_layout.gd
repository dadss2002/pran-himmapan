class_name ForestLayout
extends RefCounted
## The forest map as data (res://data/map_forest.json): terrain shapes on a corner grid, props,
## hero spawn and pack homes. Pure rules, no scene access: which tile each cell uses, what blocks.
## Corner (cx, cy) sits at pixel (cx * 32, cy * 32). A cell's mask is NW<<3 | NE<<2 | SW<<1 | SE,
## a set bit meaning that corner is the cell's terrain (grass otherwise).

const TILE := 32
const PATH := "res://data/map_forest.json"
const TILES_MANIFEST := "res://assets/map/tiles/manifest.json"
const PROPS_MANIFEST := "res://assets/map/props/manifest.json"

var cols := 0
var rows := 0
var base := "grass"
var tiles: Dictionary = {}        # terrain -> {row, masks: {"<mask>": column}} (tiles manifest "terrains")
var ground: Dictionary = {}       # whole tiles manifest: file, tile, grass, terrains
var catalog: Dictionary = {}      # prop id -> {file, size, feet, foot, flat}
var props: Array = []             # [{id, at: Vector2}]
var fx: Array = []                # [{id, at: Vector2}]
var walk: Array = []              # [Rect2] pixel rects where water does not block (the bridge deck)
var hero_spawn := Vector2.ZERO
var pack_homes: Array = []        # [Vector2]
var _corner := PackedStringArray()

static func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return {}
	return JSON.parse_string(f.get_as_text())

static func open(path := PATH) -> ForestLayout:
	return from_dict(_json(path), _json(TILES_MANIFEST), _json(PROPS_MANIFEST))

static func from_dict(d: Dictionary, tiles_manifest: Dictionary, props_manifest: Dictionary) -> ForestLayout:
	var l := ForestLayout.new()
	l.cols = int(d.cells[0])
	l.rows = int(d.cells[1])
	l.base = String(d.get("base", "grass"))
	l.ground = tiles_manifest
	l.tiles = tiles_manifest.get("terrains", tiles_manifest)
	l.catalog = props_manifest
	l._corner.resize((l.cols + 1) * (l.rows + 1))
	l._corner.fill(l.base)
	for s in d.get("terrain", []):
		l._paint(s)
	l._smooth()
	l._smooth()
	for r in d.get("walk", []):
		l.walk.append(Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])))
	for p in d.get("props", []):
		l.props.append({"id": String(p.id), "at": Vector2(p.at[0], p.at[1])})
	for p in d.get("fx", []):
		l.fx.append({"id": String(p.id), "at": Vector2(p.at[0], p.at[1])})
	var hs: Array = d.get("hero_spawn", [0, 0])
	l.hero_spawn = Vector2(hs[0], hs[1])
	for h in d.get("pack_homes", []):
		l.pack_homes.append(Vector2(h[0], h[1]))
	return l

func _paint(s: Dictionary) -> void:
	var t := String(s.t)
	for cy in rows + 1:
		for cx in cols + 1:
			var inside := false
			if s.has("rect"):
				var r: Array = s.rect
				inside = cx >= r[0] and cx <= r[0] + r[2] and cy >= r[1] and cy <= r[1] + r[3]
			elif s.has("ellipse"):
				var e: Array = s.ellipse
				var dx := (cx - float(e[0])) / float(e[2])
				var dy := (cy - float(e[1])) / float(e[3])
				inside = dx * dx + dy * dy <= 1.0
			if inside: _corner[cy * (cols + 1) + cx] = t

## A corner with fewer than two same-terrain neighbours (an ellipse tip) reverts to the base terrain,
## so shores and clumps have no one-corner bumps.
func _smooth() -> void:
	var snap := _corner.duplicate()
	var w := cols + 1
	for cy in rows + 1:
		for cx in w:
			var t := snap[cy * w + cx]
			if t == base: continue
			var n := 0
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var x: int = cx + o.x
				var y: int = cy + o.y
				if x >= 0 and y >= 0 and x < w and y <= rows and snap[y * w + x] == t: n += 1
			if n < 2: _corner[cy * w + cx] = base

func size_px() -> Vector2:
	return Vector2(cols * TILE, rows * TILE)

func corners() -> PackedStringArray:
	return _corner

func corner(cx: int, cy: int) -> String:
	return _corner[cy * (cols + 1) + cx]

## {terrain, mask}: "grass"/0 when all four corners are grass; terrain "" and mask -1 when the
## cell touches two non-grass terrains (no tileset draws that).
func cell(x: int, y: int) -> Dictionary:
	var c := [corner(x, y), corner(x + 1, y), corner(x, y + 1), corner(x + 1, y + 1)]
	var other := ""
	for t in c:
		if t == base: continue
		if other != "" and t != other: return {"terrain": "", "mask": -1}
		other = t
	if other == "": return {"terrain": base, "mask": 0}
	var m := 0
	for i in 4:
		if c[i] == other: m |= 1 << (3 - i)
	return {"terrain": other, "mask": m}

func in_walk(p: Vector2) -> bool:
	for r in walk:
		if r.has_point(p): return true
	return false

## Water blocks a cell when two or more of its corners are water (the bridge deck is cut out
## of this by blocked_at and by ForestMap's colliders, not here).
func cell_blocked(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= cols or y >= rows: return true
	var c := cell(x, y)
	if c.terrain != "water": return false
	var n := 0
	for i in 4:
		if int(c.mask) & (1 << i): n += 1
	return n >= 2

## The blocking box of a prop, or an empty Rect2 when it has none: spans `foot` up from its feet.
func foot_rect(p: Dictionary) -> Rect2:
	var m: Dictionary = catalog.get(p.id, {})
	var f = m.get("foot")
	if f == null: return Rect2()
	var at: Vector2 = p.at
	return Rect2(at.x - float(f[0]) / 2.0, at.y - float(f[1]), float(f[0]), float(f[1]))

func blocked_at(p: Vector2) -> bool:
	var sz := size_px()
	if p.x < 0 or p.y < 0 or p.x >= sz.x or p.y >= sz.y: return true
	if not in_walk(p) and cell_blocked(int(p.x) / TILE, int(p.y) / TILE): return true
	for pr in props:
		var r := foot_rect(pr)
		if r.size != Vector2.ZERO and r.has_point(p): return true
	return false

## The points a pack's wolves spawn on (same ring WolfPack.spawn uses).
static func ring(home: Vector2, count: int) -> Array:
	var out := []
	for i in count:
		out.append(home + Vector2(Balance.num("wolf.pack_ring"), 0).rotated(TAU * i / count) * Vector2(1, 0.7))
	return out

## Every problem with this layout; empty means it is playable.
func validate() -> Array[String]:
	var errs: Array[String] = []
	for y in rows:
		for x in cols:
			var c := cell(x, y)
			if int(c.mask) < 0: errs.append("cell %d,%d touches two terrains" % [x, y])
			elif c.terrain != base and not tiles.has(c.terrain): errs.append("no tileset for %s" % c.terrain)
	var sz := size_px()
	for p in props:
		if not catalog.has(p.id): errs.append("unknown prop %s" % p.id)
		elif p.at.x < 0 or p.at.y < 0 or p.at.x > sz.x or p.at.y > sz.y: errs.append("prop %s outside map" % p.id)
		elif not bool(catalog[p.id].get("flat", false)) and cell_blocked(int(p.at.x) / TILE, int(p.at.y) / TILE):
			errs.append("prop %s at %s stands in water" % [p.id, p.at])
	if blocked_at(hero_spawn): errs.append("hero spawn blocked")
	var packs: Array = Balance.data().get("packs", [])
	if pack_homes.size() != packs.size(): errs.append("%d pack homes for %d packs" % [pack_homes.size(), packs.size()])
	for i in mini(pack_homes.size(), packs.size()):
		for q in ring(pack_homes[i], int(packs[i].count)):
			if blocked_at(q): errs.append("pack %d spawn %s blocked" % [i, q])
	return errs
