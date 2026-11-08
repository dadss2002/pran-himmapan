class_name Hud
extends CanvasLayer
## In-game HUD (approved mockup): status panel top-left, gold/bag/minimap top-right,
## EXP bar along the bottom, plus the touch joystick and buttons on touch devices.

const GOLD := Color("#edbb55")
const PANEL := Color(0.055, 0.145, 0.11, 0.78)

var hero: Hero
var hp_label: Label
var hp_bar: ProgressBar
var mp_bar: ProgressBar
var mp_label: Label
var level_label: Label
var gold_label: Label
var exp_bar: ProgressBar
var joystick: TouchJoystick
var buttons: TouchButtons
var touch_ui: Node
var bag_panel: BagPanel
var bag_button: Button
var skill_panel: SkillPanel
var skills_button: Button
var dim: ColorRect
var top_right: HBoxContainer
var status_panel: PanelContainer
## M4d Task 3d: icon-only buttons in the top-right block (skills, bag, map, settings; IconButton) and the
## small settings panel ("เต็มจอ", "แสดง FPS") under them.
var map_button: Button
var settings_button: Button
var settings_panel: PanelContainer
var fullscreen_button: Button            # in the settings panel
var fps_toggle: CheckButton              # in the settings panel
## Task 3g (sound spec): "เสียง" on/off and the volume slider (0-100 %), in the settings panel too. The panel's
## rows sit in a grid: one column upright, two side by side on a phone held sideways (clear of the touch buttons).
var sound_toggle: CheckButton
var volume_slider: HSlider
var settings_grid: GridContainer
var minimap_box: PanelContainer
var toast: Label
var _toast_tween: Tween
const TOAST_TIME := 1.5
## M4d addendum 3 follow-up: the iPhone "เต็มจอ" tip stays 4 s ("ข้อความนี้ค้าง 4 วินาที"); other toasts 1.5 s.
const IOS_TIP_TIME := 4.0
var toast_secs := TOAST_TIME             # how long the toast showing now stays (tests read it)
var settings_path := GameSettings.PATH   # tests point this at a scratch file before build()
## What "เต็มจอ" calls off iOS (tests swap it so the real window is left alone).
var fullscreen_toggle: Callable = ScreenFit.toggle_fullscreen
var settings := {}
## Frame-rate meter for phone testing (owner 2026-11-07): "FPS 60 · 16 ms"; tap to fold it down to
## a faint "FPS" and tap again to bring it back.
var fps_button: Button
var fps_open := true
var _fps_t := 0.0
var saver_on := false          # M3k: shown as "ประหยัด" in the FPS meter
const DEAD_DIM := 0.6

func _ready() -> void:
	if hp_label == null:
		build()
	layout(get_viewport().get_visible_rect().size)
	get_viewport().size_changed.connect(func(): layout(get_viewport().get_visible_rect().size))
	wire_click_sounds()
	get_tree().node_added.connect(_on_node_added)

## Screen px per HUD px (the window shows the HUD's visible rect enlarged by this much).
func screen_scale() -> float:
	var v := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(640, 360)
	var w := get_window() if is_inside_tree() else null
	if w == null or v.x <= 0.0: return 1.0
	return float(w.size.x) / v.x

func icon_buttons() -> Array:
	return [skills_button, bag_button, map_button, settings_button]

