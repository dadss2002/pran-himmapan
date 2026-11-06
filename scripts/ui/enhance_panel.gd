class_name EnhancePanel
extends CanvasLayer
## ตีบวก window (approved sketch "ตีบวก"), opened from the bag on a bow or armor, worn or in the bag.
## Shows the step, the main stats before → after, chance, ore and gold (red when short) and a warning
## that turns red from +6 (a miss drops one step). The bag below keeps the game paused.

signal closed()

const GOLD := Color("#edbb55")
const TEXT := Color("#f3e9d2")
const DIM_TEXT := Color("#b8b09c")
const UP := Color("#6ccf62")
const DOWN := Color("#ff9d8a")
const SAFE_TEXT := Color("#bfe8b9")
const RISK_TEXT := Color("#ffc2b5")

var hero: Hero
var ref := {}             # {"worn": slot} or {"bag": index}
var rng := RandomNumberGenerator.new()
var _result := ""
var _result_good := false
var _root: Control
var _panel: PanelContainer
var _icon: TextureRect
var _frame: PanelContainer
var _title: Label
var _stat: Label
var _chance: Label
var _ore: Label
var _gold: Label
var _warn: Label
var _warn_box: PanelContainer
var _res: Label
var _button: Button
var _close_button: Button

func _ready() -> void:
	if _root == null: build()
	_layout()
	get_viewport().size_changed.connect(_layout)

func open(h: Hero, item_ref: Dictionary) -> void:
	hero = h
	ref = item_ref
	_result = ""
	if _root == null: build()
	visible = true
	refresh()

func close() -> void:
	visible = false
	closed.emit()

func is_open() -> bool:
	return visible

func _unhandled_input(e: InputEvent) -> void:
	if visible and (e.is_action_pressed("ui_cancel") or e.is_action_pressed("bag") or e.is_action_pressed("skills")):
		close()
		get_viewport().set_input_as_handled()

func item() -> Dictionary:
	if hero == null: return {}
	if ref.has("worn"):
		var it = hero.equipped.get(String(ref.worn))
		return it if typeof(it) == TYPE_DICTIONARY else {}
	var i := int(ref.get("bag", -1))
	if i < 0 or i >= hero.inventory.slots.size(): return {}
	return hero.inventory.slots[i].get("item", {})

## title, stat, chance, ore_text, gold_text, ore_ok, gold_ok, safe, warn, can, button, result
func detail() -> Dictionary:
	var it := item()
	var d := {"title": "", "stat": "", "chance": "", "ore_text": "", "gold_text": "", "ore_ok": false, "gold_ok": false,
		"safe": true, "warn": "", "can": false, "button": "", "result": _result, "result_good": _result_good, "color": TEXT, "icon": ""}
	if it.is_empty() or not Enhance.can(it): return d
	var plus := int(it.get("plus", 0))
	d.icon = LootDrop.icon_path(String(it.base))
	d.color = Gear.rarity_color(String(it.rarity))
	if plus >= Enhance.max_plus():
		d.title = "%s (สูงสุด)" % Gear.item_name(it)
		d.stat = Gear.main_text(Gear.main_stats(it))
		d.button = "สูงสุดแล้ว"
		return d
	var target := plus + 1
	d.title = "%s → +%d" % [Gear.item_name(it), target]
	var before := Gear.main_stats(it)
	var after := Gear.main_stats(it, target)
	var parts: Array = []
	for k in ["atk", "def", "hp"]:
		if before.has(k):
			parts.append("%s +%s → +%s" % [k.to_upper(), Gear._trim(snappedf(float(before[k]), 0.1)), Gear._trim(snappedf(float(after[k]), 0.1))])
	d.stat = " · ".join(parts)
	d.chance = Gear._trim(Enhance.chance(target) * 100.0) + "%"
	var ore_id := String(Balance.data()["enhance"]["ore_id"])
	var have_ore := hero.inventory.count_of(ore_id)
	d.ore_ok = have_ore >= Enhance.ore(target)
	d.gold_ok = hero.inventory.gold >= Enhance.gold(target)
	d.ore_text = "%d (มี %d)" % [Enhance.ore(target), have_ore]
	d.gold_text = "%s (มี %s)" % [_num(Enhance.gold(target)), _num(hero.inventory.gold)]
	d.safe = plus <= int(Balance.num("enhance.safe_max"))
	d.warn = "ตีไม่ติด: เสียแค่แร่กับทอง ขั้นไม่ลด" if d.safe else "ตีไม่ติด: ลดเหลือ +%d" % (plus - 1)
	d.can = d.ore_ok and d.gold_ok
	d.button = "ตีบวก" if d.can else ("แร่ไม่พอ" if not d.ore_ok else "ทองไม่พอ")
	return d

static func _num(n: int) -> String:
	var s := str(n)
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0: out += ","
		out += s[i]
	return out

