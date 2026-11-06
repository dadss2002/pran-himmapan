extends SceneTree
## M3a real-render screenshots: xvfb-run -a godot --path . --rendering-driver opengl3 --script tests/screenshots_m3a.gd -- --touch

const OUT := "res://docs/preview/"
const SAVE := "user://shots_m3a_save.json"
var g: Node2D
var hero: Hero

func _initialize() -> void:
	_run()
	_watchdog()

func _watchdog() -> void:
	await create_timer(100.0).timeout
	print("watchdog: giving up")
	quit(1)

func _snap(name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.resize(img.get_width() * 2, img.get_height() * 2, Image.INTERPOLATE_NEAREST)
	img.save_png(ProjectSettings.globalize_path(OUT + name))
	print("saved ", name)

func _frames(n: int) -> void:
	for i in n: await physics_frame

func _until(cond: Callable, max_frames := 600) -> bool:
	for i in max_frames:
		if cond.call(): return true
		await physics_frame
	return false

func _pack(level: int) -> WolfPack:
	for p in g.packs:
		if p.level == level: return p
	return null

func _snap_idle(name: String) -> void:      # works while the tree is paused (bag open)
	await process_frame
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.resize(img.get_width() * 2, img.get_height() * 2, Image.INTERPOLATE_NEAREST)
	img.save_png(ProjectSettings.globalize_path(OUT + name))
	print("saved ", name)

func _gem(type: String, rarity := "rare", opts: Array = [], extra := {}) -> Dictionary:
	var g := {"type": type, "level": 3, "exp": 410, "rarity": rarity, "opts": opts}
	g.merge(extra, true)
	return g

func _bag_index(type: String) -> int:
	for i in hero.inventory.slots.size():
		if hero.inventory.slots[i].get("gem", {}).get("type", "") == type: return i
	return -1

func _run() -> void:
	seed(11)
	Combat.rng.seed = 11
	if FileAccess.file_exists(SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = SAVE
	root.add_child(g)
	await process_frame
	hero = g.hero
	hero.set_progress(5, 0)
	hero.inventory.add("ore_himmapan", 12)
	hero.inventory.gold = 1240
	hero.inventory.add_gem(_gem("split", "rare", [{"k": "mp_cut", "v": 0.06}, {"k": "crit", "v": 0.03}]))
	hero.inventory.add_gem(_gem("multiply", "good", [{"k": "dmg_pct", "v": 0.05}]))
	hero.inventory.add_gem(_gem("pierce", "common"))
	hero.inventory.add_gem(_gem("element", "epic", [{"k": "cd_cut", "v": 0.05}, {"k": "gem_exp", "v": 0.2}, {"k": "dmg_pct", "v": 0.04}], {"element": "fire"}))
	hero.inventory.add_gem(_gem("expand", "common"))
	await _frames(5)

	# skill screen: multiply socketed in piercing, split selected (previews)
	hero.socket("piercing", 0, _bag_index("multiply"))
	g.hud.open_skills()
	var sp: SkillPanel = g.hud.skill_panel
	sp.select_gem(_bag_index("split"))
	await _snap_idle("m3a_skill_screen.png")
	sp.press_slot("piercing", 0)              # swap: split in, multiply back to the bag
	sp.close()

	# piercing + split: three piercing lines through the Lv1 pack
	var p1 := _pack(1)
	hero.global_position = p1.home + Vector2(170, 0)
	await _until(func():
		for w in p1.wolves:
			if w.state == "chase": return true
		return false, 120)
	await _frames(8)
	hero.mp = hero.max_mp()
	hero.try_skill("piercing")
	await _frames(28)
	await _snap("m3a_split_piercing.png")
	print("piercing arrows: ", hero.build("piercing").arrows)

	# burn / frost / chain on the Lv3 pack
	var p3 := _pack(3)
	hero.global_position = p3.home + Vector2(120, 60)
	await _frames(10)
	var ws: Array = p3.wolves
	var spot := hero.global_position + Vector2(-150, -40)
	for i in 3:
		ws[i].global_position = spot + Vector2(i * 60, (i % 2) * 30)
		ws[i].state = "idle"
	ws[0].apply_status("burn", 3.0)
	ws[1].apply_status("slow")
	await _frames(4)
	var z := FxSprite.make("chain_zap")
	z.position = ws[2].hurt_point()
	g.world.add_child(z)
	z.play("chain_zap")
	await _frames(3)
	await _snap("m3a_status.png")

	# ตีบวก: safe (+2 → +3) and risky (+6 → +7) on the worn bow, bag shows +N
	hero.global_position = Vector2(300, 1100)
	hero.equipped.bow = {"base": "bow_buffalo_horn", "rarity": "good", "level": 5, "opts": [{"k": "atk_speed", "v": 0.06}], "plus": 2}
	hero._on_gear_changed()
	g.hud.open_bag()
	var bag: BagPanel = g.hud.bag_panel
	bag.select_worn("bow")
	await _snap_idle("m3a_bag_plus.png")
	bag.press_enhance()
	await _snap_idle("m3a_enhance_safe.png")
	hero.equipped.bow.plus = 6
	bag.enhance_panel.refresh()
	await _snap_idle("m3a_enhance_risky.png")
	bag.enhance_panel.close()
	bag.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	quit(0)
