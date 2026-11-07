extends RefCounted
## Rooms in the real test ground: warps, saving the room, packs and drops per room, colliders.

const TMP_SAVE := "user://test_rooms_save.json"
var tree: SceneTree

func setup(t: SceneTree) -> void:
	tree = t

func _ground(in_tree := true, keep_save := false) -> Node2D:
	if not keep_save and FileAccess.file_exists(TMP_SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))
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

func _onto_warp(g: Node2D, warp_id: String) -> void:
	var h: Hero = g.hero
	h.set_physics_process(false)
	h.global_position = g.rooms.warp_at(g.room_id, warp_id)
	var from: String = g.room_id
	for i in 90:                         # M4c: 0.25 s fade out before the room changes
		await tree.physics_frame
		if g.room_id != from and not g.warping: break

func test_starts_in_start_room():
	var g := _ground(false)
	var r := "" if g.room_id == "c1r1" and g.hero.position == g.rooms.spawn("c1r1") else "room %s at %s" % [g.room_id, g.hero.position]
	await _done(g)
	return r

func test_warp_moves_to_paired_room():
	var g := _ground()
	await tree.physics_frame
	await _onto_warp(g, "west")
	var r := ""
	if g.room_id != "c0r1": r = "in %s after the west warp" % g.room_id
	elif g.hero.global_position != g.rooms.arrival("c0r1", "east"): r = "hero at %s, want %s" % [g.hero.global_position, g.rooms.arrival("c0r1", "east")]
	await _done(g)
	return r

func test_no_bounce():
	var g := _ground()
	await tree.physics_frame
	await _onto_warp(g, "west")
	for i in 60: await tree.physics_frame
	var r := "" if g.room_id == "c0r1" else "bounced to %s" % g.room_id
	await _done(g)
	return r

func test_bag_and_level_kept():
	var g := _ground()
	await tree.physics_frame
	g.hero.set_progress(4, 10)
	g.hero.inventory.gold = 77
	await _onto_warp(g, "east")
	var r := "" if g.hero.level == 4 and g.hero.inventory.gold == 77 else "level %d gold %d after warping" % [g.hero.level, g.hero.inventory.gold]
	await _done(g)
	return r

func test_save_remembers_room():
	var g := _ground()
	await tree.physics_frame
	await _onto_warp(g, "west")
	await _done(g)
	var g2 := _ground(false, true)
	var r := "" if g2.room_id == "c0r1" else "loaded into %s" % g2.room_id
	await _done(g2)
	return r

func test_bad_room_in_save():
	var st := SaveGame.new_state()
	st["room"] = "c9r9"
	SaveGame.save(st, TMP_SAVE)
	var g := _ground(false, true)
	var r := "" if g.room_id == "c1r1" and g.hero.position == g.rooms.spawn("c1r1") else "bad room loaded %s" % g.room_id
	await _done(g)
	return r

## M4b removed rooms w1, w3, e2: a save made in one of them loads into the start room at its spawn
## (saves store only the room, not the position).
func test_save_in_removed_room_loads_at_start():
	var r := ""
	for gone in ["w1", "w3", "e2"]:
		var st := SaveGame.new_state()
		st["room"] = gone
		SaveGame.save(st, TMP_SAVE)
		var g := _ground(false, true)
		if g.rooms.has(gone): r = "%s still exists" % gone
		elif g.room_id != g.rooms.start: r = "save in %s loaded into %s" % [gone, g.room_id]
		elif g.hero.position != g.rooms.spawn(g.rooms.start): r = "save in %s: hero at %s, spawn %s" % [gone, g.hero.position, g.rooms.spawn(g.rooms.start)]
		elif g.layout.blocked_at(g.hero.position): r = "save in %s: hero on blocked ground" % gone
		await _done(g)
		if r != "": break
	return r

