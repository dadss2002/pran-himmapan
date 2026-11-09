extends RefCounted
## Fit to the full screen, portrait and landscape (owner 2026-11-07): ScreenFit picks the UI view,
## the camera zooms until the room covers the screen, and the touch / HUD / panels fit portrait.

var tree: SceneTree

func setup(t: SceneTree) -> void:
	tree = t

func test_base_view_by_orientation():
	if ScreenFit.base_for(Vector2i(390, 844)) != Vector2i(360, 640): return "portrait base %s" % ScreenFit.base_for(Vector2i(390, 844))
	if ScreenFit.base_for(Vector2i(844, 390)) != Vector2i(640, 360): return "landscape base %s" % ScreenFit.base_for(Vector2i(844, 390))
	return ""

func test_camera_covers_the_room():
	var cases := [
		# M4b rooms, 512x512
		[Vector2(512, 512), Vector2(360, 779), 779.0 / 512.0],    # portrait phone: room height fills the screen
		[Vector2(512, 512), Vector2(779, 360), 779.0 / 512.0],    # landscape phone: room width fills the screen
		[Vector2(512, 512), Vector2(640, 360), 1.25],             # 16:9 base view: width fills, camera scrolls up/down
		# pre-M4b rooms, 688x384
		[Vector2(688, 384), Vector2(360, 779), 779.0 / 384.0],
		[Vector2(688, 384), Vector2(779, 360), 779.0 / 688.0],
		[Vector2(688, 384), Vector2(640, 360), 1.0],              # the room is already bigger than the view
	]
	for c in cases:
		var room: Vector2 = c[0]
		var z := ScreenFit.camera_zoom(c[1], room)
		if absf(z - c[2]) > 0.001: return "%s room, view %s zoom %.3f (want %.3f)" % [room, c[1], z, c[2]]
		var seen: Vector2 = c[1] / z
		if seen.x > room.x + 0.5 or seen.y > room.y + 0.5: return "view %s still shows %s of a %s room" % [c[1], seen, room]
	var rs := RoomSet.open()
	for id in rs.ids():
		if rs.layout(id).size_px() != Vector2(512, 512): return "%s is %s, add its zoom cases" % [id, rs.layout(id).size_px()]
	return ""

func test_portrait_buttons_fit_and_leave_the_joystick_side_free():
	var b := TouchButtons.new()
	b.build_default()
	var r := ""
	for view in [Vector2(360, 779), Vector2(640, 360), Vector2(779, 360)]:
		r = _buttons_ok(b, view)
		if r != "": break
	b.layout(Vector2(640, 360))
	if r == "" and b.center_of("dodge") != Vector2(430, 312): r = "landscape dodge moved to %s" % b.center_of("dodge")
	b.free()
	return r

## Touch-target rule (docs/design/design-research.md §4): skill buttons at least r22 (≈44 pt).
func test_touch_targets_big_enough():
	var b := TouchButtons.new()
	b.build_default()
	var r := ""
	for n in b.buttons:
		var want := 34.0 if n == "shoot" else (20.0 if n.begins_with("potion") else 22.0)
		if b.buttons[n].radius < want: r = "%s radius %d (want >= %d)" % [n, b.buttons[n].radius, want]
	b.free()
	return r

func _buttons_ok(b: TouchButtons, view: Vector2) -> String:
	b.layout(view)
	var names: Array = b.buttons.keys()
	var r := ""
	for n in names:
		var c: Vector2 = b.center_of(n)
		var rad: float = b.buttons[n].radius
		if c.x - rad < 0 or c.x + rad > view.x or c.y - rad < 0 or c.y + rad > view.y: r = "%s off screen at %s" % [n, c]
		elif c.x - rad < view.x * 0.5 - 0.5: r = "%s at %s is in the joystick half" % [n, c]
		for m in names:
			if r == "" and m != n and c.distance_to(b.center_of(m)) < rad + b.buttons[m].radius: r = "%s overlaps %s" % [n, m]
		if r != "": break
	return "" if r == "" else "%s view: %s" % [view, r]

