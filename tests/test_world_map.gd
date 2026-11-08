extends RefCounted
## M4c §4 full map (Task 8; docs/superpowers/specs/2026-11-07-m4c-farm-links-fog-minimap.md §4 + addendum): only the
## rooms visited in this game, each at its grid place in this session's random layout with its own fog; path lines
## between linked exits of drawn rooms; "?" on exits into rooms not visited; current room outlined + hero dot; stones
## and the arena labelled; tap a room for its name and level range. Opens from the minimap, the map button and M;
## closes with ✕, the minimap spot, M and Esc; pauses the game and always unpauses. Fits 5 phone sizes both ways,
## never under the ✕ / minimap or the iPhone bottom inset. Second fingers tap (TouchTaps), cancelled touches never.
## B11 (owner 2026-11-09): exits, "?", path lines and stones only once their fog cell is revealed.

const SAVE := "user://test_world_map_save.json"
const SETTINGS := "user://test_world_map_settings.json"
const SIZES := [Vector2i(1688, 780), Vector2i(780, 1688), Vector2i(1334, 750), Vector2i(750, 1334), Vector2i(1280, 720)]

var tree: SceneTree

func setup(t: SceneTree) -> void:
	tree = t

func _clean() -> void:
	for f in [SAVE, SETTINGS]:
		if FileAccess.file_exists(f): DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

func _ground() -> Node2D:
	var g: Node2D = load("res://scenes/test_ground.tscn").instantiate()
	g.layout_seed = 7
	g.save_path = SAVE
	g.settings_path = SETTINGS
	tree.root.add_child(g)
	await tree.process_frame
	_quiet(g)
	return g

func _quiet(g: Node2D) -> void:
	for p in g.packs: p.calm = 1000.0

func _free(n: Node) -> void:
	if is_instance_valid(n):
		n.queue_free()
		await tree.process_frame
	tree.paused = false

## Walks from the hero's room through warps into `n` rooms not visited yet (each step: the first joined room not
## known to the fog), like a player; returns the rooms entered.
func _walk(g: Node2D, n: int) -> Array:
	var went: Array = []
	for i in n:
		var next := {}
		for w in g.rooms.room(g.room_id).warps:
			if not g.fog.known(String(w.to)):
				next = w
				break
		if next.is_empty():
			for id in g.fog.known_ids():
				for w in g.rooms.room(id).warps:
					if next.is_empty() and not g.fog.known(String(w.to)):
						g.go_to(id, "", false)
						next = w
			if next.is_empty(): break
		g.go_to(String(next.to), String(next.to_warp), false)
		_quiet(g)
		went.append(g.room_id)
	return went

## Every room on the layout entered (the biggest map this seed can show).
func _visit_all(g: Node2D) -> void:
	for id in g.rooms.active.get("pos", {}):
		g.go_to(String(id), "", false)
	g.go_to("c1r1", "", false)
	_quiet(g)

## Reveals all of room id's fog.
func _reveal_room(f: FogGrid, id: String) -> void:
	var c := f.cells(id)
	for cy in c.y:
		for cx in c.x:
			f.reveal(id, Vector2(cx * FogGrid.CELL + 16, cy * FogGrid.CELL + 16))

func _window(hud: Hud, o: Vector2i) -> Vector2:
	var w := tree.root
	DisplayServer.window_set_size(o)
	w.size = o
	w.content_scale_size = ScreenFit.base_for(o)
	for i in 4: await tree.process_frame
	var view := w.get_visible_rect().size
	hud.buttons.layout(view)
	hud.joystick.view_size = view
	hud.joystick.reset()
	hud.layout(view)
	await tree.process_frame
	return view

func _restore(size0: Vector2i, scale0: Vector2i) -> void:
	var w := tree.root
	DisplayServer.window_set_size(size0)
	w.size = size0
	w.content_scale_size = scale0
	for i in 3: await tree.process_frame