## Wider phones (aspect "expand"): keep the top-right block and EXP bar on the real edges.
func layout(size: Vector2) -> void:
	var sc := screen_scale()
	for b in icon_buttons():
		if b is IconButton: b.fit(sc)
	top_right.size = top_right.get_combined_minimum_size()
	top_right.position.x = size.x - 6 - top_right.size.x
	# portrait (360 wide): no room beside the status panel, so the block goes on a second row
	top_right.position.y = 60.0 if ScreenFit.is_portrait(size) else 6.0
	if fps_button:
		# landscape: under the status panel; portrait: under the top-right row
		fps_button.position = Vector2(6, 60 if not ScreenFit.is_portrait(size) else top_right.position.y + top_right.size.y + 4)
	if settings_panel:
		if settings_grid: settings_grid.columns = 1 if ScreenFit.is_portrait(size) else 2
		settings_panel.size = settings_panel.get_combined_minimum_size()
		settings_panel.position = Vector2(size.x - 6 - settings_panel.size.x, top_right.position.y + top_right.size.y + 4)
	if toast and map_button:
		# under the whole top-right block (so never over the minimap box) and, while the settings panel is
		# open, under the panel too; centred under the map button, kept on screen
		toast.size = toast.get_combined_minimum_size()
		var mr := Rect2(top_right.position + map_button.position, map_button.size)
		var y := top_right.position.y + top_right.size.y + 4
		if settings_panel and settings_panel.visible: y = maxf(y, settings_panel.position.y + settings_panel.size.y + 4)
		toast.position = Vector2(clampf(mr.get_center().x - toast.size.x / 2.0, 4, size.x - 4 - toast.size.x), y)
		# the backing makes it a little wider: slide left off any touch button it would touch, again and again
		# until it touches none (sliding off one may land it on another); it stops at the left edge
		if touch_ui and touch_ui.visible and buttons:
			var moved := true
			while moved:
				moved = false
				for n in buttons.buttons:
					var b: Dictionary = buttons.buttons[n]
					var br := Rect2(b.center - Vector2(b.radius, b.radius), Vector2(b.radius, b.radius) * 2.0).grow(1.0)
					if Rect2(toast.position, toast.size).intersects(br):
						var x := maxf(4.0, br.position.x - toast.size.x)
						if x < toast.position.x:
							toast.position.x = x
							moved = true
	exp_bar.position = Vector2(0, size.y - 4)
	exp_bar.size.x = size.x
	exp_bar.custom_minimum_size.x = size.x

