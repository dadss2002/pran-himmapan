extends RefCounted
## M4c §4 corner minimap (Task 7; docs/superpowers/specs/2026-11-07-m4c-farm-links-fog-minimap.md §4 + addendum
## 2026-11-09): top-right, 96 x 96 HUD px sideways / 80 x 80 upright, under the top-right buttons, 85 % opacity;
## the current room's picture filling the box with FogGrid's unrevealed cells drawn dark over it; hero = white dot
## with a facing tick; joined exits = small arrows on the box edge (red into the boss arena); the waypoint stone =
## a diamond (blue unlocked, grey locked); no monsters (owner 2026-11-09). It fades to 30 % while the hero's
## on-screen box is under it. A tap (any finger) emits `tapped` (the full map is Task 8) and never reaches the game.
## It never covers the HUD or the touch controls on 1688x780, 780x1688, 1334x750, 750x1334 or the default window.

const SAVE := "user://test_mini_map_save.json"
const SETTINGS := "user://test_mini_map_settings.json"
const SIZES := [Vector2i(1688, 780), Vector2i(780, 1688), Vector2i(1334, 750), Vector2i(750, 1334), Vector2i(1280, 720)]

var tree: SceneTree

func setup(t: SceneTree) -> void:
	tree = t

func _clean() -> void:
	for f in [SAVE, SETTINGS]:
		if FileAccess.file_exists(f): DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

func _hud() -> Hud:
	var hud := Hud.new()
	hud.settings_path = SETTINGS
	hud.build()
	return hud

## A test ground in the tree (seed 7), monsters quiet.
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

func _frames(n: int) -> void:
	for i in n: await tree.physics_frame

## Sets the root window to `o` (as a phone of that size would) and lets the HUD lay out.
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

## A bare minimap (not in the HUD) laid out for a 640 x 360 view, showing room "a" (512 x 512).
func _mini() -> MiniMap:
	var m := MiniMap.new()
	m.build()
	m.fit(Vector2(640, 360))
	m.position = Vector2(538, 60)
	m.show_room("a", Vector2(512, 512), null, [], Vector2.INF, false)
	return m

## 96 x 96 sideways (1688x780, 1334x750, the default 1280x720), 80 x 80 upright (780x1688, 750x1334).
func test_size_by_orientation():
	_clean()
	var size0 := tree.root.size
	var scale0 := tree.root.content_scale_size
	var hud := _hud()
	tree.root.add_child(hud)
	var fails := []
	for o in SIZES:
		await _window(hud, o)
		var want := 80.0 if o.y > o.x else 96.0
		var got: Vector2 = hud.minimap.get_global_rect().size
		if got != Vector2(want, want): fails.append("%s: %s (want %d x %d)" % [o, got, want, want])
		if hud.minimap_box != hud.minimap: fails.append("minimap_box is not the minimap")
	if MiniMap.side_for(Vector2(640, 360)) != 96.0 or MiniMap.side_for(Vector2(360, 640)) != 80.0: fails.append("side_for")
	await _free(hud)
	await _restore(size0, scale0)
	_clean()
	return "" if fails.is_empty() else "%d problems, e.g. %s" % [fails.size(), fails.slice(0, 4)]