## A touch (with Godot's emulated mouse for the GUI finger); true when marked handled.
func _touch(index: int, p: Vector2, pressed: bool, mouse := false, canceled := false) -> bool:
	if mouse:
		var mm := InputEventMouseMotion.new()
		mm.device = InputEvent.DEVICE_ID_EMULATION
		mm.position = p
		mm.global_position = p
		tree.root.push_input(mm, true)
		var mb := InputEventMouseButton.new()
		mb.device = InputEvent.DEVICE_ID_EMULATION
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		mb.pressed = pressed
		mb.position = p
		mb.global_position = p
		tree.root.push_input(mb, true)
	var st := InputEventScreenTouch.new()
	st.index = index
	st.position = p
	st.pressed = pressed
	st.canceled = canceled
	tree.root.push_input(st, true)
	return tree.root.is_input_handled()

func _tap(p: Vector2) -> void:
	_touch(0, p, true, true)
	await tree.process_frame
	_touch(0, p, false, true)
	await tree.process_frame

func _key(code: Key) -> void:
	for down in [true, false]:
		var k := InputEventKey.new()
		k.keycode = code
		k.physical_keycode = code
		k.pressed = down
		tree.root.push_input(k)
		await tree.process_frame

## A bare map with hand-made data: rooms a (grid 0,0) and b (1,0) joined a.east <-> b.west, a.north into c
## (grid 0,-1, not visited), a stone in a; b is the arena. Only the cells round a's middle and b's middle revealed.
func _bare() -> Array:
	var f := FogGrid.new()
	for id in ["a", "b", "c"]: f.set_room_size(id, Vector2(512, 512))
	f.reveal("a", Vector2(256, 256))
	f.reveal("b", Vector2(256, 256))
	var data := {"fog": f, "current": "a", "hero": Vector2(256, 256), "facing": Vector2.RIGHT, "rooms": {
		"a": {"grid": Vector2i(0, 0), "size": Vector2(512, 512), "picture": "", "name": "ห้องเอ", "levels": Vector2i(2, 3),
			"exits": [{"side": "east", "at": Vector2(504, 240), "to": "b", "arena": true}, {"side": "north", "at": Vector2(250, 8), "to": "c", "arena": false}],
			"stone": Vector2(120, 400), "stone_unlocked": true, "arena": false},
		"b": {"grid": Vector2i(1, 0), "size": Vector2(512, 512), "picture": "", "name": "ห้องบี", "levels": Vector2i(5, 5),
			"exits": [{"side": "west", "at": Vector2(8, 260), "to": "a", "arena": false}], "stone": Vector2.INF, "stone_unlocked": false, "arena": true},
		"c": {"grid": Vector2i(0, -1), "size": Vector2(512, 512), "picture": "", "name": "ห้องซี", "levels": Vector2i(4, 4),
			"exits": [{"side": "south", "at": Vector2(250, 504), "to": "a", "arena": false}], "stone": Vector2.INF, "stone_unlocked": false, "arena": false}}}
	var m := WorldMap.new()
	m.build()
	tree.root.add_child(m)
	return [m, f, data]

# ---------------------------------------------------------------------------------------------------------------

