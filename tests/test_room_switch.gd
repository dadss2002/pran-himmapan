extends RefCounted
## Rooms in the real test ground: warps, saving the room, packs and drops per room, colliders.
## M4d: the session's layout is random; these tests fix its seed (SEED, a layout where c1r1's north, east
## and west exits are all joined) and read where each warp leads from that layout, never from a fixed map.

const TMP_SAVE := "user://test_rooms_save.json"
const SEED := 1
var tree: SceneTree

func setup(t: SceneTree) -> void:
	tree = t

func _ground(in_tree := true, keep_save := false) -> Node2D:
	if not keep_save and FileAccess.file_exists(TMP_SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))
	var g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = TMP_SAVE
	g.layout_seed = SEED
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

## Where the start room's `side` exit leads in this session's layout ({} = dead end).
func _dest(g: Node2D, side: String, from := "c1r1") -> Dictionary:
	return g.rooms.warp(from, side)

func test_seed_joins_every_start_exit():
	var g := _ground(false)
	var r := ""
	for side in ["north", "east", "west"]:
		if _dest(g, side).is_empty(): r = "seed %d leaves c1r1 %s a dead end; pick another SEED" % [SEED, side]
	if r == "" and g.rooms.active.get("fallback", true): r = "seed %d fell back to the fixed layout" % SEED
	await _done(g)
	return r

func test_starts_in_start_room():
	var g := _ground(false)
	var r := "" if g.room_id == "c1r1" and g.hero.position == g.rooms.spawn("c1r1") else "room %s at %s" % [g.room_id, g.hero.position]
	await _done(g)
	return r

func test_warp_moves_to_paired_room():
	var g := _ground()
	await tree.physics_frame
	var w := _dest(g, "west")
	await _onto_warp(g, "west")
	var r := ""
	if g.room_id != String(w.to): r = "in %s after the west warp (layout says %s)" % [g.room_id, w.to]
	elif g.hero.global_position != g.rooms.arrival(w.to, w.to_warp): r = "hero at %s, want %s" % [g.hero.global_position, g.rooms.arrival(w.to, w.to_warp)]
	await _done(g)
	return r

func test_no_bounce():
	var g := _ground()
	await tree.physics_frame
	var to := String(_dest(g, "west").to)
	await _onto_warp(g, "west")
	for i in 60: await tree.physics_frame
	var r := "" if g.room_id == to else "bounced to %s" % g.room_id
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

## M4d: the save still records the room, but the map is new every session, so the next session always
## starts in c1r1 at its spawn (spec "What stays and what changes").
func test_saved_room_not_used_next_session():
	var g := _ground()
	await tree.physics_frame
	var to := String(_dest(g, "west").to)
	await _onto_warp(g, "west")
	await _done(g)
	var st := SaveGame.load_or_new(TMP_SAVE)
	var g2 := _ground(false, true)
	var r := ""
	if String(st.get("room", "")) != to: r = "save holds room %s, want %s" % [st.get("room", ""), to]
	elif g2.room_id != "c1r1": r = "loaded into %s" % g2.room_id
	elif g2.hero.position != g2.rooms.spawn("c1r1"): r = "hero at %s, not the c1r1 spawn" % g2.hero.position
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
	if r == "" and g.room_id != String(_dest(g, "west").to): r = "did not warp after closing the bag (in %s)" % g.room_id
	await _done(g)
	return r

