class_name PaintedMap
extends Node2D
## Builds the painted forest from a PaintedLayout: the PixelLab scene chunks under everything,
## one StaticBody2D for the blocked cells (merged into rectangles), pond ripples, and the leaf
## overlays that hang over walkable ground drawn above characters (walking "under" the trees).

const BORDER := 64.0
const OVERLAY_Z := 30

var layout: PaintedLayout
var chunk_sprites: Array = []
var overlay_sprites: Array = []
var fx_nodes: Array = []
var blockers: StaticBody2D
var box_count := 0

func build(l: PaintedLayout) -> void:
	layout = l
	name = "PaintedMap"
	for c in layout.chunks:
		var s := _sprite(c)
		s.z_index = -10
		chunk_sprites.append(s)
	for f in layout.fx:
		_add_fx(f)
	for o in layout.overlays:
		var s := _sprite(o)
		s.z_index = OVERLAY_Z
		overlay_sprites.append(s)
	_build_blockers()

func _sprite(c: Dictionary) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = load(String(c.file))
	s.centered = false
	s.position = c.at
	add_child(s)
	return s

## Blocked cells as few rectangles: runs along each row, stacked down while the next row has the same run.
func _build_blockers() -> void:
	blockers = StaticBody2D.new()
	blockers.name = "Blockers"
	add_child(blockers)
	var c := float(layout.cell)
	var open := {}           # Vector2i(x0, x1) -> Rect2 (in cells) still growing downward
	for y in layout.rows + 1:
		var runs := {}
		if y < layout.rows:
			var x := 0
			while x < layout.cols:
				if not layout.cell_blocked(x, y):
					x += 1
					continue
				var x0 := x
				while x < layout.cols and layout.cell_blocked(x, y): x += 1
				runs[Vector2i(x0, x)] = true
		var still := {}
		for k in open:
			if runs.has(k):
				var r: Rect2 = open[k]
				r.size.y += 1
				still[k] = r
			else:
				var r: Rect2 = open[k]
				_box(Rect2(r.position * c, r.size * c))
		for k in runs:
			if not still.has(k): still[k] = Rect2(k.x, y, k.y - k.x, 1)
		open = still
	var sz := layout.size_px()
	_box(Rect2(-BORDER, -BORDER, sz.x + 2 * BORDER, BORDER))
	_box(Rect2(-BORDER, sz.y, sz.x + 2 * BORDER, BORDER))
	_box(Rect2(-BORDER, 0, BORDER, sz.y))
	_box(Rect2(sz.x, 0, BORDER, sz.y))

func _box(r: Rect2) -> void:
	var cs := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = r.size
	cs.shape = shape
	cs.position = r.get_center()
	blockers.add_child(cs)
	box_count += 1

func _add_fx(f: Dictionary) -> void:
	if not FxSprite._manifest().has(f.id): return
	var s := FxSprite.make(String(f.id), true)
	s.position = f.at
	s.z_index = -9
	add_child(s)
	fx_nodes.append(s)
	s.play(String(f.id))
