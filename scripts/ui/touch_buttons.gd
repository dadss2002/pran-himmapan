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

## Portrait (360 px wide): the skill arc stays in the bottom-right corner; dodge and the potions move
## up over it so the whole left half stays free for the joystick. Offsets from the bottom-right corner.
const PORTRAIT_OFF := {
	"dodge": Vector2(-150, -170),
	"potion_hp": Vector2(-56, -215),
	"potion_mp": Vector2(-104, -212),
}

## Every button keeps its distance from the bottom-right corner (wider screens, portrait).
func layout(size: Vector2) -> void:
	view_size = size
	var portrait := size.y > size.x
	var i := 0
	for name in buttons:
		var off: Vector2 = buttons[name].off
		if portrait and PORTRAIT_OFF.has(name): off = PORTRAIT_OFF[name]
		buttons[name].center = size + off
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
	# Sizes follow the touch-target guidance (docs/design/design-research.md §4): skills r24 ≈ 48+ pt
	# across, dodge r26, potions r20; the skill arc sits on a 97 px circle round the shoot button.
	_add("shoot", "attack", Vector2(584, 302), 36, "res://assets/skills/basic_shot.png", true, "ยิง")
	_add("skill1", "skill_1", Vector2(487, 302), 24, "res://assets/skills/piercing.png", true, "")
	_add("skill2", "skill_2", Vector2(500, 253.5), 24, "res://assets/skills/spread.png", false, "Lv3")
	_add("skill3", "", Vector2(535.5, 218), 24, "res://assets/skills/arrow_rain.png", false, "Lv7")
	_add("skill4", "", Vector2(584, 205), 24, "res://assets/skills/slot_empty.png", false, "")
	_add("dodge", "dodge", Vector2(430, 312), 26, "res://assets/skills/dodge.png", true, "กลิ้ง")
	_add("potion_hp", "potion_hp", Vector2(446, 262), 20, "res://assets/items/potion_hp.png", true, "5")
	_add("potion_mp", "potion_mp", Vector2(398, 276), 20, "res://assets/items/potion_mp.png", true, "3")

func _add(name: String, action: String, c: Vector2, r: float, icon: String, enabled: bool, note: String) -> void:
	buttons[name] = {"action": action, "center": c, "radius": r, "enabled": enabled, "note": note, "off": c - BASE}
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

## Live state from the HUD: locked/unusable buttons grey out and ignore touches.
func set_state(name: String, enabled: bool, note: String) -> void:
	var b: Dictionary = buttons[name]
	if b.enabled == enabled and b.note == note: return
	b.enabled = enabled
	b.note = note
	var i := buttons.keys().find(name)
	get_child(i).material.set_shader_parameter("dim", 0.0 if enabled else 0.75)
	queue_redraw()

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
			draw_string(FONT, b.center + Vector2(-15, 6), t, HORIZONTAL_ALIGNMENT_CENTER, 30, UiKit.fs(12), Color.WHITE)
		if b.note != "":
			var y: float = b.radius + 11
			draw_string_outline(FONT, b.center + Vector2(-30, y), b.note, HORIZONTAL_ALIGNMENT_CENTER, 60, UiKit.fs(9), 3, Color(0, 0, 0, 0.8))
			draw_string(FONT, b.center + Vector2(-30, y), b.note, HORIZONTAL_ALIGNMENT_CENTER, 60, UiKit.fs(9), Color("#fde39a"))
