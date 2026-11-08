class_name BagPanel
extends CanvasLayer
## The bag screen (approved mockup "กระเป๋า · สวมใส่"), laid out for the 640×360 view:
## worn slots + stats on the left, 6×4 bag grid with tabs in the middle, detail on the right.
## The game pauses while it is open. Logic (select / selected_detail / press_action) works
## without a tree so tests can drive it.

signal closed()

const GOLD := Color("#edbb55")
const TEXT := Color("#f3e9d2")
const DIM_TEXT := Color("#b8b09c")
const UP := Color("#6ccf62")       # better / option lines
const DOWN := Color("#ff9d8a")     # worse / locked
const PANEL_BG := Color(0.05, 0.137, 0.102, 0.96)
const CELL := 34
const TABS := ["ทั้งหมด", "อุปกรณ์", "ยา", "วัตถุดิบ"]
const SLOT_NAMES := {"bow": "ธนู", "armor": "ชุด", "ring": "แหวน", "necklace": "สร้อย"}
const ITEMS_PATH := "res://data/items.json"

var hero: Hero
var tab := 0
var _sel := {}                     # {"bag": index} or {"worn": slot}
var _notice := ""                  # why the last action was refused; cleared on the next selection
var _items := {}
var _root: Control
var _panel: PanelContainer
var _body: BoxContainer        # the columns; stacked top-to-bottom in portrait
var _gold: Label
var _cells: Array = []             # Buttons
var _worn_buttons := {}
var _stats: GridContainer
var _who: Label
var _used: Label
var _tab_buttons: Array = []
var _d_icon: TextureRect
var _d_frame: PanelContainer
var _d_name: Label
var _d_sub: Label
var _d_main: Label
var _d_lines: VBoxContainer
var _d_action: Button
var _d_enhance: Button
var _d_top: HBoxContainer       # icon + name row; in portrait the action buttons sit at its right
var _d_box: VBoxContainer       # the detail column
var _d_btns: HBoxContainer      # สวมใส่/ใช้/ถอด + ตีบวก
## Owner 2026-11-08 ("กดสวมใส่ไม่ได้"): Safari's bottom bar on iPhone covered the action button, so the
## buttons moved up beside the item name, and on iPhone web the portrait panel keeps clear of the bottom.
const IOS_BOTTOM_INSET := 64.0
var enhance_panel: EnhancePanel
var _close_button: Button

func _ready() -> void:
	if _root == null: build()
	_layout()
	get_viewport().size_changed.connect(_layout)

func _items_text() -> Dictionary:
	if _items.is_empty():
		_items = JSON.parse_string(FileAccess.open(ITEMS_PATH, FileAccess.READ).get_as_text())
	return _items

# ---------- open / close ----------

func open(h: Hero) -> void:
	hero = h
	if _root == null: build()
	visible = true
	if _sel.is_empty() or not _sel_valid(): _select_first()
	refresh()
	if is_inside_tree(): get_tree().paused = true

func close() -> void:
	if enhance_panel and enhance_panel.is_open(): enhance_panel.close()
	visible = false
	if is_inside_tree(): get_tree().paused = false
	closed.emit()

func is_open() -> bool:
	return visible

## I/B open and close the bag; Esc closes. Opening goes through the HUD so touch input lets go.
func _unhandled_input(e: InputEvent) -> void:
	if not visible:
		if e.is_action_pressed("bag") and get_parent() is Hud:
			(get_parent() as Hud).open_bag()
			get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("bag") or e.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

# ---------- logic ----------

func set_tab(i: int) -> void:
	tab = i
	if _sel.has("bag") and not (int(_sel.bag) in visible_cells()): _select_first()
	refresh()

## Bag indices shown under the current tab, in bag order.
func visible_cells() -> Array:
	var out: Array = []
	if hero == null: return out
	for i in hero.inventory.slots.size():
		var s: Dictionary = hero.inventory.slots[i]
		var k := _kind(s)
		if tab == 0 or (tab == 1 and k == "gear") or (tab == 2 and k == "potion") or (tab == 3 and k == "material"):
			out.append(i)
	return out

func select(bag_index: int) -> void:
	_sel = {"bag": bag_index}
	_notice = ""
	refresh()