func test_leaving_clears_drops_and_monsters():
	var g := _ground()
	await tree.physics_frame
	g.go_to("c1r0", "", false)
	var old_pack: WolfPack = g.packs[0]
	var w: Wolf = old_pack.wolves[0]
	w.health.take_hit(99999, false)
	for i in 3: await tree.physics_frame
	var had: int = g.drops.size()
	g.go_to("c1r1", "north", false)
	await tree.physics_frame
	var here := 0                          # c1r1's own monsters (deer, spec M3d §3)
	for m in g.rooms.room("c1r1").get("monsters", []): here += int(m.count)
	var r := ""
	if had == 0: r = "no drops to test with"
	elif not g.drops.is_empty() or is_instance_valid(old_pack): r = "drops %d / old pack %s left behind" % [g.drops.size(), is_instance_valid(old_pack)]
	elif g.packs.size() != g.rooms.room("c1r1").get("monsters", []).size(): r = "%d packs in c1r1" % g.packs.size()
	elif tree.get_nodes_in_group("enemies").size() != here: r = "%d enemies in the tree (c1r1 has %d)" % [tree.get_nodes_in_group("enemies").size(), here]
	await _done(g)
	return r

func test_arrival_safe_from_pack():
	var g := _ground()
	await tree.physics_frame
	g.go_to("c1r2", "west", false)
	var r := ""
	for p in g.packs:
		for w in p.wolves:
			if w.global_position.distance_to(g.hero.global_position) < 60.0: r = "wolf %s near arrival %s" % [w.global_position, g.hero.global_position]
			elif w.health.hp < w.health.max_hp: r = "wolf not at full HP"
	await _done(g)
	return r

func test_death_respawns_in_room():
	var g := _ground()
	await tree.physics_frame
	g.go_to("c2r2", "north", false)
	var h: Hero = g.hero
	h.health.take_hit(99999, false)
	for i in 150: await tree.physics_frame
	var r := ""
	if g.room_id != "c2r2": r = "respawned in %s" % g.room_id
	elif h.global_position.distance_to(g.rooms.spawn("c2r2")) > 2.0: r = "respawned at %s, spawn %s" % [h.global_position, g.rooms.spawn("c2r2")]
	await _done(g)
	return r

func test_no_warp_while_paused():
	var g := _ground()
	await tree.physics_frame
	g.hud.open_bag()
	await tree.process_frame
	g.hero.global_position = g.rooms.warp_at("c1r1", "west")
	for i in 30: await tree.process_frame
	var r := "" if g.room_id == "c1r1" else "warped while the bag was open"
	g.hud.bag_panel.close()
	for i in 90:
		await tree.physics_frame
		if g.room_id != "c1r1" and not g.warping: break
	if r == "" and g.room_id != "c0r1": r = "did not warp after closing the bag (in %s)" % g.room_id
	await _done(g)
	return r

func test_roll_into_warp():
	var g := _ground()
	await tree.physics_frame
	var h: Hero = g.hero
	h.set_physics_process(false)
	var wp: Vector2 = g.rooms.warp_at("c1r1", "east")
	h.global_position = wp + Vector2(-30, 0)
	await tree.physics_frame
	h.try_dodge(Vector2.RIGHT)
	for i in 30:
		h.step(1.0 / 60.0, Vector2.ZERO)
		await tree.physics_frame
	for i in 90:
		if g.room_id == "c2r1" and not g.warping: break
		await tree.physics_frame
	var r := ""
	if g.room_id != "c2r1": r = "rolled into the warp but stayed in %s" % g.room_id
	elif h.state == "roll": r = "still rolling after arrival"
	await _done(g)
	return r

func test_colliders_match_blocked_at_every_room():
	var g := _ground()
	await tree.physics_frame
	var r := ""
	for id in g.rooms.ids():
		g.go_to(id, "", false)
		await tree.physics_frame
		await tree.physics_frame
		var space: PhysicsDirectSpaceState2D = g.world.get_world_2d().direct_space_state   # the room lives in world_vp (M3j)
		var q := PhysicsPointQueryParameters2D.new()
		q.collision_mask = 1
		var sz: Vector2 = g.layout.size_px()   # each room's own size (M4b: 512x512)
		var y := 3.5
		while y < sz.y and r == "":
			var x := 3.5
			while x < sz.x:
				q.position = Vector2(x, y)
				var solid := false
				for hit in space.intersect_point(q, 4):
					if hit.collider is StaticBody2D: solid = true
				if solid != g.layout.blocked_at(q.position):
					r = "%s at %s physics %s, blocked_at %s" % [id, q.position, solid, not solid]
					break
				x += 8.0
			y += 8.0
		if r != "": break
	await _done(g)
	return r