func test_portrait_hud_and_bag_fit():
	await tree.process_frame
	var w := tree.root
	var old := w.content_scale_size
	var old_size := w.size
	w.size = Vector2i(390, 844)                 # a portrait phone
	w.content_scale_size = ScreenFit.base_for(w.size)
	await tree.process_frame
	var size := w.get_visible_rect().size
	var hero: Hero = load("res://scenes/hero.tscn").instantiate()
	w.add_child(hero)
	var hud := Hud.new()
	hud.build()
	w.add_child(hud)
	hud.bind(hero)
	await tree.process_frame
	var r := ""
	if not ScreenFit.is_portrait(size): r = "test view %s is not portrait" % size
	hud.layout(size)
	var tr: Rect2 = hud.top_right.get_rect()
	if r == "" and (tr.position.x < 0 or tr.end.x > size.x + 0.5): r = "top-right block %s off a %s view" % [tr, size]
	if r == "" and tr.position.y < 56: r = "top-right block at y %d overlaps the status panel" % tr.position.y
	hud.open_bag()
	await tree.process_frame
	await tree.process_frame
	var p: PanelContainer = hud.bag_panel._panel
	var shown := Rect2(p.position, p.size * p.scale)
	if r == "" and (shown.position.x < 0 or shown.end.x > size.x + 0.5 or shown.position.y < 0 or shown.end.y > size.y + 0.5):
		r = "bag panel %s does not fit a %s view" % [shown, size]
	if r == "" and p.scale.x < 0.99: r = "portrait bag shrunk to %.2f instead of stacking" % p.scale.x
	if r == "" and not hud.bag_panel._body.vertical: r = "bag columns not stacked in portrait"
	hud.bag_panel.close()
	tree.paused = false
	hud.queue_free()
	hero.queue_free()
	w.content_scale_size = old
	w.size = old_size
	await tree.process_frame
	return r

## M3j: the room is drawn at its own pixel size and enlarged to cover the screen; damage text stays
## at full resolution on the overlay that follows the camera.
func test_world_drawn_at_pixel_size():
	var g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = "user://test_m3j_save.json"
	if FileAccess.file_exists(g.save_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(g.save_path))
	tree.root.add_child(g)
	await tree.process_frame
	await tree.process_frame
	var v: Vector2 = tree.root.get_visible_rect().size
	var r := ""
	var px: Vector2 = Vector2(g.world_vp.size)
	var s: float = g._scale
	var room: Vector2 = g.layout.size_px()
	if px.x > room.x + 1 or px.y > room.y + 1: r = "world view %s is bigger than the %s room" % [px, room]
	elif g.view.size.x < v.x - 0.5 or g.view.size.y < v.y - 0.5: r = "world picture %s does not cover the %s screen" % [g.view.size, v]
	elif absf(g.view.size.x / px.x - s) > 0.001: r = "picture scale %.3f != cover scale %.3f" % [g.view.size.x / px.x, s]
	elif g.hero.get_viewport() != g.world_vp: r = "the hero is not drawn in the world view"
	elif g.hud.get_viewport() == g.world_vp: r = "the HUD must stay at full resolution"
	else:
		g._number(g.hero.global_position, 5, false, false)
		if g.overlay.get_child_count() == 0: r = "damage number not on the overlay"
		else:
			await tree.process_frame
			var want: Vector2 = g.world_to_screen(g.hero.global_position)
			var got: Vector2 = g.overlay.transform * g.hero.global_position
			if got.distance_to(want) > 0.5: r = "overlay %s != world_to_screen %s" % [got, want]
	g.queue_free()
	await tree.process_frame
	return r

func test_fps_meter_folds():
	var hud := Hud.new()
	hud.build()
	tree.root.add_child(hud)
	await tree.process_frame
	hud._tick_fps(1.0)
	var open_text: String = hud.fps_button.text
	hud.fps_button.pressed.emit()
	hud._tick_fps(1.0)
	var folded: String = hud.fps_button.text
	hud.queue_free()
	if not open_text.begins_with("FPS "): return "meter shows %s" % open_text
	return "" if folded == "FPS" else "folded meter shows %s" % folded

## Owner 2026-11-08: portrait pause screens keep Safari's bottom bar clear on iPhone web only — not
## landscape, not when opened from the home screen, not off iPhone.
func test_bottom_inset_iphone_safari_portrait_only():
	var cases := [[true, 1, 0, ScreenFit.IOS_BOTTOM_INSET], [false, 1, 0, 0.0], [true, 1, 1, 0.0], [true, 0, 0, 0.0]]
	var r := ""
	for c in cases:
		ScreenFit.ios_override = c[1]
		ScreenFit.standalone_override = c[2]
		var got := ScreenFit.bottom_inset(c[0])
		if got != c[3]: r = "portrait=%s iphone=%d home=%d: %.0f (want %.0f)" % [c[0], c[1], c[2], got, c[3]]; break
	ScreenFit.ios_override = -1
	ScreenFit.standalone_override = -1
	return r