## Inside the safe area at the top-right (its right edge 6 px from the screen's), under the top-right buttons, at
## 85 % opacity; and clear of the status panel, the FPS line, each top-right button, the settings panel (shut and
## open), the toast (short note and the long iPhone tip, panel shut and open), every touch button (its 6 px touch
## margin and note), the joystick ring; listed in blocked_rects (exit labels and the travel list avoid it). The
## settings panel and toast stay clear of everything else too (they moved left of the minimap).
func test_inside_screen_and_clear_of_hud():
	_clean()
	var size0 := tree.root.size
	var scale0 := tree.root.content_scale_size
	var hud := _hud()
	tree.root.add_child(hud)
	hud.touch_ui.visible = true
	var fails := []
	for o in SIZES:
		var view: Vector2 = await _window(hud, o)
		var tag := str(o)
		for open in [false, true]:
			for text in ["", "เร็ว ๆ นี้", ScreenFit.IOS_TIP]:
				hud.settings_panel.visible = open
				hud.toast.visible = false
				if text != "": hud.show_toast(text)
				hud.layout(view)
				await tree.process_frame
				var t2 := "%s%s%s" % [tag, " settings" if open else "", (" toast '%s'" % text) if text != "" else ""]
				var mm: Rect2 = hud.minimap.get_global_rect()
				if not hud.safe_rect().encloses(mm): fails.append("%s: minimap %s off the safe area %s" % [t2, mm, hud.safe_rect()])
				if absf(mm.end.x - (view.x - 6.0)) > 0.5: fails.append("%s: minimap right edge %.1f (want %.1f)" % [t2, mm.end.x, view.x - 6.0])
				if mm.position.y < hud.top_right.get_global_rect().end.y: fails.append("%s: minimap %s not under the top-right buttons" % [t2, mm])
				if absf(hud.minimap.modulate.a - MiniMap.OPACITY) > 0.01: fails.append("%s: opacity %.2f" % [t2, hud.minimap.modulate.a])
				if not hud.blocked_rects().has(mm): fails.append("%s: minimap not in blocked_rects" % t2)
				var keep := {"status panel": hud.status_panel.get_global_rect(), "FPS line": hud.fps_button.get_global_rect()}
				for c in hud.top_right.get_children(): keep["top-right " + c.name] = c.get_global_rect()
				if open: keep["settings panel"] = hud.settings_panel.get_global_rect()
				if hud.toast.visible: keep["toast"] = hud.toast.get_global_rect()
				for n in hud.buttons.buttons:
					var b: Dictionary = hud.buttons.buttons[n]
					var r6: float = b.radius + 6.0                 # a touch button reacts 6 px outside its ring
					var rr := Rect2(b.center - Vector2(r6, r6), Vector2(r6, r6) * 2.0)
					if b.note != "": rr = rr.merge(Rect2(b.center.x - 24.0, b.center.y + b.radius, 48.0, 16.0))
					keep["touch " + n] = rr
				var jr := TouchJoystick.RADIUS
				keep["joystick"] = Rect2(hud.joystick.idle_center() - Vector2(jr, jr), Vector2(jr, jr) * 2.0)
				for k in keep:
					if keep[k].intersects(mm): fails.append("%s: minimap %s over %s %s" % [t2, mm, k, keep[k]])
				# the settings panel and the toast (now left of the minimap): on screen, clear of the rest of the HUD,
				# of each other and of the touch rings (the toast is not tappable: plain ring radius)
				var others := {"minimap": mm, "status panel": keep["status panel"], "FPS line": keep["FPS line"], "joystick": keep["joystick"]}
				for c in hud.top_right.get_children(): others["top-right " + c.name] = c.get_global_rect()
				for n in hud.buttons.buttons:
					var b: Dictionary = hud.buttons.buttons[n]
					others["touch " + n] = Rect2(b.center - Vector2(b.radius, b.radius), Vector2(b.radius, b.radius) * 2.0)
				for k in ["settings panel", "toast"]:
					if not keep.has(k): continue
					var r: Rect2 = keep[k]
					if not hud.safe_rect().encloses(r): fails.append("%s: %s %s off the safe area" % [t2, k, r])
					for k2 in others:
						if others[k2].intersects(r): fails.append("%s: %s %s over %s %s" % [t2, k, r, k2, others[k2]])
				if keep.has("toast") and keep.has("settings panel") and keep["toast"].intersects(keep["settings panel"]):
					fails.append("%s: toast over the settings panel" % t2)
	hud.settings_panel.visible = false
	hud.toast.visible = false
	await _free(hud)
	await _restore(size0, scale0)
	_clean()
	return "" if fails.is_empty() else "%d problems, e.g. %s" % [fails.size(), fails.slice(0, 4)]