## In the game (seed 7, 5 rooms walked): exactly the rooms the fog knows are drawn (not the rest of the layout),
## each at its grid place (tile steps = grid steps), each with its own fog texture; after a waypoint re-roll the
## visited rooms stay (fog per game); a new game draws only its start room.
func test_only_visited_rooms_at_grid_places():
	_clean()
	var g: Node2D = await _ground()
	var went := _walk(g, 4)
	var r := ""
	if went.size() != 4: r = "setup: walked %s" % [went]
	var wm: WorldMap = g.hud.world_map
	if r == "":
		g.hud.open_map()
		var want: Array = g.fog.known_ids()
		if wm.drawn_ids() != want: r = "drawn %s (want the visited %s)" % [wm.drawn_ids(), want]
		elif want.size() != 5: r = "setup: %d rooms visited (want 5)" % want.size()
		elif g.rooms.active.pos.size() <= want.size(): r = "setup: every room visited"
	if r == "":
		var a: String = wm.drawn_ids()[0]
		var ra: Rect2 = wm.rects[a]
		var step: float = wm.tile * (1.0 + WorldMap.GAP)
		for id in wm.drawn_ids():
			var d: Vector2i = g.rooms.grid_pos(id) - g.rooms.grid_pos(a)
			var got: Vector2 = (wm.rects[id].position - ra.position) / step
			if got.distance_to(Vector2(d)) > 0.01: r = "%s at %s steps from %s (grid says %s)" % [id, got, a, d]
			elif not is_equal_approx(wm.rects[id].size.x, wm.tile): r = "%s tile %s" % [id, wm.rects[id].size]
			var img: Image = wm.fog_texture(id).get_image() if wm.fog_texture(id) else null
			if r == "" and (img == null or img.get_size() != g.fog.cells(id)): r = "%s: no fog texture of its cells" % id
			if r == "":
				for cy in img.get_height():
					for cx in img.get_width():
						if r == "" and g.fog.is_revealed(id, cx, cy) != (img.get_pixel(cx, cy).a == 0.0): r = "%s fog cell (%d,%d) wrong" % [id, cx, cy]
	g.hud.close_map()
	if r == "":
		var before: Array = g.fog.known_ids()
		g.reroll()
		g.go_to("c1r1", g.WAYPOINT_ARRIVAL, false)
		g.hud.open_map()
		if wm.drawn_ids() != before: r = "after a waypoint re-roll drawn %s (want %s)" % [wm.drawn_ids(), before]
		g.hud.close_map()
	await _free(g)
	if r == "":
		var g2: Node2D = await _ground()
		g2.hud.open_map()
		if g2.hud.world_map.drawn_ids() != ["c1r1"]: r = "new game draws %s" % [g2.hud.world_map.drawn_ids()]
		await _free(g2)
	_clean()
	return r

## The current room has the outline (current_id) and the hero dot sits on the hero's feet in its tile; another
## room becomes current after a room change.
func test_current_room_outlined_with_hero_dot():
	_clean()
	var g: Node2D = await _ground()
	_walk(g, 2)
	g.hero.global_position = Vector2(300, 200)
	var wm: WorldMap = g.hud.world_map
	g.hud.open_map()
	var r := ""
	if wm.current_id() != g.room_id: r = "outlined %s (hero in %s)" % [wm.current_id(), g.room_id]
	elif wm.hero_at().distance_to(wm.to_tile(g.room_id, Vector2(300, 200))) > 0.01: r = "hero dot %s" % wm.hero_at()
	elif not wm.rects[g.room_id].has_point(wm.hero_at()): r = "hero dot off its tile"
	g.hud.close_map()
	if r == "":
		g.go_to("c1r1", "", false)
		g.hud.open_map()
		if wm.current_id() != "c1r1": r = "after going back: outlined %s" % wm.current_id()
		g.hud.close_map()
	await _free(g)
	_clean()
	return r

## Marks shown always (B11 setting true, to check the shape): every joined exit of a drawn room into a room not
## visited has one "?" in the gap just past its edge, every link between two drawn rooms one path line from exit to
## exit (shorter than a gap + a tile), red ones for the arena; nothing else.
func test_question_marks_and_path_lines():
	_clean()
	var g: Node2D = await _ground()
	_walk(g, 4)
	var wm: WorldMap = g.hud.world_map
	wm.marks_under_fog = true
	g.hud.open_map()
	var r := ""
	var want_q := 0
	var want_p := {}
	for id in wm.drawn_ids():
		for w in g.rooms.room(id).warps:
			var to := String(w.to)
			if wm.rects.has(to): want_p[[id, to] if id < to else [to, id]] = true
			else: want_q += 1
	var qs: Array = wm.question_marks()
	var ps: Array = wm.path_lines()
	if want_q == 0: r = "setup: no exit into an unvisited room"
	elif qs.size() != want_q: r = "%d '?' (want %d)" % [qs.size(), want_q]
	elif ps.size() != want_p.size(): r = "%d path lines (want %d)" % [ps.size(), want_p.size()]
	if r == "":
		for q in qs:
			var rr: Rect2 = wm.rects[q.room]
			if rr.has_point(q.at): r = "'?' inside its room %s" % q.room
			elif q.at.distance_to(q.edge) > wm.tile * WorldMap.GAP * 0.6: r = "'?' far from its exit"
			for id in wm.rects:
				if r == "" and wm.rects[id].has_point(q.at): r = "'?' over drawn room %s" % id
		for p in ps:
			if r == "" and not want_p.has([p.a, p.b]): r = "unexpected path %s-%s" % [p.a, p.b]
			if r == "" and (p.from as Vector2).distance_to(p.to) > wm.tile * (1.0 + WorldMap.GAP): r = "path %s-%s is %.1f long" % [p.a, p.b, (p.from as Vector2).distance_to(p.to)]
	g.hud.close_map()
	await _free(g)
	_clean()
	return r