func select_worn(slot: String) -> void:
	_sel = {"worn": slot}
	_notice = ""
	refresh()

func _kind(s: Dictionary) -> String:
	if s.has("item"): return "gear"
	return String(_items_text().get(String(s.id), {}).get("kind", "material"))

func _sel_valid() -> bool:
	if _sel.has("bag"): return int(_sel.bag) < hero.inventory.slots.size() and int(_sel.bag) in visible_cells()
	if _sel.has("worn"): return hero.equipped.get(String(_sel.worn)) != null
	return false

func _select_first() -> void:
	var v := visible_cells()
	_sel = {"bag": v[0]} if not v.is_empty() else {"worn": "bow"}

## Everything the detail panel shows: name, color, sub, main, lines [{text, color}],
## action (button text, "" = no button) and action_ok.
func selected_detail() -> Dictionary:
	var d := {"name": "", "color": TEXT, "sub": "", "main": "", "lines": [], "action": "", "action_ok": false, "icon": "", "enhance": false}
	if hero == null or not _sel_valid(): return d
	_detail_body(d)
	if _notice != "": d.lines.append({"text": _notice, "color": DOWN})
	return d

func _detail_body(d: Dictionary) -> void:
	if _sel.has("worn"):
		var it: Dictionary = hero.equipped[String(_sel.worn)]
		_gear_detail(d, it)
		d.lines.append({"text": "สวมอยู่", "color": GOLD})
		if _sel.worn == "bow":
			d.lines.append({"text": "เปลี่ยนธนูได้โดยสวมธนูอันอื่น", "color": DIM_TEXT})
			d.action = "สวมอยู่"
		else:
			d.action = "ถอด"
			d.action_ok = true
		return
	var s: Dictionary = hero.inventory.slots[int(_sel.bag)]
	d.icon = LootDrop.icon_path(String(s.id))
	if s.has("item"):
		var it: Dictionary = s.item
		_gear_detail(d, it)
		_compare(d, it)
		var req := Gear.req_level(String(it.base))
		if hero.level < req:
			d.lines.append({"text": "ต้อง Lv%d · ตอนนี้ Lv%d" % [req, hero.level], "color": DOWN})
			d.action = "ต้อง Lv%d" % req
		else:
			d.action = "สวมใส่"
			d.action_ok = true
		return
	if s.has("gem"):
		var g: Dictionary = s.gem
		d.name = "%s Lv%d" % [Gem.display_name(String(g.type)), int(g.level)]
		d.color = Gear.rarity_color(String(g.rarity))
		d.sub = "ระดับ %s · ป้าย%s · MP ×%s" % [Gear.rarity_name(String(g.rarity)), Gem.label_text(String(g.type)), Gear._trim(Gem.mp_mult(String(g.type)))]
		d.main = Gem.describe_effect(g)
		for o in g.get("opts", []): d.lines.append({"text": Gem.describe_option(o), "color": UP})
		d.lines.append({"text": "ใส่ได้ที่หน้าสกิล (ปุ่ม \"สกิล\")", "color": DIM_TEXT})
		return
	var t: Dictionary = _items_text().get(String(s.id), {})
	d.name = String(t.get("name", s.id))
	d.sub = "%s · มี %d" % [t.get("sub", ""), int(s.count)]
	if t.get("kind", "") == "potion":
		var stat := "HP" if String(s.id) == "potion_hp" else "MP"
		var other := "MP" if stat == "HP" else "HP"
		d.main = "ฟื้น %s %d%%" % [stat, int(round(Balance.num("potion.heal_frac") * 100))]
		d.lines.append({"text": "คูลดาวน์ %d วิ ใช้ร่วมกับยา %s" % [int(Balance.num("potion.cooldown")), other], "color": DIM_TEXT})
		d.action = "ใช้"
		d.action_ok = true
	else:
		d.main = String(t.get("main", ""))
		if String(s.id).begins_with("gem_"):
			d.lines.append({"text": "ใส่ได้ที่หน้าสกิล (ปุ่ม \"สกิล\")", "color": DIM_TEXT})