## The hero dot maps world (room px) to the box: the room's corners land on the picture's corners, its middle on
## the picture's middle (512 x 512 and a 688 x 384 room); the facing tick points the hero's way; a point outside
## the room stays on the picture's edge.
func test_hero_dot_maps_from_world():
	var m := _mini()
	var fails := []
	for sz in [Vector2(512, 512), Vector2(688, 384)]:
		m.show_room("a", sz, null, [], Vector2.INF, false)
		var inner := m.inner_rect()
		if inner.size.x < 80.0 or not Rect2(Vector2.ZERO, m.size).encloses(inner): fails.append("inner rect %s in %s" % [inner, m.size])
		var cases := {Vector2(0, 0): inner.position, Vector2(sz.x, 0): Vector2(inner.end.x, inner.position.y),
			Vector2(0, sz.y): Vector2(inner.position.x, inner.end.y), sz: inner.end, sz / 2.0: inner.get_center(),
			Vector2(-50, sz.y / 2.0): Vector2(inner.position.x, inner.get_center().y)}
		for p in cases:
			m.track(p, Vector2.RIGHT, Rect2())
			var got: Vector2 = m.dot_at()
			if got.distance_to(cases[p]) > 0.01: fails.append("%s room, hero %s: dot %s (want %s)" % [sz, p, got, cases[p]])
			if m.to_map(p).distance_to(cases[p]) > 0.01 and p.x >= 0: fails.append("to_map %s" % p)
	m.track(Vector2(100, 100), Vector2.UP, Rect2())
	if m.hero_dot.facing != Vector2.UP: fails.append("facing tick %s (want up)" % m.hero_dot.facing)
	m.free()
	return "" if fails.is_empty() else "%d problems, e.g. %s" % [fails.size(), fails.slice(0, 4)]

## The fog layer is FogGrid's picture: one pixel per cell, clear where revealed and dark where fogged, drawn
## stretched over the picture with the nearest filter; it is redrawn after the room's `changed` (and only then:
## another room's change, or a step that reveals nothing, leaves it alone).
func test_fog_pixels_match_fog_grid():
	var f := FogGrid.new()
	f.set_room_size("a", Vector2(512, 512))
	f.set_room_size("b", Vector2(512, 512))
	f.reveal("a", Vector2(100, 100))
	var m := _mini()
	tree.root.add_child(m)
	m.bind_fog(f)
	m.show_room("a", Vector2(512, 512), null, [], Vector2.INF, false)
	await tree.process_frame
	var r := _fog_matches(m, f, "a")
	if r == "" and m.fog_rect.texture_filter != CanvasItem.TEXTURE_FILTER_NEAREST: r = "fog not drawn with the nearest filter"
	if r == "" and (m.fog_rect.get_rect() != m.inner_rect() or m.picture.get_rect() != m.inner_rect()): r = "fog %s / picture %s not over the inner rect %s" % [m.fog_rect.get_rect(), m.picture.get_rect(), m.inner_rect()]
	if r == "" and m.fog_rect.texture != m.fog_tex: r = "fog rect does not show the fog texture"
	var before: int = m.fog_redraws
	if r == "":
		f.reveal("a", Vector2(400, 420))
		await tree.process_frame
		r = _fog_matches(m, f, "a")
		if r == "" and m.fog_redraws != before + 1: r = "changed: %d redraws (want 1)" % (m.fog_redraws - before)
	if r == "":
		before = m.fog_redraws
		f.reveal("b", Vector2(256, 256))           # another room
		f.reveal("a", Vector2(400, 420))           # nothing new
		await tree.process_frame
		await tree.process_frame
		if m.fog_redraws != before: r = "redrawn %d times without a change to its room" % (m.fog_redraws - before)
	if r == "":
		m.show_room("b", Vector2(512, 512), null, [], Vector2.INF, false)
		r = _fog_matches(m, f, "b")
	await _free(m)
	return r

