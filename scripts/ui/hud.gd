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

func _ready() -> void:
	if hp_label == null:
		build()

func build() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

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
	tr.add_theme_constant_override("separation", 6)
	tr.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr.position = Vector2(640 - 6 - 190, 6)
	tr.size = Vector2(190, 56)
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
	var bag := Button.new()
	bag.text = "กระเป๋า"
	bag.disabled = true          # bag arrives in M2c
	bag.add_theme_font_size_override("font_size", 8)
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

static func show_touch() -> bool:
	return DisplayServer.is_touchscreen_available() or "--touch" in OS.get_cmdline_user_args()

func bind(h: Hero) -> void:
	hero = h
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
	buttons.set_cooldown("shoot", hero.cooldown, Balance.num("shot.cooldown"))
	buttons.set_cooldown("dodge", hero.dodge_cooldown_left(), Balance.dodge(hero.level).cooldown)

func _process(_delta: float) -> void:
	if hero == null: return
	hero.external_input = joystick.vector if touch_ui.visible else Vector2.ZERO
	refresh()

func _label(t: String, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
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