func _gear_detail(d: Dictionary, it: Dictionary) -> void:
	var base := String(it.base)
	d.icon = LootDrop.icon_path(base)
	d.name = Gear.item_name(it)
	d.color = Gear.rarity_color(String(it.rarity))
	d.enhance = Enhance.can(it)
	d.sub = "ระดับ %s · %s · ใช้ได้ Lv%d" % [Gear.rarity_name(String(it.rarity)), SLOT_NAMES.get(Gear.slot_of(base), ""), Gear.req_level(base)]
	d.main = _main_text(it)
	for o in it.get("opts", []):
		var line := Gear.describe_option(o)
		if o.k == "element_dmg": line += " (ใช้กับเจมธาตุ)"
		d.lines.append({"text": line, "color": UP})

func _main_text(it: Dictionary) -> String:
	var t := Gear.main_text(Gear.main_stats(it))
	return t if t != "" else "ไม่มีค่าหลัก ใช้ออฟชั่นสุ่ม"

## "เทียบที่ใส่อยู่: ATK +8 ▲" per main stat, green when better, red when worse.
func _compare(d: Dictionary, it: Dictionary) -> void:
	var slot := Gear.slot_of(String(it.base))
	var worn = hero.equipped.get(slot)
	if worn == null:
		d.lines.append({"text": "ช่อง%sยังว่าง" % SLOT_NAMES.get(slot, ""), "color": UP})
		return
	if Gear.base(String(it.base)).get("from_source", false):      # ring/necklace: options only
		var parts: Array = []
		for o in worn.get("opts", []): parts.append(Gear.describe_option(o))
		d.lines.append({"text": "ที่ใส่อยู่: " + (", ".join(parts) if not parts.is_empty() else "ไม่มีออฟชั่น"), "color": DIM_TEXT})
		return
	var a := Gear.main_stats(it)
	var b := Gear.main_stats(worn)
	for k in ["atk", "def", "hp"]:
		if not (a.has(k) or b.has(k)): continue
		var diff := snappedf(float(a.get(k, 0)) - float(b.get(k, 0)), 0.1)
		if diff > 0: d.lines.append({"text": "เทียบที่ใส่อยู่: %s +%s ▲" % [k.to_upper(), Gear._trim(diff)], "color": UP})
		elif diff < 0: d.lines.append({"text": "เทียบที่ใส่อยู่: %s −%s ▼" % [k.to_upper(), Gear._trim(-diff)], "color": DOWN})
		else: d.lines.append({"text": "เทียบที่ใส่อยู่: %s เท่าเดิม" % k.to_upper(), "color": DIM_TEXT})

## Opens the ตีบวก window for the selected bow/armor (worn or in the bag). false when not possible.
func press_enhance() -> bool:
	if not selected_detail().enhance: return false
	var ref := {"worn": String(_sel.worn)} if _sel.has("worn") else {"bag": int(_sel.bag)}
	if enhance_panel == null:
		enhance_panel = EnhancePanel.new()
		enhance_panel.build()
		add_child(enhance_panel)
	enhance_panel.open(hero, ref)
	return true

