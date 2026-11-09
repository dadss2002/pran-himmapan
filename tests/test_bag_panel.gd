extends RefCounted
## Bag screen (approved mockup "กระเป๋า"): pause, tabs, detail + compare, equip/unequip/use.

var tree: SceneTree

func setup(t: SceneTree) -> void:
	tree = t

func _hero(level := 1) -> Hero:
	var h: Hero = load("res://scenes/hero.tscn").instantiate()
	h.setup_sprites()
	if level > 1: h.set_progress(level, 0)
	return h

func _panel(h: Hero) -> BagPanel:
	var p := BagPanel.new()
	p.build()
	p.open(h)
	return p

func _find(lines: Array, part: String) -> Dictionary:
	for l in lines:
		if String(l.text).contains(part): return l
	return {}

func _horn(rarity := "good") -> Dictionary:
	return {"base": "bow_buffalo_horn", "rarity": rarity, "level": 5, "opts": [{"k": "atk_speed", "v": 0.06}]}

func test_open_pauses_and_close_resumes():
	var h := _hero()
	var p := BagPanel.new()
	p.build()
	tree.root.add_child(p)
	await tree.process_frame          # nodes enter the tree once the main loop runs
	p.open(h)
	var r := ""
	if not tree.paused or not p.visible: r = "open: paused %s visible %s" % [tree.paused, p.visible]
	p.close()
	if r == "" and (tree.paused or p.visible): r = "close: paused %s visible %s" % [tree.paused, p.visible]
	tree.paused = false
	p.queue_free()
	h.free()
	return r

func test_select_shows_compare():
	var h := _hero(5)
	h.inventory.add_item(_horn())
	var p := _panel(h)
	p.select(h.inventory.slots.size() - 1)
	var d := p.selected_detail()
	var r := ""
	if d.name != "ธนูเขาควาย" or not Color(d.color).is_equal_approx(Gear.rarity_color("good")): r = "name %s colour %s" % [d.name, d.color]
	elif d.main != "ATK +16": r = "main %s" % d.main
	elif _find(d.lines, "ความเร็วยิง +6%").is_empty(): r = "option line missing %s" % [d.lines]
	elif _find(d.lines, "ATK +8 ▲").is_empty() or not Color(_find(d.lines, "ATK +8 ▲").color).is_equal_approx(BagPanel.UP): r = "compare line %s" % [d.lines]
	elif d.action != "สวมใส่" or not d.action_ok: r = "action %s %s" % [d.action, d.action_ok]
	p.free(); h.free()
	return r

func test_equip_from_panel():
	var h := _hero(5)
	h.inventory.add_item(_horn())
	var i := h.inventory.slots.size() - 1
	var p := _panel(h)
	p.select(i)
	var res := p.press_action()
	var r := ""
	if res != "": r = "refused: %s" % res
	elif h.equipped.bow.base != "bow_buffalo_horn": r = "not worn"
	elif p.selected_detail().name != "ธนูไม้ไผ่": r = "selection should now show the bow that came off, got %s" % p.selected_detail().name
	p.free(); h.free()
	return r

func test_level_lock_shown_red():
	var h := _hero(2)
	h.inventory.add_item(_horn())
	var p := _panel(h)
	p.select(h.inventory.slots.size() - 1)
	var d := p.selected_detail()
	var lock := _find(d.lines, "ต้อง Lv5 · ตอนนี้ Lv2")
	var r := ""
	if lock.is_empty() or not Color(lock.color).is_equal_approx(BagPanel.DOWN): r = "lock line %s" % [d.lines]
	elif d.action_ok or d.action != "ต้อง Lv5": r = "button %s %s" % [d.action, d.action_ok]
	elif p.press_action() == "" or h.equipped.bow.base != "bow_bamboo": r = "equipped above level"
	p.free(); h.free()
	return r

