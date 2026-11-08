extends RefCounted
## M4d Task 3d: the HUD's icon-only buttons (skills, bag, map, settings), the settings panel ("เต็มจอ",
## "แสดง FPS", remembered in user://settings.json) and their place on a phone held upright (780x1688)
## and sideways (1688x780): at least 44 px, pixel art at a whole-number scale, and clear of the status
## panel, the minimap box, the FPS line, each other and the touch controls; Hud.blocked_rects (the exit
## labels' keep-out list) holds every one of them.

const TMP_SETTINGS := "user://test_hud_settings.json"
const ICONS := {"skills_button": "skills", "bag_button": "bag", "map_button": "map", "settings_button": "settings"}

var tree: SceneTree

func setup(t: SceneTree) -> void:
	tree = t

func _clean() -> void:
	if FileAccess.file_exists(TMP_SETTINGS): DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SETTINGS))

func _hud() -> Hud:
	var hud := Hud.new()
	hud.settings_path = TMP_SETTINGS
	hud.build()
	return hud

func test_icon_buttons_replace_text_buttons():
	_clean()
	var hud := _hud()
	var r := ""
	for k in ICONS:
		var b = hud.get(k)
		if not (b is IconButton): r = "%s is not an icon button" % k
		elif b.text != "": r = "%s still has text '%s'" % [k, b.text]
		elif b.art == null or b.art.resource_path != "res://assets/ui/icons/%s.png" % ICONS[k]: r = "%s shows %s" % [k, b.art.resource_path if b.art else "nothing"]
		elif b.texture_filter != CanvasItem.TEXTURE_FILTER_NEAREST: r = "%s is not drawn with the nearest filter" % k
		elif b.art.get_size() != Vector2(48, 48): r = "%s art is %s (want 48x48)" % [k, b.art.get_size()]
		if r != "": break
	if r == "":
		for c in hud.top_right.get_children():
			if c is Button and c.text in ["สกิล", "กระเป๋า", "เต็มจอ"]: r = "text button '%s' still in the top-right block" % c.text
	if r == "" and hud.fullscreen_button.get_parent().get_parent() != hud.settings_panel: r = "เต็มจอ is not in the settings panel"
	hud.free()
	return r

## The art scale is a whole number of screen pixels per art pixel and the button is never under 44 px.
func test_icon_scale_whole_number():
	for sv in [0.75, 1.0, 1.0833, 1.5, 1.9, 2.0, 2.1667, 2.6375, 3.0, 4.2]:
		var s := float(sv)
		var b := IconButton.make("res://assets/ui/icons/bag.png", "B")
		b.fit(s)
		var on_screen := b.side * s
		var k := b.art_scale
		b.free()
		if k < 1: return "scale %.3f: art scale %d" % [s, k]
		if absf(on_screen - 48.0 * k) > 0.01: return "scale %.3f: icon %.2f screen px, not %d x 48" % [s, on_screen, k]
		var side := 48.0 * k / s
		if side < 44.0 - 0.001: return "scale %.3f: button %.1f px (want >= 44)" % [s, side]
		if k > 1 and 48.0 * (k - 1) / s >= 44.0: return "scale %.3f: art scale %d is bigger than needed" % [s, k]
	return ""

func test_map_button_says_soon():
	_clean()
	var hud := _hud()
	tree.root.add_child(hud)
	await tree.process_frame
	hud.map_button.pressed.emit()
	var r := ""
	if not hud.toast.visible or hud.toast.text != "เร็ว ๆ นี้": r = "map button: toast '%s' visible=%s" % [hud.toast.text, hud.toast.visible]
	elif not hud.blocked_rects().has(hud.toast.get_global_rect()): r = "the toast is not in blocked_rects"
	else:
		await tree.create_timer(Hud.TOAST_TIME + 0.6).timeout
		if hud.toast.visible: r = "the toast never went away"
	hud.queue_free()
	await tree.process_frame
	return r