## B11 (owner 2026-11-09): the shared constant is false (marks only once revealed). MiniMap.mark_shown for both
## settings; the full map with both settings: false hides a's exits ("?", the path to b) and its stone while their
## cells are fogged and shows them once revealed (at the next open: the game is paused while it is open); true shows
## all of them at once.
func test_marks_under_fog_both_values():
	var r := ""
	if MiniMap.MARKS_UNDER_FOG != false: r = "MARKS_UNDER_FOG is %s (owner chose false)" % MiniMap.MARKS_UNDER_FOG
	var f := FogGrid.new()
	f.set_room_size("a", Vector2(512, 512))
	f.reveal("a", Vector2(40, 40))
	if r == "" and not (MiniMap.mark_shown(f, "a", Vector2(500, 500), true) and not MiniMap.mark_shown(f, "a", Vector2(500, 500), false)):
		r = "fogged point: true -> shown, false -> hidden"
	if r == "" and not (MiniMap.mark_shown(f, "a", Vector2(40, 0), false) and MiniMap.mark_shown(f, "a", Vector2(-5, 40), false)):
		r = "revealed cell (edge point / outside clamps to the edge cell) not shown"
	if r == "" and MiniMap.mark_shown(f, "zz", Vector2(10, 10), false): r = "unknown room's mark shown"
	if r != "": return r
	var b := _bare()
	var m: WorldMap = b[0]
	var fog: FogGrid = b[1]
	var data: Dictionary = b[2]
	for under in [true, false]:
		m.marks_under_fog = under
		m.open(data, Vector2(640, 360), Rect2(538, 64, 96, 96))
		var q := m.question_marks().size()
		var p := m.path_lines().size()
		var s := m.stone_marks().size()
		if m.drawn_ids() != ["a", "b"]: r = "drawn %s (want a, b)" % [m.drawn_ids()]
		elif under and (q != 1 or p != 1 or s != 1): r = "true: '?' %d, paths %d, stones %d (want 1 each)" % [q, p, s]
		elif not under and (q != 0 or p != 0 or s != 0): r = "false, fogged: '?' %d, paths %d, stones %d (want 0)" % [q, p, s]
		elif under and (m.labels().size() != 2): r = "labels %s" % [m.labels()]
		m.close()
		if r != "": break
	if r == "":
		m.marks_under_fog = false
		fog.reveal("a", Vector2(250, 8))            # the north exit's cell
		m.open(data, Vector2(640, 360), Rect2(538, 64, 96, 96))
		if m.question_marks().size() != 1 or m.path_lines().size() != 0: r = "north revealed: '?' %d paths %d (want 1, 0)" % [m.question_marks().size(), m.path_lines().size()]
		m.close()
		fog.reveal("a", Vector2(504, 240))          # a's east exit; b's west exit still fogged
		m.open(data, Vector2(640, 360), Rect2(538, 64, 96, 96))
		if r == "" and m.path_lines().size() != 0: r = "path shown with b's end fogged"
		m.close()
		fog.reveal("b", Vector2(8, 260))
		fog.reveal("a", Vector2(120, 392))          # the stone
		m.open(data, Vector2(640, 360), Rect2(538, 64, 96, 96))
		if r == "" and (m.path_lines().size() != 1 or m.stone_marks().size() != 1): r = "all revealed: paths %d stones %d" % [m.path_lines().size(), m.stone_marks().size()]
		if r == "" and not m.path_lines()[0].arena: r = "the path into the arena is not red"
		if r == "" and m.labels().filter(func(l): return l.text == WorldMap.STONE_LABEL).size() != 1: r = "no stone label"
		if r == "" and m.labels().filter(func(l): return l.text == WorldMap.ARENA_LABEL and l.room == "b").size() != 1: r = "no arena label on b"
		m.close()
	m.queue_free()
	await tree.process_frame
	tree.paused = false
	return r