func build() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	fps_button = Button.new()
	fps_button.flat = true
	fps_button.focus_mode = Control.FOCUS_NONE
	fps_button.add_theme_font_size_override("font_size", UiKit.fs(8))
	fps_button.add_theme_color_override("font_color", Color("#cfe8b0"))
	fps_button.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	fps_button.add_theme_constant_override("outline_size", 3)
	fps_button.position = Vector2(6, 60)
	fps_button.pressed.connect(func():
		fps_open = not fps_open
		_fps_t = 0.0)
	root.add_child(fps_button)

	# --- status panel (top-left)
	var panel := PanelContainer.new()
	status_panel = panel
	panel.position = Vector2(6, 6)
	panel.add_theme_stylebox_override("panel", _box(PANEL, GOLD, 8))
	root.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	var face := TextureRect.new()
	var at := AtlasTexture.new()
	at.atlas = load("res://assets/hero/idle_south.png")
	at.region = Rect2(16, 10, 32, 32)
	face.texture = at
	face.custom_minimum_size = Vector2(30, 30)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/circle_mask.gdshader")
	face.material = m
	row.add_child(face)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	var name_row := HBoxContainer.new()
	col.add_child(name_row)
	name_row.add_child(_label("พราน", 10, Color("#f3e9d2")))
	level_label = _label("Lv 1", 9, GOLD)
	name_row.add_child(level_label)
	hp_bar = _bar(Color("#e0574a"), Color("#3a1414"), Vector2(110, 9))
	col.add_child(hp_bar)
	hp_label = _label("HP 0 / 0", 7, Color.WHITE)
	hp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_bar.add_child(hp_label)
	mp_bar = _bar(Color("#4a8be0"), Color("#13233f"), Vector2(110, 7))
	mp_bar.value = 100
	col.add_child(mp_bar)
	mp_label = _label("MP 0 / 0", 6, Color.WHITE)
	mp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	mp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mp_bar.add_child(mp_label)

	# --- top-right: gold, bag (M2c), minimap frame
	var tr := HBoxContainer.new()
	top_right = tr
	tr.add_theme_constant_override("separation", 6)
	tr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr.position = Vector2(640 - 6 - 232, 6)
	tr.size = Vector2(232, 56)
	tr.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(tr)
	var gold := HBoxContainer.new()
	var coin := TextureRect.new()
	coin.texture = load("res://assets/items/coin_gold.png")
	coin.custom_minimum_size = Vector2(14, 14)
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	gold.add_child(coin)
	gold_label = _label("0", 10, Color("#f3e9d2"))
	gold.add_child(gold_label)
	var gold_panel := PanelContainer.new()
	gold_panel.add_theme_stylebox_override("panel", _box(PANEL, Color(0, 0, 0, 0), 10))
	gold_panel.add_child(gold)
	gold_panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tr.add_child(gold_panel)
	# M4d Task 3d: icon-only buttons (owner-chosen PixelLab icons, 48x48)
	skills_button = IconButton.make("res://assets/ui/icons/skills.png", "SkillsButton")
	skills_button.pressed.connect(open_skills)
	tr.add_child(skills_button)
	bag_button = IconButton.make("res://assets/ui/icons/bag.png", "BagButton")
	bag_button.pressed.connect(open_bag)
	tr.add_child(bag_button)
	map_button = IconButton.make("res://assets/ui/icons/map.png", "MapButton")
	map_button.pressed.connect(open_map)
	tr.add_child(map_button)
	settings_button = IconButton.make("res://assets/ui/icons/settings.png", "SettingsButton")
	settings_button.pressed.connect(toggle_settings)
	tr.add_child(settings_button)
	var mini := PanelContainer.new()
	mini.name = "MinimapBox"
	minimap_box = mini
	mini.custom_minimum_size = Vector2(72, 54)
	mini.add_theme_stylebox_override("panel", _box(Color(0.055, 0.145, 0.11, 0.6), Color(0.93, 0.73, 0.33, 0.45), 8))
	var ml := _label("แผนที่ย่อ", 8, Color("#cfc6b0"))
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ml.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mini.add_child(ml)
	tr.add_child(mini)

	# --- settings panel (hidden until the settings button is tapped)
	settings = GameSettings.load_or_default(settings_path)
	settings_panel = PanelContainer.new()
	settings_panel.name = "SettingsPanel"
	settings_panel.add_theme_stylebox_override("panel", _box(Color(0.055, 0.145, 0.11, 0.92), GOLD, 8))
	settings_panel.visible = false
	root.add_child(settings_panel)
	var sv := GridContainer.new()
	sv.name = "SettingsGrid"
	sv.columns = 1
	sv.add_theme_constant_override("h_separation", 4)
	sv.add_theme_constant_override("v_separation", 4)
	settings_grid = sv
	settings_panel.add_child(sv)
	var fs := Button.new()                 # full screen on/off (hides the browser bars on phones)
	fs.name = "FullscreenButton"
	fs.text = "เต็มจอ"
	fs.focus_mode = Control.FOCUS_NONE
	fs.add_theme_font_size_override("font_size", UiKit.fs(9))
	fs.custom_minimum_size = Vector2(110, IconButton.MIN_TOUCH)
	fs.pressed.connect(press_fullscreen)
	fullscreen_button = fs
	sv.add_child(fs)
	fps_toggle = CheckButton.new()
	fps_toggle.name = "FpsToggle"
	fps_toggle.text = "แสดง FPS"
	fps_toggle.focus_mode = Control.FOCUS_NONE
	fps_toggle.add_theme_font_size_override("font_size", UiKit.fs(9))
	fps_toggle.custom_minimum_size = Vector2(110, IconButton.MIN_TOUCH)
	fps_toggle.button_pressed = bool(settings.show_fps)
	fps_toggle.toggled.connect(func(on): set_show_fps(on))
	sv.add_child(fps_toggle)
	set_show_fps(bool(settings.show_fps), false)
	sound_toggle = CheckButton.new()
	sound_toggle.name = "SoundToggle"
	sound_toggle.text = "เสียง"
	sound_toggle.focus_mode = Control.FOCUS_NONE
	sound_toggle.add_theme_font_size_override("font_size", UiKit.fs(9))
	sound_toggle.custom_minimum_size = Vector2(110, IconButton.MIN_TOUCH)
	sound_toggle.button_pressed = bool(settings.sound)
	sound_toggle.toggled.connect(func(on): set_sound(on))
	sv.add_child(sound_toggle)
	var vol_row := HBoxContainer.new()
	vol_row.name = "VolumeRow"
	vol_row.add_theme_constant_override("separation", 2)
	vol_row.custom_minimum_size = Vector2(110, IconButton.MIN_TOUCH)
	var vl := _label("ความดัง", 8, Color("#f3e9d2"))
	vl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vol_row.add_child(vl)
	volume_slider = HSlider.new()
	volume_slider.name = "VolumeSlider"
	volume_slider.min_value = 0
	volume_slider.max_value = 100
	volume_slider.step = 5
	volume_slider.focus_mode = Control.FOCUS_NONE
	volume_slider.custom_minimum_size = Vector2(68, IconButton.MIN_TOUCH)   # the whole row height is the touch target
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_slider.value = int(settings.volume)
	volume_slider.value_changed.connect(func(v): set_volume(int(round(v))))
	vol_row.add_child(volume_slider)
	sv.add_child(vol_row)
	set_sound(bool(settings.sound), false)
	set_volume(int(settings.volume), false)

	# --- short notes under the top-right block ("เร็ว ๆ นี้" for the map until Task 8)
	toast = _label("", 9, Color("#f3e9d2"))
	toast.name = "Toast"
	# dark rounded backing so the note reads over bright grass
	var tb := StyleBoxFlat.new()
	tb.bg_color = Color(0.03, 0.07, 0.05, 0.86)
	tb.border_color = Color(GOLD, 0.55)
	tb.set_border_width_all(1)
	tb.set_corner_radius_all(4)
	tb.content_margin_left = 6
	tb.content_margin_right = 6
	tb.content_margin_top = 2
	tb.content_margin_bottom = 3
	toast.add_theme_stylebox_override("normal", tb)
	toast.visible = false
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast)

	# --- EXP bar (filled from M2b)
	exp_bar = _bar(GOLD, Color(0, 0, 0, 0.55), Vector2(640, 4))
	exp_bar.position = Vector2(0, 356)
	root.add_child(exp_bar)

	# --- death dim (design §5.3: screen goes dark while dead)
	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	# --- touch controls
	touch_ui = Node2D.new()
	touch_ui.name = "Touch"
	add_child(touch_ui)
	joystick = TouchJoystick.new()
	touch_ui.add_child(joystick)
	buttons = TouchButtons.new()
	buttons.build_default()
	touch_ui.add_child(buttons)
	touch_ui.visible = show_touch()
	bag_panel = BagPanel.new()
	bag_panel.build()
	add_child(bag_panel)
	skill_panel = SkillPanel.new()
	skill_panel.build()
	add_child(skill_panel)

