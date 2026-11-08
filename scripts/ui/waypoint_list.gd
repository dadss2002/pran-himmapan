class_name WaypointList
extends PanelContainer
## The waypoint travel list (M4c §2, Task 5): opens while the hero stands on an unlocked waypoint stone. A title
## "จุดวาป" with a close button ("ปิด"), then one row per unlocked stone with its room's Thai name (rooms.json
## "name"); the room the hero stands in is marked "· ที่นี่" (still tappable: a trip there re-rolls the monsters,
## the way to reset a room). Rows and the close button are at least IconButton.MIN_TOUCH (44) HUD px tall; one
## column upright, two side by side on a phone held sideways. The HUD places it (spot()) inside the safe area,
## clear of the HUD panels, the touch buttons, the joystick ring and the hero.

signal chosen(id: String)
signal closed

const GOLD := Color("#edbb55")
const ROW_W := 128.0                 # HUD px: room for the longest name ("ทางแยกขอนไม้ · ที่นี่")
const HERE_COLOR := Color("#9fe3ff")
const MARGIN := 4.0                  # HUD px kept from every blocked rect (touch buttons react 6 px outside
                                     # their ring; their blocked rect already adds 3)

var title: Label
var close_button: Button
var grid: GridContainer
var rows := {}                       # room id -> Button
var here := ""

func build() -> void:
	name = "WaypointList"
	visible = false
	add_theme_stylebox_override("panel", UiKit.box(Color(0.055, 0.145, 0.11, 0.92), GOLD, 8, 6))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	add_child(col)
	var head := HBoxContainer.new()
	head.name = "Head"
	col.add_child(head)
	title = UiKit.label("จุดวาป", 10, GOLD)
	title.name = "Title"
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("outline_size", 2)
	head.add_child(title)
	close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "ปิด"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.add_theme_font_size_override("font_size", UiKit.fs(9))
	close_button.custom_minimum_size = Vector2(IconButton.MIN_TOUCH + 8, IconButton.MIN_TOUCH)
	close_button.pressed.connect(func():
		close()
		closed.emit())
	head.add_child(close_button)
	grid = GridContainer.new()
	grid.name = "Rows"
	grid.columns = 1
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	col.add_child(grid)

## Shows the list: entries = [{id, name}] (the unlocked stones, list order); `here_id` = the room the hero is in.
func open(entries: Array, here_id: String) -> void:
	here = here_id
	for c in grid.get_children(): c.free()
	rows.clear()
	for e in entries:
		var id := String(e.id)
		var b := Button.new()
		b.name = "Row_" + id
		b.focus_mode = Control.FOCUS_NONE
		b.text = String(e.name) + (" · ที่นี่" if id == here_id else "")
		b.add_theme_font_size_override("font_size", UiKit.fs(9))
		b.custom_minimum_size = Vector2(ROW_W, IconButton.MIN_TOUCH)
		if id == here_id:
			for k in ["font_color", "font_hover_color", "font_pressed_color"]: b.add_theme_color_override(k, HERE_COLOR)
		b.pressed.connect(func(): chosen.emit(id))
		grid.add_child(b)
		rows[id] = b
	visible = true
	size = get_combined_minimum_size()

func close() -> void:
	visible = false

func is_open() -> bool:
	return visible

## One column upright, two sideways (only when there is more than one row).
func fit_columns(portrait: bool) -> void:
	var cols := 1 if portrait or rows.size() < 2 else 2
	if grid.columns != cols:
		grid.columns = cols
	size = get_combined_minimum_size()

## Where a panel of size `sz` goes (top-left, HUD px): inside `safe`, clear of every rect in `blocked` (grown by
## MARGIN) and of the rects in `avoid` (grown too; the hero first, then his stone): when no spot clears all of them
## the last one is dropped, then the next, so the hero is kept clear before the stone, and the HUD always. As close
## as possible to `prefer` (the panel's wanted middle). Candidates are the safe edges, the rects' edges and the
## wanted spot, so the answer is exact and cheap. Vector2.INF when nothing fits even with no `avoid`.
static func spot(sz: Vector2, safe: Rect2, blocked: Array, avoid: Array, prefer: Vector2) -> Vector2:
	var keep: Array = []
	for r in avoid:
		if (r as Rect2).size != Vector2.ZERO: keep.append(r)
	while true:
		var at := _spot(sz, safe, blocked + keep, prefer)
		if at != Vector2.INF or keep.is_empty(): return at
		keep.pop_back()
	return Vector2.INF

static func _spot(sz: Vector2, safe: Rect2, blocked: Array, prefer: Vector2) -> Vector2:
	var grown: Array = []
	for r in blocked: grown.append((r as Rect2).grow(MARGIN))
	var xs := [safe.position.x, safe.end.x - sz.x, prefer.x - sz.x / 2.0]
	var ys := [safe.position.y, safe.end.y - sz.y, prefer.y - sz.y / 2.0]
	for r in grown:
		xs.append_array([r.end.x, r.position.x - sz.x])
		ys.append_array([r.end.y, r.position.y - sz.y])
	var best := Vector2.INF
	var best_d := INF
	for x in xs:
		for y in ys:
			var p := Vector2(x, y)
			var rect := Rect2(p, sz)
			if not safe.encloses(rect): continue
			var d := (p + sz / 2.0).distance_squared_to(prefer)
			if d >= best_d or not fits(rect, grown): continue
			best_d = d
			best = p
	return best

## true when rect touches none of `rects`.
static func fits(rect: Rect2, rects: Array) -> bool:
	for r in rects:
		if rect.intersects(r): return false
	return true