## The minimap under B11 false: an exit arrow and the stone diamond are hidden while their cell is fogged and
## appear the frame after the reveal (one marks redraw); a reveal that uncovers no mark redraws no marks.
func test_minimap_marks_appear_after_reveal():
	var f := FogGrid.new()
	f.set_room_size("a", Vector2(512, 512))
	var m := MiniMap.new()
	m.build()
	m.fit(Vector2(640, 360))
	tree.root.add_child(m)
	m.bind_fog(f)
	f.reveal("a", Vector2(256, 256))
	m.show_room("a", Vector2(512, 512), null, [{"side": "north", "at": Vector2(250, 8), "arena": true}], Vector2(120, 470), false)
	await tree.process_frame
	var r := ""
	if not m.marks_under_fog: pass
	else: r = "minimap marks_under_fog is true"
	if r == "" and not m.marks().is_empty(): r = "fogged marks shown: %s" % [m.marks()]
	var n0: int = m.marks_redraws
	if r == "":
		f.reveal("a", Vector2(400, 300))            # no mark there
		await tree.process_frame
		if m.marks_redraws != n0: r = "marks redrawn by a reveal that uncovered none"
	if r == "":
		f.reveal("a", Vector2(250, 8))              # the arena exit
		await tree.process_frame
		var ks: Array = m.marks().map(func(x): return x.kind)
		if ks != ["exit"]: r = "after revealing the exit: %s" % [ks]
		elif m.marks_redraws != n0 + 1: r = "%d marks redraws (want 1)" % (m.marks_redraws - n0)
		elif not (m.marks()[0].color as Color).is_equal_approx(MiniMap.EXIT_ARENA): r = "arena exit not red"
	if r == "":
		f.reveal("a", Vector2(120, 462))            # the stone
		await tree.process_frame
		if m.marks().size() != 2: r = "after revealing the stone: %s" % [m.marks()]
	if r == "":
		m.marks_under_fog = true                    # the other setting shows everything at once
		m.show_room("a", Vector2(512, 512), null, [{"side": "south", "at": Vector2(250, 504), "arena": false}], Vector2(400, 100), false)
		if m.marks().size() != 2: r = "true: %d marks (want 2)" % m.marks().size()
	m.queue_free()
	await tree.process_frame
	return r