func test_settings_panel_fullscreen_and_fps():
	_clean()
	var hud := _hud()
	tree.root.add_child(hud)
	await tree.process_frame
	var r := ""
	if hud.settings_panel.visible: r = "settings panel open at start"
	elif not hud.fps_button.visible or not hud.fps_toggle.button_pressed: r = "FPS line hidden by default"
	if r == "":
		hud.settings_button.pressed.emit()
		await tree.process_frame
		if not hud.settings_panel.visible: r = "settings button did not open the panel"
		elif not hud.blocked_rects().has(hud.settings_panel.get_global_rect()): r = "the open panel is not in blocked_rects"
	if r == "":
		var wired := false
		for c in hud.fullscreen_button.pressed.get_connections():
			if c.callable.get_method() == "press_fullscreen": wired = true
		if not wired: r = "เต็มจอ is not wired to Hud.press_fullscreen"
		elif hud.fullscreen_toggle.get_method() != "toggle_fullscreen": r = "off iOS เต็มจอ does not call ScreenFit.toggle_fullscreen"
		elif hud.fullscreen_button.text != "เต็มจอ" or hud.fps_toggle.text != "แสดง FPS": r = "panel texts %s / %s" % [hud.fullscreen_button.text, hud.fps_toggle.text]
		elif hud.fullscreen_button.size.y < 44 or hud.fps_toggle.size.y < 44: r = "panel buttons under 44 px"
	if r == "":
		hud.fps_toggle.button_pressed = false          # emits toggled
		if hud.fps_button.visible: r = "แสดง FPS off did not hide the FPS line"
		elif hud.blocked_rects().has(hud.fps_button.get_global_rect()): r = "hidden FPS line still blocks labels"
	if r == "":
		hud.settings_button.pressed.emit()
		if hud.settings_panel.visible: r = "settings button did not close the panel"
	hud.queue_free()
	await tree.process_frame
	if r == "":
		var again := _hud()                             # next session: remembered
		if again.fps_button.visible or again.fps_toggle.button_pressed: r = "FPS off not remembered (%s)" % GameSettings.load_or_default(TMP_SETTINGS)
		again.set_show_fps(true)
		again.free()
		var back := _hud()
		if r == "" and not back.fps_button.visible: r = "FPS on not remembered"
		back.free()
	_clean()
	return r

## M4d addendum 3: on iPhone / iPad web "เต็มจอ" shows the tip toast and leaves the window alone; on desktop
## and Android it toggles full screen (as before) and shows no toast. ScreenFit.ios_override forces the check.
func test_fullscreen_ios_tip():
	_clean()
	var hud := _hud()
	tree.root.add_child(hud)
	await tree.process_frame
	var calls := [0]
	hud.fullscreen_toggle = func(): calls[0] += 1
	var r := ""
	hud.toggle_settings()
	ScreenFit.ios_override = 1
	hud.fullscreen_button.pressed.emit()
	if calls[0] != 0: r = "iOS: full screen was called"
	elif not hud.toast.visible or hud.toast.text != "กดแชร์ → เพิ่มไปยังหน้าจอโฮม": r = "iOS: toast '%s' visible=%s" % [hud.toast.text, hud.toast.visible]
	elif not hud.blocked_rects().has(hud.toast.get_global_rect()): r = "iOS: the tip is not in blocked_rects"
	if r == "":
		hud.toast.visible = false
		ScreenFit.ios_override = 0
		hud.fullscreen_button.pressed.emit()
		if calls[0] != 1: r = "desktop/Android: full screen called %d times (want 1)" % calls[0]
		elif hud.toast.visible: r = "desktop/Android: a toast showed"
	ScreenFit.ios_override = -1
	hud.queue_free()
	await tree.process_frame
	_clean()
	return r

## The user-agent rule behind ScreenFit.is_ios_web (when the web_ios feature tag is missing).
func test_ios_user_agent_rule():
	var cases := {
		"Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Safari/604.1|5": true,
		"Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X)|5": true,
		"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/18.0 Safari/605.1.15|5": true,   # iPadOS
		"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/18.0 Safari/605.1.15|0": false,  # a Mac
		"Mozilla/5.0 (Linux; Android 14; Pixel 8) Chrome/130.0 Mobile Safari/537.36|5": false,
		"Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/130.0|0": false,
	}
	for ua in cases:
		if ScreenFit.ios_user_agent(ua) != cases[ua]: return "%s -> %s" % [ua, not cases[ua]]
	ScreenFit.ios_override = -1
	if not OS.has_feature("web") and ScreenFit.is_ios_web(): return "not a web build but is_ios_web() is true"
	return ""

