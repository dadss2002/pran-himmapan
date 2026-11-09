class_name WorldMap
extends CanvasLayer
## M4c §4 full map (Task 8; docs/superpowers/specs/2026-11-07-m4c-farm-links-fog-minimap.md §4 + addendum).
## Opens from a tap on the corner minimap, the HUD map button or the M key (Hud.open_map); closes with the ✕ button,
## a tap where the minimap is, M or Esc. While open the game is paused (single-player, owner 2026-11-09 "หยุดเกมตาม
## สเปก") and it is always unpaused again: on close, on a room change (test_ground.go_to closes it) and when the map
## leaves the tree (a new game frees the old HUD).
##
## Shows only the rooms visited in this game (fog per game, owner 2026-11-08: FogGrid.known() - every room entered
## has its arrival revealed at once, and the fog lives for one game), each at its grid place in this session's random
## layout (RoomSet.grid_pos) as its shrunk picture with its own fog over it. Linked exits of two drawn rooms are
## joined by a short path line across the gap; an exit into a room not visited yet gets a "?" in the gap. Exits,
## path lines, "?" and waypoint stones follow MiniMap.MARKS_UNDER_FOG (B11, owner 2026-11-09: only once their fog
## cell is revealed). The current room has a bright outline and the hero dot; waypoint stones ("จุดวาป") and the boss
## arena ("บอส") are labelled. Tapping a room shows a small card with its Thai name and level range; tapping
## anywhere else hides it. No monsters (owner 2026-11-09).
##
## Fits the whole visited map inside the screen in both orientations, above ScreenFit.bottom_inset, never under the
## ✕ button or the minimap's spot (both kept in a strip at the top-right: a column on the right sideways, a band at
## the top upright). Any finger taps (TouchTaps; a cancelled touch never taps); while open no touch reaches the game
## (the tree is paused and every touch is marked handled).
##
## Cost: everything is built once on open (one fog texture per drawn room, a few nodes); nothing runs per frame while
## open (no _process); the canvas is redrawn only on open, a resize and the card.

signal opened
signal closed
signal wants_open                 # the M key while shut (the HUD decides, Hud.open_map)

const LAYER := 15                 # over the HUD (10), under the bag / skill screens (20; never open together)
const MARGIN := 8.0               # HUD px round the screen and round the ✕ / minimap strip
const GAP := 0.32                 # gap between room tiles as a fraction of a tile (path lines and "?" live there)
const MAX_TILE := 120.0           # HUD px: a map of one or two rooms does not blow up to the whole screen
const CLOSE_SIDE := IconButton.MIN_TOUCH   # ✕ touch target (44 HUD px)
const DIM := Color(0.016, 0.047, 0.035, 0.94)
const FOG := MiniMap.FOG
const TILE_EDGE := Color(0.93, 0.73, 0.33, 0.55)
const CURRENT := Color("#fff27a")
const ARENA := MiniMap.EXIT_ARENA
const PATH := Color(0.98, 0.92, 0.72, 0.95)
const QUESTION := Color("#f3e9d2")
const LABEL := Color("#f3e9d2")
const STONE_LABEL := "จุดวาป"
const ARENA_LABEL := "บอส"
const TITLE := "แผนที่"

var info: Dictionary = {}         # what open() was given (see open())
var fog: FogGrid
var view := Vector2(640, 360)
var minimap_rect := Rect2()       # the corner minimap's rect (HUD px): a tap there closes; kept clear of the map
var bottom_inset := 0.0
var area := Rect2()               # where the rooms may go
var tile := 0.0
var rects := {}                   # drawn room id -> Rect2 (HUD px)
var card_id := ""                 # the room whose card shows ("" = none)
var builds := 0                   # tests: how many times the rooms were built (once per open)
var close_button: Button
var minimap_zone: Button
var background: Button
var card: PanelContainer
var card_name: Label
var card_level: Label
var title: Label
var _root: Control
var _rooms_layer: Control         # pictures and fog (TextureRects, one pair per drawn room)
var _canvas: MapCanvas            # outlines, paths, "?", stones, labels, hero dot
var _buttons: Control             # one flat Button per drawn room
var _fog_tex := {}                # id -> ImageTexture (made on open)
var _paused_tree := false         # this map paused the tree (and so unpauses it)
var _taps := TouchTaps.new()

