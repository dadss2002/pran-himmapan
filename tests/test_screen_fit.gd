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
	var room := Vector2(688, 384)
	var cases := [
		[Vector2(360, 779), 779.0 / 384.0],    # portrait phone: room height fills the screen
		[Vector2(779, 360), 779.0 / 688.0],    # landscape phone: room width fills the screen
		[Vector2(640, 360), 1.0],              # 16:9: the room is already bigger than the view
	]
	for c in cases:
		var z := ScreenFit.camera_zoom(c[0], room)
		if absf(z - c[1]) > 0.001: return "view %s zoom %.3f (want %.3f)" % [c[0], z, c[1]]
		var seen: Vector2 = c[0] / z
		if seen.x > room.x + 0.5 or seen.y > room.y + 0.5: return "view %s still shows %s of a %s room" % [c[0], seen, room]
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