## Runs the detail button. "" on success, otherwise the reason.
func press_action() -> String:
	var d := selected_detail()
	if not d.action_ok: return d.action if d.action != "" else "ทำไม่ได้"
	var res := ""
	if _sel.has("worn"):
		var slot := String(_sel.worn)
		res = hero.unequip(slot)
		if res == "":
			_sel = {"bag": hero.inventory.slots.size() - 1}
			if not (int(_sel.bag) in visible_cells()): tab = 0     # show where it went
	else:
		var i := int(_sel.bag)
		var s: Dictionary = hero.inventory.slots[i]
		if s.has("item"):
			var slot := Gear.slot_of(String(s.item.base))
			var had_old: bool = hero.equipped.get(slot) != null
			res = hero.equip(i)
			if res == "" and not had_old: _sel = {"worn": slot}
		elif d.action == "ใช้":
			res = "" if hero.try_potion(String(s.id).trim_prefix("potion_")) else "ใช้ตอนนี้ไม่ได้"
	if not _sel_valid(): _select_first()
	_notice = res
	refresh()
	return res

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
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.size = Vector2(4000, 4000)
	dim.position = Vector2(-1000, -1000)
	_root.add_child(dim)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _box(PANEL_BG, Color(GOLD, 0.55), 12, 8))
	_panel.position = Vector2(8, 8)
	_panel.size = Vector2(624, 344)
	_root.add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_panel.add_child(col)

	# header
	var head := HBoxContainer.new()
	col.add_child(head)
	head.add_child(_label("กระเป๋า · สวมใส่", 13, GOLD))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(_icon("res://assets/items/coin_gold.png", 14))
	_gold = _label("0", 11, TEXT)
	head.add_child(_gold)
	var x := Button.new()
	x.text = "×"
	x.custom_minimum_size = Vector2(30, 26)
	x.focus_mode = Control.FOCUS_NONE
	x.pressed.connect(close)
	_close_button = x
	head.add_child(x)

	var body := BoxContainer.new()     # side by side; stacked in portrait (_layout)
	_body = body
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)

	# left: worn slots around the hero + stats
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(150, 0)
	body.add_child(left)
	var worn := HBoxContainer.new()
	worn.add_theme_constant_override("separation", 4)
	left.add_child(worn)
	var lcol := VBoxContainer.new()
	var rcol := VBoxContainer.new()
	for s in ["bow", "armor"]: lcol.add_child(_worn_button(s))
	for s in ["ring", "necklace"]: rcol.add_child(_worn_button(s))
	worn.add_child(lcol)
	var face := TextureRect.new()
	var at := AtlasTexture.new()
	at.atlas = load("res://assets/hero/idle_south.png")
	at.region = Rect2(0, 0, 64, 64)
	face.texture = at
	face.custom_minimum_size = Vector2(62, 72)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	worn.add_child(face)
	worn.add_child(rcol)
	_who = _label("พราน · Lv 1", 11, GOLD)
	left.add_child(_who)
	_stats = GridContainer.new()
	_stats.columns = 2
	_stats.add_theme_constant_override("h_separation", 10)
	left.add_child(_stats)

	# middle: tabs + grid
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 5)
	body.add_child(mid)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	mid.add_child(tabs)
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i]
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", UiKit.fs(9))
		b.custom_minimum_size = Vector2(0, 20)
		b.pressed.connect(set_tab.bind(i))
		tabs.add_child(b)
		_tab_buttons.append(b)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	mid.add_child(grid)
	for i in int(Balance.num("bag.slots")):
		var c := Button.new()
		c.custom_minimum_size = Vector2(CELL, CELL)
		c.focus_mode = Control.FOCUS_NONE
		var ic := TextureRect.new()
		ic.name = "Icon"
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		ic.position = Vector2(4, 4)
		ic.size = Vector2(CELL - 8, CELL - 8)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(ic)
		var q := _label("", 8, Color.WHITE)
		q.name = "Qty"
		q.position = Vector2(CELL - 16, CELL - 14)
		q.size = Vector2(14, 12)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		q.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(q)
		c.pressed.connect(_on_cell.bind(i))
		grid.add_child(c)
		_cells.append(c)
	_used = _label("", 8, DIM_TEXT)
	mid.add_child(_used)

	# right: detail
	var det := PanelContainer.new()
	det.add_theme_stylebox_override("panel", _box(Color(0, 0, 0, 0.25), Color(1, 1, 1, 0.15), 10, 8))
	det.custom_minimum_size = Vector2(196, 0)
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
	_d_frame.custom_minimum_size = Vector2(42, 42)
	top.add_child(_d_frame)
	_d_icon = _icon("", 34)
	_d_frame.add_child(_d_icon)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(names)
	_d_name = _label("", 13, TEXT)
	names.add_child(_d_name)
	_d_sub = _label("", 8, Color("#cfc6b0"))
	names.add_child(_d_sub)
	_d_main = _label("", 11, Color.WHITE)
	dv.add_child(_d_main)
	_d_lines = VBoxContainer.new()
	_d_lines.add_theme_constant_override("separation", 0)
	dv.add_child(_d_lines)
	_d_action = Button.new()
	_d_action.custom_minimum_size = Vector2(0, 32)
	_d_action.focus_mode = Control.FOCUS_NONE
	_d_action.add_theme_font_size_override("font_size", UiKit.fs(12))
	_d_action.pressed.connect(func(): press_action())
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	dv.add_child(btns)
	dv.move_child(btns, 1)          # right under the name row (landscape); _place_buttons moves it in portrait
	_d_btns = btns
	_d_action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btns.add_child(_d_action)
	_d_enhance = Button.new()
	_d_enhance.text = "ตีบวก"
	_d_enhance.custom_minimum_size = Vector2(56, 32)
	_d_enhance.focus_mode = Control.FOCUS_NONE
	_d_enhance.add_theme_font_size_override("font_size", UiKit.fs(12))
	_d_enhance.pressed.connect(func(): press_enhance())
	btns.add_child(_d_enhance)
	enhance_panel = EnhancePanel.new()
	enhance_panel.build()
	enhance_panel.closed.connect(refresh)
	add_child(enhance_panel)