## A roll into the ring in the real game: the hero's own physics carries him (no test stepping), the
## ring freezes him on touch (he stays put and stops rolling while it is dark) and he arrives standing.
func test_roll_into_warp():
	var g := _ground()
	await tree.physics_frame
	var h: Hero = g.hero
	for p in g.packs: p.process_mode = Node.PROCESS_MODE_DISABLED
	var wp: Vector2 = g.rooms.warp_at("c1r1", "east")
	var to := String(_dest(g, "east").to)
	h.global_position = wp + Vector2(-30, 0)
	h.reset_physics_interpolation()
	await tree.physics_frame
	h.try_dodge(Vector2.RIGHT)
	var r := ""
	var frozen_at := Vector2.INF
	for i in 120:
		await tree.physics_frame
		if g.room_id == to and not g.warping: break
		if g.warping and g.room_id == "c1r1":
			if frozen_at == Vector2.INF:
				frozen_at = h.global_position
				if h.is_physics_processing(): r = "hero still stepping on the ring"
				elif h.state in ["roll", "walk"]: r = "hero still in '%s' while frozen" % h.state
				elif not h.warping: r = "hero not told he is warping"
				elif String(h.body.animation).begins_with("walk"): r = "walk animation plays while frozen (%s)" % h.body.animation
			elif r == "" and h.global_position != frozen_at: r = "hero moved %s -> %s during the fade" % [frozen_at, h.global_position]
	if r == "" and frozen_at == Vector2.INF: r = "no fade seen (warped at once?)"
	elif r == "" and g.room_id != to: r = "rolled into the warp but stayed in %s" % g.room_id
	elif r == "" and h.state == "roll": r = "still rolling after arrival"
	elif r == "" and h.warping: r = "hero still marked warping after arrival"
	elif r == "" and not h.is_physics_processing(): r = "hero physics not back on after arrival"
	await _done(g)
	return r

## Review 2026-11-08: a wolf mid-bite when the hero steps on the ring. Nothing lands while it is dark:
## no damage, no knockback, no hurt pose or red flash carried into the new room.
func test_no_hits_during_fade():
	var r := ""
	for trial in 3:
		var g := _ground()
		await tree.process_frame
		g.go_to("c1r0", "", false)
		await tree.physics_frame
		var h: Hero = g.hero
		var ring: Vector2 = g.rooms.warp_at("c1r0", "south")
		h.global_position = ring + Vector2(0, -16)
		h.reset_physics_interpolation()
		h.health.setup(100000)
		var p = null
		for q in g.packs:
			if q.kind == "wolf": p = q
		if p == null:
			await _done(g)
			return "c1r0 has no wolf pack"
		p.home = h.global_position + Vector2(0, -22)
		for w in p.wolves:
			w.home = p.home
			w.global_position = h.global_position + Vector2(randf_range(-6, 6), -22)
		p.alert(h)
		var biting := false
		for i in 300:
			await tree.physics_frame
			for w in p.wolves:
				if w.state == "bite" and w._t > 0.12 and w._t < 0.3 and not h.health.is_invulnerable(): biting = true
			if biting: break
		if not biting:
			await _done(g)
			return "trial %d: no wolf started a bite" % trial
		var dmg := [0]
		h.health.damaged.connect(func(a, _c): dmg[0] += a)
		h.global_position = ring + Vector2(0, -13)
		var frames := 0
		while g.room_id == "c1r0" and frames < 60:
			await tree.physics_frame
			frames += 1
		if g.room_id == "c1r0": r = "trial %d: never left c1r0" % trial
		elif dmg[0] > 0: r = "trial %d: hero took %d damage during the fade" % [trial, dmg[0]]
		elif h.global_position != g.rooms.arrival(g.room_id, String(g.rooms.warp("c1r0", "south").to_warp)): r = "trial %d: hero at %s, not the arrival point (knocked back?)" % [trial, h.global_position]
		elif h.state == "hurt": r = "trial %d: hurt pose carried into the new room" % trial
		elif h._flash > 0.0: r = "trial %d: red flash carried into the new room" % trial
		await _done(g)
		if r != "": return r
	return r

## Old room's packs stop while it is dark, so their bites, lunges and shots cannot even start.
func test_old_room_stops_during_fade():
	var g := _ground()
	await tree.physics_frame
	g.hero.set_physics_process(false)
	g.hero.global_position = g.rooms.warp_at("c1r1", "east")
	var r := ""
	for i in 3: await tree.physics_frame
	if not g.warping: r = "no fade started"
	else:
		for p in g.packs:
			if p.can_process(): r = "a pack of the old room still runs during the fade"
		if r == "" and g.hero.receive_hit(50.0, 1.0, g.hero.global_position + Vector2(0, -10)) != 0: r = "a hit landed while warping"
	await _done(g)
	return r