## M4c: where world text (exit labels) may go on screen: inside the edges and above the EXP bar.
func safe_rect() -> Rect2:
	var v := get_viewport().get_visible_rect().size
	return Rect2(Vector2(4, 4), v - Vector2(8, 8 + 4))

## M4c: screen rects (HUD px) that world text must stay clear of: the status panel, the FPS line, the
## top-right block (gold, buttons, minimap), the EXP bar, and on touch screens every touch button with
## its note under it and the joystick's resting ring.
func blocked_rects() -> Array:
	var out := []
	for c in [status_panel, fps_button, exp_bar, settings_panel, toast]:
		if c and c.is_visible_in_tree(): out.append(c.get_global_rect())
	if top_right and top_right.is_visible_in_tree():
		for c in top_right.get_children():
			if c is Control and c.visible: out.append(c.get_global_rect())
	if touch_ui and touch_ui.visible:
		for n in buttons.buttons:
			var b: Dictionary = buttons.buttons[n]
			var r: float = b.radius + 3.0
			var rect := Rect2(b.center - Vector2(r, r), Vector2(r, r) * 2.0)
			if b.note != "": rect = rect.merge(Rect2(b.center.x - 24.0, b.center.y + b.radius, 48.0, 16.0))
			out.append(rect)
		var jr := TouchJoystick.RADIUS
		out.append(Rect2(joystick.idle_center() - Vector2(jr, jr), Vector2(jr, jr) * 2.0))
	return out

static func show_touch() -> bool:
	return DisplayServer.is_touchscreen_available() or "--touch" in OS.get_cmdline_user_args()

func bind(h: Hero) -> void:
	hero = h
	for sig in [h.gear_changed, h.gems_changed, h.leveled_up]:
		sig.connect(func(_a = null): _nums.clear())         # new costs / cooldowns at once
	bag_panel.hero = h
	skill_panel.hero = h

## Opens the skill · gem screen (touch input lets go first, like the bag).
func open_skills() -> void:
	if hero == null or hero.warping or skill_panel.is_open() or bag_panel.is_open(): return   # M4c: not mid-fade
	joystick.release_all()
	buttons.release_all()
	hero.external_input = Vector2.ZERO
	skill_panel.open(hero)
	Sfx.play("ui_open")

