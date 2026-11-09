class_name TouchJoystick
extends Control
## ROV-style floating joystick: faint at its idle spot; a touch anywhere in the left half
## (below the status bar) moves it under the finger; dragging past the rim drags the ring along.
## Coordinates are game-viewport pixels (640×360).

const RADIUS := 48.0
const KNOB := 18.0
const DEADZONE := 6.0
const IDLE_ALPHA := 0.2
const ACTIVE_ALPHA := 0.85
const IDLE_CENTER := Vector2(92, 240)   # in a 640×360 view; follows the bottom-left corner
const TOP_BAR := 56.0

var view_size := Vector2(640, 360)
var vector := Vector2.ZERO      # unit direction or zero
var active := false
var center := IDLE_CENTER
var knob := IDLE_CENTER
var _index := -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	view_size = get_viewport_rect().size
	get_viewport().size_changed.connect(func(): view_size = get_viewport_rect().size; reset())
	reset()

func idle_center() -> Vector2:
	return Vector2(IDLE_CENTER.x, view_size.y - (360.0 - IDLE_CENTER.y))

## App/tab lost focus mid-touch: the release may never arrive.
func release_all() -> void:
	reset()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		release_all()

func reset() -> void:
	active = false
	vector = Vector2.ZERO
	center = idle_center()
	knob = center
	_index = -1
	queue_redraw()

func alpha() -> float:
	return ACTIVE_ALPHA if active else IDLE_ALPHA

## Task 5: a touch for which this returns true never starts the joystick (the HUD sets it: a tap on the open
## waypoint list, which may sit in the left half, must not walk the hero off the stone).
var ignore_at: Callable

func in_zone(pos: Vector2) -> bool:
	if ignore_at.is_valid() and ignore_at.call(pos): return false
	return pos.x < view_size.x * 0.5 and pos.y > TOP_BAR

func handle_touch(index: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		if _index == -1 and in_zone(pos):
			_index = index
			active = true
			center = pos
			knob = pos
			vector = Vector2.ZERO
	elif index == _index:
		reset()
	queue_redraw()

func handle_drag(index: int, pos: Vector2) -> void:
	if index != _index:
		return
	var off := pos - center
	if off.length() > RADIUS:
		center = pos - off.normalized() * RADIUS
		off = pos - center
	knob = pos
	vector = off.normalized() if off.length() > DEADZONE else Vector2.ZERO
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		handle_touch(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		handle_drag(event.index, event.position)

func _draw() -> void:
	var a := alpha()
	draw_circle(center, RADIUS, Color(1, 1, 1, 0.07 * a / ACTIVE_ALPHA))
	draw_arc(center, RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.45 * a), 2.0, true)
	if vector != Vector2.ZERO:
		var ang := vector.angle()
		draw_arc(center, RADIUS - 3, ang - 0.6, ang + 0.6, 16, Color(1, 1, 1, 0.9 * a), 4.0, true)
	draw_circle(knob, KNOB, Color(1, 1, 1, 0.35 * a))
	draw_arc(knob, KNOB, 0, TAU, 32, Color(1, 1, 1, 0.9 * a), 2.0, true)
