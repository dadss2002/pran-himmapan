class_name ForestMap
extends Node2D
## Builds the forest from a ForestLayout: one ground TileMapLayer, flat props (flowers, bridge) and
## pond effects under everything, standing props (trees, rocks, well) Y-sorted inside `world` with a
## collider at their feet, and one StaticBody2D for water cells and the map border.

const BORDER := 64.0

var layout: ForestLayout
var ground: TileMapLayer
var flat: Node2D
var blockers: StaticBody2D
var props: Array = []        # standing prop nodes (in world)
var flats: Array = []        # flat prop nodes
var fx_nodes: Array = []

func build(l: ForestLayout, world: Node2D) -> void:
	layout = l
	name = "ForestMap"
	z_index = -10
	_build_ground()
	flat = Node2D.new()
	flat.name = "Flat"
	flat.z_index = 1
	add_child(flat)
	for p in layout.props:
		_add_prop(p, world)
	_build_blockers()
	for f in layout.fx:
		_add_fx(f)

func _build_ground() -> void:
	var m: Dictionary = layout.ground
	var ts := TileSet.new()
	var t := int(m.tile)
	ts.tile_size = Vector2i(t, t)
	var src := TileSetAtlasSource.new()
	src.texture = load(String(m.file))
	src.texture_region_size = Vector2i(t, t)
	var grid := Vector2i(src.texture.get_width() / t, src.texture.get_height() / t)
	for y in grid.y:
		for x in grid.x:
			src.create_tile(Vector2i(x, y))
	ts.add_source(src, 0)
	ground = TileMapLayer.new()
	ground.name = "Ground"
	ground.tile_set = ts
	add_child(ground)
	for y in layout.rows:
		for x in layout.cols:
			ground.set_cell(Vector2i(x, y), 0, atlas_for(x, y), _flip(x, y))

## Atlas coords of the tile drawn at cell x, y.
func atlas_for(x: int, y: int) -> Vector2i:
	var c := layout.cell(x, y)
	if c.terrain == layout.base or int(c.mask) < 0:
		var g: Array = layout.ground.grass
		return Vector2i(g[0], g[1])
	var info: Dictionary = layout.tiles[c.terrain]
	return Vector2i(int(info.masks[str(c.mask)]), int(info.row))

## Full tiles (all grass or all one terrain) are flipped by cell so the repeat is less visible.
func _flip(x: int, y: int) -> int:
	var c := layout.cell(x, y)
	if c.terrain != layout.base and int(c.mask) != 15: return 0
	var h := (x * 73856093) ^ (y * 19349663)
	match absi(h) % 4:
		1: return TileSetAtlasSource.TRANSFORM_FLIP_H
		2: return TileSetAtlasSource.TRANSFORM_FLIP_V
		3: return TileSetAtlasSource.TRANSFORM_FLIP_H | TileSetAtlasSource.TRANSFORM_FLIP_V
	return 0

func _add_prop(p: Dictionary, world: Node2D) -> void:
	var m: Dictionary = layout.catalog[p.id]
	var n := Node2D.new()
	n.name = String(p.id)
	n.set_meta("prop_id", String(p.id))       # names can be renamed on clashes; the id stays here
	n.position = p.at
	var s := Sprite2D.new()
	s.texture = load(String(m.file))
	s.centered = false
	s.offset = -Vector2(m.feet[0], m.feet[1])
	n.add_child(s)
	var r := layout.foot_rect(p)
	if r.size != Vector2.ZERO:
		var b := StaticBody2D.new()
		var cs := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = r.size
		cs.shape = shape
		cs.position = r.get_center() - p.at
		b.add_child(cs)
		n.add_child(b)
	if bool(m.get("flat", false)):
		flat.add_child(n)
		flats.append(n)
	else:
		world.add_child(n)
		props.append(n)

func _build_blockers() -> void:
	blockers = StaticBody2D.new()
	blockers.name = "Blockers"
	add_child(blockers)
	var t := float(ForestLayout.TILE)
	for y in layout.rows:
		var x := 0
		while x < layout.cols:
			if not layout.cell_blocked(x, y):
				x += 1
				continue
			var x0 := x
			while x < layout.cols and layout.cell_blocked(x, y): x += 1
			for part in _minus_walk(Rect2(x0 * t, y * t, (x - x0) * t, t)):
				_box(part)
	var sz := layout.size_px()
	_box(Rect2(-BORDER, -BORDER, sz.x + 2 * BORDER, BORDER))
	_box(Rect2(-BORDER, sz.y, sz.x + 2 * BORDER, BORDER))
	_box(Rect2(-BORDER, 0, BORDER, sz.y))
	_box(Rect2(sz.x, 0, BORDER, sz.y))

## Cuts each walk rect (the bridge deck) out of a row run, left/right of it.
func _minus_walk(r: Rect2) -> Array:
	var parts := [r]
	for w in layout.walk:
		var out := []
		for q in parts:
			var qr: Rect2 = q
			if not qr.intersects(w) or w.position.y > qr.position.y or w.end.y < qr.end.y:
				out.append(qr)
				continue
			if w.position.x > qr.position.x: out.append(Rect2(qr.position.x, qr.position.y, w.position.x - qr.position.x, qr.size.y))
			if w.end.x < qr.end.x: out.append(Rect2(w.end.x, qr.position.y, qr.end.x - w.end.x, qr.size.y))
		parts = out
	return parts

func _box(r: Rect2) -> void:
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = r.size
	cs.shape = shape
	cs.position = r.get_center()
	blockers.add_child(cs)

func _add_fx(f: Dictionary) -> void:
	if not FxSprite._manifest().has(f.id): return
	var s := FxSprite.make(String(f.id), true)
	s.position = f.at
	flat.add_child(s)
	fx_nodes.append(s)
	s.play(String(f.id))