func test_drops_avoid_blocked():
	var g := _ground(false)
	var rng := RandomNumberGenerator.new()
	var r := ""
	for id in g.rooms.ids():
		g.go_to(id, "", false)
		for s in 30:
			rng.seed = s
			var center: Vector2 = g.rooms.spawn(id)
			for p in LootDrop.scatter(center, 6, rng, g._blocked):
				if p != center and g.layout.blocked_at(p): r = "%s drop at %s blocked" % [id, p]
		if r != "": break
	await _done(g)
	return r

## M4c §1 approved timings: 0.25 s fade out, then the new room, 0.25 s fade in; monsters calm 1.0 s.
func test_fade_and_calm_numbers():
	var g := _ground(false)
	var r := ""
	if g.FADE_OUT != 0.25 or g.FADE_IN != 0.25: r = "fade %s out / %s in" % [g.FADE_OUT, g.FADE_IN]
	elif g.CALM != 1.0: r = "calm %s" % g.CALM
	await _done(g)
	return r

## Walking into the ring starts the fade at once; the room changes when the screen is dark (~0.25 s),
## then the screen clears in ~0.25 s and the new room's monsters stay calm for 1.0 s.
func test_warp_fades_out_then_in():
	var g := _ground()
	await tree.physics_frame
	var h: Hero = g.hero
	h.set_physics_process(false)
	for i in 10: await tree.process_frame   # let the heavy set-up frame pass (its delta would feed the tween)
	h.global_position = g.rooms.warp_at("c1r1", "east")
	var t0 := Time.get_ticks_msec()
	await tree.physics_frame
	await tree.physics_frame
	var r := ""
	if g.room_id != "c1r1": r = "room changed before the fade out"
	elif not g.warping: r = "no fade started on the ring"
	var waited := 0
	while r == "" and g.room_id == "c1r1" and waited < 120:
		await tree.physics_frame
		waited += 1
	var dt := (Time.get_ticks_msec() - t0) / 1000.0
	if r == "" and g.room_id != "c2r1": r = "never warped (in %s)" % g.room_id
	elif r == "" and (dt < 0.2 or dt > 0.5): r = "room changed after %.2f s (want ~0.25)" % dt
	elif r == "" and g.fade.color.a < 0.9: r = "screen not dark at the swap (alpha %.2f)" % g.fade.color.a
	if r == "":
		for p in g.packs:
			if p.calm < 0.9: r = "pack calm %.2f after arrival (want 1.0)" % p.calm
	if r == "":
		await tree.create_timer(0.4).timeout
		if g.fade.color.a > 0.01: r = "screen still dark 0.4 s after arrival (alpha %.2f)" % g.fade.color.a
		elif g.warping: r = "still warping"
		else:
			for p in g.packs:
				if p.calm <= 0.0: r = "pack calm ran out before 1.0 s"
	await _done(g)
	return r

## The exit label shows in the game only near the ring, with the next room's name.
func test_exit_label_near_ring():
	var g := _ground()
	await tree.physics_frame
	var h: Hero = g.hero
	h.set_physics_process(false)
	var north: Vector2 = g.rooms.warp_at("c1r1", "north")
	h.global_position = north + Vector2(0, 100)
	for i in 3: await tree.process_frame
	var lab: Control = null
	for w in g.warps:
		if w.warp_id == "north": lab = w.label
	var r := ""
	if lab == null or not lab.is_inside_tree(): r = "north exit has no label in the game"
	elif lab.visible: r = "label shown 100 px away"
	if r == "":
		h.global_position = north + Vector2(0, 40)
		for i in 3: await tree.process_frame
		if not lab.visible: r = "label hidden 40 px away"
		elif not lab.has_node("Text") or lab.get_node("Text").text != "→ ลานเสาหิน": r = "label text wrong"
	if r == "":
		var w0 = g.warps[0]
		g.go_to("c1r0", "south", false)
		await tree.process_frame
		if is_instance_valid(w0) or is_instance_valid(lab): r = "old room's warp or label left behind"
	await _done(g)
	return r