## Opens from the map button, a tap on the minimap and M; closes with ✕, a tap on the minimap's spot, M and Esc.
## Open = the tree paused; closed = unpaused, every way. Not over the bag / skill screens; they do not open over it.
func test_open_close_every_way_and_pause():
	_clean()
	var g: Node2D = await _ground()
	var hud: Hud = g.hud
	var wm: WorldMap = hud.world_map
	await tree.process_frame
	var r := ""
	var opens := {
		"map button": func(): hud.map_button.pressed.emit(),
		"minimap tap": func(): await _tap(hud.minimap.get_global_rect().get_center()),
		"M key": func(): await _key(KEY_M)}
	var closes := {
		"✕": func(): await _tap(wm.close_button.get_global_rect().get_center()),
		"minimap spot": func(): await _tap(hud.minimap.get_global_rect().get_center()),
		"M key": func(): await _key(KEY_M),
		"Esc": func(): await _key(KEY_ESCAPE)}
	for o in opens:
		for c in closes:
			if r != "": break
			await opens[o].call()
			await tree.process_frame
			if not wm.is_open(): r = "%s did not open the map" % o
			elif not tree.paused: r = "%s: game not paused" % o
			if r == "":
				await closes[c].call()
				await tree.process_frame
				if wm.is_open(): r = "%s did not close the map (opened by %s)" % [c, o]
				elif tree.paused: r = "closed by %s: game still paused" % c
	if r == "":
		hud.open_bag()
		hud.open_map()
		if wm.is_open(): r = "the map opened over the bag"
		hud.bag_panel.close()
	if r == "":
		hud.open_map()
		hud.open_bag()
		hud.open_skills()
		if hud.bag_panel.is_open() or hud.skill_panel.is_open(): r = "bag / skills opened over the map"
		hud.close_map()
		if tree.paused: r = "paused after closing"
	await _free(g)
	_clean()
	return r

## The game never stays paused: a room change (exit trip or waypoint landing) closes the map; freeing the game
## while it is open (a new game) unpauses; it does not open mid-fade.
func test_never_left_paused():
	_clean()
	var g: Node2D = await _ground()
	var r := ""
	g.hud.open_map()
	var w: Dictionary = g.rooms.room(g.room_id).warps[0]
	g.go_to(String(w.to), String(w.to_warp), false)
	if g.hud.map_open() or tree.paused: r = "room change: open %s paused %s" % [g.hud.map_open(), tree.paused]
	if r == "":
		g.hud.open_map()
		g.reroll()
		g.go_to("c1r1", g.WAYPOINT_ARRIVAL)
		if g.hud.map_open() or tree.paused: r = "waypoint landing: open %s paused %s" % [g.hud.map_open(), tree.paused]
	if r == "":
		await tree.create_timer(0.6).timeout
		g.warp_through(g.warps[0])
		g.hud.open_map()
		if g.hud.map_open(): r = "opened mid-fade"
		await tree.create_timer(0.8).timeout
	if r == "":
		g.hud.open_map()
		if not tree.paused: r = "setup: not paused"
		g.queue_free()
		await tree.process_frame
		if tree.paused: r = "new game (old game freed with the map open): still paused"
	else:
		await _free(g)
	tree.paused = false
	_clean()
	return r