func build() -> void:
	name = "WorldMap"
	layer = LAYER
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.name = "Root"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.size = view
	_root.visible = false                         # hidden with the layer: a shut map must take no GUI picks
	add_child(_root)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = DIM
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.position = Vector2(-1000, -1000)
	dim.size = Vector2(4000, 4000)
	_root.add_child(dim)
	background = _flat_button("Background")       # a tap on nothing hides the card
	background.pressed.connect(hide_card)
	_root.add_child(background)
	_rooms_layer = Control.new()
	_rooms_layer.name = "Rooms"
	_rooms_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_rooms_layer)
	_canvas = MapCanvas.new()
	_canvas.name = "Canvas"
	_canvas.map = self
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_canvas)
	_buttons = Control.new()
	_buttons.name = "RoomButtons"
	_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_buttons)
	title = UiKit.label(TITLE, 10, LABEL)
	title.name = "Title"
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	title.add_theme_constant_override("outline_size", 3)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(title)
	card = PanelContainer.new()
	card.name = "Card"
	card.add_theme_stylebox_override("panel", UiKit.box(Color(0.055, 0.145, 0.11, 0.96), Color("#edbb55"), 6, 6))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE   # a tap on it falls to what is under it (same for every finger)
	card.visible = false
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 0)
	card.add_child(col)
	card_name = UiKit.label("", 9, LABEL)
	card_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(card_name)
	card_level = UiKit.label("", 8, Color("#edbb55"))
	card_level.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(card_level)
	_root.add_child(card)
	minimap_zone = _flat_button("MinimapZone")    # "tap the minimap again" closes
	minimap_zone.pressed.connect(close)
	_root.add_child(minimap_zone)
	close_button = Button.new()
	close_button.name = "Close"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.add_theme_stylebox_override("normal", UiKit.box(Color(0.055, 0.145, 0.11, 0.92), Color("#edbb55"), 8, 0))
	close_button.add_theme_stylebox_override("hover", UiKit.box(Color(0.09, 0.2, 0.15, 0.95), Color("#edbb55"), 8, 0))
	close_button.add_theme_stylebox_override("pressed", UiKit.box(Color(0.03, 0.08, 0.06, 0.95), Color("#edbb55"), 8, 0))
	close_button.custom_minimum_size = Vector2(CLOSE_SIDE, CLOSE_SIDE)
	close_button.size = Vector2(CLOSE_SIDE, CLOSE_SIDE)
	close_button.pressed.connect(close)
	var cross := Cross.new()                      # drawn: Kanit has no ✕ glyph
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	close_button.add_child(cross)
	_root.add_child(close_button)

func _flat_button(n: String) -> Button:
	var b := Button.new()
	b.name = n
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.set_meta("click_sound", true)               # no click for these (Hud.wire_click_sounds skips them)
	for k in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		b.add_theme_stylebox_override(k, StyleBoxEmpty.new())
	return b

func is_open() -> bool:
	return visible

## Opens over the game and pauses it. `data`:
## {"fog": FogGrid, "current": room id, "hero": Vector2 (feet, room px), "facing": Vector2,
##  "rooms": {id: {"grid": Vector2i, "size": Vector2, "picture": path, "name": String, "levels": Vector2i (min, max;
##  0 = unknown), "exits": [{"side", "at": Vector2, "to": id, "arena": bool}], "stone": Vector2 (INF = none),
##  "stone_unlocked": bool, "arena": bool}}} - every room on the layout; only the visited ones are drawn.
## view_size, mini (the corner minimap's rect) and inset (ScreenFit.bottom_inset) place everything.
func open(data: Dictionary, view_size: Vector2, mini: Rect2, inset := 0.0) -> void:
	info = data
	fog = data.get("fog")
	card_id = ""
	card.visible = false
	_taps.reset()
	visible = true
	_root.visible = true
	_build_rooms()
	relayout(view_size, mini, inset)
	if is_inside_tree() and not get_tree().paused:
		get_tree().paused = true
		_paused_tree = true
	opened.emit()

