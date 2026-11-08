class_name MiniMap
extends Control
## M4c §4 corner minimap (Task 7; spec docs/superpowers/specs/2026-11-07-m4c-farm-links-fog-minimap.md §4 and its
## addendum, owner 2026-11-09). Approved ⚙: 96 x 96 HUD px sideways, 80 x 80 upright, top-right under the HUD's
## top-right buttons, 85 % opacity. It shows the current room only: the room picture shrunk to fill the box, the
## FogGrid's unrevealed cells drawn dark over it (one fog pixel per cell, nearest filter), the hero as a white dot
## with a tick pointing his way, the joined exits as small arrows on the box edge (red into the boss arena) and the
## waypoint stone as a diamond (blue unlocked, grey locked). No monsters (owner 2026-11-09: "ไม่แสดงมอน", the elite
## gold dot included). While the hero's on-screen box overlaps it, it fades to 30 % ("มินิแมพจางลงเหลือ 30%").
## A tap (any finger, TouchTaps; a cancelled touch never taps) emits `tapped`: the full map opens from it in Task 8.
##
## Cost (every frame): track() moves the dot child and compares two rects; the fog image and texture are made once
## per room size and refilled only after FogGrid.changed for this room (at most once a frame); the exit / stone
## layer is redrawn only on a room change or an unlock.
##
## Marks under fog (risk B11, owner 2026-11-09 "แสดงเมื่อหมอกตรงนั้นเปิดแล้ว"): an exit arrow (the red arena one too)
## and the stone diamond show only once the fog cell they sit on is revealed (MARKS_UNDER_FOG = false; the WorldMap
## follows the same constant through mark_shown()). The marks layer is redrawn when a fog refill changes which marks
## show (a reveal uncovering a mark's cell), not on every refill.
## Choices (not in the spec): a room that is not square is stretched to the square box ("the room fills the box"); the fade
## takes FADE_TIME (linear, no Tween object); exit arrows sit on the box edge at the exit's place along it.

signal tapped

const SIDE_LANDSCAPE := 96.0     # ⚙ approved (spec §4)
const SIDE_PORTRAIT := 80.0      # ⚙ approved (spec §4)
const OPACITY := 0.85            # ⚙ approved (spec §4)
const FADED := 0.30              # owner 2026-11-09: hero under the minimap
const FADE_TIME := 0.15          # s for a full fade either way
const BORDER := 3.0              # HUD px of frame round the picture
const FOG := Color(0.02, 0.04, 0.035, 0.92)
const FRAME_BG := Color(0.055, 0.145, 0.11, 1.0)
const FRAME_EDGE := Color(0.93, 0.73, 0.33, 0.9)
const EXIT_COLOR := Color(1.0, 0.95, 0.7)          # as the warp arrows in the room (Warp.ARROW_COLOR)
const EXIT_ARENA := Color("#ff5a4a")               # Warp.ARENA_COLOR
const STONE_ON := Color("#4aa8ff")
const STONE_OFF := Color("#8a8f94")
const OUTLINE := Color(0.03, 0.05, 0.04, 0.95)
const ARROW_LEN := 4.0           # HUD px, from the edge inward
const ARROW_HALF := 3.5
const STONE_HALF := 3.5
const DOT_R := 2.4
const TICK_LEN := 4.5
## Risk B11 (owner 2026-11-09): false = exits and waypoint stones show only once their fog cell is revealed; true =
## they always show. The one switch for both the corner MiniMap and the full WorldMap.
const MARKS_UNDER_FOG := false
const SIDE_DIRS := {"north": Vector2.UP, "south": Vector2.DOWN, "east": Vector2.RIGHT, "west": Vector2.LEFT}

