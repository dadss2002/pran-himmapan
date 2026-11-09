class_name SkillPanel
extends CanvasLayer
## Skill · gem screen (approved sketch "หน้าสกิล · เจม"), opened by the HUD "สกิล" button or N.
## Left: skills with their gem slots. Middle: gems in the bag (dim = fits no unlocked skill).
## Right: the selected gem — level, EXP, effect, options and what it would do in each skill.
## Tap a gem, then a slot (a filled slot swaps). Tap a filled slot with nothing selected to see
## that gem and take it out. The game pauses while open. Logic works without a tree (tests).

signal closed()

const GOLD := Color("#edbb55")
const TEXT := Color("#f3e9d2")
const DIM_TEXT := Color("#b8b09c")
const UP := Color("#6ccf62")
const DOWN := Color("#ff9d8a")
const PANEL_BG := Color(0.05, 0.137, 0.102, 0.96)
const CELL := 34
const SKILLS := ["piercing", "spread"]
## Owner 2026-11-08 (combos spec): 2 slots from unlock, slot 3 / 4 at skill level gem_slots[2] / [3].
const SLOT_HELP := "ช่องเจม: 2 ช่องตั้งแต่ปลดสกิล · ช่องที่ 3 ที่เลเวลสกิล %d · ช่องที่ 4 ที่เลเวลสกิล %d · ถอดเจมฟรี เจมเก็บ EXP ไว้"
const SKILL_NAMES := {"piercing": "ศรทะลวง", "spread": "ศรกระจาย"}
const SKILL_ICONS := {"piercing": "res://assets/skills/piercing.png", "spread": "res://assets/skills/spread.png"}

var hero: Hero
var _sel := {}            # {"bag": index} or {"socket": [skill_id, slot]}
var _notice := ""
var _root: Control
var _panel: PanelContainer
var _body: BoxContainer        # the columns; stacked top-to-bottom in portrait
var _mp: Label
var _rows := {}           # skill_id -> {sub: Label, slots: HBoxContainer}
var _gem_grid: GridContainer
var _gem_cells: Array = []
var _d_icon: TextureRect
var _d_frame: PanelContainer
var _d_name: Label
var _d_sub: Label
var _d_bar: ProgressBar
var _d_effect: Label
var _d_lines: VBoxContainer
var _d_action: Button
var _d_top: HBoxContainer       # icon + name row; in portrait the action button sits at its right
var _d_box: VBoxContainer       # the detail column
var _close_button: Button

func _ready() -> void:
	if _root == null: build()
	_layout()
	get_viewport().size_changed.connect(_layout)

func open(h: Hero) -> void:
	hero = h
	hero.return_closed_gems()      # owner 2026-11-09: a gem left in a closed slot comes back once the bag has room
	if _root == null: build()
	visible = true
	_notice = ""
	if not _sel_valid(): _sel = {}
	refresh()
	if is_inside_tree(): get_tree().paused = true

func close() -> void:
	visible = false
	_taps.reset()
	if is_inside_tree(): get_tree().paused = false
	closed.emit()

func is_open() -> bool:
	return visible

## Taps from any finger (TouchTaps): a thumb still resting where the joystick was must not stop another finger
## pressing this screen's buttons; while open, other fingers' touches stop here.
var _taps := TouchTaps.new()

func _input(e: InputEvent) -> void:
	if _taps.feed(e, _root, TouchTaps.EVERYWHERE, visible):
		get_viewport().set_input_as_handled()

func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		if e.is_action_pressed("skills") and get_parent() is Hud:
			(get_parent() as Hud).open_skills()
			get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("skills") or e.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

# ---------- logic ----------

## Bag indices that hold gems, in bag order.
func gem_cells() -> Array:
	var out: Array = []
	if hero == null: return out
	for i in hero.inventory.slots.size():
		var s: Dictionary = hero.inventory.slots[i]
		if String(s.id).begins_with("gem_") and not s.has("item"): out.append(i)
	return out

## True when the gem in this grid cell fits at least one unlocked skill.
func cell_usable(cell: int) -> bool:
	var v := gem_cells()
	if cell >= v.size(): return false
	var type := String(hero.inventory.slots[v[cell]].id).trim_prefix("gem_")
	for id in SKILLS:
		if hero.level >= Skills.unlock_level(id) and Gem.fits(type, id): return true
	return false

