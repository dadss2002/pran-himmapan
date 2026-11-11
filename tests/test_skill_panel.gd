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

## M5b Task 8a: the area skills exist now, so an expand gem at Lv1 fits skills that are still locked: dimmed, and
## each of them is named with its unlock level (was: "ยังไม่มีสกิลที่ใส่ได้ (ใช้กับห่าศรในรอบถัดไป)").
func test_unusable_gem_dimmed_and_explained():
	var h := _hero()
	h.inventory.add_gem(_g("expand"))
	var p := _panel(h)
	p.select_gem(0)
	var r := ""
	if p.cell_usable(0): r = "expand should be dimmed"
	elif _find(p.gem_detail().lines, "ห่าศร: ปลดที่ Lv7").is_empty(): r = "no explanation %s" % [p.gem_detail().lines]
	elif _find(p.gem_detail().lines, "กับดักหนาม: ปลดที่ Lv10").is_empty() or _find(p.gem_detail().lines, "ศรเพลิง: ปลดที่ Lv10").is_empty(): r = "Lv10 skills not named %s" % [p.gem_detail().lines]
	elif not _find(p.gem_detail().lines, "ศรทะลวง").is_empty(): r = "expand does not fit ศรทะลวง: %s" % [p.gem_detail().lines]
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

## Owner 2026-11-08 (same fix as the bag, "กดสวมใส่ไม่ได้"): after selecting a gem the panel refits by itself
## (refresh() defers _layout; nothing calls it by hand here), the action button stays on screen, sits beside
## the gem's name in portrait (touch-sized) and right under the name row in landscape, for a tall phone and
## an iPhone-SE-like window. On iPhone web (Safari, not from the home screen) portrait keeps the bottom
## ScreenFit.IOS_BOTTOM_INSET px free; opened from the home screen it does not need to.
func test_action_button_on_screen_after_select():
	var w := tree.root
	var size0 := w.size
	var scale0 := w.content_scale_size
	var h := _hero(10)
	h.inventory.add_gem({"type": "split", "level": 1, "exp": 0, "rarity": "good", "opts": [{"k": "mp_cut", "v": 0.05}, {"k": "crit", "v": 0.03}]})
	h.inventory.add_gem({"type": "split", "level": 2, "exp": 0, "rarity": "good", "opts": [{"k": "crit", "v": 0.03}, {"k": "mp_cut", "v": 0.05}]})
	h.socket("piercing", 0, 0)
	var p := SkillPanel.new()
	p.build()
	w.add_child(p)
	await tree.process_frame
	var fails := []
	for o in [Vector2i(780, 1688), Vector2i(1688, 780), Vector2i(750, 1334), Vector2i(1334, 750)]:
		DisplayServer.window_set_size(o)
		w.size = o
		w.content_scale_size = ScreenFit.base_for(o)
		for i in 3: await tree.process_frame
		for mode in ["plain", "iphone", "home"]:
			ScreenFit.ios_override = 0 if mode == "plain" else 1
			ScreenFit.standalone_override = 1 if mode == "home" else 0
			for pick in ["socket", "bag"]:
				p._sel = {}
				p.open(h)
				if pick == "socket": p.press_slot("piercing", 0)
				else: p.select_gem(p.gem_cells()[0])
				for i in 3: await tree.process_frame
				var view := Rect2(Vector2.ZERO, w.get_visible_rect().size)
				var portrait: bool = o.y > o.x
				var tag := "%s %s %s %s" % ["portrait" if portrait else "landscape", o, mode, pick]
				var d := p.gem_detail()
				if d.name == "": fails.append("%s: no gem selected" % tag)
				if pick == "socket" and not d.action_ok: fails.append("%s: ถอดเจม not offered" % tag)
				var a := p._d_action.get_global_rect()
				var panel := p._panel.get_global_rect()
				if not p._d_action.visible: fails.append("%s: action hidden" % tag)
				if not view.encloses(a): fails.append("%s: action %s off screen %s" % [tag, a, view])
				if not view.grow(0.5).encloses(panel): fails.append("%s: panel %s off screen %s" % [tag, panel, view])
				var name_row := p._d_name.get_global_rect()
				if portrait and absf(a.get_center().y - name_row.get_center().y) > 24.0: fails.append("%s: action %s not beside the name %s" % [tag, a, name_row])
				if a.position.y > name_row.end.y + 60.0: fails.append("%s: action %s far below the name %s" % [tag, a, name_row])
				if portrait and p._d_action.size.y * p._panel.scale.y < IconButton.MIN_TOUCH - 0.01:
					fails.append("%s: action only %.1f px tall (touch minimum %d)" % [tag, p._d_action.size.y * p._panel.scale.y, IconButton.MIN_TOUCH])
				var keep := ScreenFit.IOS_BOTTOM_INSET if mode == "iphone" and portrait else 0.0
				if panel.end.y > view.size.y - keep + 0.5: fails.append("%s: panel bottom %.1f over Safari bar (free to %.1f)" % [tag, panel.end.y, view.size.y - keep])
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

func _labels(n: Node, out: Array) -> Array:
	if n is Label: out.append(n.text)
	for c in n.get_children(): _labels(c, out)
	return out

## M5b Task 1 (owner 2026-11-08): the slot help reads the new rule from balance.json gem_slots; opening the screen
## moves a gem left in a closed slot to the bag (owner 2026-11-09), and each open skill shows 2 slots at Lv3.
func test_slot_help_and_closed_gems_on_open():
	var h := _hero(3)
	h.set_skill_gems({"piercing": [_g("split"), _g("multiply"), _g("execute")]})
	var p := _panel(h)
	var r := ""
	var texts := _labels(p, [])
	var want := SkillPanel.SLOT_HELP % [10, 50]
	if not texts.has(want): r = "slot help missing; want '%s'" % want
	elif h.skill_gems.piercing.size() > 2 and h.skill_gems.piercing[2] != null: r = "opening the screen did not return the slot-3 gem"
	elif h.inventory.slots.size() != 1 or h.inventory.slots[0].get("gem", {}).get("type", "") != "execute": r = "bag %s" % [h.inventory.slots]
	else:
		for id in ["piercing", "spread"]:
			var n: int = p._rows[id].slots.get_child_count()
			if n != 2: r = "%s shows %d slots, want 2" % [id, n]
	p.free()
	h.free()
	return r