var room_id := ""
var room_size := Vector2(512, 512)
var picture: TextureRect
var fog_rect: TextureRect
var fog_img: Image
var fog_tex: ImageTexture
var fog: FogGrid
var fog_redraws := 0             # tests: fog refills done
var marks_redraws := 0           # tests: exit / stone layer redraws asked for
var exits: Array = []            # [{side, at: Vector2 (room px), arena: bool}]
var stone := Vector2.INF         # the stone's base point (room px); INF = no stone in this room
var stone_unlocked := false
var hero_dot: HeroDot
var tap_button: Button
var under := false               # the hero's screen box overlaps the minimap
var taps := TouchTaps.new()
var _marks_layer: MarksLayer
var _fog_dirty := false
## This minimap's copy of MARKS_UNDER_FOG (tests flip it to check both behaviours; the game never changes it).
var marks_under_fog := MARKS_UNDER_FOG
var _shown_key := -1             # which marks showed at the last marks redraw (bit per exit, then the stone)

func build() -> void:
	name = "MiniMap"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	modulate.a = OPACITY
	picture = TextureRect.new()
	picture.name = "Picture"
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(picture)
	fog_rect = TextureRect.new()
	fog_rect.name = "Fog"
	fog_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fog_rect.stretch_mode = TextureRect.STRETCH_SCALE
	fog_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fog_rect)
	_marks_layer = MarksLayer.new()
	_marks_layer.name = "Marks"
	_marks_layer.map = self
	_marks_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_marks_layer)
	hero_dot = HeroDot.new()
	hero_dot.name = "HeroDot"
	hero_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_dot.size = Vector2.ZERO
	add_child(hero_dot)
	# the whole box is one invisible button: a one-finger tap goes through Godot's emulated mouse (GUI), other
	# fingers through TouchTaps in _input
	tap_button = Button.new()
	tap_button.name = "Tap"
	tap_button.flat = true
	tap_button.focus_mode = Control.FOCUS_NONE
	for k in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		tap_button.add_theme_stylebox_override(k, StyleBoxEmpty.new())
	tap_button.pressed.connect(func(): tapped.emit())
	add_child(tap_button)
	fit(Vector2(640, 360))

## The box side for a view (HUD px): 80 upright, 96 sideways.
static func side_for(view: Vector2) -> float:
	return SIDE_PORTRAIT if ScreenFit.is_portrait(view) else SIDE_LANDSCAPE

## Sizes the box for the view (the HUD places it).
func fit(view: Vector2) -> void:
	var s := side_for(view)
	custom_minimum_size = Vector2(s, s)    # first: a bigger old minimum would keep the box from shrinking
	size = Vector2(s, s)
	var inner := inner_rect()
	for c in [picture, fog_rect, _marks_layer]:
		c.position = inner.position
		c.size = inner.size
	_marks_layer.position = Vector2.ZERO          # draws in the minimap's own coordinates
	_marks_layer.size = size
	tap_button.position = Vector2.ZERO
	tap_button.size = size
	_request_marks()
	queue_redraw()

## The picture's rect inside the box (local HUD px).
func inner_rect() -> Rect2:
	return Rect2(Vector2(BORDER, BORDER), size - Vector2(BORDER, BORDER) * 2.0)

## A room point (room px) on the box (local HUD px), kept on the picture.
func to_map(p: Vector2) -> Vector2:
	var inner := inner_rect()
	var f := Vector2(clampf(p.x / maxf(1.0, room_size.x), 0.0, 1.0), clampf(p.y / maxf(1.0, room_size.y), 0.0, 1.0))
	return inner.position + f * inner.size

## Follows a FogGrid (the game's, one per game): the fog layer is refilled after its `changed` for this room.
func bind_fog(f: FogGrid) -> void:
	if fog and fog.changed.is_connected(_on_fog_changed): fog.changed.disconnect(_on_fog_changed)
	fog = f
	if fog: fog.changed.connect(_on_fog_changed)
	_redraw_fog()