func select_gem(bag_index: int) -> void:
	_sel = {"bag": bag_index}
	_notice = ""
	refresh()

## A slot tap: socket the selected bag gem (swap if filled), or select the socketed gem.
func press_slot(skill_id: String, slot: int) -> String:
	var res := ""
	if _sel.has("bag"):
		res = hero.socket(skill_id, slot, int(_sel.bag))
		if res == "": _sel = {"socket": [skill_id, slot]}
	else:
		var sockets: Array = hero.skill_gems.get(skill_id, [])
		if slot < sockets.size() and sockets[slot] != null:
			_sel = {"socket": [skill_id, slot]}
		else:
			res = "แตะเจมก่อน แล้วแตะช่องนี้"
	_notice = res
	refresh()
	return res

## Detail button: take the selected socketed gem out.
func press_action() -> String:
	if not _sel.has("socket"): return "ไม่มีเจมที่เลือก"
	var res := hero.unsocket(String(_sel.socket[0]), int(_sel.socket[1]))
	if res == "": _sel = {}
	_notice = res
	refresh()
	return res

func _sel_valid() -> bool:
	if hero == null: return false
	if _sel.has("bag"): return int(_sel.bag) in gem_cells()
	if _sel.has("socket"):
		var sockets: Array = hero.skill_gems.get(String(_sel.socket[0]), [])
		return int(_sel.socket[1]) < sockets.size() and sockets[int(_sel.socket[1])] != null
	return false

func _selected_gem() -> Dictionary:
	if _sel.has("bag"):
		var s: Dictionary = hero.inventory.slots[int(_sel.bag)]
		if s.has("gem"): return s.gem
		return {"type": String(s.id).trim_prefix("gem_"), "level": 1, "exp": 0, "rarity": "common", "opts": [], "_plain_count": int(s.count)}
	if _sel.has("socket"): return hero.skill_gems[String(_sel.socket[0])][int(_sel.socket[1])]
	return {}

## name, color, sub, exp_frac, effect, lines [{text, color}], action, action_ok, icon
func gem_detail() -> Dictionary:
	var d := {"name": "", "color": TEXT, "sub": "", "exp_frac": 0.0, "effect": "", "lines": [], "action": "", "action_ok": false, "icon": ""}
	if hero == null or not _sel_valid():
		d.effect = "แตะเจมในกระเป๋า แล้วแตะช่องเจมของสกิลทางซ้าย"
		if _notice != "": d.lines.append({"text": _notice, "color": DOWN})
		return d
	var g := _selected_gem()
	var t := String(g.type)
	d.icon = LootDrop.icon_path("gem_" + t)
	d.name = "%s Lv%d" % [Gem.display_name(t), int(g.level)]
	d.color = Gear.rarity_color(String(g.rarity))
	d.sub = "ระดับ %s · ป้าย%s · MP ×%s" % [Gear.rarity_name(String(g.rarity)), Gem.label_text(t), Gear._trim(Gem.mp_mult(t))]
	if int(g.level) >= Gem.cap(): d.sub += " · EXP ตัน"
	else:
		d.sub += " · EXP %d/%d" % [int(g.exp), Gem.exp_to_next(int(g.level))]
		d.exp_frac = float(g.exp) / Gem.exp_to_next(int(g.level))
	if g.has("_plain_count") and int(g._plain_count) > 1: d.sub += " · มี %d" % int(g._plain_count)
	d.effect = Gem.describe_effect(g)
	for o in g.get("opts", []): d.lines.append({"text": Gem.describe_option(o), "color": UP})
	if _sel.has("socket"):
		d.lines.append({"text": "ใส่อยู่ที่%s ช่อง %d" % [SKILL_NAMES[_sel.socket[0]], int(_sel.socket[1]) + 1], "color": GOLD})
		d.action = "ถอดเจม"
		d.action_ok = true
	else:
		_previews(d, g)
		d.action = "แตะช่องทางซ้ายเพื่อใส่"
	if _notice != "": d.lines.append({"text": _notice, "color": DOWN})
	return d