## Shuts the map and unpauses the game (if the map paused it). Safe to call when shut.
func close() -> void:
	if not visible: return
	visible = false
	_root.visible = false
	card_id = ""
	card.visible = false
	_taps.reset()
	_unpause()
	for c in _rooms_layer.get_children(): c.free()
	for c in _buttons.get_children(): c.free()
	_fog_tex.clear()
	rects.clear()
	closed.emit()

func _unpause() -> void:
	if _paused_tree and is_inside_tree(): get_tree().paused = false
	_paused_tree = false

## A new game / a freed HUD never leaves the tree paused.
func _exit_tree() -> void:
	if visible and _paused_tree: get_tree().paused = false
	_paused_tree = false
	visible = false
	if _root: _root.visible = false

## The rooms drawn: visited in this game (FogGrid.known) and on the layout (a grid place), sorted.
func drawn_ids() -> Array[String]:
	var out: Array[String] = []
	var rooms: Dictionary = info.get("rooms", {})
	for id in rooms:
		if fog == null or not fog.known(String(id)): continue
		var g = rooms[id].get("grid", Vector2i(-1, -1))
		if g is Vector2i and g.x >= 0 and g.y >= 0: out.append(String(id))
	out.sort()
	return out

## Fog textures and the picture / fog / button nodes for the drawn rooms, once per open.
func _build_rooms() -> void:
	for c in _rooms_layer.get_children(): c.free()
	for c in _buttons.get_children(): c.free()
	_fog_tex.clear()
	builds += 1
	for id in drawn_ids():
		var r: Dictionary = info.rooms[id]
		var pic := TextureRect.new()
		pic.name = id
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_SCALE
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var path := String(r.get("picture", ""))
		if path != "" and ResourceLoader.exists(path): pic.texture = load(path)
		_rooms_layer.add_child(pic)
		var c := fog.cells(id)
		var img := Image.create_empty(c.x, c.y, false, Image.FORMAT_RGBA8)
		img.fill(FOG)
		var clear := Color(0, 0, 0, 0)
		for cy in c.y:
			for cx in c.x:
				if fog.is_revealed(id, cx, cy): img.set_pixel(cx, cy, clear)
		_fog_tex[id] = ImageTexture.create_from_image(img)
		var fr := TextureRect.new()
		fr.name = id + "_fog"
		fr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fr.stretch_mode = TextureRect.STRETCH_SCALE
		fr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		fr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fr.texture = _fog_tex[id]
		_rooms_layer.add_child(fr)
		var b := _flat_button(id)
		b.pressed.connect(show_card.bind(id))
		_buttons.add_child(b)

## The fog texture of a drawn room (tests).
func fog_texture(id: String) -> ImageTexture:
	return _fog_tex.get(id)

## Places everything for a view (on open and on a resize / turn while open).
func relayout(view_size: Vector2, mini: Rect2, inset := 0.0) -> void:
	view = view_size
	minimap_rect = mini
	bottom_inset = inset
	_root.size = view
	background.position = Vector2.ZERO
	background.size = view
	close_button.position = close_rect().position
	close_button.size = close_rect().size
	minimap_zone.visible = mini.size != Vector2.ZERO
	minimap_zone.position = mini.position
	minimap_zone.size = mini.size
	area = map_area(view, keep_out(), inset)
	var grid := {}
	for id in drawn_ids(): grid[id] = info.rooms[id].grid
	var p := plan(grid, area)
	tile = p.tile
	rects = centre_on_screen(p.rects, tile, view, keep_out(), inset)
	for c in _rooms_layer.get_children():
		var id := String(c.name).trim_suffix("_fog")
		if rects.has(id):
			c.position = rects[id].position
			c.size = rects[id].size
	for b in _buttons.get_children():
		if rects.has(String(b.name)):
			b.position = rects[String(b.name)].position
			b.size = rects[String(b.name)].size
	_canvas.position = Vector2.ZERO
	_canvas.size = view
	title.size = title.get_combined_minimum_size()
	var k := keep_out()
	if ScreenFit.is_portrait(view): title.position = Vector2(MARGIN + 2.0, MARGIN + 2.0)
	else: title.position = Vector2(k.get_center().x - title.size.x / 2.0, k.end.y + 2.0)
	if card_id != "": _place_card()
	_canvas.queue_redraw()