## Review: opening the bag or skills mid-fade must not pause the game with the screen half dark.
func test_panels_ignored_mid_fade():
	var g := _ground()
	await tree.physics_frame
	var h: Hero = g.hero
	h.set_physics_process(false)
	h.global_position = g.rooms.warp_at("c1r1", "west")
	var r := ""
	for i in 4:
		await tree.physics_frame
		if g.warping: break
	if not g.warping: r = "no fade started"
	else:
		g.hud.open_bag()
		g.hud.open_skills()
		if g.hud.bag_panel.is_open() or g.hud.skill_panel.is_open(): r = "a panel opened mid-fade"
		elif tree.paused: r = "game paused mid-fade"
	if r == "":
		for i in 90:
			await tree.physics_frame
			if g.room_id != "c1r1" and not g.warping: break
		await tree.create_timer(0.4).timeout
		if g.room_id != String(_dest(g, "west").to): r = "did not arrive (in %s)" % g.room_id
		elif g.fade.color.a > 0.01: r = "screen left dark (alpha %.2f)" % g.fade.color.a
		else:
			g.hud.open_bag()
			if not g.hud.bag_panel.is_open(): r = "bag does not open after arrival"
	if g.hud.bag_panel.is_open(): g.hud.bag_panel.close()
	if g.hud.skill_panel.is_open(): g.hud.skill_panel.close()
	tree.paused = false
	await _done(g)
	return r

## Even if the tree is paused mid-fade, the fade still finishes (it does not freeze half dark).
func test_fade_runs_while_paused():
	var g := _ground()
	await tree.physics_frame
	g.hero.set_physics_process(false)
	g.hero.global_position = g.rooms.warp_at("c1r1", "west")
	for i in 4:
		await tree.physics_frame
		if g.warping: break
	var r := "" if g.warping else "no fade started"
	tree.paused = true
	await tree.create_timer(0.8, true).timeout
	if r == "" and g.room_id != String(_dest(g, "west").to): r = "fade stopped while paused (in %s)" % g.room_id
	elif r == "" and g.fade.color.a > 0.01: r = "screen left dark while paused (alpha %.2f)" % g.fade.color.a
	tree.paused = false
	await _done(g)
	return r

## Review: go_to(..., with_fade=false) during a fade wins; the old fade's callback never moves us again.
func test_go_to_without_fade_cancels_fade():
	var g := _ground()
	await tree.physics_frame
	g.hero.global_position = g.rooms.warp_at("c1r1", "west")
	for i in 4:
		await tree.physics_frame
		if g.warping: break
	var r := "" if g.warping else "no fade started"
	var changes := [0]
	g.room_changed.connect(func(_id): changes[0] += 1)
	g.go_to("c1r2", "", false)
	await tree.create_timer(0.8).timeout
	if r == "" and g.room_id != "c1r2": r = "the old fade moved us on to %s" % g.room_id
	elif r == "" and changes[0] != 1: r = "%d room changes, want 1" % changes[0]
	elif r == "" and g.fade.color.a > 0.01: r = "screen dark after a no-fade go_to (alpha %.2f)" % g.fade.color.a
	elif r == "" and (g.warping or g.hero.warping): r = "still warping"
	elif r == "" and not g.hero.is_physics_processing(): r = "hero left frozen"
	await _done(g)
	return r

## Review: touching a ring twice (or a second ring) during the fade changes room once.
func test_double_trigger_warps_once():
	var g := _ground()
	await tree.physics_frame
	var h: Hero = g.hero
	h.set_physics_process(false)
	var changes := []
	g.room_changed.connect(func(id): changes.append(id))
	h.global_position = g.rooms.warp_at("c1r1", "west")
	for i in 4:
		await tree.physics_frame
		if g.warping: break
	var r := "" if g.warping else "no fade started"
	for w in g.warps:                    # every ring again, mid-fade
		g.warp_through(w)
	h.global_position = g.rooms.warp_at("c1r1", "east")
	for i in 60: await tree.physics_frame
	var want := [String(_dest(g, "west").to)]
	if r == "" and changes != want: r = "room changes %s, want %s" % [changes, want]
	await _done(g)
	return r