## The map button: the full map comes with Task 8; until then a short "เร็ว ๆ นี้" note.
func open_map() -> void:
	show_toast("เร็ว ๆ นี้")

## A short note under the top-right block (and the open settings panel) that fades after `secs`
## (TOAST_TIME unless given).
func show_toast(text: String, secs := TOAST_TIME) -> void:
	if _toast_tween and _toast_tween.is_valid(): _toast_tween.kill()
	toast.text = text
	toast_secs = secs
	toast.modulate.a = 1.0
	toast.visible = true
	Sfx.play("toast")
	layout(get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(640, 360))
	if not is_inside_tree(): return
	_toast_tween = create_tween()
	_toast_tween.tween_interval(secs)
	_toast_tween.tween_property(toast, "modulate:a", 0.0, 0.3)
	_toast_tween.tween_callback(func(): toast.visible = false)

## "เต็มจอ": full screen on/off; on iPhone web (no full-screen call in Safari) a 4 s tip toast instead
## (M4d addendum 3); on iPhone opened from the home screen nothing happens (already full screen); iPad
## gets real full screen (ScreenFit.fullscreen_action).
func press_fullscreen() -> void:
	var iphone := ScreenFit.is_ios_web()
	match ScreenFit.fullscreen_action(iphone, iphone and ScreenFit.is_standalone_web()):
		"tip": show_toast(ScreenFit.IOS_TIP, IOS_TIP_TIME)
		"toggle": fullscreen_toggle.call()

## The settings button opens / closes the small settings panel under the top-right block.
func toggle_settings() -> void:
	settings_panel.visible = not settings_panel.visible
	layout(get_viewport().get_visible_rect().size if is_inside_tree() else Vector2(640, 360))   # the toast moves too

## "แสดง FPS": shows or hides the frame-rate line; remembered in the settings file.
func set_show_fps(on: bool, save := true) -> void:
	settings["show_fps"] = on
	if fps_button: fps_button.visible = on
	if fps_toggle and fps_toggle.button_pressed != on: fps_toggle.set_pressed_no_signal(on)
	if save: GameSettings.save(settings, settings_path)

## "เสียง": every sound on or off at once; remembered in the settings file.
func set_sound(on: bool, save := true) -> void:
	settings["sound"] = on
	Sfx.set_enabled(on)
	if sound_toggle and sound_toggle.button_pressed != on: sound_toggle.set_pressed_no_signal(on)
	if save: GameSettings.save(settings, settings_path)

## The volume slider: 0-100 %, applied at once (also to sounds still ringing) and remembered.
func set_volume(pct: int, save := true) -> void:
	pct = clampi(pct, 0, 100)
	settings["volume"] = pct
	Sfx.set_volume(pct / 100.0)
	if volume_slider and int(round(volume_slider.value)) != pct: volume_slider.set_value_no_signal(pct)
	if save: GameSettings.save(settings, settings_path)

## Every HUD / menu button (the panels' too, and ones made later: _ready watches the tree) clicks
## "ui_button" when pressed. The bag and skills icons play "ui_open" when their screen opens instead, and the
## map icon only shows its toast for now ("toast" sound) until the full map (Task 8) opens with "ui_open".
func wire_click_sounds(n: Node = self) -> void:
	if n is BaseButton: _wire_click(n)
	for c in n.get_children(): wire_click_sounds(c)

func _wire_click(b: BaseButton) -> void:
	if b.has_meta("click_sound"): return
	b.set_meta("click_sound", true)
	if b == bag_button or b == skills_button or b == map_button: return
	b.pressed.connect(_click)

func _click() -> void:
	Sfx.play("ui_button")

func _on_node_added(n: Node) -> void:
	if n is BaseButton and is_ancestor_of(n): _wire_click(n)

## Opens the bag; held touch buttons and the joystick let go first so nothing stays pressed.
func open_bag() -> void:
	if hero == null or hero.warping or bag_panel.is_open() or skill_panel.is_open(): return
	joystick.release_all()
	buttons.release_all()
	hero.external_input = Vector2.ZERO
	bag_panel.open(hero)
	Sfx.play("ui_open")
	refresh()