## The ✕ button's rect: the screen's top-right corner (where the HUD's settings button is).
func close_rect() -> Rect2:
	return Rect2(Vector2(view.x - MARGIN - CLOSE_SIDE, MARGIN), Vector2(CLOSE_SIDE, CLOSE_SIDE))

## The strip kept free of the map: the ✕ and the minimap's spot (grown by MARGIN / 2).
func keep_out() -> Rect2:
	var k := close_rect()
	if minimap_rect.size != Vector2.ZERO: k = k.merge(minimap_rect)
	return k.grow(MARGIN / 2.0)

## Where the rooms may go: the screen less MARGIN and the bottom inset, less the keep-out strip (a column on the
## right when sideways, a band at the top when upright).
static func map_area(view_size: Vector2, keep: Rect2, inset: float) -> Rect2:
	var safe := Rect2(Vector2(MARGIN, MARGIN), view_size - Vector2(MARGIN * 2.0, MARGIN * 2.0 + inset))
	if ScreenFit.is_portrait(view_size):
		var top := maxf(safe.position.y, keep.end.y + MARGIN / 2.0)
		return Rect2(safe.position.x, top, safe.size.x, maxf(0.0, safe.end.y - top))
	var right := minf(safe.end.x, keep.position.x - MARGIN / 2.0)
	return Rect2(safe.position, Vector2(maxf(0.0, right - safe.position.x), safe.size.y))

## Tile size and each room's rect for grid places (id -> Vector2i) inside `area`: n tiles with a GAP between and a
## GAP round the outside (for a "?"), as big as fits (whole HUD px, at most MAX_TILE), centred in the area.
static func plan(grid: Dictionary, a: Rect2) -> Dictionary:
	if grid.is_empty(): return {"tile": 0.0, "rects": {}}
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	for id in grid:
		var g: Vector2i = grid[id]
		lo = Vector2i(mini(lo.x, g.x), mini(lo.y, g.y))
		hi = Vector2i(maxi(hi.x, g.x), maxi(hi.y, g.y))
	var n := hi - lo + Vector2i.ONE
	var units := Vector2(n.x + (n.x + 1) * GAP, n.y + (n.y + 1) * GAP)
	var t := floorf(minf(MAX_TILE, minf(a.size.x / units.x, a.size.y / units.y)))
	t = maxf(t, 1.0)
	var block := units * t
	var origin := (a.position + (a.size - block) / 2.0).floor()
	var out := {}
	for id in grid:
		var g: Vector2i = grid[id] - lo
		out[id] = Rect2(origin + (Vector2(g) * (1.0 + GAP) + Vector2(GAP, GAP)) * t, Vector2(t, t))
	return {"tile": t, "rects": out}

## The planned rects moved (same tile) so the map block (its "?" ring included) is centred on the whole screen,
## when that still keeps it inside the screen less MARGIN / inset and off the keep-out strip; else as planned.
static func centre_on_screen(planned: Dictionary, t: float, view_size: Vector2, keep: Rect2, inset: float) -> Dictionary:
	if planned.is_empty(): return planned
	var block := Rect2()
	var first := true
	for id in planned:
		block = planned[id] if first else block.merge(planned[id])
		first = false
	block = block.grow(t * GAP)
	var safe := Rect2(Vector2(MARGIN, MARGIN), view_size - Vector2(MARGIN * 2.0, MARGIN * 2.0 + inset))
	var shift := (safe.get_center() - block.get_center()).floor()
	var moved := Rect2(block.position + shift, block.size)
	if not safe.encloses(moved) or moved.intersects(keep): return planned
	var out := {}
	for id in planned: out[id] = Rect2(planned[id].position + shift, planned[id].size)
	return out