func _fog_matches(m: MiniMap, f: FogGrid, id: String) -> String:
	var img: Image = m.fog_img
	if img == null or img.get_size() != f.cells(id): return "fog image %s (want %s cells)" % [img.get_size() if img else null, f.cells(id)]
	var want := f.fog_image(id, MiniMap.FOG)
	for cy in img.get_height():
		for cx in img.get_width():
			var a := img.get_pixel(cx, cy)
			if f.is_revealed(id, cx, cy) != (a.a == 0.0): return "%s cell (%d, %d): alpha %.2f, revealed %s" % [id, cx, cy, a.a, f.is_revealed(id, cx, cy)]
			if not a.is_equal_approx(want.get_pixel(cx, cy)): return "%s cell (%d, %d): %s (want %s)" % [id, cx, cy, a, want.get_pixel(cx, cy)]
			if not f.is_revealed(id, cx, cy) and (a.get_luminance() > 0.1 or a.a < 0.8): return "fog not dark: %s" % a
	return ""

## In the game (seed 7), each room fully revealed (B11: marks show once their fog cell is revealed): every room's marks are its joined exits (rooms.json warps of this layout) as arrows on the
## matching edge of the box at the exit's place along it, red only into the boss arena, and its waypoint stone as a
## diamond on the stone, blue when unlocked and grey when not; nothing else (no monsters, owner 2026-11-09).
func test_exit_and_stone_marks():
	_clean()
	var g: Node2D = await _ground()
	var m: MiniMap = g.hud.minimap
	var fails := []
	var reds := 0
	var stones := 0
	var unlocked := 0
	for id in g.rooms.active.get("pos", {}):
		g.go_to(String(id), "", false)
		_quiet(g)
		var c: Vector2i = g.fog.cells(id)               # B11: marks show once revealed, so reveal the whole room
		for cy in c.y:
			for cx in c.x: g.fog.reveal(id, Vector2(cx * FogGrid.CELL + 16, cy * FogGrid.CELL + 16))
		await tree.process_frame
		var inner := m.inner_rect()
		var want := []
		for w in g.rooms.room(id).warps:
			var at := m.to_map(Vector2(w.at[0], w.at[1]))
			match String(w.id):
				"north": at.y = inner.position.y
				"south": at.y = inner.end.y
				"west": at.x = inner.position.x
				"east": at.x = inner.end.x
			var arena: bool = bool(g.rooms.room(String(w.to)).get("arena", false))
			want.append({"kind": "exit", "side": String(w.id), "at": at, "color": MiniMap.EXIT_ARENA if arena else MiniMap.EXIT_COLOR})
			if arena: reds += 1
		var st: Vector2 = g.rooms.waypoint(id)
		if st != Vector2.INF:
			stones += 1
			var on: bool = g.waypoints.is_unlocked(id)
			if on: unlocked += 1
			want.append({"kind": "stone", "at": m.to_map(Waypoints.centre(st)), "color": MiniMap.STONE_ON if on else MiniMap.STONE_OFF})
		var got: Array = m.marks()
		if got.size() != want.size(): fails.append("%s: %d marks (want %d): %s" % [id, got.size(), want.size(), got])
		for wm in want:
			var hit := false
			for gm in got:
				if gm.kind == wm.kind and gm.get("side", "") == wm.get("side", "") and (gm.at as Vector2).distance_to(wm.at) < 0.01 \
						and (gm.color as Color).is_equal_approx(wm.color):
					hit = true
			if not hit: fails.append("%s: no mark %s in %s" % [id, wm, got])
		for gm in got:
			if not gm.kind in ["exit", "stone"]: fails.append("%s: unexpected mark %s" % [id, gm])
	if reds == 0: fails.append("no room with an exit into the arena was checked")
	if stones != 4 or unlocked < 1 or unlocked == stones: fails.append("stones %d, unlocked %d (want 4 stones, some of each colour)" % [stones, unlocked])
	await _free(g)
	_clean()
	return "" if fails.is_empty() else "%d problems, e.g. %s" % [fails.size(), fails.slice(0, 4)]

