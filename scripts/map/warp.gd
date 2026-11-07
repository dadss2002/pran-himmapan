class_name Warp
extends Node2D
## A warp circle on the ground. step() reports, once, when the hero's feet come within RoomSet.WARP_RADIUS;
## after that it stays quiet until the hero has moved further than RoomSet.REARM away (so arriving
## next to a warp never sends you straight back).
## M4c §1: the glowing ring (warp_ring FX), a small arrow pointing out of the room, and a label with the
## next room's Thai name shown within LABEL_RANGE px ("→ <name>"; red with a drawn skull into the arena).

const LABEL_RANGE := 48.0            # approved (spec M4c §1)
const LABEL_COLOR := Color("#fff4d6")
const ARENA_COLOR := Color("#ff5a4a")
const ARROW_COLOR := Color(1.0, 0.95, 0.7, 0.9)
const ARROW_AT := Vector2(8, 5)      # px from the ring's middle toward the room's edge, sideways / up-down
                                     # (on the ring, so exits by the very edge still show it)
const SIDE_DIRS := {"north": Vector2.UP, "south": Vector2.DOWN, "east": Vector2.RIGHT, "west": Vector2.LEFT}

var warp_id := ""
var to_room := ""
var to_warp := ""
var to_name := ""
var to_arena := false
var armed := true
var ring: FxSprite
var label: Control                   # built by make_label(); lives on the screen-resolution text layer
var _t := 0.0

## w: the warp's rooms.json entry; to: the room it leads to (for its name and arena flag).
static func make(w: Dictionary, to: Dictionary = {}) -> Warp:
	var n := Warp.new()
	n.warp_id = String(w.id)
	n.to_room = String(w.to)
	n.to_warp = String(w.to_warp)
	n.to_name = String(to.get("name", ""))
	n.to_arena = bool(to.get("arena", false))
	n.position = Vector2(w.at[0], w.at[1])
	n.name = "Warp_" + n.warp_id
	n.z_index = -9
	if FxSprite._manifest().has("warp_ring"):
		n.ring = FxSprite.make("warp_ring", true)
		n.ring.show_behind_parent = true   # the arrow draws over the ring
		n.add_child(n.ring)
		n.ring.play("warp_ring")
	return n

func step(hero_pos: Vector2) -> bool:
	var d := hero_pos.distance_to(position)
	if not armed:
		if d > RoomSet.REARM: armed = true
		return false
	if d <= RoomSet.WARP_RADIUS:
		armed = false
		return true
	return false

func label_text() -> String:
	return "→ " + (to_name if to_name != "" else to_room)

func label_color() -> Color:
	return ARENA_COLOR if to_arena else LABEL_COLOR

## true while the hero's feet are within LABEL_RANGE px of the ring.
func show_label(hero_pos: Vector2) -> bool:
	return hero_pos.distance_to(position) <= LABEL_RANGE

## Out of the room: the side the warp sits on (north = up).
func out_dir() -> Vector2:
	return SIDE_DIRS.get(warp_id, Vector2.UP)

## The label control: [skull if arena] + "→ name", outlined like the damage numbers. Its origin is
## the middle of its bottom edge once placed with place_label().
func make_label() -> Control:
	var box := HBoxContainer.new()
	box.name = "ExitLabel_" + warp_id
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	if to_arena:
		var s := Skull.new()
		s.name = "Skull"
		s.custom_minimum_size = Vector2(9, 10)
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(s)
	var l := Label.new()
	l.name = "Text"
	l.text = label_text()
	l.add_theme_color_override("font_color", label_color())
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 3)
	l.add_theme_font_size_override("font_size", 11)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(l)
	box.visible = false
	box.z_index = 40
	label = box
	return box

## Where the label goes, clear of a hero standing by the ring: beside the ring for north/south exits
## (right side, left if it would leave the room; nudged toward the room's middle), above a hero's head for east/west exits; always
## inside the room.
func place_label(room_size: Vector2) -> void:
	if label == null: return
	var sz := label.get_combined_minimum_size()
	label.size = sz
	var at: Vector2
	if warp_id == "north" or warp_id == "south":
		# a little into the room from the ring's row, away from the top HUD / bottom buttons
		at = Vector2(position.x + 30.0, position.y + 8.0 if warp_id == "north" else position.y - 8.0 - sz.y)
		if at.x + sz.x > room_size.x - 2.0: at.x = position.x - 30.0 - sz.x
	else:
		at = Vector2(position.x - sz.x / 2.0, position.y - 50.0 - sz.y)
	at.x = clampf(at.x, 2.0, maxf(2.0, room_size.x - sz.x - 2.0))
	at.y = clampf(at.y, 2.0, maxf(2.0, room_size.y - sz.y - 2.0))
	label.position = at

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

## The arrow: a small chevron on the ring pointing toward the room edge, bobbing 2 px outward.
func _draw() -> void:
	var d := out_dir()
	var side := Vector2(-d.y, d.x)
	var at := ARROW_AT.x if d.x != 0.0 else ARROW_AT.y
	var tip := d * (at + 2.0 * (0.5 + 0.5 * sin(_t * 4.0)))
	var back := tip - d * 6.0
	var pts := PackedVector2Array([tip, back + side * 6.0, back + d * 2.0, back - side * 6.0])
	var edge := PackedVector2Array([tip + d * 1.5, back + side * 7.5 - d * 0.8, back + d * 2.0 - d * 1.2,
		back - side * 7.5 - d * 0.8])
	draw_colored_polygon(edge, Color(0.05, 0.08, 0.05, 0.85))
	draw_colored_polygon(pts, ARROW_COLOR if not to_arena else ARENA_COLOR.lightened(0.2))

## A small drawn skull (Kanit has no ☠ glyph).
class Skull extends Control:
	func _draw() -> void:
		var w := size.x
		var c := Color("#ff5a4a")
		var o := Color(0, 0, 0, 0.9)
		var mid := Vector2(w / 2.0, 4.0)
		draw_circle(mid, 4.6, o)
		draw_rect(Rect2(mid.x - 3.0, 5.5, 6.0, 4.5), o)
		draw_circle(mid, 3.6, c)
		draw_rect(Rect2(mid.x - 2.0, 5.5, 4.0, 3.5), c)
		draw_rect(Rect2(mid.x - 2.6, 3.0, 1.8, 1.8), o)
		draw_rect(Rect2(mid.x + 0.8, 3.0, 1.8, 1.8), o)
		draw_rect(Rect2(mid.x - 0.5, 7.5, 1.0, 1.5), o)