func test_worn_slot_unequip_and_potion_use():
	var h := _hero()
	var p := _panel(h)
	p.select_worn("armor")
	var r := ""
	if p.selected_detail().action != "ถอด": r = "worn armor action %s" % p.selected_detail().action
	elif p.press_action() != "" or h.equipped.armor != null: r = "armor not removed"
	h.health.take_hit(50, false)
	for i in h.inventory.slots.size():
		if h.inventory.slots[i].id == "potion_hp": p.select(i)
	if r == "" and p.selected_detail().action != "ใช้": r = "potion action %s" % p.selected_detail().action
	elif r == "" and (p.press_action() != "" or h.inventory.count_of("potion_hp") != 4): r = "potion not used"
	p.free(); h.free()
	return r

func test_tabs_filter():
	var h := _hero()
	h.inventory.add("ore_himmapan", 2)
	h.inventory.add_item(_horn())
	var p := _panel(h)
	var r := ""
	var want := {0: 4, 1: 1, 2: 2, 3: 1}     # all, gear, potions, materials
	for tab in want:
		p.set_tab(tab)
		if p.visible_cells().size() != want[tab]: r = "tab %d shows %d" % [tab, p.visible_cells().size()]
	p.free(); h.free()
	return r

func test_hud_bag_button_opens_and_releases_touch():
	var h := _hero()
	var hud := Hud.new()
	hud.build()
	hud.bind(h)
	hud.joystick.handle_touch(0, Vector2(120, 250), true)
	hud.joystick.handle_drag(0, Vector2(150, 225))
	hud.bag_button.pressed.emit()
	var r := ""
	if not hud.bag_panel.is_open(): r = "bag did not open"
	elif hud.joystick.vector != Vector2.ZERO or hud.joystick.active: r = "joystick still held"
	hud.free(); h.free()
	return r


func test_refusal_reason_shown():
	var h := _hero()
	for i in 22: h.inventory.add("junk_%d" % i, 1)
	var p := _panel(h)
	p.select_worn("armor")
	p.press_action()
	var d := p.selected_detail()
	var r := ""
	if _find(d.lines, "กระเป๋าเต็ม").is_empty(): r = "full-bag refusal not shown: %s" % [d.lines]
	elif not Color(_find(d.lines, "กระเป๋าเต็ม").color).is_equal_approx(BagPanel.DOWN): r = "refusal not red"
	p.select(0)
	if r == "" and not _find(p.selected_detail().lines, "กระเป๋าเต็ม").is_empty(): r = "old refusal stuck after selecting something else"
	p.free(); h.free()
	return r

func test_selection_follows_tab_and_used_up_potion():
	var h := _hero(5)
	h.inventory.add_item(_horn())
	var p := _panel(h)
	p.select(h.inventory.slots.size() - 1)
	p.set_tab(2)                                   # ยา: the bow is hidden
	var r := ""
	if not (p.selected_detail().name in ["ยาฟื้น HP", "ยาฟื้น MP"]): r = "potion tab still shows %s" % p.selected_detail().name
	h.inventory.remove("potion_hp", 4)             # one left
	h.health.take_hit(50, false)
	for i in h.inventory.slots.size():
		if h.inventory.slots[i].id == "potion_hp": p.select(i)
	p.press_action()                               # last HP potion used: slot disappears
	if r == "" and p.selected_detail().name == "ธนูเขาควาย": r = "selection jumped to a hidden item"
	p.set_tab(1)
	p.select(p.visible_cells()[0])
	p.select_worn("armor")
	p.press_action()                               # armor goes to the bag, tab อุปกรณ์ shows it
	if r == "" and p.selected_detail().name != "ชุดพรานฝึกหัด": r = "after ถอด selection %s" % p.selected_detail().name
	p.free(); h.free()
	return r