func _worn_button(slot: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(CELL + 4, CELL + 4)
	b.focus_mode = Control.FOCUS_NONE
	var ic := TextureRect.new()
	ic.name = "Icon"
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ic.position = Vector2(4, 4)
	ic.size = Vector2(CELL - 4, CELL - 4)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ic)
	b.add_theme_font_size_override("font_size", UiKit.fs(8))
	b.add_theme_color_override("font_color", Color("#a59c86"))
	b.pressed.connect(func(): if hero and hero.equipped.get(slot) != null: select_worn(slot))
	_worn_buttons[slot] = b
	return b

func _on_cell(cell: int) -> void:
	var v := visible_cells()
	if cell < v.size(): select(v[cell])

func refresh() -> void:
	if hero == null or _root == null: return
	_gold.text = str(hero.inventory.gold)
	_who.text = "พราน · Lv %d" % hero.level
	for c in _stats.get_children(): c.free()
	var st := hero.stats()
	for pair in [["HP", str(st.hp)], ["MP", str(st.mp)], ["ATK", str(int(round(st.atk)))], ["DEF", Gear._trim(float(st.def))],
			["คริ", "%s%%" % Gear._trim(st.crit * 100.0)], ["ยิง", "%s/วิ" % Gear._trim(1.0 / st.shot_cd)]]:
		var row := HBoxContainer.new()
		row.add_child(_label(pair[0], 9, Color("#e8e2d4")))
		row.add_child(_label(pair[1], 9, Color.WHITE))
		_stats.add_child(row)
	for s in _worn_buttons:
		var b: Button = _worn_buttons[s]
		var it = hero.equipped.get(s)
		(b.get_node("Icon") as TextureRect).texture = load(LootDrop.icon_path(String(it.base))) if it != null else null
		b.text = "" if it != null else SLOT_NAMES[s]      # empty slot shows its name
		var on: bool = _sel.get("worn", "") == s
		_style_cell(b, Gear.rarity_color(String(it.rarity)) if it != null else Color("#6b6450"), it != null, on)
	var v := visible_cells()
	for i in _cells.size():
		var c: Button = _cells[i]
		var ic: TextureRect = c.get_node("Icon")
		var q: Label = c.get_node("Qty")
		if i < v.size():
			var s: Dictionary = hero.inventory.slots[v[i]]
			ic.texture = load(LootDrop.icon_path(String(s.id)))
			q.text = str(s.count) if s.count > 1 else ""
			var border := Color("#9aa0a6")
			if s.has("item"): border = Gear.rarity_color(String(s.item.rarity))
			elif s.has("gem"): border = Gear.rarity_color(String(s.gem.rarity))
			_style_cell(c, border, true, _sel.get("bag", -1) == v[i])
		else:
			ic.texture = null
			q.text = ""
			_style_cell(c, Color(1, 1, 1, 0.08), false, false)
	_used.text = "%d/%d ช่อง · แตะของเพื่อดูรายละเอียด" % [hero.inventory.slots.size(), int(Balance.num("bag.slots"))]
	for i in _tab_buttons.size():
		var b: Button = _tab_buttons[i]
		b.add_theme_color_override("font_color", Color("#fde39a") if i == tab else Color("#e8e2d4"))
		b.add_theme_stylebox_override("normal", _box(Color(GOLD, 0.18) if i == tab else Color(0, 0, 0, 0), GOLD if i == tab else Color(1, 1, 1, 0.2), 9, 6))
	var d := selected_detail()
	_d_icon.texture = load(d.icon) if d.icon != "" else null
	_d_frame.add_theme_stylebox_override("panel", _box(Color(0, 0, 0, 0.35), d.color, 8, 4))
	_d_name.text = d.name
	_d_name.add_theme_color_override("font_color", d.color)
	_d_sub.text = d.sub
	_d_main.text = d.main
	for c in _d_lines.get_children(): c.free()
	for l in d.lines: _d_lines.add_child(_label(l.text, 9, l.color))
	_d_enhance.visible = d.enhance
	UiKit.style_action(_d_enhance, true)
	_d_action.visible = d.action != ""
	_d_action.text = d.action
	_d_action.disabled = not d.action_ok
	_d_action.add_theme_color_override("font_color", Color("#1a2a12") if d.action_ok else Color("#a59c86"))
	_d_action.add_theme_stylebox_override("normal", _box(GOLD if d.action_ok else Color(1, 1, 1, 0.06), GOLD if d.action_ok else Color("#6b6450"), 8, 4))
	_d_action.add_theme_stylebox_override("disabled", _box(Color(1, 1, 1, 0.06), Color("#6b6450"), 8, 4))
	_layout.call_deferred()          # the detail changed size: fit the panel to the screen again

