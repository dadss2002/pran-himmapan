extends RefCounted
## ForestMap inside the real test ground: ground tiles, props, Y-sort, colliders, drops, packs.

const TMP_SAVE := "user://test_forest_save.json"
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

func _prop(g: Node2D, id_prefix: String, at: Vector2) -> Node2D:
	for n in g.forest.props:
		if String(n.get_meta("prop_id", "")).begins_with(id_prefix) and n.position == at: return n
	return null

func test_builds_ground_and_props():
	var g := _ground()
	var f: ForestMap = g.forest
	var l: ForestLayout = g.layout
	var r := ""
	var water: Dictionary = l.tiles["water"]
	var want := Vector2i(int(water.masks["15"]), int(water.row))
	if f.ground.get_cell_atlas_coords(Vector2i(12, 30)) != want: r = "pond centre tile %s, want %s" % [f.ground.get_cell_atlas_coords(Vector2i(12, 30)), want]
	elif f.ground.get_used_cells().size() != l.cols * l.rows: r = "%d ground cells" % f.ground.get_used_cells().size()
	elif f.props.size() + f.flats.size() != l.props.size(): r = "%d + %d prop nodes for %d props" % [f.props.size(), f.flats.size(), l.props.size()]
	elif f.flats.is_empty() or f.flats[0].get_parent() == g.world: r = "flat props should sit under the ground, not in world"
	await _done(g)
	return r

func test_tree_y_sort():
	var g := _ground()
	var t := _prop(g, "tree", Vector2(700, 690))
	var r := ""
	if t == null: r = "tree at 700,690 missing"
	elif t.get_parent() != g.world or not g.world.y_sort_enabled: r = "tree not in the y-sorted world"
	elif g.hero.get_parent() != g.world: r = "hero not in the same y-sorted world"
	else:
		var s: Sprite2D = t.get_child(0)
		# the canopy is drawn above the origin and the trunk base sits on it (a few px of roots below)
		if s.offset.y > -100 or s.offset.y + s.texture.get_height() > 16: r = "sprite offset %s does not put the feet on the origin" % s.offset
	await _done(g)
	return r

func test_hero_blocked_by_tree_feet():
	var g := _ground(true)
	await tree.physics_frame
	var at := Vector2(700, 690)
	var h: Hero = g.hero
	h.set_physics_process(false)
	h.global_position = at + Vector2(0, 24)
	await tree.physics_frame
	for i in 60:
		h.step(1.0 / 60.0, Vector2.UP)
		await tree.physics_frame
	var y := h.global_position.y
	await _done(g)
	if y < at.y: return "hero walked through the trunk (y %.1f, feet at %.0f)" % [y, at.y]
	return "" if y < at.y + 20 else "hero never reached the trunk (y %.1f)" % y

func test_border_and_water_stop_roll():
	var g := _ground(true)
	await tree.physics_frame
	var h: Hero = g.hero
	var l: ForestLayout = g.layout
	h.set_physics_process(false)
	var r := ""
	for start_dir in [[Vector2(70, 640), Vector2.LEFT], [Vector2(384, 770), Vector2.DOWN], [Vector2(960, 900), Vector2.DOWN]]:
		h.global_position = start_dir[0]
		await tree.physics_frame
		for k in 4:
			h._dodge_cd = 0.0
			h.try_dodge(start_dir[1])
			for i in 40:
				h.step(1.0 / 60.0, start_dir[1])
				await tree.physics_frame
		var p := h.global_position
		var bridge := l.in_walk(p)
		if p.x < 0 or p.y < 0 or p.x > l.size_px().x or p.y > l.size_px().y: r = "left the map at %s" % p
		elif l.blocked_at(p) and not bridge: r = "ended on a blocked spot %s (from %s)" % [p, start_dir[0]]
		if r != "": break
	await _done(g)
	return r

func test_bridge_crosses_stream():
	var g := _ground(true)
	await tree.physics_frame
	var h: Hero = g.hero
	h.set_physics_process(false)
	h.global_position = Vector2(960, 900)
	await tree.physics_frame
	for i in 150:
		h.step(1.0 / 60.0, Vector2.DOWN)
		await tree.physics_frame
	var y := h.global_position.y
	await _done(g)
	return "" if y > 1040 else "could not cross the bridge (stopped at y %.1f)" % y

func test_drops_avoid_water_and_props():
	var g := _ground()
	var rng := RandomNumberGenerator.new()
	var r := ""
	for s in 200:
		rng.seed = s
		for center in [Vector2(384, 800), Vector2(700, 702), Vector2(960, 1060)]:
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

func test_no_placeholder_label():
	var g := _ground()
	var r := ""
	for n in g.hud.find_children("*", "Label", true, false):
		if n.text.contains("PLACEHOLDER"): r = "placeholder label still shown"
	await _done(g)
	return r

func test_fx_points_play():
	var g := _ground()
	var r := ""
	if not FxSprite._manifest().has("water_ripple"): r = "water_ripple missing from the fx manifest"
	elif g.forest.fx_nodes.size() != g.layout.fx.size(): r = "%d ripples for %d points" % [g.forest.fx_nodes.size(), g.layout.fx.size()]
	else:
		for i in g.layout.fx.size():
			var s: FxSprite = g.forest.fx_nodes[i]
			if s.position != g.layout.fx[i].at or not s.keep: r = "ripple %d at %s keep %s" % [i, s.position, s.keep]
	await _done(g)
	return r