## The way into the arena (e0) has the red label with the drawn skull: in whichever room e0 hangs off
## this session (M4d), and in no other exit.
func test_arena_label_has_skull():
	var g := _ground()
	await tree.physics_frame
	var gate := ""
	for k in g.rooms.active.links:
		if k[2] == "e0": gate = k[0]
	if gate == "":
		await _done(g)
		return "e0 not joined in the layout"
	g.go_to(gate, "", false)
	var r := "no east exit in %s" % gate
	for w in g.warps:
		if w.warp_id == "east":
			if not w.label.has_node("Skull"): r = "arena label has no skull"
			elif w.label.get_node("Text").get_theme_color("font_color") != Warp.ARENA_COLOR: r = "arena label not red"
			else: r = ""
		elif w.label.has_node("Skull"): r = "non-arena exit %s has a skull" % w.warp_id
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
	if r == "" and g.room_id != String(_dest(g, "east").to): r = "never warped (in %s)" % g.room_id
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
		elif not lab.has_node("Text") or lab.get_node("Text").text != "→ " + String(g.rooms.room(String(_dest(g, "north").to)).name): r = "label text wrong (%s)" % lab.get_node("Text").text
	if r == "":
		var w0 = g.warps[0]
		g.go_to("c1r0", "south", false)
		await tree.process_frame
		if is_instance_valid(w0) or is_instance_valid(lab): r = "old room's warp or label left behind"
	await _done(g)
	return r

## The HUD's own controls and the touch buttons, read straight from the nodes (not Hud.blocked_rects).
func _ui_rects(g: Node2D) -> Array:
	var out := []
	var vp: Vector2 = g.get_viewport().get_visible_rect().size
	var stack: Array = [g.hud]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children(): stack.append(c)
		if n is Control and n.is_visible_in_tree() and (n is Button or n is Panel or n is PanelContainer or n is ProgressBar):
			var rr: Rect2 = n.get_global_rect()
			if rr.size.x < vp.x * 0.6 and rr.size.y < vp.y * 0.6 and rr.size.x > 4: out.append([n.name, rr])
	if g.hud.touch_ui.visible:
		for name in g.hud.buttons.buttons:
			var b: Dictionary = g.hud.buttons.buttons[name]
			out.append(["touch " + name, Rect2(b.center - Vector2(b.radius, b.radius), Vector2(b.radius, b.radius) * 2.0)])
		var jc: Vector2 = g.hud.joystick.idle_center()
		out.append(["joystick", Rect2(jc - Vector2(48, 48), Vector2(96, 96))])
	return out

## Review 2026-11-08: every exit label of every room, hero 40 px inside the ring, touch controls on,
## on a phone held upright (780x1688) and sideways (1688x780): shown, fully on screen, and not under
## the HUD panels, the FPS line, the minimap box or any touch button.
func test_exit_labels_clear_of_hud_both_orientations():
	var g := _ground()
	await tree.process_frame
	g.hero.set_physics_process(false)
	var win0 := DisplayServer.window_get_size()
	var root_size0 := tree.root.size
	var touch0: bool = g.hud.touch_ui.visible
	g.hud.touch_ui.visible = true
	var fails := []
	var checked := 0
	for o in [Vector2i(780, 1688), Vector2i(1688, 780)]:
		DisplayServer.window_set_size(o)
		tree.root.size = o
		for i in 4: await tree.process_frame
		var vp: Vector2 = g.get_viewport().get_visible_rect().size
		if (o.y > o.x) != (vp.y > vp.x): fails.append("view %s did not follow the window %s" % [vp, o])
		for id in g.rooms.ids():
			g.go_to(id, "", false)
			for p in g.packs: p.process_mode = Node.PROCESS_MODE_DISABLED
			for w in g.warps:
				g.hero.global_position = w.position - w.out_dir() * 40.0
				g.hero.reset_physics_interpolation()
				for i in 3: await tree.process_frame
				checked += 1
				var lr: Rect2 = w.label.get_rect()
				var sr := Rect2(g.world_to_screen(lr.position), lr.size * float(g._scale))
				var tag := "%s %s %s" % ["portrait" if o.y > o.x else "landscape", id, w.warp_id]
				if not w.label.visible: fails.append(tag + " hidden")
				elif not Rect2(Vector2.ZERO, vp).encloses(sr): fails.append("%s off-screen %s" % [tag, sr])
				else:
					for hr in _ui_rects(g):
						if hr[1].intersects(sr): fails.append("%s under %s" % [tag, hr[0]])
	DisplayServer.window_set_size(win0)
	tree.root.size = root_size0
	g.hud.touch_ui.visible = touch0
	for i in 3: await tree.process_frame
	await _done(g)
	if checked < 40: return "only %d labels checked" % checked
	return "" if fails.is_empty() else "%d problems, e.g. %s" % [fails.size(), fails.slice(0, 4)]
