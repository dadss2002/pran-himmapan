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