## "ศรทะลวง: MP 8 → 11.2" for each skill (with the gem added, or replacing slot 1 when full).
func _previews(d: Dictionary, g: Dictionary) -> void:
	var t := String(g.type)
	var any := false
	for id in SKILLS:
		if not Gem.fits(t, id): continue
		any = true
		if hero.level < Skills.unlock_level(id):
			d.lines.append({"text": "%s: ปลดที่ Lv%d" % [SKILL_NAMES[id], Skills.unlock_level(id)], "color": DIM_TEXT})
			continue
		var now: Array = hero.open_gems(id)      # a closed slot's gem has no effect (M5b Task 1)
		var after := now.duplicate()
		var free := after.find(null)
		if free == -1 and after.size() < hero.gem_slots(id): after.append(g)
		elif free != -1: after[free] = g
		else: after[0] = g
		var b0 := SkillBuild.of(id, hero.level, now, hero.stats())
		var b1 := SkillBuild.of(id, hero.level, after, hero.stats())
		var text := "%s: MP %s → %s" % [SKILL_NAMES[id], Gear._trim(snappedf(b0.mp, 0.1)), Gear._trim(snappedf(b1.mp, 0.1))]
		if b1.arrows != b0.arrows: text += " · ลูกศร %d → %d" % [b0.arrows, b1.arrows]
		if t == "pierce" and b0.pierce_all: text += " · ทะลุทุกตัวอยู่แล้ว ไม่มีผลเพิ่ม"
		d.lines.append({"text": text, "color": UP if not (t == "pierce" and b0.pierce_all) else DIM_TEXT})
	if not any: d.lines.append({"text": "ยังไม่มีสกิลที่ใส่ได้ (ใช้กับห่าศรในรอบถัดไป)", "color": DOWN})

# ---------- view ----------

func build() -> void:
	layer = 20
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.size = Vector2(640, 360)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.016, 0.047, 0.035, 0.7)
	dim.size = Vector2(4000, 4000)
	dim.position = Vector2(-1000, -1000)
	_root.add_child(dim)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiKit.box(PANEL_BG, Color(GOLD, 0.55), 12, 8))
	_panel.position = Vector2(8, 8)
	_panel.size = Vector2(624, 344)
	_root.add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_panel.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	head.add_child(UiKit.label("สกิล · เจม", 13, GOLD))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_mp = UiKit.label("", 10, Color("#9ad0ff"))
	head.add_child(_mp)
	_close_button = Button.new()
	_close_button.text = "×"
	_close_button.custom_minimum_size = Vector2(30, 26)
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.pressed.connect(close)
	head.add_child(_close_button)

	var body := BoxContainer.new()     # side by side; stacked in portrait (_layout)
	_body = body
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(232, 0)
	left.add_theme_constant_override("separation", 6)
	body.add_child(left)
	for id in SKILLS:
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0.25), Color(1, 1, 1, 0.12), 10, 6))
		left.add_child(row)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		row.add_child(h)
		h.add_child(UiKit.icon(SKILL_ICONS[id], 30))
		var names := VBoxContainer.new()
		names.add_theme_constant_override("separation", 0)
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(names)
		names.add_child(UiKit.label(SKILL_NAMES[id], 11, TEXT))
		var sub := UiKit.label("", 8, Color("#cfc6b0"))
		names.add_child(sub)
		var slots := HBoxContainer.new()
		slots.add_theme_constant_override("separation", 4)
		h.add_child(slots)
		_rows[id] = {"sub": sub, "slots": slots}
	var rain := HBoxContainer.new()
	rain.modulate.a = 0.55
	rain.add_child(UiKit.icon("res://assets/skills/arrow_rain.png", 30))
	rain.add_child(UiKit.label("ห่าศร · มาในรอบถัดไป (ป้ายพื้นที่·ต่อเนื่อง)", 9, DIM_TEXT))
	left.add_child(rain)
	var slot_lv: Array = Balance.data()["gem_slots"]
	var slot_help := UiKit.label(SLOT_HELP % [int(slot_lv[2]), int(slot_lv[3])], 8, DIM_TEXT)
	slot_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART    # longer than the 232 px column
	left.add_child(slot_help)

	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 5)
	body.add_child(mid)
	mid.add_child(UiKit.label("เจมในกระเป๋า", 10, GOLD))
	_gem_grid = GridContainer.new()
	_gem_grid.columns = 4
	_gem_grid.add_theme_constant_override("h_separation", 4)
	_gem_grid.add_theme_constant_override("v_separation", 4)
	mid.add_child(_gem_grid)
	for i in int(Balance.num("bag.slots")):
		var c := UiKit.cell(CELL)
		var q := UiKit.label("", 8, Color.WHITE)
		q.name = "Qty"
		q.position = Vector2(CELL - 16, CELL - 14)
		q.size = Vector2(14, 12)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		q.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(q)
		c.pressed.connect(_on_gem_cell.bind(i))
		_gem_grid.add_child(c)
		_gem_cells.append(c)
	mid.add_child(UiKit.label("จาง = ยังไม่มีสกิลที่ใส่ได้", 8, DIM_TEXT))

	var det := PanelContainer.new()
	det.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0.25), Color(1, 1, 1, 0.15), 10, 8))
	det.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(det)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 3)
	det.add_child(dv)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	dv.add_child(top)
	_d_top = top
	_d_box = dv
	_d_frame = PanelContainer.new()
	_d_frame.custom_minimum_size = Vector2(40, 40)
	_d_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER   # stays square beside the 44 px button
	top.add_child(_d_frame)
	_d_icon = UiKit.icon("", 32)
	_d_frame.add_child(_d_icon)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 0)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nv)
	_d_name = UiKit.label("", 12, TEXT)
	nv.add_child(_d_name)
	_d_sub = UiKit.label("", 7, Color("#cfc6b0"))
	_d_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nv.add_child(_d_sub)
	_d_bar = ProgressBar.new()
	_d_bar.show_percentage = false
	_d_bar.custom_minimum_size = Vector2(0, 4)
	_d_bar.add_theme_stylebox_override("background", UiKit.box(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 2, 0))
	_d_bar.add_theme_stylebox_override("fill", UiKit.box(GOLD, Color(0, 0, 0, 0), 2, 0))
	dv.add_child(_d_bar)
	_d_effect = UiKit.label("", 10, Color.WHITE)
	_d_effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dv.add_child(_d_effect)
	_d_lines = VBoxContainer.new()
	_d_lines.add_theme_constant_override("separation", 0)
	dv.add_child(_d_lines)
	_d_action = Button.new()
	_d_action.custom_minimum_size = Vector2(0, 32)
	_d_action.focus_mode = Control.FOCUS_NONE
	_d_action.add_theme_font_size_override("font_size", UiKit.fs(11))
	_d_action.pressed.connect(func(): press_action())
	dv.add_child(_d_action)
	dv.move_child(_d_action, 1)     # right under the name row (landscape); _place_button moves it in portrait

