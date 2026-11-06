extends Node2D
## Ground warning for a monster's ring attack (shroom spores, kongkoi stomp): a flat ellipse of the
## hit radius whose fill grows from the centre over the warning time, so the player sees when to leave.

var radius := 40.0
var warn := 0.6
var color := Color(1.0, 0.3, 0.25)
var _t := 0.0
const SQUASH := 0.6

func start(radius_: float, warn_: float, color_: Color) -> void:
	radius = radius_
	warn = maxf(warn_, 0.01)
	color = color_
	_t = 0.0
	visible = true
	queue_redraw()

func _process(delta: float) -> void:
	if not visible: return
	_t = minf(_t + delta, warn)
	queue_redraw()

func progress() -> float:
	return _t / warn

func _ellipse(r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 33: pts.append(Vector2(r, 0).rotated(TAU * i / 32) * Vector2(1, SQUASH))
	return pts

func _draw() -> void:
	var fill := Color(color, 0.22)
	draw_colored_polygon(_ellipse(radius), fill)
	draw_colored_polygon(_ellipse(maxf(1.0, radius * progress())), Color(color, 0.4))
	draw_polyline(_ellipse(radius), Color(color, 0.95), 1.5)
