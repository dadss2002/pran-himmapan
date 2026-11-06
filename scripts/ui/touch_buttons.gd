class_name TouchButtons
extends Node2D
## Right-hand touch buttons (layout from the approved mockup, scaled to the 640×360 viewport).
## Multi-touch safe: each finger index presses at most one button and only that finger releases it.

const FONT := preload("res://assets/fonts/Kanit-SemiBold.ttf")
const MASK := preload("res://shaders/circle_mask.gdshader")

## name -> {action, center, radius, icon, enabled, note, count}
var buttons := {}
var _held := {}          # touch index -> button name
var _cd := {}            # name -> [remaining, total]
var view_size := Vector2(640, 360)
const BASE := Vector2(640, 360)   # layout below is authored for this view; buttons hug the bottom-right

func _ready() -> void:
	if buttons.is_empty():
		build_default()
	layout(get_viewport_rect().size)
	get_viewport().size_changed.connect(func(): layout(get_viewport_rect().size))

## Keep every button at the same distance from the bottom-right corner on wider screens.
func layout(size: Vector2) -> void:
	var shift := size - view_size
	view_size = size
	var i := 0
	for name in buttons:
		buttons[name].center += shift
		get_child(i).position = buttons[name].center
		i += 1
	queue_redraw()

func release_all() -> void:
	for idx in _held.keys():
		var name: String = _held[idx]
		_held.erase(idx)
		if not _held.values().has(name):
			Input.action_release(buttons[name].action)
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		release_all()

func build_default() -> void:
	_add("shoot", "attack", Vector2(584, 302), 34, "res://assets/skills/basic_shot.png", true, "ยิง")
	_add("skill1", "", Vector2(506, 302), 20, "res://assets/skills/piercing.png", false, "เร็ว ๆ นี้")
	_add("skill2", "", Vector2(516.5, 263), 20, "res://assets/skills/spread.png", false, "Lv3")
	_add("skill3", "", Vector2(545, 234.5), 20, "res://assets/skills/arrow_rain.png", false, "Lv7")
	_add("skill4", "", Vector2(584, 224), 20, "res://assets/skills/slot_empty.png", false, "")
	_add("dodge", "dodge", Vector2(447, 314), 23, "res://assets/skills/dodge.png", true, "กลิ้ง")
	_add("potion_hp", "", Vector2(394, 321), 17, "res://assets/items/potion_hp.png", false, "0")
	_add("potion_mp", "", Vector2(355, 321), 17, "res://assets/items/potion_mp.png", false, "0")

func _add(name: String, action: String, c: Vector2, r: float, icon: String, enabled: bool, note: String) -> void:
	buttons[name] = {"action": action, "center": c, "radius": r, "enabled": enabled, "note": note}
	var s := Sprite2D.new()
	s.texture = load(icon)
	s.position = c
	var tex_size: Vector2 = s.texture.get_size()
	s.scale = Vector2.ONE * (r * 2.0 / tex_size.x)
	var m := ShaderMaterial.new()
	m.shader = MASK
	m.set_shader_parameter("dim", 0.0 if enabled else 0.75)
	s.material = m
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.show_behind_parent = true   # icons under the rings / cooldown shade drawn in _draw
	add_child(s)

func center_of(name: String) -> Vector2:
	return buttons[name].center

func pressed_names() -> Array:
	return _held.values()

func set_cooldown(name: String, remaining: float, total: float) -> void:
	_cd[name] = [remaining, total]
	queue_redraw()

func handle_touch(index: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		for name in buttons:
			var b: Dictionary = buttons[name]
			if b.enabled and b.action != "" and pos.distance_to(b.center) <= b.radius + 6.0:
				_held[index] = name
				Input.action_press(b.action)
				break
	elif _held.has(index):
		var name: String = _held[index]
		_held.erase(index)
		if not _held.values().has(name):
			Input.action_release(buttons[name].action)
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		handle_touch(event.index, event.position, event.pressed)

func _draw() -> void:
	for name in buttons:
		var b: Dictionary = buttons[name]
		var held: bool = _held.values().has(name)
		var ring := Color("#edbb55") if b.enabled else Color("#6b6450")
		if name == "dodge": ring = Color("#7fd0c0")
		if held:
			draw_circle(b.center, b.radius, Color(1, 1, 1, 0.18))
		draw_arc(b.center, b.radius + 1, 0, TAU, 40, ring, 2.0 if name != "shoot" else 3.0, true)
		if _cd.has(name) and _cd[name][0] > 0.0:
			var frac: float = clampf(_cd[name][0] / _cd[name][1], 0.0, 1.0)
			var pts := PackedVector2Array([b.center])
			for k in 25:
				var a := -PI / 2 + TAU * frac * k / 24.0
				pts.append(b.center + Vector2(cos(a), sin(a)) * b.radius)
			draw_colored_polygon(pts, Color(0, 0, 0, 0.55))
			var t := "%.1f" % _cd[name][0]
			draw_string(FONT, b.center + Vector2(-10, 5), t, HORIZONTAL_ALIGNMENT_CENTER, 20, 12, Color.WHITE)
		if b.note != "":
			var y: float = b.radius + 9
			draw_string_outline(FONT, b.center + Vector2(-30, y), b.note, HORIZONTAL_ALIGNMENT_CENTER, 60, 9, 3, Color(0, 0, 0, 0.8))
			draw_string(FONT, b.center + Vector2(-30, y), b.note, HORIZONTAL_ALIGNMENT_CENTER, 60, 9, Color("#fde39a"))