func _on_gem_cell(cell: int) -> void:
	var v := gem_cells()
	if cell < v.size(): select_gem(v[cell])

func refresh() -> void:
	if hero == null or _root == null: return
	_mp.text = "MP %d/%d · ฟื้น %s/วิ" % [int(hero.mp), hero.max_mp(), Gear._trim(hero.stats().mp_regen)]
	for id in SKILLS:
		var row: Dictionary = _rows[id]
		var slots: HBoxContainer = row.slots
		for c in slots.get_children():      # a slot button may be mid-press: free it next frame
			slots.remove_child(c)
			c.queue_free()
		var unlocked := hero.level >= Skills.unlock_level(id)
		if unlocked:
			var b := hero.build(id)
			row.sub.text = "Lv%d · ป้ายลูกศร · MP %s · CD %s วิ" % [Skills.skill_level(id, hero.level), Gear._trim(snappedf(b.mp, 0.1)), Gear._trim(snappedf(b.cooldown, 0.1))]
		else:
			row.sub.text = "ปลดที่ Lv%d" % Skills.unlock_level(id)
		var n := maxi(1, hero.gem_slots(id))
		var sockets: Array = hero.skill_gems.get(id, [])
		for i in n:
			var c := UiKit.cell(CELL + 2)
			var g = sockets[i] if i < sockets.size() else null
			(c.get_node("Icon") as TextureRect).texture = load(LootDrop.icon_path("gem_" + String(g.type))) if g != null else null
			if g == null:
				c.text = "ว่าง" if unlocked else "ล็อก"
				c.add_theme_font_size_override("font_size", UiKit.fs(8))
				c.add_theme_color_override("font_color", Color("#a59c86"))
			var on: bool = _sel.has("socket") and _sel.socket[0] == id and int(_sel.socket[1]) == i
			UiKit.style_cell(c, Gear.rarity_color(String(g.rarity)) if g != null else Color("#6b6450"), g != null, on)
			c.disabled = not unlocked
			c.pressed.connect(press_slot.bind(id, i))
			slots.add_child(c)
	var v := gem_cells()
	for i in _gem_cells.size():
		var c: Button = _gem_cells[i]
		var ic: TextureRect = c.get_node("Icon")
		var q: Label = c.get_node("Qty")
		c.visible = i < maxi(v.size(), 8)
		if i < v.size():
			var s: Dictionary = hero.inventory.slots[v[i]]
			ic.texture = load(LootDrop.icon_path(String(s.id)))
			ic.modulate.a = 1.0 if cell_usable(i) else 0.4
			q.text = str(s.count) if s.count > 1 else ("Lv%d" % int(s.gem.level) if s.has("gem") else "")
			var border := Gear.rarity_color(String(s.gem.rarity)) if s.has("gem") else Color("#9aa0a6")
			UiKit.style_cell(c, border, true, _sel.get("bag", -1) == v[i])
		else:
			ic.texture = null
			q.text = ""
			UiKit.style_cell(c, Color(1, 1, 1, 0.08), false, false)
	var d := gem_detail()
	_d_icon.texture = load(d.icon) if d.icon != "" else null
	_d_frame.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0.35), d.color, 8, 4, 2))
	_d_name.text = d.name
	_d_name.add_theme_color_override("font_color", d.color)
	_d_sub.text = d.sub
	_d_bar.value = 100.0 * d.exp_frac
	_d_bar.visible = d.name != ""
	_d_effect.text = d.effect
	for c in _d_lines.get_children(): c.free()
	for l in d.lines:
		var lab := UiKit.label(l.text, 8, l.color)
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_d_lines.add_child(lab)
	_d_action.visible = d.action != ""
	_d_action.text = d.action
	UiKit.style_action(_d_action, d.action_ok)
	_layout.call_deferred()          # the detail changed size: fit the panel to the screen again