## A room point (room px) on its tile (HUD px).
func to_tile(id: String, p: Vector2) -> Vector2:
	var r: Rect2 = rects[id]
	var sz: Vector2 = info.rooms[id].get("size", Vector2(512, 512))
	var f := Vector2(clampf(p.x / maxf(1.0, sz.x), 0.0, 1.0), clampf(p.y / maxf(1.0, sz.y), 0.0, 1.0))
	return r.position + f * r.size

## An exit's point on its tile's edge (HUD px).
func exit_point(id: String, e: Dictionary) -> Vector2:
	var r: Rect2 = rects[id]
	var at := to_tile(id, e.at)
	match String(e.side):
		"north": at.y = r.position.y
		"south": at.y = r.end.y
		"west": at.x = r.position.x
		"east": at.x = r.end.x
	return at

func _shown(id: String, at: Vector2) -> bool:
	return MiniMap.mark_shown(fog, id, at, marks_under_fog)

## This map's copy of MiniMap.MARKS_UNDER_FOG (tests flip it; the game never does).
var marks_under_fog := MiniMap.MARKS_UNDER_FOG

## Path lines between linked exits of two drawn rooms, each link once: [{a, b, from: Vector2, to: Vector2, arena}].
## Shown only when both ends' exits show (B11).
func path_lines() -> Array:
	var out: Array = []
	for id in rects:
		for e in info.rooms[id].get("exits", []):
			var to := String(e.to)
			if not rects.has(to) or to < id: continue
			var back := _exit_to(to, id, e)
			if back.is_empty(): continue
			if not _shown(id, e.at) or not _shown(to, back.at): continue
			out.append({"a": id, "b": to, "from": exit_point(id, e), "to": exit_point(to, back), "arena": bool(e.get("arena", false)) or bool(back.get("arena", false))})
	return out

## Room `id`'s exit back into `to` (the one on the opposite side of e, else any into `to`).
func _exit_to(id: String, to: String, e: Dictionary) -> Dictionary:
	var want := String(RoomLayout.OPPOSITE.get(String(e.side), ""))
	var any := {}
	for b in info.rooms[id].get("exits", []):
		if String(b.to) != to: continue
		if String(b.side) == want: return b
		if any.is_empty(): any = b
	return any

## "?" marks: [{room, side, at: Vector2 (HUD px, in the gap beyond the exit), edge: Vector2, arena}] for every shown
## exit of a drawn room into a room not visited this game.
func question_marks() -> Array:
	var out: Array = []
	for id in rects:
		for e in info.rooms[id].get("exits", []):
			if rects.has(String(e.to)) or not _shown(id, e.at): continue
			var edge := exit_point(id, e)
			var d: Vector2 = MiniMap.SIDE_DIRS.get(String(e.side), Vector2.UP)
			out.append({"room": id, "side": String(e.side), "edge": edge, "at": edge + d * tile * GAP * 0.5, "arena": bool(e.get("arena", false))})
	return out

## Waypoint stones of drawn rooms that show (B11): [{room, at (HUD px), unlocked}].
func stone_marks() -> Array:
	var out: Array = []
	for id in rects:
		var st = info.rooms[id].get("stone", Vector2.INF)
		if not (st is Vector2) or st == Vector2.INF: continue
		var c := Waypoints.centre(st)
		if not _shown(id, c): continue
		out.append({"room": id, "at": to_tile(id, c), "unlocked": bool(info.rooms[id].get("stone_unlocked", false))})
	return out

