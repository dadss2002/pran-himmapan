extends RefCounted
## M3h elite monsters (docs/superpowers/specs/2026-11-07-m3h-elite-monsters-design.md).

var tree: SceneTree

func setup(t: SceneTree) -> void:
	tree = t

func _world() -> Node2D:
	await tree.process_frame
	var w := Node2D.new()
	tree.root.add_child(w)
	return w

func _pack(world: Node2D, kind: String, lv := 3, count := 1) -> WolfPack:
	var p := WolfPack.new()
	p.kind = kind
	p.level = lv
	p.count = count
	p.home = Vector2(300, 300)
	world.add_child(p)
	p.set_physics_process(false)
	return p

func test_elite_stats_x_spec():
	var world: Node2D = await _world()
	var p := _pack(world, "boar", 3)
	await tree.physics_frame
	var m: Monster = p.wolves[0]
	var base := m.stats().duplicate()
	m.set_elite(true)
	var e := m.stats()
	var r := ""
	if e.hp != int(round(base.hp * 4)): r = "hp %d (want %d x4)" % [e.hp, base.hp]
	elif e.atk != int(round(base.atk * 1.5)): r = "atk %d (want %d x1.5)" % [e.atk, base.atk]
	elif e.exp != int(round(base.exp * 5)): r = "exp %d (want %d x5)" % [e.exp, base.exp]
	elif e.def != base.def: r = "def changed"
	elif m.health.max_hp != e.hp: r = "health %d not reset to elite hp %d" % [m.health.max_hp, e.hp]
	world.queue_free()
	return r

func test_elite_chance_about_10pct():
	Wolf.elites_enabled = true
	var world: Node2D = await _world()
	var p := _pack(world, "wolf", 1, 1)
	await tree.physics_frame
	var w: Wolf = p.wolves[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var n := 4000
	var hits := 0
	for i in n:
		w.roll_elite(rng)
		if w.elite: hits += 1
	Wolf.elites_enabled = false
	w.set_elite(false)
	world.queue_free()
	var rate := float(hits) / n
	return "" if absf(rate - 0.1) < 0.015 else "elite rate %.3f (want ~0.10)" % rate

func test_elite_not_knocked_back_and_tagged():
	var world: Node2D = await _world()
	var p := _pack(world, "wolf", 1, 2)
	await tree.physics_frame
	var a: Wolf = p.wolves[0]
	var b: Wolf = p.wolves[1]
	a.set_elite(true)
	a.global_position = Vector2(300, 300)
	b.global_position = Vector2(400, 300)
	a.receive_hit(1, 1.0, Vector2(290, 300))
	b.receive_hit(1, 1.0, Vector2(390, 300))
	var r := ""
	if a.global_position != Vector2(300, 300): r = "elite knocked to %s" % a.global_position
	elif b.global_position == Vector2(400, 300): r = "normal wolf not knocked back"
	elif a._tag == null or not a._tag.visible: r = "elite has no ★ tag"
	elif b._tag != null and b._tag.visible: r = "a normal wolf shows the elite tag"
	world.queue_free()
	return r

func test_elite_loot_x3_and_rarity_up():
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var n := 6000
	var ore := 0
	var gear := 0
	var common := 0
	for i in n:
		for it in Loot.roll("wolf", 3, rng, true):
			if it.id == "ore_himmapan": ore += 1
			if it.has("item"):
				gear += 1
				if it.item.rarity == "common": common += 1
	var want_ore := Balance.num("loot.wolf.ore") * 0.5 * 3.0
	var want_gear := Balance.num("loot.wolf.gear") * 0.5 * 3.0
	if absf(float(ore) / n - want_ore) > 0.03: return "elite ore rate %.3f (want ~%.3f)" % [float(ore) / n, want_ore]
	if absf(float(gear) / n - want_gear) > 0.015: return "elite gear rate %.3f (want ~%.3f)" % [float(gear) / n, want_gear]
	if common > 0: return "%d elite gear drops were common (rarity should go up a tier)" % common
	if Gear.rarity_up("legend", 1) != "legend": return "legend went past the top tier"
	return "" if Gear.rarity_up("common", 1) == "good" else "common +1 = %s" % Gear.rarity_up("common", 1)