## The toast (short "เร็ว ๆ นี้" and the long iPhone tip) never covers the open or closed settings panel, the
## minimap box or a touch button, upright and sideways, and stays on screen.
func test_toast_clear_of_settings_and_minimap():
	_clean()
	var w := tree.root
	var size0 := w.size
	var scale0 := w.content_scale_size
	var hud := _hud()
	w.add_child(hud)
	hud.touch_ui.visible = true
	var fails := []
	for o in [Vector2i(780, 1688), Vector2i(1688, 780)]:
		DisplayServer.window_set_size(o)
		w.size = o
		w.content_scale_size = ScreenFit.base_for(o)
		for i in 4: await tree.process_frame
		var view := w.get_visible_rect().size
		hud.buttons.layout(view)
		for open in [false, true]:
			for text in ["เร็ว ๆ นี้", ScreenFit.IOS_TIP]:
				hud.settings_panel.visible = open
				hud.show_toast(text)
				hud.layout(view)
				await tree.process_frame
				var tag := "%s%s '%s'" % ["portrait" if o.y > o.x else "landscape", " settings open" if open else "", text]
				var t := hud.toast.get_global_rect()
				if t.size.x < 10: fails.append("%s: toast not laid out %s" % [tag, t])
				if t.intersects(hud.minimap_box.get_global_rect()): fails.append("%s: toast %s over the minimap box %s" % [tag, t, hud.minimap_box.get_global_rect()])
				if open and t.intersects(hud.settings_panel.get_global_rect()): fails.append("%s: toast %s over the settings panel %s" % [tag, t, hud.settings_panel.get_global_rect()])
				if t.intersects(hud.top_right.get_global_rect()): fails.append("%s: toast over the top-right block" % tag)
				for n in hud.buttons.buttons:
					var b: Dictionary = hud.buttons.buttons[n]
					var br := Rect2(b.center - Vector2(b.radius, b.radius), Vector2(b.radius, b.radius) * 2.0)
					if t.intersects(br): fails.append("%s: toast over the touch button %s" % [tag, n])
				if not hud.safe_rect().encloses(t): fails.append("%s: toast %s off the safe area" % [tag, t])
	hud.settings_panel.visible = false
	DisplayServer.window_set_size(size0)
	w.size = size0
	w.content_scale_size = scale0
	hud.queue_free()
	for i in 3: await tree.process_frame
	_clean()
	return "" if fails.is_empty() else "%d problems, e.g. %s" % [fails.size(), fails.slice(0, 4)]

## Review: only the four chosen icons ship under assets/ui/icons (the PixelLab candidates *_0..3 live in
## docs/preview/m4b/icon_candidates/, which the web export leaves out).
func test_only_chosen_icons_ship():
	var extra := []
	for f in DirAccess.get_files_at("res://assets/ui/icons"):
		if f.ends_with(".png") and not f.get_basename() in ICONS.values(): extra.append(f)
	if not extra.is_empty(): return "candidate icons still in assets/ui/icons: %s" % extra
	var cfg := ConfigFile.new()
	if cfg.load("res://export_presets.cfg") != OK: return "no export_presets.cfg"
	if not String(cfg.get_value("preset.0", "exclude_filter", "")).contains("docs/*"): return "the export does not leave out docs/"
	return ""

## The test ground hands its settings file to the HUD before the HUD reads it (screenshots, tests).
func test_ground_passes_settings_path_before_build():
	_clean()
	var f := FileAccess.open(TMP_SETTINGS, FileAccess.WRITE)
	f.store_string(JSON.stringify({"show_fps": false}))
	f.close()
	var g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = "user://test_hud_ground_save.json"
	g.settings_path = TMP_SETTINGS
	g.layout_seed = 7
	g.build()
	var r := ""
	if g.hud.settings_path != TMP_SETTINGS: r = "HUD settings_path %s" % g.hud.settings_path
	elif g.hud.fps_toggle.button_pressed: r = "HUD did not read the scratch settings (FPS on)"
	g.free()
	_clean()
	if FileAccess.file_exists("user://test_hud_ground_save.json"): DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_hud_ground_save.json"))
	return r