## The hero's on-screen box overlapping the minimap fades it to 30 % (within a short fade); off it, back to 85 %.
## A box just touching its edge does not count. In the game the test ground feeds the hero's real screen box.
func test_fade_when_hero_under():
	var m := _mini()
	tree.root.add_child(m)
	var box := m.get_global_rect()
	var r := ""
	m.track(Vector2(256, 256), Vector2.DOWN, Rect2(box.position.x - 20, box.position.y + 30, 30, 50))   # half under
	await tree.create_timer(MiniMap.FADE_TIME + 0.15).timeout
	if absf(m.modulate.a - MiniMap.FADED) > 0.01: r = "hero under: opacity %.2f (want %.2f)" % [m.modulate.a, MiniMap.FADED]
	if r == "":
		m.track(Vector2(256, 256), Vector2.DOWN, Rect2(box.position.x - 30, box.position.y, 30, 50))       # touching
		await tree.create_timer(MiniMap.FADE_TIME + 0.15).timeout
		if absf(m.modulate.a - MiniMap.OPACITY) > 0.01: r = "hero beside it: opacity %.2f (want %.2f)" % [m.modulate.a, MiniMap.OPACITY]
	if r == "" and (MiniMap.FADED != 0.30 or MiniMap.OPACITY != 0.85 or MiniMap.FADE_TIME > 0.3): r = "constants %s / %s / %s" % [MiniMap.FADED, MiniMap.OPACITY, MiniMap.FADE_TIME]
	await _free(m)
	if r != "": return r
	# the game: hero near the room's top-right corner (camera at the room's edge) on a landscape phone
	_clean()
	var size0 := tree.root.size
	var scale0 := tree.root.content_scale_size
	var g: Node2D = await _ground()
	await _window(g.hud, Vector2i(1688, 780))
	g.hero.set_physics_process(false)
	g.hero.global_position = Vector2(482, 96)
	await tree.create_timer(MiniMap.FADE_TIME + 0.2).timeout
	var hs: Rect2 = g.hero_screen_rect()
	if not hs.intersects(g.hud.minimap.get_global_rect()): r = "setup: hero %s not under the minimap %s" % [hs, g.hud.minimap.get_global_rect()]
	elif absf(g.hud.minimap.modulate.a - MiniMap.FADED) > 0.01: r = "game, hero under: opacity %.2f" % g.hud.minimap.modulate.a
	if r == "":
		g.hero.global_position = Vector2(256, 300)
		await tree.create_timer(MiniMap.FADE_TIME + 0.2).timeout
		if absf(g.hud.minimap.modulate.a - MiniMap.OPACITY) > 0.01: r = "game, hero away: opacity %.2f" % g.hud.minimap.modulate.a
	await _free(g)
	await _restore(size0, scale0)
	_clean()
	return r

## Room changes refresh the minimap: an exit trip (picture, fog, marks), waypoint travel (re-roll + landing by the
## stone), unlocking a stone (diamond turns blue), and a new game (start room, only the arrival revealed). The dot
## follows the hero every frame.
func test_room_change_refresh():
	_clean()
	var g: Node2D = await _ground()
	var m: MiniMap = g.hud.minimap
	var r: String = await _same_room(g, m)
	if r == "":
		g.hero.global_position = Vector2(300, 260)
		await _frames(2)
		await tree.process_frame
		if m.dot_at().distance_to(m.to_map(g.hero.global_position)) > 0.01: r = "dot %s not on the hero %s" % [m.dot_at(), m.to_map(g.hero.global_position)]
	if r == "":
		var to: String = String(g.rooms.room(g.room_id).warps[0].to)
		g.go_to(to, String(g.rooms.room(g.room_id).warps[0].to_warp), false)
		_quiet(g)
		r = await _same_room(g, m)
	if r == "":
		# a locked stone room: the diamond is grey, touching the stone unlocks it and the diamond turns blue
		g.go_to("c2r0", "", false)
		_quiet(g)
		r = await _same_room(g, m)
		if r == "" and g.waypoints.is_unlocked("c2r0"): r = "setup: c2r0 already unlocked"
		if r == "":
			g.hero.global_position = g.rooms.waypoint_landing("c2r0")
			await _frames(3)
			if not g.waypoints.is_unlocked("c2r0"): r = "setup: standing on the stone did not unlock it"
			else: r = await _same_room(g, m)
	if r == "":
		g.hud.close_waypoints()
		g.reroll()                                     # waypoint travel: re-roll then land by the stone
		g.go_to("c1r1", g.WAYPOINT_ARRIVAL, false)
		_quiet(g)
		r = await _same_room(g, m)
	await _free(g)
	if r == "":
		var g2: Node2D = await _ground()               # a new game: all fog but the arrival
		r = await _same_room(g2, g2.hud.minimap)
		if r == "" and g2.hud.minimap.room_id != "c1r1": r = "new game shows %s" % g2.hud.minimap.room_id
		await _free(g2)
	_clean()
	return r