func _style_cell(b: Button, border: Color, filled: bool, selected: bool) -> void:
	var sb := _box(Color(0, 0, 0, 0.35 if filled else 0.15), Color("#fde39a") if selected else border, 7, 2)
	sb.set_border_width_all(2)
	for k in ["normal", "hover", "pressed"]: b.add_theme_stylebox_override(k, sb)

## Landscape: the 624x344 three-column panel. Portrait: the columns stack and the panel takes the
## screen width (scaled down only if it would still not fit).
func _layout() -> void:
	if _panel == null or not is_inside_tree(): return
	var size := get_viewport().get_visible_rect().size
	var portrait := ScreenFit.is_portrait(size)
	_place_buttons(portrait)
	if _body.vertical != portrait:
		_body.vertical = portrait
		_panel.size = Vector2.ZERO
	if portrait:
		_panel.size = Vector2(size.x - 12, 0)
		_panel.size = Vector2(size.x - 12, _panel.get_combined_minimum_size().y)
	else:
		_panel.size = Vector2(624, 344)
		_panel.size = Vector2(624, maxf(344.0, _panel.get_combined_minimum_size().y))
	var bottom := bottom_inset(portrait)
	var room := Vector2(size.x - 8, size.y - 8 - bottom)
	var fit := minf(1.0, minf(room.x / _panel.size.x, room.y / _panel.size.y))
	_panel.scale = Vector2(fit, fit)
	var shown := _panel.size * fit
	_panel.position = Vector2(floorf((size.x - shown.x) / 2.0), floorf((size.y - bottom - shown.y) / 2.0))

## Space kept free at the bottom of the screen: Safari's floating bar on iPhone (portrait, not opened
## from the home screen). 0 elsewhere.
static func bottom_inset(portrait: bool) -> float:
	if not portrait or not ScreenFit.is_ios_web() or ScreenFit.is_standalone_web(): return 0.0
	return IOS_BOTTOM_INSET

## Portrait: the action buttons sit at the right of the icon + name row. Landscape (narrow detail
## column): right under that row.
func _place_buttons(portrait: bool) -> void:
	if _d_btns == null: return
	var want: Node = _d_top if portrait else _d_box
	if _d_btns.get_parent() != want:
		_d_btns.get_parent().remove_child(_d_btns)
		want.add_child(_d_btns)
		if want == _d_box: _d_box.move_child(_d_btns, 1)
	_d_action.custom_minimum_size = Vector2(72, 32) if portrait else Vector2(0, 32)
	_d_btns.size_flags_horizontal = Control.SIZE_SHRINK_END if portrait else Control.SIZE_EXPAND_FILL

func _label(t: String, font_size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", UiKit.fs(font_size))
	l.add_theme_color_override("font_color", c)
	return l

func _icon(path: String, px: int) -> TextureRect:
	var t := TextureRect.new()
	if path != "": t.texture = load(path)
	t.custom_minimum_size = Vector2(px, px)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return t

func _box(bg: Color, border: Color, radius: int, margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1 if border.a > 0 else 0)
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin; s.content_margin_right = margin
	s.content_margin_top = margin * 0.6; s.content_margin_bottom = margin * 0.6
	return s