func test_broken_settings_file_gives_defaults():
	var f := FileAccess.open(TMP_SETTINGS, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	var d := GameSettings.load_or_default(TMP_SETTINGS)
	_clean()
	return "" if d == GameSettings.DEFAULTS else "broken file gave %s" % d

## Upright and sideways phones with touch on: every icon button >= 44 px, whole-number art scale, on
## screen, clear of the status panel, minimap box, FPS line, each other, the touch buttons (with their notes)
## and the joystick, and listed in blocked_rects; the open settings panel too.
func test_layout_portrait_and_landscape():
	_clean()
	var w := tree.root
	var size0 := w.size
	var scale0 := w.content_scale_size
	var hud := _hud()
	w.add_child(hud)
	hud.touch_ui.visible = true
	var fails := []
	for o in [Vector2i(780, 1688), Vector2i(1688, 780)]:
		DisplayServer.window_set_size(o)
		w.size = o
		w.content_scale_size = ScreenFit.base_for(o)
		for i in 4: await tree.process_frame
		var view := w.get_visible_rect().size
		hud.layout(view)
		hud.buttons.layout(view)
		hud.joystick.view_size = view
		hud.joystick.reset()
		for open in [false, true]:
			hud.settings_panel.visible = open
			hud.layout(view)
			await tree.process_frame
			var tag := "%s%s" % ["portrait" if o.y > o.x else "landscape", " (settings open)" if open else ""]
			if (o.y > o.x) != ScreenFit.is_portrait(view): fails.append("%s: view %s" % [tag, view])
			var s := hud.screen_scale()
			if absf(s - float(o.x) / view.x) > 0.01: fails.append("%s: screen scale %.3f" % [tag, s])
			var keep := {"status panel": hud.status_panel.get_global_rect(), "minimap box": hud.minimap_box.get_global_rect(),
				"FPS line": hud.fps_button.get_global_rect()}
			for n in hud.buttons.buttons:
				var b: Dictionary = hud.buttons.buttons[n]
				var rr := Rect2(b.center - Vector2(b.radius, b.radius), Vector2(b.radius, b.radius) * 2.0)
				if b.note != "": rr = rr.merge(Rect2(b.center.x - 24.0, b.center.y + b.radius, 48.0, 16.0))
				keep["touch " + n] = rr
			var jr := TouchJoystick.RADIUS
			keep["joystick"] = Rect2(hud.joystick.idle_center() - Vector2(jr, jr), Vector2(jr, jr) * 2.0)
			var blocked: Array = hud.blocked_rects()
			var mine := {}
			for k in ICONS: mine[k] = hud.get(k).get_global_rect()
			if open: mine["settings panel"] = hud.settings_panel.get_global_rect()
			for k in mine:
				var rect: Rect2 = mine[k]
				if k in ICONS:
					var b: IconButton = hud.get(k)
					if rect.size.x < 44.0 - 0.01 or rect.size.y < 44.0 - 0.01: fails.append("%s: %s is %s" % [tag, k, rect.size])
					if absf(b.side * s - 48.0 * b.art_scale) > 0.05: fails.append("%s: %s art %.2f screen px (not a whole x48)" % [tag, k, b.side * s])
				if not hud.safe_rect().encloses(rect): fails.append("%s: %s %s off the safe area %s" % [tag, k, rect, hud.safe_rect()])
				if not blocked.has(rect): fails.append("%s: %s not in blocked_rects" % [tag, k])
				for o2 in keep:
					if keep[o2].intersects(rect): fails.append("%s: %s %s over %s %s" % [tag, k, rect, o2, keep[o2]])
				for k2 in mine:
					if k2 != k and mine[k2].intersects(rect): fails.append("%s: %s over %s" % [tag, k, k2])
	hud.settings_panel.visible = false
	DisplayServer.window_set_size(size0)
	w.size = size0
	w.content_scale_size = scale0
	hud.queue_free()
	for i in 3: await tree.process_frame
	return "" if fails.is_empty() else "%d problems, e.g. %s" % [fails.size(), fails.slice(0, 4)]