func test_ring_compare_lists_worn_options():
	var h := _hero()
	h.set_equipped({"bow": Gear.new_item("bow_bamboo"), "armor": null, "necklace": null,
		"ring": {"base": "ring", "rarity": "good", "level": 2, "opts": [{"k": "crit", "v": 0.01}]}})
	h.inventory.add_item({"base": "ring", "rarity": "good", "level": 2, "opts": [{"k": "hp", "v": 8}]})
	var p := _panel(h)
	p.select(h.inventory.slots.size() - 1)
	var r := "" if not _find(p.selected_detail().lines, "ที่ใส่อยู่: คริ +1%").is_empty() else "no worn-ring line: %s" % [p.selected_detail().lines]
	p.free(); h.free()
	return r

## Owner 2026-11-08 (iPhone, portrait): "กดสวมใส่ไม่ได้" — the panel was sized before the detail was filled,
## so a selected item's lines pushed the action button off the bottom of the screen. The whole panel, and
## the action button, must stay on screen in portrait and landscape after selecting a long item, for a tall
## phone and an iPhone-SE-like window. On iPhone web (Safari, not from the home screen) the portrait panel
## also keeps the bottom IOS_BOTTOM_INSET px free. The panel must refit by itself after open/select (no
## manual _layout() here: refresh() defers one), and portrait buttons are touch-sized (reviewer 2026-11-08).
func test_action_button_on_screen_after_select():
	var w := tree.root
	var size0 := w.size
	var scale0 := w.content_scale_size
	var h := _hero(5)
	h.inventory.add_item(_horn())
	var p := BagPanel.new()
	p.build()
	w.add_child(p)
	await tree.process_frame
	var fails := []
	for o in [Vector2i(780, 1688), Vector2i(1688, 780), Vector2i(750, 1334), Vector2i(1334, 750)]:
		DisplayServer.window_set_size(o)
		w.size = o
		w.content_scale_size = ScreenFit.base_for(o)
		for i in 3: await tree.process_frame
		for iphone in [false, true]:
			ScreenFit.ios_override = 1 if iphone else 0
			ScreenFit.standalone_override = 0
			p.open(h)
			p.select(h.inventory.slots.size() - 1)
			for i in 3: await tree.process_frame
			var view := Rect2(Vector2.ZERO, w.get_visible_rect().size)
			var portrait: bool = o.y > o.x
			var tag := "%s %s%s" % ["portrait" if portrait else "landscape", o, " iPhone" if iphone else ""]
			var a := p._d_action.get_global_rect()
			var panel := p._panel.get_global_rect()
			if not p._d_action.visible: fails.append("%s: action hidden" % tag)
			if not view.encloses(a): fails.append("%s: action %s off screen %s" % [tag, a, view])
			if not view.grow(0.5).encloses(panel): fails.append("%s: panel %s off screen %s" % [tag, panel, view])
			var name_row := p._d_name.get_global_rect()
			if portrait and absf(a.get_center().y - name_row.get_center().y) > 24.0: fails.append("%s: action %s not beside the name %s" % [tag, a, name_row])
			if a.position.y > name_row.end.y + 60.0: fails.append("%s: action %s far below the name %s" % [tag, a, name_row])
			if portrait:
				for b in [p._d_action, p._d_enhance]:
					var hgt: float = b.size.y * p._panel.scale.y       # in HUD px, as shown
					if b.visible and hgt < IconButton.MIN_TOUCH - 0.01: fails.append("%s: %s only %.1f px tall (touch minimum %d)" % [tag, b.text, hgt, IconButton.MIN_TOUCH])
			var free_y := view.size.y - (ScreenFit.IOS_BOTTOM_INSET if iphone and portrait else 0.0)
			if panel.end.y > free_y + 0.5: fails.append("%s: panel bottom %.1f over Safari bar (free to %.1f)" % [tag, panel.end.y, free_y])
			p.close()
	ScreenFit.ios_override = -1
	ScreenFit.standalone_override = -1
	tree.paused = false
	DisplayServer.window_set_size(size0)
	w.size = size0
	w.content_scale_size = scale0
	p.queue_free()
	h.free()
	await tree.process_frame
	return "; ".join(fails)