## Shows room id (size_px big, its picture `pic`): its joined exits [{side, at, arena}] and its waypoint stone (base
## point, Vector2.INF without one; `unlocked`). Called on every room change (exit, waypoint travel, new game).
func show_room(id: String, size_px: Vector2, pic: Texture2D, room_exits: Array, stone_at: Vector2, unlocked: bool) -> void:
	room_id = id
	room_size = size_px
	picture.texture = pic
	exits = []
	for e in room_exits:
		var at = e.at
		exits.append({"side": String(e.side), "at": Vector2(at[0], at[1]) if at is Array else at, "arena": bool(e.get("arena", false))})
	stone = stone_at
	stone_unlocked = unlocked
	_redraw_fog()
	_request_marks()

## The stone in this room was unlocked (or locked): the diamond's colour.
func set_stone_unlocked(on: bool) -> void:
	if stone_unlocked == on: return
	stone_unlocked = on
	_request_marks()

## Every frame: the hero's feet (room px) and facing (a unit vector), and his body on screen (HUD px, global) for
## the fade. Moves the dot (no redraw of the rest), turns the tick when the facing changes.
func track(feet: Vector2, facing: Vector2, hero_screen: Rect2) -> void:
	hero_dot.position = to_map(feet)
	if facing != hero_dot.facing:
		hero_dot.facing = facing
		hero_dot.queue_redraw()
	under = hero_screen.size != Vector2.ZERO and hero_screen.intersects(get_global_rect())

## The dot's middle (local HUD px).
func dot_at() -> Vector2:
	return hero_dot.position

## Whether a mark at `at` (room px) of room id shows: always when under_fog, else only once FogGrid has revealed the
## cell it sits on (a point outside the room counts as its nearest edge cell). No FogGrid = nothing hidden.
static func mark_shown(f: FogGrid, id: String, at: Vector2, under_fog := MARKS_UNDER_FOG) -> bool:
	if under_fog or f == null: return true
	var c := f.cells(id)
	var cx := clampi(floori(at.x / FogGrid.CELL), 0, c.x - 1)
	var cy := clampi(floori(at.y / FogGrid.CELL), 0, c.y - 1)
	return f.is_revealed(id, cx, cy)

## Bit i set = exit i shows, bit exits.size() = the stone shows (for spotting a change after a fog refill).
func _shown_bits() -> int:
	var k := 0
	for i in exits.size():
		if mark_shown(fog, room_id, exits[i].at, marks_under_fog): k |= 1 << i
	if stone != Vector2.INF and mark_shown(fog, room_id, Waypoints.centre(stone), marks_under_fog): k |= 1 << exits.size()
	return k

## Opacity the fade heads for.
func target_alpha() -> float:
	return FADED if under else OPACITY

## What the marks layer draws (local HUD px): [{kind: "exit", side, at, color}] and [{kind: "stone", at, color}].
func marks() -> Array:
	var out: Array = []
	var inner := inner_rect()
	for e in exits:
		if not mark_shown(fog, room_id, e.at, marks_under_fog): continue
		var at := to_map(e.at)
		match String(e.side):
			"north": at.y = inner.position.y
			"south": at.y = inner.end.y
			"west": at.x = inner.position.x
			"east": at.x = inner.end.x
		out.append({"kind": "exit", "side": String(e.side), "at": at, "color": EXIT_ARENA if e.arena else EXIT_COLOR})
	if stone != Vector2.INF and mark_shown(fog, room_id, Waypoints.centre(stone), marks_under_fog):
		out.append({"kind": "stone", "at": to_map(Waypoints.centre(stone)), "color": STONE_ON if stone_unlocked else STONE_OFF})
	return out

func _process(delta: float) -> void:
	if _fog_dirty: _redraw_fog()
	var want := target_alpha()
	if modulate.a != want:
		modulate.a = move_toward(modulate.a, want, delta * (OPACITY - FADED) / FADE_TIME)

func _on_fog_changed(id: String) -> void:
	if id == room_id: _fog_dirty = true

