extends SceneTree
## Real-finger check for the bag (needs a window: touch→mouse emulation does not run headless).
## xvfb-run -a godot --path . --rendering-driver opengl3 --script tests/touch_check.gd
## Sends InputEventScreenTouch in window coordinates, like a phone does. Exit 0 = pass.

var hud: Hud
var h: Hero

func _initialize() -> void:
	_run()

func _tap(at_view: Vector2) -> void:
	var at := root.get_final_transform() * at_view
	for pressed in [true, false]:
		var e := InputEventScreenTouch.new()
		e.index = 0
		e.position = at
		e.pressed = pressed
		Input.parse_input_event(e)
		await process_frame
		await process_frame

func _fail(msg: String) -> void:
	print("TOUCH FAIL: ", msg)
	quit(1)

func _run() -> void:
	if not Input.is_emulating_mouse_from_touch(): return _fail("project.godot: pointing/emulate_mouse_from_touch must be true")
	h = load("res://scenes/hero.tscn").instantiate()
	h.setup_sprites()
	h.set_progress(5, 0)
	h.inventory.add_item({"base": "bow_buffalo_horn", "rarity": "good", "level": 5, "opts": []})
	hud = Hud.new()
	root.add_child(hud)
	await process_frame
	hud.bind(h)
	await process_frame
	await _tap(hud.bag_button.get_global_rect().get_center())
	if not hud.bag_panel.is_open(): return _fail("tapping กระเป๋า did not open the bag")
	var bag := hud.bag_panel
	await _tap(bag._tab_buttons[1].get_global_rect().get_center())
	if bag.tab != 1: return _fail("tapping the อุปกรณ์ tab did nothing")
	var idx := h.inventory.slots.size() - 1
	await _tap(bag._cells[bag.visible_cells().find(idx)].get_global_rect().get_center())
	if bag.selected_detail().name != "ธนูเขาควาย": return _fail("tapping a bag cell did not select it")
	await _tap(bag._d_action.get_global_rect().get_center())
	if h.equipped.bow.base != "bow_buffalo_horn": return _fail("tapping สวมใส่ did not equip")
	await _tap(bag._close_button.get_global_rect().get_center())
	if bag.is_open() or paused: return _fail("tapping ✕ did not close the bag / unpause")
	print("TOUCH PASS: open, tab, select, equip, close")
	quit(0)