## Landscape: the 624x344 three-column panel. Portrait: the columns stack and the panel takes the
## screen width (scaled down only if it would still not fit). Owner 2026-11-08 (same fix as the bag): on
## iPhone web the portrait panel keeps Safari's bottom bar clear (ScreenFit.bottom_inset), and refresh()
## refits it each time the detail changes.
func _layout() -> void:
	if _panel == null or not is_inside_tree(): return
	var size := get_viewport().get_visible_rect().size
	var portrait := ScreenFit.is_portrait(size)
	_place_button(portrait)
	if _body.vertical != portrait:
		_body.vertical = portrait
		_panel.size = Vector2.ZERO
	if portrait:
		_panel.size = Vector2(size.x - 12, 0)
		_panel.size = Vector2(size.x - 12, _panel.get_combined_minimum_size().y)
	else:
		_panel.size = Vector2(624, maxf(344.0, _panel.get_combined_minimum_size().y))
	var bottom := ScreenFit.bottom_inset(portrait)
	var room := Vector2(size.x - 8, size.y - 8 - bottom)
	var fit := minf(1.0, minf(room.x / _panel.size.x, room.y / _panel.size.y))
	_panel.scale = Vector2(fit, fit)
	var shown := _panel.size * fit
	_panel.position = Vector2(floorf((size.x - shown.x) / 2.0), floorf((size.y - bottom - shown.y) / 2.0))

## Portrait: the action button sits at the right of the icon + name row, at least IconButton.MIN_TOUCH
## tall. Landscape (narrow detail column): right under that row.
func _place_button(portrait: bool) -> void:
	if _d_action == null: return
	var want: Node = _d_top if portrait else _d_box
	if _d_action.get_parent() != want:
		_d_action.get_parent().remove_child(_d_action)
		want.add_child(_d_action)
		if want == _d_box: _d_box.move_child(_d_action, 1)
	_d_action.custom_minimum_size = Vector2(72, IconButton.MIN_TOUCH) if portrait else Vector2(0, 32)
	_d_action.size_flags_horizontal = Control.SIZE_SHRINK_END if portrait else Control.SIZE_FILL