## Every size both ways, with every room of the layout visited (the biggest map) and with only the start: the
## rooms, "?" marks and the card stay inside the screen less the margin and the iPhone bottom inset, never under
## the ✕ or the minimap spot; ✕ is at least 44 HUD px; a 7 x 7 grid (the whole layout grid) fits too.
func test_fits_every_size_clear_of_close_and_inset():
	_clean()
	var size0 := tree.root.size
	var scale0 := tree.root.content_scale_size
	var g: Node2D = await _ground()
	var hud: Hud = g.hud
	hud.touch_ui.visible = true
	var wm: WorldMap = hud.world_map
	var fails := []
	for full in [false, true]:
		if full: _visit_all(g)
		for ios in [0, 1]:
			ScreenFit.ios_override = ios
			ScreenFit.standalone_override = 0
			for o in SIZES:
				var view: Vector2 = await _window(hud, o)
				var tag := "%s%s %s" % ["all rooms" if full else "start", " iPhone" if ios else "", o]
				hud.open_map()
				var inset := ScreenFit.bottom_inset(ScreenFit.is_portrait(view))
				if ios == 1 and ScreenFit.is_portrait(view) and inset <= 0.0: fails.append("%s: no inset" % tag)
				var safe := Rect2(Vector2(WorldMap.MARGIN, WorldMap.MARGIN), view - Vector2(WorldMap.MARGIN * 2.0, WorldMap.MARGIN * 2.0 + inset))
				var x: Rect2 = wm.close_button.get_global_rect()
				var mm: Rect2 = hud.minimap.get_global_rect()
				if x.size.x < IconButton.MIN_TOUCH or x.size.y < IconButton.MIN_TOUCH: fails.append("%s: ✕ %s" % [tag, x.size])
				if not safe.encloses(x): fails.append("%s: ✕ off screen" % tag)
				if wm.minimap_zone.get_global_rect() != mm: fails.append("%s: minimap spot %s (minimap %s)" % [tag, wm.minimap_zone.get_global_rect(), mm])
				if wm.drawn_ids().size() != g.fog.known_ids().size(): fails.append("%s: drawn %d" % [tag, wm.drawn_ids().size()])
				if wm.tile < 24.0: fails.append("%s: tile %.0f px" % [tag, wm.tile])
				var things := {}
				for id in wm.rects: things["room " + id] = wm.rects[id]
				wm.marks_under_fog = true
				for q in wm.question_marks(): things["? %s %s" % [q.room, q.side]] = Rect2(q.at - Vector2(5, 7), Vector2(10, 14))
				wm.marks_under_fog = MiniMap.MARKS_UNDER_FOG
				for k in things:
					var rr: Rect2 = things[k]
					if not safe.encloses(rr): fails.append("%s: %s %s off the safe area %s" % [tag, k, rr, safe])
					if rr.intersects(x) or rr.intersects(mm): fails.append("%s: %s %s under ✕ / minimap" % [tag, k, rr])
				for id in wm.rects:
					wm.show_card(id)
					var cr: Rect2 = wm.card.get_global_rect()
					if not safe.encloses(cr): fails.append("%s: card of %s %s off the safe area" % [tag, id, cr])
					if cr.intersects(x) or cr.intersects(mm): fails.append("%s: card of %s under ✕ / minimap" % [tag, id])
					if cr.intersects(wm.rects[id]): fails.append("%s: card covers its room %s" % [tag, id])
				wm.hide_card()
				var big := WorldMap.plan({"a": Vector2i(0, 0), "b": Vector2i(6, 6)}, wm.area)
				for id in big.rects:
					if not wm.area.encloses(big.rects[id]): fails.append("%s: 7x7 grid room %s off the area" % [tag, id])
				if big.tile < 24.0: fails.append("%s: 7x7 tile %.0f" % [tag, big.tile])
				hud.close_map()
	ScreenFit.ios_override = -1
	ScreenFit.standalone_override = -1
	await _free(g)
	await _restore(size0, scale0)
	_clean()
	return "" if fails.is_empty() else "%d problems, e.g. %s" % [fails.size(), fails.slice(0, 4)]

## A tap on a room shows its card: its Thai name (rooms.json) and level range (test_ground.level_range: the forest
## room's layout level, +1 groups; e0 from the rooms joined to it, max 11); a tap elsewhere hides it; level_text.
func test_tap_room_shows_name_and_levels():
	_clean()
	var g: Node2D = await _ground()
	_walk(g, 4)
	var wm: WorldMap = g.hud.world_map
	g.hud.open_map()
	await tree.process_frame
	var r := ""
	if WorldMap.level_text(Vector2i(3, 4)) != "Lv 3–4" or WorldMap.level_text(Vector2i(5, 5)) != "Lv 5" or WorldMap.level_text(Vector2i.ZERO) != "":
		r = "level_text"
	for id in wm.drawn_ids():
		if r != "": break
		await _tap(wm.rects[id].get_center())
		if not wm.card.visible or wm.card_id != id: r = "tap on %s: card %s / %s" % [id, wm.card.visible, wm.card_id]
		elif wm.card_name.text != String(g.rooms.room(id).name): r = "%s card name '%s'" % [id, wm.card_name.text]
		elif wm.card_level.text != WorldMap.level_text(g.level_range(id)) or wm.card_level.text == "": r = "%s card level '%s' (range %s)" % [id, wm.card_level.text, g.level_range(id)]
	if r == "":
		var lv: Dictionary = g.rooms.room_levels()
		var want := Vector2i(int(lv["c1r1"]), int(lv["c1r1"]))
		if g.level_range("c1r1") != want: r = "c1r1 range %s (want %s)" % [g.level_range("c1r1"), want]
		var lo := 99
		var hi := 0
		for w in g.rooms.room("e0").warps:
			var a := RoomLevels.arena_level(int(lv.get(String(w.to), 0)))
			lo = mini(lo, a)
			hi = maxi(hi, a)
		if r == "" and g.level_range("e0") != Vector2i(lo, hi): r = "e0 range %s (want %s)" % [g.level_range("e0"), Vector2i(lo, hi)]
	if r == "":
		var empty := Vector2(wm.area.position.x + 2, wm.area.end.y - 2)
		for id in wm.rects:
			if wm.rects[id].has_point(empty): r = "setup: corner on a room"
		await _tap(empty)
		if r == "" and wm.card.visible: r = "a tap elsewhere did not hide the card"
		if r == "" and not wm.is_open(): r = "a tap elsewhere closed the map"
	g.hud.close_map()
	await _free(g)
	_clean()
	return r