## One attempt. roll: tests pass the 0–1 draw; < 0 uses rng. Returns the Thai result line.
func press(roll := -1.0) -> String:
	var d := detail()
	if not d.can:
		_result = d.button
		_result_good = false
		refresh()
		return _result
	var it := item()
	var res := Enhance.attempt(it, hero.inventory, rng, roll)
	match res.result:
		"ok": _result = "ตีติด! +%d" % res.plus
		"fail": _result = "ตีไม่ติด (เสียแร่และทอง)"
		"down": _result = "ตีไม่ติด ลดเหลือ +%d" % res.plus
		_: _result = String(res.result)
	_result_good = res.result == "ok"
	hero._on_gear_changed()          # stats, HP clamp and the save follow at once
	refresh()
	return _result

func build() -> void:
	layer = 25
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.size = Vector2(640, 360)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.016, 0.047, 0.035, 0.6)
	dim.size = Vector2(4000, 4000)
	dim.position = Vector2(-1000, -1000)
	_root.add_child(dim)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiKit.box(Color("#0f2a1f"), Color(GOLD, 0.7), 12, 10))
	_panel.size = Vector2(380, 250)
	_panel.position = Vector2(130, 55)
	_root.add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_panel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	head.add_child(UiKit.label("ตีบวก", 13, GOLD))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_close_button = Button.new()
	_close_button.text = "✕"
	_close_button.custom_minimum_size = Vector2(30, 26)
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.pressed.connect(close)
	head.add_child(_close_button)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	col.add_child(top)
	_frame = PanelContainer.new()
	_frame.custom_minimum_size = Vector2(46, 46)
	top.add_child(_frame)
	_icon = UiKit.icon("", 38)
	_frame.add_child(_icon)
	var nv := VBoxContainer.new()
	top.add_child(nv)
	_title = UiKit.label("", 12, TEXT)
	nv.add_child(_title)
	_stat = UiKit.label("", 10, Color.WHITE)
	nv.add_child(_stat)
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 6)
	col.add_child(grid)
	_chance = _stat_box(grid, "โอกาสติด", "")
	_ore = _stat_box(grid, "แร่หิมพานต์", "res://assets/items/ore_himmapan.png")
	_gold = _stat_box(grid, "ทอง", "res://assets/items/coin_gold.png")
	_warn_box = PanelContainer.new()
	col.add_child(_warn_box)
	_warn = UiKit.label("", 10, SAFE_TEXT)
	_warn_box.add_child(_warn)
	col.add_child(UiKit.label("ตีได้เฉพาะธนูและชุด · ค่าหลัก +%s%%/ขั้น ถึง +%d แล้ว +%s%%/ขั้น" % [
		Gear._trim(Balance.num("enhance.bonus_low") * 100.0), int(Balance.num("enhance.bonus_low_until")), Gear._trim(Balance.num("enhance.bonus_high") * 100.0)], 8, DIM_TEXT))
	_res = UiKit.label("", 11, UP)
	col.add_child(_res)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(fill)
	_button = Button.new()
	_button.custom_minimum_size = Vector2(0, 34)
	_button.focus_mode = Control.FOCUS_NONE
	_button.add_theme_font_size_override("font_size", 13)
	_button.pressed.connect(func(): press())
	col.add_child(_button)

func _stat_box(parent: Control, title: String, icon_path: String) -> Label:
	var b := PanelContainer.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0.3), Color(0, 0, 0, 0), 8, 6))
	parent.add_child(b)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	b.add_child(h)
	if icon_path != "": h.add_child(UiKit.icon(icon_path, 18))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	h.add_child(v)
	v.add_child(UiKit.label(title, 8, DIM_TEXT))
	var val := UiKit.label("", 11, Color("#fde39a"))
	v.add_child(val)
	return val

func refresh() -> void:
	if _root == null or hero == null: return
	var d := detail()
	_icon.texture = load(d.icon) if d.icon != "" else null
	_frame.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0.35), d.color, 8, 4, 2))
	_title.text = d.title
	_title.add_theme_color_override("font_color", d.color)
	_stat.text = d.stat
	_chance.text = d.chance
	_ore.text = d.ore_text
	_ore.add_theme_color_override("font_color", UP if d.ore_ok else DOWN)
	_gold.text = d.gold_text
	_gold.add_theme_color_override("font_color", UP if d.gold_ok else DOWN)
	_warn.text = d.warn
	_warn.add_theme_color_override("font_color", SAFE_TEXT if d.safe else RISK_TEXT)
	_warn_box.add_theme_stylebox_override("panel", UiKit.box(Color(UP, 0.08) if d.safe else Color(DOWN, 0.1), Color(UP, 0.5) if d.safe else Color(DOWN, 0.6), 8, 6))
	_warn_box.visible = d.warn != ""
	_res.text = d.result
	_res.add_theme_color_override("font_color", UP if d.result_good else DOWN)
	_button.text = d.button
	UiKit.style_action(_button, d.can)

func _layout() -> void:
	if _panel == null or not is_inside_tree(): return
	var size := get_viewport().get_visible_rect().size
	_panel.position = Vector2(floorf((size.x - _panel.size.x) / 2.0), floorf((size.y - _panel.size.y) / 2.0))