## Refills the fog image from the FogGrid (FogGrid.fog_image's picture, without making a new image) and uploads it
## to the same texture; a new image / texture only when the room's cell count differs.
func _redraw_fog() -> void:
	_fog_dirty = false
	if fog == null or room_id == "":
		fog_rect.texture = null
		return
	var c := fog.cells(room_id)
	if fog_img == null or fog_img.get_size() != c:
		fog_img = Image.create_empty(c.x, c.y, false, Image.FORMAT_RGBA8)
		fog_img.fill(FOG)
		fog_tex = ImageTexture.create_from_image(fog_img)
		fog_rect.texture = fog_tex
	fog_img.fill(FOG)
	if fog.known(room_id):
		var clear := Color(0, 0, 0, 0)
		for cy in c.y:
			for cx in c.x:
				if fog.is_revealed(room_id, cx, cy): fog_img.set_pixel(cx, cy, clear)
	fog_tex.update(fog_img)
	fog_redraws += 1
	if not marks_under_fog and _shown_bits() != _shown_key: _request_marks()   # B11: a reveal uncovered a mark

func _request_marks() -> void:
	if _marks_layer == null: return
	_shown_key = _shown_bits()
	marks_redraws += 1
	_marks_layer.queue_redraw()

## The frame round the picture.
func _draw() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = FRAME_BG
	sb.border_color = FRAME_EDGE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	draw_style_box(sb, Rect2(Vector2.ZERO, size))

## Any finger: a tap on the box emits `tapped` (TouchTaps; its cancel rule holds) and every touch on it is marked
## handled so it never reaches the game (the joystick also ignores it, Hud.build).
func _input(e: InputEvent) -> void:
	if not is_visible_in_tree(): return
	var hit := taps.feed(e, self, get_global_rect(), true)
	if not hit and e is InputEventScreenTouch and get_global_rect().has_point((e as InputEventScreenTouch).position): hit = true
	if hit: get_viewport().set_input_as_handled()

## Exit arrows and the stone diamond (static per room).
class MarksLayer extends Control:
	var map: MiniMap
	func _draw() -> void:
		if map == null: return
		for m in map.marks():
			if m.kind == "exit":
				var d: Vector2 = MiniMap.SIDE_DIRS.get(m.side, Vector2.UP)
				var side := Vector2(-d.y, d.x)
				var tip: Vector2 = m.at
				var back := tip - d * MiniMap.ARROW_LEN
				var pts := PackedVector2Array([tip, back + side * MiniMap.ARROW_HALF, back - side * MiniMap.ARROW_HALF])
				var edge := PackedVector2Array([tip + d * 1.0, back + side * (MiniMap.ARROW_HALF + 1.0) - d, back - side * (MiniMap.ARROW_HALF + 1.0) - d])
				draw_colored_polygon(edge, MiniMap.OUTLINE)
				draw_colored_polygon(pts, m.color)
			elif m.kind == "stone":
				var c: Vector2 = m.at
				var h := MiniMap.STONE_HALF
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h - 1), c + Vector2(h + 1, 0), c + Vector2(0, h + 1), c + Vector2(-h - 1, 0)]), MiniMap.OUTLINE)
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h), c + Vector2(h, 0), c + Vector2(0, h), c + Vector2(-h, 0)]), m.color)

## The hero: a white dot with a tick his way (drawn round the node's position).
class HeroDot extends Control:
	var facing := Vector2.DOWN
	func _draw() -> void:
		var tip := facing.normalized() * MiniMap.TICK_LEN
		draw_line(Vector2.ZERO, tip, MiniMap.OUTLINE, 2.6)
		draw_circle(Vector2.ZERO, MiniMap.DOT_R + 0.9, MiniMap.OUTLINE)
		draw_circle(Vector2.ZERO, MiniMap.DOT_R, Color.WHITE)
		draw_line(Vector2.ZERO, tip, Color.WHITE, 1.3)
