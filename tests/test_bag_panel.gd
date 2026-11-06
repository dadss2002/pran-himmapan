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