## Text labels on tiles: [{room, text}] - "จุดวาป" on a room whose stone shows, "บอส" on the arena.
func labels() -> Array:
	var out: Array = []
	for s in stone_marks(): out.append({"room": s.room, "text": STONE_LABEL})
	for id in rects:
		if bool(info.rooms[id].get("arena", false)): out.append({"room": id, "text": ARENA_LABEL})
	return out

## The current room (outlined, with the hero dot), "" when it is not drawn.
func current_id() -> String:
	var c := String(info.get("current", ""))
	return c if rects.has(c) else ""

## The hero dot (HUD px; Vector2.INF when the current room is not drawn).
func hero_at() -> Vector2:
	var c := current_id()
	return to_tile(c, info.get("hero", Vector2.ZERO)) if c != "" else Vector2.INF

## "Lv 3" / "Lv 3–4" / "" (unknown).
static func level_text(levels: Vector2i) -> String:
	if levels.x <= 0: return ""
	if levels.y <= levels.x: return "Lv %d" % levels.x
	return "Lv %d–%d" % [levels.x, levels.y]

## Shows room id's card (its name and level range) next to its tile.
func show_card(id: String) -> void:
	if not rects.has(id): return
	card_id = id
	var r: Dictionary = info.rooms[id]
	card_name.text = String(r.get("name", id))
	card_level.text = level_text(r.get("levels", Vector2i.ZERO))
	card_level.visible = card_level.text != ""
	card.visible = true
	card.size = Vector2.ZERO
	_place_card()

func hide_card() -> void:
	card_id = ""
	card.visible = false

## The card beside its room's tile: under, over, right or left of it, the first that stays inside the screen (less
## MARGIN and the bottom inset) and off the ✕ / minimap strip; else the closest such spot is clamped in.
func _place_card() -> void:
	card.size = card.get_combined_minimum_size()
	var sz := card.size
	var r: Rect2 = rects[card_id]
	var safe := Rect2(Vector2(MARGIN, MARGIN), view - Vector2(MARGIN * 2.0, MARGIN * 2.0 + bottom_inset))
	var k := keep_out()
	var g := 3.0
	var tries := [Vector2(r.get_center().x - sz.x / 2.0, r.end.y + g), Vector2(r.get_center().x - sz.x / 2.0, r.position.y - g - sz.y),
		Vector2(r.end.x + g, r.get_center().y - sz.y / 2.0), Vector2(r.position.x - g - sz.x, r.get_center().y - sz.y / 2.0)]
	var best := Vector2.INF
	for t in tries:
		var p := Vector2(clampf(t.x, safe.position.x, safe.end.x - sz.x), clampf(t.y, safe.position.y, safe.end.y - sz.y))
		var c := Rect2(p, sz)
		if c.intersects(k) or c.intersects(r): continue
		best = p
		break
	if best == Vector2.INF:   # nowhere clear of the tile: under it, kept on screen and off the strip
		best = Vector2(clampf(tries[0].x, safe.position.x, safe.end.x - sz.x), clampf(tries[0].y, safe.position.y, safe.end.y - sz.y))
		if Rect2(best, sz).intersects(k):
			if ScreenFit.is_portrait(view): best.y = maxf(best.y, k.end.y + 1.0)
			else: best.x = minf(best.x, k.position.x - 1.0 - sz.x)
	card.position = best.floor()

## Any finger (TouchTaps): taps on the map's buttons; while open every touch and every drag stops here
## (review M1: a finger sliding over the open map must not reach the joystick or the game).
func _input(e: InputEvent) -> void:
	if _taps.feed(e, _root, TouchTaps.EVERYWHERE, visible) or (visible and e is InputEventScreenDrag):
		get_viewport().set_input_as_handled()

## M toggles (opening goes through the HUD: Hud.open_map); Esc closes.
func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		if e.is_action_pressed("map"):
			wants_open.emit()
			get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("map") or e.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