## The minimap shows the hero's room (after a process frame: a fog change is drawn on the next frame).
func _same_room(g: Node2D, m: MiniMap) -> String:
	await tree.process_frame
	var id: String = g.room_id
	if m.room_id != id: return "minimap shows %s, hero in %s" % [m.room_id, id]
	if m.room_size != g.layout.size_px(): return "%s: room size %s" % [id, m.room_size]
	var pic: Texture2D = m.picture.texture
	if pic == null or pic.resource_path != String(g.rooms.room(id).image): return "%s: picture %s" % [id, pic.resource_path if pic else null]
	var fr := _fog_matches(m, g.fog, id)
	if fr != "": return fr
	var exits := 0
	var stone := []
	for mk in m.marks():
		if mk.kind == "exit": exits += 1
		if mk.kind == "stone": stone.append(mk)
	var want_exits := 0                               # B11: only exits whose fog cell is revealed
	for w in g.rooms.room(id).warps:
		if MiniMap.mark_shown(g.fog, id, Vector2(w.at[0], w.at[1])): want_exits += 1
	var st_at: Vector2 = g.rooms.waypoint(id)
	var want_stone := st_at != Vector2.INF and MiniMap.mark_shown(g.fog, id, Waypoints.centre(st_at))
	if exits != want_exits: return "%s: %d exit marks (want %d)" % [id, exits, want_exits]
	if want_stone != (stone.size() == 1): return "%s: stone marks %s (want %s)" % [id, stone, want_stone]
	if stone.size() == 1:
		var want: Color = MiniMap.STONE_ON if g.waypoints.is_unlocked(id) else MiniMap.STONE_OFF
		if not (stone[0].color as Color).is_equal_approx(want): return "%s: stone colour %s (unlocked %s)" % [id, stone[0].color, g.waypoints.is_unlocked(id)]
	return ""

## A touch with the emulated mouse + its touch event; true when the touch was marked handled.
func _touch(index: int, p: Vector2, pressed: bool, mouse := false, canceled := false) -> bool:
	if mouse:
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

