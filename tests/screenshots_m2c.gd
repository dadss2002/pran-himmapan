extends SceneTree
## M2c real-render screenshots: xvfb-run -a godot --path . --rendering-driver opengl3 --script tests/screenshots_m2c.gd -- --touch

const OUT := "res://docs/preview/"
const SAVE := "user://shots_m2c_save.json"
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

func _gear(base: String, rarity: String, opts: Array = []) -> Dictionary:
	return {"base": base, "rarity": rarity, "level": Gear.req_level(base), "opts": opts}

func _run() -> void:
	seed(5)
	Combat.rng.seed = 5
	if FileAccess.file_exists(SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = SAVE
	root.add_child(g)
	await process_frame
	hero = g.hero
	hero.global_position = Vector2(300, 1100)       # quiet corner, away from the packs
	hero.facing = 2
	await _frames(10)

	# gear on the ground: common (no beam), rare / epic / legend beams in their colours
	var drops := [_gear("armor_trainee", "common"), _gear("bow_buffalo_horn", "rare"),
		_gear("ring", "epic"), _gear("necklace", "legend")]
	for i in drops.size():
		var d := LootDrop.make_item(drops[i])
		d.position = hero.global_position + Vector2(-150 + i * 34, 30)
		d.settle()
		g.world.add_child(d)          # not in g.drops: they stay put for the photo
	await _frames(14)
	await _snap("m2c_gear_drops.png")

	# bag at Lv1: the Lv5 bow is locked
	hero.inventory.add("ore_himmapan", 4)
	hero.inventory.add("gem_split", 1)
	hero.inventory.add_item(_gear("bow_buffalo_horn", "good", [{"k": "atk_speed", "v": 0.06}]))
	hero.inventory.add_item(_gear("armor_wolf_leather", "rare", [{"k": "hp", "v": 18}, {"k": "crit", "v": 0.012}]))
	hero.inventory.add_item({"base": "ring", "rarity": "epic", "level": 3, "opts": [{"k": "crit_dmg", "v": 0.05}, {"k": "mp", "v": 6}, {"k": "gold_pct", "v": 0.03}]})
	g.hud.open_bag()
	var bag: BagPanel = g.hud.bag_panel
	bag.select(4)
	await _snap_idle("m2c_level_lock.png")

	# Lv5: compare, then equip the horn bow
	hero.set_progress(5, 0)
	bag.select(4)
	await _snap_idle("m2c_bag_compare.png")
	print("equip: '", bag.press_action(), "'")
	bag.select(6)
	bag.press_action()                       # ring into the empty ring slot
	await _snap_idle("m2c_bag_equipped.png")
	bag.close()
	await _frames(5)
	hero.try_shoot()
	await _frames(5)
	await _snap("m2c_bow_in_hand.png")
	print("bow: ", hero.equipped.bow.base, " ring: ", hero.equipped.ring.base)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	quit(0)
