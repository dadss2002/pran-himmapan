extends RefCounted
## Loot on the ground: magnet, lifetime, full bag, scatter.

const DT := 1.0 / 60.0

func _hero(pos: Vector2) -> Hero:
	var h: Hero = load("res://scenes/hero.tscn").instantiate()
	h.setup_sprites()
	h.position = pos
	return h

func _drop(id: String, count: int, pos: Vector2) -> LootDrop:
	var d := LootDrop.make(id, count)
	d.position = pos
	d.settle()          # skip the pop-out arc
	return d

func test_magnet_radius_and_speed():
	var h := _hero(Vector2.ZERO)
	var inv := Inventory.new()
	var far := _drop("ore_himmapan", 1, Vector2(70, 0))
	far.step(0.1, h, inv)
	var r := ""
	if far.position != Vector2(70, 0): r = "drop at 70 px moved to %s" % far.position
	var near := _drop("ore_himmapan", 1, Vector2(60, 0))
	near.step(0.1, h, inv)
	if r == "" and absf(near.position.x - 34.0) > 0.5: r = "magnet speed: at %.1f, want 34 (260 px/s for 0.1 s)" % near.position.x
	var got := false
	for i in 30:
		if near.step(DT, h, inv): got = true; break
	if r == "" and not got: r = "never collected"
	if r == "" and inv.count_of("ore_himmapan") != 1: r = "ore not in the bag"
	far.free(); near.free(); h.free()
	return r

func test_lifetime_60s():
	var h := _hero(Vector2(1000, 0))
	var inv := Inventory.new()
	var d := _drop("gold", 5, Vector2.ZERO)
	d.step(59.9, h, inv)
	var r := "" if not d.expired else "expired before 60 s"
	d.step(0.2, h, inv)
	if r == "" and not d.expired: r = "should expire after 60 s"
	d.free(); h.free()
	return r

func test_bag_full_gold_still_collected():
	var h := _hero(Vector2.ZERO)
	var inv := Inventory.new()
	for i in 24: inv.add("gem_split", 99)
	var gold := _drop("gold", 9, Vector2(5, 0))
	var ore := _drop("ore_himmapan", 1, Vector2(40, 0))
	var g_ok := false
	for i in 30:
		if gold.step(DT, h, inv): g_ok = true
		ore.step(DT, h, inv)
	var r := ""
	if not g_ok or inv.gold != 9: r = "gold not collected with a full bag"
	elif ore.position != Vector2(40, 0): r = "ore should stay put when the bag is full, at %s" % ore.position
	elif not ore.bag_full_notice: r = "ore should raise the bag-full notice"
	gold.free(); ore.free(); h.free()
	return r

func test_drop_scatter_not_inside_walls():
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var blocked := func(p: Vector2) -> bool: return p.x > 100.0
	var pts := LootDrop.scatter(Vector2(100, 100), 6, rng, blocked)
	if pts.size() != 6: return "want 6 points, got %d" % pts.size()
	for p in pts:
		if p.distance_to(Vector2(100, 100)) > 24.01: return "point %s farther than 24 px" % p
		if blocked.call(p): return "point %s inside a blocked area" % p
	return ""

func test_icon_for_items():
	var r := ""
	for id in ["gold", "ore_himmapan", "gem_split", "gem_multiply", "gem_leech"]:
		if LootDrop.icon_path(id) == "" or not ResourceLoader.exists(LootDrop.icon_path(id)): r = "no icon for %s" % id
	return r

func test_bag_full_notice_clears_when_away():
	var h := _hero(Vector2.ZERO)
	var inv := Inventory.new()
	for i in 24: inv.add("item_%d" % i, 1)
	var d := _drop("ore_himmapan", 1, Vector2(30, 0))
	d.step(DT, h, inv)
	var r := "" if d.bag_full_notice else "no bag-full notice next to the hero"
	h.position = Vector2(1000, 0)
	d.step(DT, h, inv)
	if r == "" and d.bag_full_notice: r = "bag-full notice still on with the hero 1000 px away"
	d.free(); h.free()
	return r

func test_gems_glint_ore_does_not():
	var gem := LootDrop.make("gem_split", 1)
	var ore := LootDrop.make("ore_himmapan", 1)
	var r := ""
	if gem.glint == null or gem.glint.animation != "item_glint": r = "gem drop has no item_glint"
	elif ore.glint != null: r = "ore should not glint"
	gem.free(); ore.free()
	return r

func _gear(base: String, rarity: String) -> Dictionary:
	return {"base": base, "rarity": rarity, "level": Gear.req_level(base), "opts": []}

func test_beam_only_rare_and_up():
	var r := ""
	for rar in ["common", "good", "rare", "epic", "legend"]:
		var d := LootDrop.make_item(_gear("ring", rar))
		var want: bool = rar in ["rare", "epic", "legend"]
		if (d.beam != null) != want: r = "%s beam %s" % [rar, d.beam != null]
		elif want and not Color(d.beam.modulate, 1.0).is_equal_approx(Gear.rarity_color(rar)): r = "%s beam colour %s" % [rar, d.beam.modulate]
		d.free()
		if r != "": break
	return r

func test_gear_pickup_needs_free_slot():
	var h := _hero(Vector2.ZERO)
	var inv := Inventory.new()
	for i in 24: inv.add("junk_%d" % i, 1)
	var d := LootDrop.make_item(_gear("bow_buffalo_horn", "rare"))
	d.position = Vector2(20, 0)
	d.settle()
	var got := false
	for i in 60: got = d.step(DT, h, inv) or got
	var r := ""
	if got or d.expired: r = "picked up into a full bag"
	elif not d.bag_full_notice: r = "no bag-full notice"
	inv.slots.pop_back()
	for i in 60: got = d.step(DT, h, inv) or got
	if r == "" and not got: r = "not picked up after a slot freed"
	elif r == "" and inv.slots.back().get("item", {}).get("rarity", "") != "rare": r = "bag %s" % [inv.slots.back()]
	if is_instance_valid(d) and not d.is_queued_for_deletion(): d.free()
	h.free()
	return r

func test_icon_for_gear():
	var r := ""
	for base in Balance.data()["gear"]:
		var p := LootDrop.icon_path(base)
		if not ResourceLoader.exists(p): r = "%s icon missing: %s" % [base, p]
	return r
