class_name WaypointStone
extends Node2D
## A waypoint stone in the room (M4c §2, Task 5): the owner's pick "แบบ 2" (assets/props/waypoint/waypoint_1.png,
## 64 x 64, PixelLab) drawn at 1 art pixel per room pixel (whole-pixel scale; the world view enlarges the room as
## a whole), its base point (bottom middle of the plinth) on the node's position, so it Y-sorts with the hero and
## monsters by its feet line. A soft cyan glow breathes over the rune (brighter once unlocked; one additive
## sprite, no shader). Walking is blocked by the room's walk grid (RoomSet.WAYPOINT_*), not by this node.

const TEXTURE := preload("res://assets/props/waypoint/waypoint_1.png")
## Art pixel of the plinth's bottom middle (the plinth spans x 10..53 and ends on row 61 of the 64 x 64 picture).
const BASE_PX := Vector2(32, 62)
## The drawn stone (its opaque pixels' box) around the base point, room px.
const ART_BOX := Rect2(10 - 32, 6 - 62, 44, 56)
## Art pixel of the rune's middle (the glow is centred there).
const RUNE_PX := Vector2(32, 30)
const GLOW_COLOR := Color(0.45, 0.85, 1.0)
const GLOW_SIZE := 28                # px across (room px)
const GLOW_PERIOD := 2.4             # s per breath
const GLOW_ALPHA := Vector2(0.25, 0.55)   # unlocked: alpha low..high over a breath
const GLOW_LOCKED := 0.12            # locked: a faint, steady glow

var room_id := ""
var unlocked := false
var sprite: Sprite2D
var glow: Sprite2D
var _t := 0.0

static func make(id: String, base: Vector2, is_unlocked: bool) -> WaypointStone:
	var n := WaypointStone.new()
	n.name = "Waypoint_" + id
	n.room_id = id
	n.position = base
	n.sprite = Sprite2D.new()
	n.sprite.name = "Stone"
	n.sprite.texture = TEXTURE
	n.sprite.centered = false
	n.sprite.offset = -BASE_PX                 # whole pixels: the picture's bottom middle on the base point
	n.sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	n.add_child(n.sprite)
	n.glow = Sprite2D.new()
	n.glow.name = "Glow"
	n.glow.texture = _glow_texture()
	n.glow.position = RUNE_PX - BASE_PX
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	n.glow.material = m
	n.add_child(n.glow)
	n.set_unlocked(is_unlocked)
	return n

func set_unlocked(on: bool) -> void:
	unlocked = on
	_apply_glow()

func _process(delta: float) -> void:
	_t = fmod(_t + delta, GLOW_PERIOD)
	_apply_glow()

func glow_alpha() -> float:
	if not unlocked: return GLOW_LOCKED
	var k := 0.5 - 0.5 * cos(TAU * _t / GLOW_PERIOD)
	return lerpf(GLOW_ALPHA.x, GLOW_ALPHA.y, k)

func _apply_glow() -> void:
	if glow: glow.modulate = Color(GLOW_COLOR, glow_alpha())

static var _glow_tex: Texture2D

## A soft round spot (radial gradient, clear at the rim), made once.
static func _glow_texture() -> Texture2D:
	if _glow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.width = GLOW_SIZE
		t.height = GLOW_SIZE
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		_glow_tex = t
	return _glow_tex
