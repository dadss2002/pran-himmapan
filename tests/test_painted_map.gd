extends RefCounted
## The painted forest (PaintedLayout + PaintedMap) in the real test ground: data, colliders,
## leaf overlays, drops, packs, and wolves that cannot reach the hero.

const TMP_SAVE := "user://test_painted_save.json"
var tree: SceneTree

func setup(t: SceneTree) -> void:
	tree = t

func _ground(in_tree := false) -> Node2D:
	if FileAccess.file_exists(TMP_SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))
	var g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = TMP_SAVE
	if in_tree: tree.root.add_child(g)
	else: g.build()
	return g

func _done(g: Node2D) -> void:
	if g.is_inside_tree():
		g.queue_free()
		await tree.process_frame
	else:
		g.free()

func _small(rows: Array) -> PaintedLayout:
	return PaintedLayout.from_dict({"size": [rows[0].length() * 8, rows.size() * 8], "cell": 8, "blocked": rows,
		"hero_spawn": [12, 12], "pack_homes": []})

func test_blocked_rules():
	var l := _small(["#####", "#...#", "#.#.#", "#####"])
	var r := ""
	if not l.blocked_at(Vector2(2, 2)): r = "border cell should block"
	elif l.blocked_at(Vector2(12, 12)): r = "open cell blocked"
	elif not l.blocked_at(Vector2(20, 20)): r = "inner wall open"
	elif not l.blocked_at(Vector2(-1, 10)): r = "left of map open"
	elif not l.blocked_at(Vector2(10, 32)): r = "below map open"
	return r

func test_reachable_needs_room_for_the_body():
	# two rooms joined by a one-row slot (too low for a hero-sized body), then by a two-row opening
	var narrow := _small(["##########", "#...#....#", "#...#....#", "#........#", "##########"])
	var wide := _small(["##########", "#...#....#", "#........#", "#........#", "##########"])
	var walled := _small(["##########", "#...#....#", "#...#....#", "#...#....#", "##########"])
	var a := Vector2(20, 28)
	var b := Vector2(60, 28)
	if narrow.reachable(a, b): return "squeezed through a one-row slot"
	if not wide.reachable(a, b): return "two-row opening not passable"
	if walled.reachable(a, b): return "walked through a wall"
	return ""

func test_layout_valid():
	var l := PaintedLayout.open()
	if l == null: return "data/map_painted.json missing"
	if l.size_px() != Vector2(2064, 1536): return "map size %s" % l.size_px()
	if l.chunks.size() != 12: return "%d chunks" % l.chunks.size()
	var errs := l.validate()
	return "" if errs.is_empty() else "%d problems, first: %s" % [errs.size(), errs.slice(0, 3)]

func test_builds_chunks_overlays_and_ripples():
	var g := _ground()
	var m: PaintedMap = g.forest
	var r := ""
	if m.chunk_sprites.size() != 12: r = "%d chunk sprites" % m.chunk_sprites.size()
	elif m.overlay_sprites.is_empty(): r = "no leaf overlays"
	elif m.overlay_sprites[0].z_index <= 0: r = "leaf overlay not above characters"
	elif m.fx_nodes.size() != g.layout.fx.size(): r = "%d ripples for %d points" % [m.fx_nodes.size(), g.layout.fx.size()]
	elif m.box_count > 4000: r = "%d collider boxes, too many" % m.box_count
	await _done(g)
	return r

func test_colliders_match_blocked_at():
	var g := _ground(true)
	await tree.physics_frame
	await tree.physics_frame
	var space: PhysicsDirectSpaceState2D = g.get_world_2d().direct_space_state
	var q := PhysicsPointQueryParameters2D.new()
	q.collision_mask = 1
	var r := ""
	var y := 3.5
	while y < 1536.0 and r == "":
		var x := 3.5
		while x < 2064.0:
			q.position = Vector2(x, y)
			var solid := false
			for hit in space.intersect_point(q, 4):
				if hit.collider is StaticBody2D: solid = true
			if solid != g.layout.blocked_at(q.position):
				r = "at %s physics %s, blocked_at %s" % [q.position, solid, not solid]
				break
			x += 8.0
		y += 8.0
	await _done(g)
	return r

func test_hero_stays_on_open_ground():
	# walk and roll hard into the forest edge from the spawn: the feet never end on a blocked cell
	var g := _ground(true)
	await tree.physics_frame
	var h: Hero = g.hero
	h.set_physics_process(false)
	var r := ""
	for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		h.global_position = g.layout.hero_spawn
		await tree.physics_frame
		for k in 3:
			h._dodge_cd = 0.0
			h.try_dodge(dir)
			for i in 60:
				h.step(1.0 / 60.0, dir)
				await tree.physics_frame
		if g.layout.blocked_at(h.global_position): r = "hero ended on a blocked spot %s going %s" % [h.global_position, dir]
		if r != "": break
	await _done(g)
	return r

func test_drops_avoid_blocked():
	var g := _ground()
	var rng := RandomNumberGenerator.new()
	var r := ""
	for s in 100:
		rng.seed = s
		for center in [g.layout.hero_spawn] + g.layout.pack_homes:
			for p in LootDrop.scatter(center, 6, rng, g._blocked):
				if p != center and g.layout.blocked_at(p): r = "drop at %s is blocked (seed %d)" % [p, s]
		if r != "": break
	await _done(g)
	return r

func test_packs_spawn_walkable():
	var g := _ground()
	var r := ""
	for p in g.packs:
		for w in p.wolves:
			if g.layout.blocked_at(w.position): r = "wolf of pack Lv%d spawns blocked at %s" % [p.level, w.position]
	await _done(g)
	return r

func test_wolves_give_up_on_an_unreachable_hero():
	# hero just across the trees from the Lv3 pack's clearing: they cannot get round in time and go home healed
	var g := _ground(true)
	await tree.physics_frame
	var h: Hero = g.hero
	h.set_physics_process(false)
	var pack: WolfPack = g.packs[1]
	var home: Vector2 = pack.home
	# find an open spot 150-220 px from home that cannot be walked to quickly (behind blocked cells)
	var spot := Vector2.ZERO
	for a in 32:
		for dist in [150.0, 190.0, 220.0]:
			var p: Vector2 = home + Vector2(dist, 0).rotated(TAU * a / 32)
			if not g.layout.blocked_at(p) and g.layout.blocked_at(home.lerp(p, 0.5)):
				spot = p
				break
		if spot != Vector2.ZERO: break
	if spot == Vector2.ZERO:
		await _done(g)
		return ""        # no spot behind trees near this pack: nothing to check
	h.global_position = spot
	pack.alert(h)
	for w in pack.wolves: w.health.take_hit(3, false)
	for i in 600: await tree.physics_frame
	var r := ""
	for w in pack.wolves:
		if w.state in ["chase", "bite", "lunge_warn", "lunge"] and w.global_position.distance_to(spot) > 60.0:
			r = "a wolf is still pinned chasing at %s (hero %s)" % [w.global_position, spot]
	await _done(g)
	return r

func test_no_placeholder_label():
	var g := _ground()
	var r := ""
	for n in g.hud.find_children("*", "Label", true, false):
		if n.text.contains("PLACEHOLDER"): r = "placeholder label still shown"
	await _done(g)
	return r