## A thumb held down (the GUI's finger) and a second finger: the second finger's tap on a room shows its card, on
## ✕ closes the map; a cancelled touch on ✕ (iOS touchcancel) does nothing; every touch while open is handled and
## the joystick never starts.
func test_second_finger_and_cancelled_touch():
	_clean()
	var g: Node2D = await _ground()
	_walk(g, 2)
	var hud: Hud = g.hud
	hud.touch_ui.visible = true
	var wm: WorldMap = hud.world_map
	hud.open_map()
	await tree.process_frame
	var r := ""
	var thumb := Vector2(wm.area.position.x + 2, wm.area.end.y - 2)
	_touch(0, thumb, true, true)
	await tree.process_frame
	var id: String = wm.drawn_ids()[0]
	var p: Vector2 = wm.rects[id].get_center()
	var d := _touch(1, p, true)
	await tree.process_frame
	var u := _touch(1, p, false)
	await tree.process_frame
	if wm.card_id != id: r = "second finger on %s: card '%s'" % [id, wm.card_id]
	elif not d or not u: r = "second finger not handled (%s, %s)" % [d, u]
	var xc: Vector2 = wm.close_button.get_global_rect().get_center()
	if r == "":
		_touch(1, xc, true)
		_touch(1, xc, false, false, true)
		await tree.process_frame
		if not wm.is_open(): r = "a cancelled touch on ✕ closed the map"
	if r == "":
		_touch(1, xc, true)
		await tree.process_frame
		_touch(1, xc, false)
		await tree.process_frame
		if wm.is_open(): r = "second finger on ✕ did not close"
		elif tree.paused: r = "still paused"
	_touch(0, thumb, false, true)
	await tree.process_frame
	if r == "" and hud.joystick.active: r = "the joystick started"
	hud.close_map()
	await _free(g)
	_clean()
	return r

## Nothing per frame while open: the rooms (fog textures, nodes) are built once per open, the canvas is not
## redrawn by frames passing, and the map has no _process.
func test_built_once_no_per_frame_work():
	_clean()
	var g: Node2D = await _ground()
	_walk(g, 4)
	var wm: WorldMap = g.hud.world_map
	g.hud.open_map()
	await tree.process_frame
	var b0 := wm.builds
	var tex: ImageTexture = wm.fog_texture(wm.drawn_ids()[0])
	var d0: int = wm._canvas.draws
	for i in 30: await tree.process_frame
	var r := ""
	if wm.builds != b0: r = "rebuilt while open"
	elif wm.fog_texture(wm.drawn_ids()[0]) != tex: r = "fog texture re-made"
	elif wm._canvas.draws != d0: r = "canvas redrawn %d times in 30 frames" % (wm._canvas.draws - d0)
	elif wm.is_processing() or wm._canvas.is_processing(): r = "processing every frame"
	g.hud.close_map()
	await _free(g)
	_clean()
	return r