## A one-finger tap (Godot's emulated mouse) and a second finger's tap (thumb on the joystick) each emit `tapped`
## once and are marked handled; neither starts the joystick nor presses a touch button; the thumb keeps the
## joystick until the full map opens (Task 8: the HUD answers a tap like the map button, which lets the joystick go);
## a cancelled touch (iOS touchcancel) taps nothing.
func test_tap_emits_and_not_passed_to_game():
	_clean()
	var hud := _hud()
	tree.root.add_child(hud)
	hud.touch_ui.visible = true
	await tree.process_frame
	var view := tree.root.get_visible_rect().size
	hud.buttons.layout(view)
	hud.joystick.view_size = view
	hud.joystick.reset()
	hud.layout(view)
	await tree.process_frame
	var taps := [0]
	hud.minimap.tapped.connect(func(): taps[0] += 1)
	var p: Vector2 = hud.minimap.get_global_rect().get_center()
	var r := ""
	var motion := InputEventMouseMotion.new()
	motion.device = InputEvent.DEVICE_ID_EMULATION
	motion.position = p
	motion.global_position = p
	tree.root.push_input(motion, true)
	var down := _touch(0, p, true, true)
	await tree.process_frame
	if hud.joystick.active: r = "one finger: the joystick started"
	elif not hud.buttons.pressed_names().is_empty(): r = "one finger: touch buttons %s" % [hud.buttons.pressed_names()]
	var up := _touch(0, p, false, true)
	await tree.process_frame
	if r == "" and taps[0] != 1: r = "one-finger tap: %d taps (want 1)" % taps[0]
	if r == "" and (not down or not up): r = "one-finger tap not marked handled (down %s, up %s)" % [down, up]
	if r == "" and not hud.map_open(): r = "the HUD did not open the full map on the tap"
	hud.close_map()                                   # Task 8: the map pauses the game; shut it for the next finger
	var thumb: Vector2 = hud.joystick.idle_center()
	if r == "":
		_touch(0, thumb, true, true)
		if not hud.joystick.active: r = "setup: the thumb did not take the joystick"
	if r == "":
		var d2 := _touch(1, p, true)
		await tree.process_frame
		var kept: bool = hud.joystick.active and hud.joystick._index == 0   # the second finger going down steals nothing
		var u2 := _touch(1, p, false)
		await tree.process_frame
		var released: bool = not hud.joystick.active    # Task 8: the full map opened and let go of the joystick (as the bag)
		hud.close_map()
		if taps[0] != 2: r = "second finger: %d taps (want 2)" % taps[0]
		elif not d2 or not u2: r = "second finger not marked handled (down %s, up %s)" % [d2, u2]
		elif not kept: r = "the joystick lost the thumb to the second finger"
		elif not released: r = "the full map opened with the joystick still held"
		elif not hud.buttons.pressed_names().is_empty(): r = "touch buttons %s" % [hud.buttons.pressed_names()]
	if r == "":
		_touch(1, p, true)
		_touch(1, p, false, false, true)               # touchcancel
		await tree.process_frame
		if taps[0] != 2: r = "a cancelled touch tapped (%d taps)" % taps[0]
	_touch(0, thumb, false, true)
	if r == "" and hud.joystick.ignore_at.is_valid() and not hud.joystick.ignore_at.call(p): r = "the joystick does not ignore the minimap"
	await _free(hud)
	_clean()
	return r

## Cheap every frame: track() (moving the dot, turning its tick, the fade check) plus the frame's _process averages
## under 0.02 ms and allocates nothing (the fog image and texture stay the same objects); a fog redraw (only after
## `changed`) stays under 0.5 ms and reuses them; the static marks are not redrawn by the hero moving.
func test_per_frame_cost():
	var f := FogGrid.new()
	f.set_room_size("a", Vector2(512, 512))
	var m := _mini()
	tree.root.add_child(m)
	m.bind_fog(f)
	m.show_room("a", Vector2(512, 512), null, [{"side": "north", "at": Vector2(250, 20), "arena": false}], Vector2(300, 300), true)
	await tree.process_frame
	var img: Image = m.fog_img
	var tex: ImageTexture = m.fog_tex
	var marks0: int = m.marks_redraws
	var n := 5000
	var dirs := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
	var box := m.get_global_rect()
	var t0 := Time.get_ticks_usec()
	for i in n:
		var p := Vector2(fmod(i * 1.7, 512.0), fmod(i * 0.9, 512.0))
		m.track(p, dirs[(i / 50) % 4], Rect2(box.position + Vector2(-60.0 + float(i % 120), 10), Vector2(30, 60)))
		m._process(0.016)
	var each := float(Time.get_ticks_usec() - t0) / n / 1000.0
	var r := ""
	if each >= 0.02: r = "track + _process: %.4f ms per frame (limit 0.02)" % each
	if r == "" and m.marks_redraws != marks0: r = "marks redrawn %d times by the hero moving" % (m.marks_redraws - marks0)
	var k := 200
	var t1 := Time.get_ticks_usec()
	for i in k:
		f.reveal("a", Vector2(fmod(i * 37.0, 512.0), fmod(i * 53.0, 512.0)))
		m._process(0.016)
	var redraw := float(Time.get_ticks_usec() - t1) / k / 1000.0
	if r == "" and redraw >= 0.5: r = "reveal + fog redraw: %.4f ms (limit 0.5)" % redraw
	if r == "" and (m.fog_img != img or m.fog_tex != tex): r = "fog image / texture re-made"
	if r == "": r = _fog_matches(m, f, "a")
	print("    minimap: %.4f ms per frame, %.4f ms per reveal + fog redraw (%d redraws)" % [each, redraw, m.fog_redraws])
	await _free(m)
	return r