## Tile frames, the current room's outline, path lines, "?", stones, labels and the hero dot.
class MapCanvas extends Control:
	var map: WorldMap
	var draws := 0               # tests: redraws (only on open, a resize and the card)
	func _draw() -> void:
		draws += 1
		if map == null or map.rects.is_empty(): return
		var font := get_theme_default_font()
		var fsz := UiKit.fs(7)
		var line_w := maxf(1.5, map.tile * 0.05)
		for p in map.path_lines():
			draw_line(p.from, p.to, MiniMap.OUTLINE, line_w + 2.0)
			draw_line(p.from, p.to, WorldMap.ARENA if p.arena else WorldMap.PATH, line_w)
		for id in map.rects:
			var r: Rect2 = map.rects[id]
			var arena := bool(map.info.rooms[id].get("arena", false))
			draw_rect(r, WorldMap.ARENA if arena else WorldMap.TILE_EDGE, false, 1.0)
		for q in map.question_marks():
			draw_line(q.edge, q.edge + (q.at - q.edge) * 0.45, WorldMap.ARENA if q.arena else WorldMap.PATH, line_w)
			var qs := UiKit.fs(9)
			var w := font.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, qs).x
			var at: Vector2 = q.at + Vector2(-w / 2.0, qs * 0.35)
			draw_string_outline(font, at, "?", HORIZONTAL_ALIGNMENT_LEFT, -1, qs, 3, MiniMap.OUTLINE)
			draw_string(font, at, "?", HORIZONTAL_ALIGNMENT_LEFT, -1, qs, WorldMap.ARENA if q.arena else WorldMap.QUESTION)
		var h := clampf(map.tile * 0.07, MiniMap.STONE_HALF, 6.0)
		for s in map.stone_marks():
			var c: Vector2 = s.at
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h - 1), c + Vector2(h + 1, 0), c + Vector2(0, h + 1), c + Vector2(-h - 1, 0)]), MiniMap.OUTLINE)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h), c + Vector2(h, 0), c + Vector2(0, h), c + Vector2(-h, 0)]), MiniMap.STONE_ON if s.unlocked else MiniMap.STONE_OFF)
		for l in map.labels():
			var r: Rect2 = map.rects[l.room]
			var w := font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
			var low := true                  # the stone label goes under the tile's bottom edge unless the stone is there
			for st in map.stone_marks():
				if st.room == l.room and st.at.y > r.get_center().y: low = false
			var y := r.end.y - 3.0 if (l.text == WorldMap.STONE_LABEL and low) else r.position.y + fsz + 1.0
			var at := Vector2(r.get_center().x - w / 2.0, y)
			draw_string_outline(font, at, l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, 3, MiniMap.OUTLINE)
			draw_string(font, at, l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, WorldMap.ARENA if l.text == WorldMap.ARENA_LABEL else WorldMap.LABEL)
		var cur := map.current_id()
		if cur != "":
			var r: Rect2 = map.rects[cur]
			draw_rect(r.grow(1.5), MiniMap.OUTLINE, false, 3.0)
			draw_rect(r.grow(1.0), WorldMap.CURRENT, false, 2.0)
			var p := map.hero_at()
			var f: Vector2 = map.info.get("facing", Vector2.DOWN)
			var tip := p + f.normalized() * MiniMap.TICK_LEN * 1.3
			draw_line(p, tip, MiniMap.OUTLINE, 3.0)
			draw_circle(p, MiniMap.DOT_R * 1.3 + 1.0, MiniMap.OUTLINE)
			draw_circle(p, MiniMap.DOT_R * 1.3, Color.WHITE)
			draw_line(p, tip, Color.WHITE, 1.5)

## The ✕ on the close button.
class Cross extends Control:
	func _draw() -> void:
		var c := size / 2.0
		var d := minf(size.x, size.y) * 0.2
		for w in [[4.0, MiniMap.OUTLINE], [2.2, Color("#f3e9d2")]]:
			draw_line(c + Vector2(-d, -d), c + Vector2(d, d), w[1], w[0])
			draw_line(c + Vector2(-d, d), c + Vector2(d, -d), w[1], w[0])
