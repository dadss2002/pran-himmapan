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
var fullscreen_button: Button
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

## Wider phones (aspect "expand"): keep the top-right block and EXP bar on the real edges.
func layout(size: Vector2) -> void:
	if fps_button:
		fps_button.position = Vector2(6, 60 if not ScreenFit.is_portrait(size) else 104)
	top_right.position.x = size.x - 6 - top_right.size.x
	# portrait (360 wide): no room beside the status panel, so the block goes on a second row
	top_right.position.y = 60.0 if ScreenFit.is_portrait(size) else 6.0
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
	var fs := Button.new()                 # full screen on/off (hides the browser bars on phones)
	fs.text = "เต็มจอ"
	fs.focus_mode = Control.FOCUS_NONE
	fs.add_theme_font_size_override("font_size", UiKit.fs(8))
	fs.custom_minimum_size = Vector2(36, 30)
	fs.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	fs.pressed.connect(ScreenFit.toggle_fullscreen)
	fullscreen_button = fs
	tr.add_child(fs)
	var sk := Button.new()
	sk.text = "สกิล"
	sk.focus_mode = Control.FOCUS_NONE
	sk.add_theme_font_size_override("font_size", UiKit.fs(8))
	sk.custom_minimum_size = Vector2(36, 30)
	sk.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	sk.pressed.connect(open_skills)
	skills_button = sk
	tr.add_child(sk)
	var bag := Button.new()
	bag.text = "กระเป๋า"
	bag.focus_mode = Control.FOCUS_NONE
	bag.pressed.connect(open_bag)
	bag_button = bag
	bag.add_theme_font_size_override("font_size", UiKit.fs(8))
	bag.custom_minimum_size = Vector2(36, 30)
	bag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tr.add_child(bag)
	var mini := PanelContainer.new()
	mini.custom_minimum_size = Vector2(72, 54)
	mini.add_theme_stylebox_override("panel", _box(Color(0.055, 0.145, 0.11, 0.6), Color(0.93, 0.73, 0.33, 0.45), 8))
	var ml := _label("แผนที่ย่อ", 8, Color("#cfc6b0"))
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ml.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mini.add_child(ml)
	tr.add_child(mini)

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
	if hero == null or skill_panel.is_open() or bag_panel.is_open(): return
	joystick.release_all()
	buttons.release_all()
	hero.external_input = Vector2.ZERO
	skill_panel.open(hero)

## Opens the bag; held touch buttons and the joystick let go first so nothing stays pressed.
func open_bag() -> void:
	if hero == null or bag_panel.is_open() or skill_panel.is_open(): return
	joystick.release_all()
	buttons.release_all()
	hero.external_input = Vector2.ZERO
	bag_panel.open(hero)
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
