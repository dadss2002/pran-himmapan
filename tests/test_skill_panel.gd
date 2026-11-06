extends RefCounted
## Skill · gem screen (approved sketch "หน้าสกิล · เจม").

var tree: SceneTree
func setup(t: SceneTree) -> void:
	tree = t

func _hero(level := 1) -> Hero:
	var h: Hero = load("res://scenes/hero.tscn").instantiate()
	h.setup_sprites()
	if level > 1: h.set_progress(level, 0)
	h.inventory.slots.clear()
	return h

func _g(type: String) -> Dictionary:
	return {"type": type, "level": 1, "exp": 0, "rarity": "good", "opts": [{"k": "mp_cut", "v": 0.05}]}

func _panel(h: Hero) -> SkillPanel:
	var p := SkillPanel.new()
	p.build()
	p.open(h)
	return p

func _find(lines: Array, part: String) -> Dictionary:
	for l in lines:
		if String(l.text).contains(part): return l
	return {}

func test_open_pauses():
	var h := _hero()
	var p := SkillPanel.new()
	p.build()
	tree.root.add_child(p)
	await tree.process_frame
	p.open(h)
	var r := "" if tree.paused and p.visible else "open did not pause"
	p.close()
	if r == "" and (tree.paused or p.visible): r = "close did not resume"
	tree.paused = false
	p.queue_free()
	h.free()
	return r

func test_preview_lines():
	var h := _hero(3)
	h.inventory.add_gem({"type": "split", "level": 1, "exp": 0, "rarity": "common", "opts": [{"k": "crit", "v": 0.03}]})
	var p := _panel(h)
	p.select_gem(0)
	var d := p.gem_detail()
	var r := ""
	if d.name != "เจมแยกศร Lv1": r = "name %s" % d.name
	elif _find(d.lines, "ศรทะลวง: MP 8 → 11.2").is_empty(): r = "piercing preview missing %s" % [d.lines]
	elif _find(d.lines, "ศรกระจาย: MP 12 → 16.8").is_empty(): r = "spread preview missing %s" % [d.lines]
	elif _find(d.lines, "คริสกิลนี้ +3%").is_empty(): r = "option line missing"
	p.free(); h.free()
	return r

func test_unusable_gem_dimmed_and_explained():
	var h := _hero()
	h.inventory.add_gem(_g("expand"))
	var p := _panel(h)
	p.select_gem(0)
	var r := ""
	if p.cell_usable(0): r = "expand should be dimmed"
	elif _find(p.gem_detail().lines, "ยังไม่มีสกิลที่ใส่ได้").is_empty(): r = "no explanation %s" % [p.gem_detail().lines]
	p.free(); h.free()
	return r

func test_press_slot_sockets_and_swaps():
	var h := _hero()
	h.inventory.add_gem(_g("split"))
	h.inventory.add_gem(_g("multiply"))
	var p := _panel(h)
	p.select_gem(0)
	var r := ""
	if p.press_slot("piercing", 0) != "" or h.skill_gems.piercing[0].type != "split": r = "socket failed"
	p.select_gem(0)                          # multiply is now bag slot 0
	if r == "" and (p.press_slot("piercing", 0) != "" or h.skill_gems.piercing[0].type != "multiply"): r = "swap failed"
	p.press_slot("piercing", 0)              # no gem selected: selects the socketed gem
	if r == "" and p.gem_detail().action != "ถอดเจม": r = "socketed gem should offer ถอดเจม, got %s" % p.gem_detail().action
	if r == "" and (p.press_action() != "" or h.skill_gems.piercing[0] != null): r = "ถอดเจม failed"
	p.free(); h.free()
	return r

func test_full_bag_refusal_shown():
	var h := _hero()
	h.inventory.add_gem(_g("split"))
	h.socket("piercing", 0, 0)
	for i in 24: h.inventory.add("junk_%d" % i, 1)
	var p := _panel(h)
	p.press_slot("piercing", 0)
	p.press_action()
	var l := _find(p.gem_detail().lines, "กระเป๋าเต็ม")
	var r := "" if not l.is_empty() and Color(l.color).is_equal_approx(SkillPanel.DOWN) else "refusal not shown red: %s" % [p.gem_detail().lines]
	p.free(); h.free()
	return r
