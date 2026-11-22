class_name BigMap
extends Node2D
## Big map Task 3 (docs/superpowers/plans/2026-11-21-big-map-game.md): draws a BigWorld.
## - ground: one TileMapLayer (z GROUND_Z) of 32 px tiles from the baked atlas; a flipped cell uses the atlas
##   source's transform flags (TRANSFORM_FLIP_H / _V) as its alternative id, so the atlas holds no flipped copies.
## - floor: `floor: true` props (bridges, pads) flat on their own layer (z FLOOR_Z, not y-sorted) over the ground.
## - props: one Sprite2D per other prop, a direct child of this node. Put BigMap under the game's y-sorted world
##   (this node is y-sorted too), so props sort with the hero and monsters by their foot point.
## - blockers: one StaticBody2D whose boxes are the walk grid's blocked cells merged into rectangles
##   (PaintedMap.merge_rects) plus a wall round the map. The walk bits already hold every prop's foot box (the
##   bake blocks each cell a box overlaps), so prop boxes get no colliders of their own: physics, blocked_at, the
##   route grid and drop placement all agree cell for cell, and no area collides twice.
## Culling: off-screen sprites are skipped by Godot's canvas culling (each item's rect against the view) and
## the TileMapLayer draws in 16x16-tile quadrants, so only what is on screen is drawn (measured in
## tests/screenshots_bigmap.gd). Nothing here is decoration for PerfSaver to drop.
## world.json is data from outside the code: each prop entry is checked as it is used and a bad one is
## skipped with a warning; a prop name must be a plain file name (no path) found in props_dir.

const GROUND_Z := -10
const FLOOR_Z := -9

var world: BigWorld
var ground: TileMapLayer
var floor_layer: Node2D
var blockers: StaticBody2D
var prop_sprites: Array[Sprite2D] = []     # y-sorted props (children of this node)
var floor_sprites: Array[Sprite2D] = []    # floor props (children of floor_layer)
var box_count := 0                         # collision boxes in blockers (merged cells + the 4 walls)
var skipped := 0                           # prop entries skipped as malformed or missing their sprite

static var _name_re: RegEx

func build(w: BigWorld) -> void:
	world = w
	name = "BigMap"
	y_sort_enabled = true
	_build_ground()
	floor_layer = Node2D.new()
	floor_layer.name = "Floor"
	floor_layer.z_index = FLOOR_Z
	add_child(floor_layer)
	_build_props()
	_build_blockers()

# ---- ground --------------------------------------------------------------------------------------------------

## Alternative id for a baked flip (0 none, 1 h, 2 v, 3 h+v; bake: 1 = mirrored left-right).
static func flip_flags(f: int) -> int:
	var a := 0
	if f & 1: a |= TileSetAtlasSource.TRANSFORM_FLIP_H
	if f & 2: a |= TileSetAtlasSource.TRANSFORM_FLIP_V
	return a

func _build_ground() -> void:
	ground = TileMapLayer.new()
	ground.name = "Ground"
	ground.z_index = GROUND_Z
	add_child(ground)
	var a := world.atlas()
	var file := String(a.file)
	if not file.begins_with("res://") or not ResourceLoader.exists(file):
		push_error("BigMap: ground atlas %s missing" % file)
		return
	var tex: Texture2D = load(file)
	var t := world.tile
	var cols: int = a.cols
	var count: int = a.count
	var rows_needed := (count + cols - 1) / cols
	if tex == null or tex.get_width() < cols * t or tex.get_height() < rows_needed * t:
		push_error("BigMap: ground atlas %s is smaller than %d tiles of %d px" % [file, count, t])
		return
	var ts := TileSet.new()
	ts.tile_size = Vector2i(t, t)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(t, t)
	for n in count: src.create_tile(Vector2i(n % cols, n / cols))
	ts.add_source(src, 0)
	ground.tile_set = ts
	var g := world.ground()
	var fl := world.flip()
	var across := int(world.size_px().x) / t
	for i in g.size():
		var n := g[i]
		ground.set_cell(Vector2i(i % across, i / across), 0, Vector2i(n % cols, n / cols), flip_flags(fl[i]))

# ---- props ---------------------------------------------------------------------------------------------------

static func _num_ok(v) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v))

static func _nums_ok(a, n: int) -> bool:
	if typeof(a) != TYPE_ARRAY or a.size() != n: return false
	for v in a:
		if not _num_ok(v): return false
	return true

## Whether prop entry p can be drawn: a plain name, numeric x / y / foot, box null or [x, y, w, h] with w, h > 0,
## floor absent or a bool.
static func prop_ok(p) -> bool:
	if typeof(p) != TYPE_DICTIONARY: return false
	if _name_re == null: _name_re = RegEx.create_from_string("^[A-Za-z0-9_]+$")
	if typeof(p.get("name")) != TYPE_STRING or _name_re.search(p.name) == null: return false
	if not _num_ok(p.get("x")) or not _num_ok(p.get("y")) or not _nums_ok(p.get("foot"), 2): return false
	var b = p.get("box")
	if b != null and (not _nums_ok(b, 4) or b[2] <= 0 or b[3] <= 0): return false
	var f = p.get("floor", false)
	return typeof(f) == TYPE_BOOL

func _build_props() -> void:
	var textures := {}
	for p in world.props():
		if not prop_ok(p):
			push_warning("BigMap: prop entry skipped (bad fields): %s" % str(p).left(120))
			skipped += 1
			continue
		var path := "%s/%s.png" % [world.props_dir, p.name]
		if not textures.has(path):
			textures[path] = load(path) if ResourceLoader.exists(path) else null
		if textures[path] == null:
			push_warning("BigMap: prop %s skipped (no sprite %s)" % [p.name, path])
			skipped += 1
			continue
		var s := Sprite2D.new()
		s.texture = textures[path]
		s.centered = false
		s.offset = -Vector2(float(p.foot[0]), float(p.foot[1]))   # the foot pixel sits on (x, y): y-sort by the feet
		s.position = Vector2(float(p.x), float(p.y))
		if bool(p.get("floor", false)):
			floor_layer.add_child(s)
			floor_sprites.append(s)
		else:
			add_child(s)
			prop_sprites.append(s)

# ---- colliders -----------------------------------------------------------------------------------------------

func _build_blockers() -> void:
	blockers = StaticBody2D.new()
	blockers.name = "Blockers"
	add_child(blockers)
	for r in PaintedMap.merge_rects(world): _box(r)
	for r in PaintedMap.border_rects(world.size_px()): _box(r)

func _box(r: Rect2) -> void:
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = r.size
	cs.shape = shape
	cs.position = r.get_center()
	blockers.add_child(cs)
	box_count += 1

## The collision rectangles in blockers (px), for tests.
func collider_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for cs in blockers.get_children():
		var sz: Vector2 = (cs.shape as RectangleShape2D).size
		out.append(Rect2(cs.position - sz / 2.0, sz))
	return out