func refresh() -> void:
	if hero == null: return
	var hp := hero.health.hp
	var mx := hero.health.max_hp
	hp_label.text = "HP %d / %d" % [hp, mx]
	hp_bar.value = 100.0 * hp / maxf(1.0, mx)
	level_label.text = "Lv %d" % hero.level
	mp_label.text = "MP %d / %d" % [int(hero.mp), hero.max_mp()]
	mp_bar.value = 100.0 * hero.mp / maxf(1.0, hero.max_mp())
	if hero.level >= Progression.cap(): exp_bar.value = 100.0
	else: exp_bar.value = 100.0 * hero.exp / float(Progression.exp_to_next(hero.level))
	gold_label.text = str(hero.inventory.gold)
	dim.color.a = DEAD_DIM if hero.state == "dead" else 0.0
	var c := _skill_numbers()
	buttons.set_state("skill1", hero.mp >= c.pierce_mp, c.pierce_note)
	if hero.level < Skills.unlock_level("spread"):
		buttons.set_state("skill2", false, "Lv%d" % Skills.unlock_level("spread"))
	else:
		buttons.set_state("skill2", hero.mp >= c.spread_mp, c.spread_note)
	for k in ["hp", "mp"]:
		var n := hero.inventory.count_of("potion_" + k)
		buttons.set_state("potion_" + k, n > 0, str(n))
		buttons.set_cooldown("potion_" + k, hero.potion_cooldown_left(), c.potion_cd)
	buttons.set_cooldown("skill1", hero.skill_cooldown_left("piercing"), c.pierce_cd)
	buttons.set_cooldown("skill2", hero.skill_cooldown_left("spread"), c.spread_cd)
	buttons.set_cooldown("shoot", hero.cooldown, c.shot_cd)
	buttons.set_cooldown("dodge", hero.dodge_cooldown_left(), c.dodge_cd)

## Skill costs and cooldown lengths only change with gear, gems or level, so they are worked out
## again a few times a second instead of every frame (M3k: 60 fps on phones).
var _nums := {}
var _nums_t := 0.0
const NUMS_EVERY := 0.25

func _skill_numbers() -> Dictionary:
	var now := Time.get_ticks_msec() / 1000.0
	if not _nums.is_empty() and now - _nums_t < NUMS_EVERY and int(_nums.level) == hero.level: return _nums
	_nums_t = now
	var pierce := hero.build("piercing")
	var spread := hero.build("spread")
	_nums = {
		"level": hero.level,
		"pierce_mp": pierce.mp, "spread_mp": spread.mp,
		"pierce_note": "MP %s" % Gear._trim(snappedf(pierce.mp, 0.1)),
		"spread_note": "MP %s" % Gear._trim(snappedf(spread.mp, 0.1)),
		"pierce_cd": pierce.cooldown, "spread_cd": spread.cooldown,
		"shot_cd": hero.stats().shot_cd, "potion_cd": Balance.num("potion.cooldown"),
		"dodge_cd": Balance.dodge(hero.level).cooldown,
	}
	return _nums

## "MP 11.2": the real cost after gems (dim button = not enough MP).
func _mp_note(skill_id: String) -> String:
	return "MP %s" % Gear._trim(snappedf(hero.skill_mp(skill_id), 0.1))

func _process(delta: float) -> void:
	_tick_fps(delta)
	if hero == null: return
	hero.external_input = joystick.vector if touch_ui.visible else Vector2.ZERO
	refresh()

func _label(t: String, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", UiKit.fs(size))
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 2)
	return l

func _bar(fill: Color, back: Color, sz: Vector2) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = sz
	b.size = sz
	b.add_theme_stylebox_override("fill", _box(fill, Color(0, 0, 0, 0), 3))
	b.add_theme_stylebox_override("background", _box(back, Color(0, 0, 0, 0), 3))
	return b

func _box(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1 if border.a > 0 else 0)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 5; s.content_margin_right = 7
	s.content_margin_top = 4; s.content_margin_bottom = 4
	return s

func fps_text(fps: float) -> String:
	var t := "FPS %d · %d ms" % [fps, int(round(1000.0 / maxf(1.0, fps)))]
	return t + " · ประหยัด" if saver_on else t

func _tick_fps(delta: float) -> void:
	if fps_button == null: return
	_fps_t -= delta
	if _fps_t > 0.0: return
	_fps_t = 0.5
	var fps := Engine.get_frames_per_second()
	fps_button.text = fps_text(fps) if fps_open else "FPS"
	fps_button.modulate.a = 1.0 if fps_open else 0.45
