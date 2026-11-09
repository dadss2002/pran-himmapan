extends RefCounted
## Task 5 waypoints (docs/superpowers/specs/2026-11-07-m4c-farm-links-fog-minimap.md §2): a stone in c1r1, c0r2,
## c2r0 and c2r1 (rooms.json "waypoint"); touching it unlocks it ("ปลดล็อกจุดวาป", notify sound, saved); standing
## on an unlocked stone opens the travel list (only unlocked stones, the hero's room marked "ที่นี่"); a tap
## re-rolls (Task 4) and travels there with the same fade, landing next to the stone on open ground with the
## arrival calm. The stone blocks walking, stands clear of exits, arrivals and monster spawn points, and the list
## fits a phone upright (780x1688) and sideways (1688x780) with the touch controls on.

const SAVE := "user://test_waypoints_save.json"
const SETTINGS := "user://test_waypoints_settings.json"
const STONES := {"c1r1": "ศาลหินเริ่มต้น", "c0r2": "บึงในป่า", "c2r0": "ปรางค์ร้าง", "c2r1": "ทางแยกขอนไม้"}

var tree: SceneTree

func setup(t: SceneTree) -> void:
	tree = t

func _clean() -> void:
	for f in [SAVE, SETTINGS, SaveGame.marker_path(SAVE)]:
		if FileAccess.file_exists(f): DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

## A test ground in the tree (seed 7), monsters quiet so they never touch the hero.
func _ground() -> Node2D:
	var g: Node2D = load("res://scenes/test_ground.tscn").instantiate()
	g.layout_seed = 7
	g.save_path = SAVE
	g.settings_path = SETTINGS
	tree.root.add_child(g)
	await tree.process_frame
	_quiet(g)
	return g

func _quiet(g: Node2D) -> void:
	for p in g.packs: p.calm = 1000.0

func _free(g: Node2D) -> void:
	if is_instance_valid(g):
		g.queue_free()
		await tree.process_frame

func _frames(n: int) -> void:
	for i in n: await tree.physics_frame

## Puts the hero's feet at p and lets the game see it.
func _stand(g: Node2D, p: Vector2) -> void:
	g.hero.global_position = p
	g.hero.velocity = Vector2.ZERO
	await _frames(3)

func _go(g: Node2D, id: String) -> void:
	g.go_to(id, "", false)
	_quiet(g)
	await _frames(2)

## Waypoints alone: the start stone always unlocked, unlock once, list order, save / load, travel only when
## unlocked, the touch radius.
func test_waypoints_rules():
	var w := Waypoints.make(["c2r1", "c0r2", "c1r1", "c2r0"])
	if w.ids != ["c1r1", "c0r2", "c2r0", "c2r1"]: return "order %s" % [w.ids]
	if w.list() != ["c1r1"]: return "fresh list %s (want the start stone only)" % [w.list()]
	if not w.unlock("c2r0") or w.unlock("c2r0"): return "unlock should say true once"
	if w.unlock("x9") or w.is_unlocked("x9"): return "a room without a stone unlocked"
	w.unlock("c0r2")
	if w.list() != ["c1r1", "c0r2", "c2r0"]: return "list %s" % [w.list()]
	var back := Waypoints.make(w.ids, w.to_save())
	if back.list() != w.list(): return "save/load %s -> %s" % [w.to_save(), back.list()]
	if Waypoints.make(w.ids, null).list() != ["c1r1"]: return "old save (no key) should hold the start stone only"
	if Waypoints.make(w.ids, ["c2r1", 5, null, "nope", {"a": 1}]).list() != ["c1r1", "c2r1"]: return "garbage in the saved list not ignored"
	if Waypoints.make(w.ids, "c2r1").list() != ["c1r1"]: return "a non-list save not ignored"
	var went := []
	w.traveller = func(id): went.append(id)
	if w.travel("c2r1") or not went.is_empty(): return "travel to a locked stone"
	if not w.travel("c2r0") or went != ["c2r0"]: return "travel to an unlocked stone: %s" % [went]
	var s := Vector2(100, 200)
	var c := Waypoints.centre(s)
	if c != Vector2(100, 192): return "centre %s" % c
	if not Waypoints.touching(s, c + Vector2(Waypoints.RADIUS, 0)) or Waypoints.touching(s, c + Vector2(Waypoints.RADIUS + 0.5, 0)):
		return "touch radius is not %s" % Waypoints.RADIUS
	return ""

## The four stones of the spec, on the 8 px grid; their rooms' names are the spec's waypoint names.
func test_four_stones_in_the_spec_rooms():
	var rooms := RoomSet.open()
	if rooms.waypoint_ids() != ["c0r2", "c1r1", "c2r0", "c2r1"]: return "stones in %s" % [rooms.waypoint_ids()]
	for id in STONES:
		if String(rooms.room(id).get("name", "")) != STONES[id]: return "%s is named %s (want %s)" % [id, rooms.room(id).get("name"), STONES[id]]
		var p := rooms.waypoint(id)
		if fmod(p.x, 8.0) != 0.0 or fmod(p.y, 8.0) != 0.0: return "%s stone %s off the 8 px grid" % [id, p]
	if rooms.waypoint("c1r2") != Vector2.INF: return "c1r2 has a stone"
	return ""

## The stone is not walkable: every footprint cell is blocked, its landing is open ground in front of it (not in
## the footprint, within the touch radius, reachable), the room still validates (every exit reachable), the hero
## can walk round it, and walking into it stops him at its edge.
func test_stone_not_walkable():
	var rooms := RoomSet.open()
	if not rooms.validate().is_empty(): return "rooms invalid: %s" % [rooms.validate().slice(0, 3)]
	for id in STONES:
		var l := rooms.layout(id)
		var foot := rooms.waypoint_rect(id)
		if foot.size != Vector2(32, 16): return "%s footprint %s" % [id, foot.size]
		for y in range(int(foot.position.y), int(foot.end.y), 2):
			for x in range(int(foot.position.x), int(foot.end.x), 2):
				if not l.blocked_at(Vector2(x, y)): return "%s footprint point %s walkable" % [id, Vector2(x, y)]
		var land := rooms.waypoint_landing(id)
		var c := Vector2i(int(land.x) / l.cell, int(land.y) / l.cell)
		if not l.roomy(c.x, c.y): return "%s landing %s not open ground" % [id, land]
		if foot.grow(0.0).has_point(land): return "%s landing inside the stone" % id
		if land.y <= rooms.waypoint(id).y: return "%s landing %s not in front of the stone" % [id, land]
		if not Waypoints.touching(rooms.waypoint(id), land): return "%s landing %s off the stone (radius %s)" % [id, land, Waypoints.RADIUS]
		if not l.reachable(l.hero_spawn, land): return "%s landing cannot be walked to" % id
		var behind := rooms.waypoint(id) - Vector2(0, 40)     # round the stone to its back
		var bc := Vector2i(int(behind.x) / l.cell, int(behind.y) / l.cell)
		if l.roomy(bc.x, bc.y) and not l.reachable(land, behind): return "%s: cannot walk round the stone" % id
	_clean()
	var g: Node2D = await _ground()
	var r := ""
	for id in STONES:
		await _go(g, id)
		var wp: Vector2 = g.rooms.waypoint(id)
		await _stand(g, g.rooms.waypoint_landing(id))
		Input.action_press("move_up")               # walk straight into the stone for 0.6 s
		await _frames(36)
		Input.action_release("move_up")
		var feet: Vector2 = g.hero.global_position
		if feet.y > g.rooms.waypoint_landing(id).y - 2.0: r = "%s: the hero did not walk (feet %s)" % [id, feet]
		elif feet.y < wp.y + 11.0: r = "%s: walked into the stone (feet %s, stone base %s)" % [id, feet, wp]
		elif g.rooms.waypoint_rect(id).has_point(feet): r = "%s: feet inside the stone" % id
		if r != "": break
	await _free(g)
	_clean()
	return r

## Every stone is clear of the room's exits (its touch circle out of the exit label's range), of every arrival
## (each exit's, the room's spawn) by more than the warp re-arm distance, and of every monster spawn point: the
## built homes' rings and all 64 baked placements (bank up to date, every point out of the footprint and out of
## the touch circle).
func test_stone_clear_of_exits_arrivals_spawns():
	var rooms := RoomSet.open()
	var bad: Array = []
	for id in STONES:
		var wp := rooms.waypoint(id)
		var c := Waypoints.centre(wp)
		var foot := rooms.waypoint_rect(id).grow(4.0)
		for e in rooms.exits(id):
			var at := Vector2(e.at[0], e.at[1])
			if c.distance_to(at) < Waypoints.RADIUS + Warp.LABEL_RANGE: bad.append("%s exit %s %.0f px from the stone" % [id, e.id, c.distance_to(at)])
			var a := rooms.arrival(id, String(e.id))
			if c.distance_to(a) < Waypoints.RADIUS + RoomSet.REARM: bad.append("%s arrival %s %.0f px from the stone" % [id, e.id, c.distance_to(a)])
		if rooms.room(id).has("spawn") and c.distance_to(rooms.spawn(id)) < Waypoints.RADIUS + RoomSet.REARM:
			bad.append("%s spawn %.0f px from the stone" % [id, c.distance_to(rooms.spawn(id))])
		var groups: Array = rooms.room(id).monsters
		for g in groups:
			for q in PaintedLayout.ring(Vector2(g.at[0], g.at[1]), int(g.count)):
				if foot.has_point(q) or c.distance_to(q) <= Waypoints.RADIUS: bad.append("%s built %s point %s by the stone" % [id, g.kind, q])
		if PileBank.find(id, rooms.pile_hash(id, groups)).is_empty(): bad.append("%s: the pile bank is stale (run %s)" % [id, PileBank.BAKE])
		var land := rooms.waypoint_landing(id)
		if not rooms.pile_room(id).arrivals.has(land): bad.append("%s: the landing is not a pile arrival" % id)
		for s in PileBank.SIZE:
			for p in rooms.piles(id, groups, s):
				if p.fallback: bad.append("%s seed %d fell back" % [id, s])
				for q in [p.home] + p.points:
					if foot.has_point(q) or c.distance_to(q) <= Waypoints.RADIUS:
						bad.append("%s seed %d: %s point %s by the stone (%.0f px)" % [id, s, p.kind, q, c.distance_to(q)])
					var floor := MonsterPiles.arrival_floor(String(p.kind), false)
					if land.distance_to(q) < floor: bad.append("%s seed %d: %s point %.0f px from the landing" % [id, s, p.kind, land.distance_to(q)])
		if bad.size() > 8: break
	return "" if bad.is_empty() else "%d problems, e.g. %s" % [bad.size(), bad.slice(0, 4)]

## Touching a stone unlocks it once: toast "ปลดล็อกจุดวาป" with the notify sound, the stone glows brighter, the
## save holds it; then the list opens (only unlocked stones, the hero's room marked); stepping off closes it and
## back on opens it; its close button keeps it shut until the hero steps off and on again.
func test_unlock_on_touch_and_list():
	_clean()
	var g: Node2D = await _ground()
	var r := ""
	if not g.waypoints.is_unlocked("c1r1") or g.waypoints.list() != ["c1r1"]: r = "new game: %s unlocked (want c1r1)" % [g.waypoints.list()]
	if r == "" and (g.stone == null or g.stone.room_id != "c1r1" or not g.stone.unlocked): r = "c1r1 stone missing or dim"
	if r == "" and g.hud.waypoints_open(): r = "list open at the start (spawn is off the stone)"
	if r == "":
		await _go(g, "c2r1")
		if g.stone == null or g.stone.unlocked: r = "c2r1 stone missing or already unlocked"
		elif g.stone.sprite.texture.resource_path != "res://assets/props/waypoint/waypoint_1.png": r = "stone art %s" % g.stone.sprite.texture.resource_path
		elif g.stone.sprite.scale != Vector2.ONE or g.stone.sprite.offset != -WaypointStone.BASE_PX: r = "stone not at whole-pixel scale on its base point"
		elif g.stone.get_parent() != g.world or not g.world.y_sort_enabled: r = "stone not in the Y-sorted world"
	if r == "":
		var near: Vector2 = Waypoints.centre(g.stone.position) + Vector2(Waypoints.RADIUS + 12.0, 0)
		await _stand(g, g.rooms.waypoint_landing("c2r1") + Vector2(0, 30))
		if g.waypoints.is_unlocked("c2r1"): r = "unlocked from %.0f px" % Waypoints.centre(g.stone.position).distance_to(g.hero.global_position)
		Sfx.requested.clear()
		if r == "":
			await _stand(g, g.rooms.waypoint_landing("c2r1"))
			var ids: Array = Sfx.requested.map(func(e): return e.id)
			if not g.waypoints.is_unlocked("c2r1"): r = "touching did not unlock"
			elif not g.stone.unlocked: r = "the stone did not light up"
			elif not g.hud.toast.visible or g.hud.toast.text != "ปลดล็อกจุดวาป": r = "toast '%s'" % g.hud.toast.text
			elif not "toast" in ids: r = "no notify sound (%s)" % [ids]
			elif not "c2r1" in SaveGame.load_or_new(SAVE).waypoints: r = "not saved: %s" % [SaveGame.load_or_new(SAVE).waypoints]
			elif not g.hud.waypoints_open(): r = "list not open on an unlocked stone"
			elif not "ui_open" in ids: r = "no menu-open sound"
			elif g.hud.waypoint_list.rows.keys() != ["c1r1", "c2r1"]: r = "rows %s" % [g.hud.waypoint_list.rows.keys()]
			elif g.hud.waypoint_list.rows["c1r1"].text != "ศาลหินเริ่มต้น": r = "c1r1 row '%s'" % g.hud.waypoint_list.rows["c1r1"].text
			elif g.hud.waypoint_list.rows["c2r1"].text != "ทางแยกขอนไม้ · ที่นี่": r = "current row '%s'" % g.hud.waypoint_list.rows["c2r1"].text
			Sfx.requested.clear()
			await _stand(g, g.rooms.waypoint_landing("c2r1") + Vector2(2, 0))
			if r == "" and Sfx.requested.map(func(e): return e.id).has("toast"): r = "a second toast on the same stone"
		if r == "":
			await _stand(g, near)
			if g.hud.waypoints_open(): r = "list still open after stepping off"
		if r == "":
			await _stand(g, g.rooms.waypoint_landing("c2r1"))
			if not g.hud.waypoints_open(): r = "list did not open again"
		if r == "":
			g.hud.waypoint_list.close_button.pressed.emit()
			await _frames(4)
			if g.hud.waypoints_open(): r = "close button: list open again while still on the stone"
		if r == "":
			await _stand(g, near)
			await _stand(g, g.rooms.waypoint_landing("c2r1"))
			if not g.hud.waypoints_open(): r = "list did not open after stepping off and on after closing"
	if r == "":
		g.hero.health.take_hit(g.hero.health.hp, false)
		await _frames(3)
		if g.hero.state != "dead": r = "setup: the hero did not die"
		elif g.hud.waypoints_open(): r = "list open while dead"
	await _free(g)
	_clean()
	return r

## Unlocked stones survive a reload; an old save (no "waypoints") loads with only the start stone and keeps the
## rest of the save; the list only ever shows unlocked stones.
func test_saved_loaded_and_only_unlocked_listed():
	_clean()
	var g: Node2D = await _ground()
	g.waypoints.unlock("c0r2")
	g.save_now()
	await _free(g)
	var g2: Node2D = await _ground()
	var r := ""
	if g2.waypoints.list() != ["c1r1", "c0r2"]: r = "after reload %s" % [g2.waypoints.list()]
	if r == "":
		var ids: Array = g2.waypoint_entries().map(func(e): return e.id)
		if ids != ["c1r1", "c0r2"]: r = "entries %s (want only the unlocked)" % [ids]
	if r == "":
		await _stand(g2, g2.rooms.waypoint_landing("c1r1"))
		if g2.hud.waypoint_list.rows.keys() != ["c1r1", "c0r2"]: r = "list rows %s" % [g2.hud.waypoint_list.rows.keys()]
	await _free(g2)
	if r == "":
		var st := SaveGame.new_state()
		st.erase("waypoints")
		st.level = 4
		SaveGame.save(st, SAVE)
		var f := FileAccess.open(SAVE, FileAccess.READ)
		var raw: Dictionary = JSON.parse_string(f.get_as_text())
		f.close()
		raw.erase("waypoints")                  # SaveGame.save keeps keys as given; make sure it is an old file
		raw.erase("sig")                        # save hardening 2026-11-09: a pre-Task-5 file is version 3, unsigned,
		raw.version = 3                         # on a device that has not written a signed save yet
		f = FileAccess.open(SAVE, FileAccess.WRITE)
		f.store_string(JSON.stringify(raw))
		f.close()
		if FileAccess.file_exists(SaveGame.marker_path(SAVE)): DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveGame.marker_path(SAVE)))
		var g3: Node2D = await _ground()
		if g3.waypoints.list() != ["c1r1"]: r = "old save: %s" % [g3.waypoints.list()]
		elif g3.hero.level != 4: r = "old save lost its level (%d)" % g3.hero.level
		await _free(g3)
	_clean()
	return r

## A tap on a row: re-roll (new pile seed, kept rooms forgotten, the room left not kept), warp gong, the fade,
## and the hero lands next to the destination stone (open ground, not in the stone) with the arrival calm and the
## list shut (he lands on the stone; it opens again once he steps off and back). The current room may be chosen:
## it re-rolls in place. A locked stone cannot be travelled to.
func test_travel_rerolls_and_lands_by_the_stone():
	_clean()
	var g: Node2D = await _ground()
	for id in STONES: g.waypoints.unlock(id)
	var r := ""
	var other := String(g.rooms.room("c1r1").warps[0].to)
	await _go(g, other)
	await _go(g, "c1r1")
	if not g.reset.has(other): r = "setup: %s not kept" % other
	var seed0: int = g.pile_seed
	if r == "":
		await _stand(g, g.rooms.waypoint_landing("c1r1"))
		if not g.hud.waypoints_open(): r = "list not open on the c1r1 stone"
	if r == "":
		Sfx.requested.clear()
		g.hud.waypoint_list.rows["c2r0"].pressed.emit()
		var ids: Array = Sfx.requested.map(func(e): return e.id)
		if not g.warping: r = "no fade after the tap"
		elif g.hud.waypoints_open(): r = "list still open during the trip"
		elif not "warp" in ids: r = "no warp gong (%s)" % [ids]
		elif g.pile_seed == seed0: r = "pile seed unchanged (no re-roll)"
		elif not g.reset.kept_ids().is_empty(): r = "kept rooms after the re-roll: %s" % [g.reset.kept_ids()]
	if r == "":
		await tree.create_timer(TestGround_fade()).timeout
		await _frames(2)
		var land: Vector2 = g.rooms.waypoint_landing("c2r0")
		var l: PaintedLayout = g.rooms.layout("c2r0")
		if g.room_id != "c2r0" or g.warping: r = "not in c2r0 after the fade (room %s, warping %s)" % [g.room_id, g.warping]
		elif g.hero.global_position.distance_to(land) > 1.0: r = "hero at %s, landing %s" % [g.hero.global_position, land]
		elif l.blocked_at(g.hero.global_position) or g.rooms.waypoint_rect("c2r0").has_point(g.hero.global_position): r = "landed in the stone"
		elif g.packs.is_empty() or g.packs[0].calm <= 0.0: r = "no arrival calm"
		elif not g.reset.kept_ids().is_empty(): r = "c1r1 kept after a re-roll: %s" % [g.reset.kept_ids()]
		elif g.hud.waypoints_open(): r = "list popped up on landing"
		var groups: Array = g.groups_for("c2r0", "c1r1")
		var want: Array = g.rooms.piles("c2r0", groups, MonsterPiles.room_seed(g.pile_seed, "c2r0"))
		if r == "" and g._room_piles != want: r = "c2r0 piles are not the new seed's"
	if r == "":
		_quiet(g)
		await _stand(g, g.rooms.waypoint_landing("c2r0") + Vector2(0, 30))
		await _stand(g, g.rooms.waypoint_landing("c2r0"))
		if not g.hud.waypoints_open(): r = "list did not open after stepping off and on"
	if r == "":
		var seed1: int = g.pile_seed
		var homes0: Array = g._room_piles.map(func(p): return p.home)
		seed(4242)                                           # RoomReset.new_seed uses randi(): a fixed draw
		g.hud.waypoint_list.rows["c2r0"].pressed.emit()      # the room the hero is in: a reset
		await tree.create_timer(TestGround_fade()).timeout
		await _frames(2)
		# Deterministic (M5b Task 4 review): the global RNG is also drawn by monsters during the real-time fade, so
		# the new seed is not fixed, and two seeds can pick the same bank entry (1 in the bank's size, ~1/64). The
		# trip must re-roll the seed and lay the new seed's piles; "different homes" is skipped only when the bank
		# exists and both seeds pick the same entry (no bank = live piles: always checked; Task 4 review).
		# Whether a re-roll must always differ is the owner's call (not decided).
		var groups2: Array = g.groups_for("c2r0", "c2r0")
		var bank := PileBank.find("c2r0", g.rooms.pile_hash("c2r0", groups2))
		var n_bank: int = bank["p"].size() if not bank.is_empty() else 0
		var idx0 := posmod(MonsterPiles.room_seed(seed1, "c2r0"), n_bank) if n_bank > 0 else -1
		var idx1 := posmod(MonsterPiles.room_seed(g.pile_seed, "c2r0"), n_bank) if n_bank > 0 else -1
		if g.room_id != "c2r0": r = "current-room trip left the room (%s)" % g.room_id
		elif g.pile_seed == seed1: r = "current-room trip did not re-roll"
		elif g._room_piles != g.rooms.piles("c2r0", groups2, MonsterPiles.room_seed(g.pile_seed, "c2r0")): r = "current-room trip: piles are not the new seed's"
		elif not (n_bank > 0 and idx0 == idx1) and g._room_piles.map(func(p): return p.home) == homes0: r = "current-room trip kept the same piles (bank entries %d → %d, bank size %d)" % [idx0, idx1, n_bank]
		elif g.hero.global_position.distance_to(g.rooms.waypoint_landing("c2r0")) > 1.0: r = "current-room trip landed at %s" % g.hero.global_position
	if r == "":
		var locked := Waypoints.make(g.waypoints.ids)
		locked.traveller = g.travel_to_waypoint
		var seed2: int = g.pile_seed
		if locked.travel("c2r1") or g.warping or g.pile_seed != seed2: r = "travelled to a locked stone"
	await _free(g)
	_clean()
	return r

func TestGround_fade() -> float:
	var tg = load("res://scripts/dev/test_ground.gd")
	return tg.FADE_OUT + tg.FADE_IN + 0.2     # + slack

## The travel list upright (780x1688, 750x1334) and sideways (1688x780, 1334x750 = a 640 x 360 view) with touch on,
## 4 rows (one marked "ที่นี่") and the unlock toast showing, for heroes at several places on screen (the centred
## camera too; hero and stone sized by the camera zoom of that view): rows and close button at least 44 px tall and
## inside the panel; one column upright; two sideways unless no two-column spot clears the hero and the HUD, then
## one; the hero is never covered; the panel inside the safe area, clear of the status panel,
## the minimap box, the FPS line, the top-right block, the toast, every touch button (with its note), the joystick
## ring and the hero with his stone; a touch on it never starts the joystick; listed in blocked_rects (exit labels avoid it).
func test_list_layout_portrait_and_landscape():
	_clean()
	var w := tree.root
	var size0 := w.size
	var scale0 := w.content_scale_size
	var hud := Hud.new()
	hud.settings_path = SETTINGS
	hud.build()
	w.add_child(hud)
	hud.touch_ui.visible = true
	var fails := []
	var covered := 0
	var entries := []
	for id in ["c1r1", "c0r2", "c2r0", "c2r1"]: entries.append({"id": id, "name": STONES[id]})
	var cases := 0
	var one_col := 0
	for o in [Vector2i(780, 1688), Vector2i(1688, 780), Vector2i(750, 1334), Vector2i(1334, 750)]:
		DisplayServer.window_set_size(o)
		w.size = o
		w.content_scale_size = ScreenFit.base_for(o)
		for i in 4: await tree.process_frame
		var view := w.get_visible_rect().size
		hud.buttons.layout(view)
		hud.joystick.view_size = view
		hud.joystick.reset()
		hud.layout(view)
		var portrait: bool = o.y > o.x
		var heroes := [Vector2(0.5, 0.5), Vector2(0.25, 0.5), Vector2(0.75, 0.5), Vector2(0.5, 0.3), Vector2(0.5, 0.75), Vector2(0.3, 0.8),
			Vector2(0.6, 0.6)]
		# camera zoom of this view for a 512 px room (1.52 on 1688x780, 1.25 on 1334x750)
		var zoom := ScreenFit.camera_zoom(view, Vector2(512, 512))
		var zk := zoom / 1.52
		# and the hero landed on each real stone, where the camera (kept inside the room) shows him in this view
		var rooms := RoomSet.open()
		var half := view / zoom / 2.0
		for id in STONES:
			var feet: Vector2 = rooms.waypoint_landing(id)
			var cam_at := Vector2(clampf(feet.x, half.x, 512.0 - half.x), clampf(feet.y, half.y, 512.0 - half.y))
			heroes.append(((feet - cam_at) * zoom + view / 2.0) / view)
		for hp in heroes:
			cases += 1
			# the hero (HERO_BOX x camera zoom) and the stone just above his head (ART_BOX x camera zoom)
			var hero := Rect2(view * hp - Vector2(18, 64) * zk, Vector2(36, 67) * zk)
			var stone_r := Rect2(view * hp - Vector2(33, 112) * zk, Vector2(67, 85) * zk)
			hud.close_waypoints()
			hud.show_toast("ปลดล็อกจุดวาป")
			hud.waypoint_avoid = hero
			hud.waypoint_avoid_stone = stone_r
			hud.open_waypoints(entries, "c2r0")
			await tree.process_frame
			var tag := "%s %s hero %s" % ["portrait" if portrait else "landscape", o, hp]
			var panel: Rect2 = hud.waypoint_list.get_global_rect()
			var cols: int = hud.waypoint_list.grid.columns
			if portrait and cols != 1: fails.append("%s: %d columns upright" % [tag, cols])
			if not portrait and cols == 1:
				# one column sideways only when no two-column spot clears the HUD and the hero
				one_col += 1
				hud.waypoint_list.set_columns(2)
				var sz2: Vector2 = hud.waypoint_list.get_combined_minimum_size()
				hud.waypoint_list.set_columns(1)
				var hud_hero: Array = hud.blocked_rects(false) + [hud.top_right.get_global_rect(), hero]
				if WaypointList.spot(sz2, hud.safe_rect(), hud_hero, [], view / 2.0) != Vector2.INF:
					fails.append("%s: one column though two columns clear the hero" % tag)
			elif not portrait and cols != 2: fails.append("%s: %d columns sideways" % [tag, cols])
			var rects := {"close": hud.waypoint_list.close_button.get_global_rect()}
			for id in hud.waypoint_list.rows: rects["row " + id] = hud.waypoint_list.rows[id].get_global_rect()
			if hud.waypoint_list.rows.size() != 4: fails.append("%s: %d rows" % [tag, hud.waypoint_list.rows.size()])
			for k in rects:
				var rr: Rect2 = rects[k]
				if rr.size.y < 44.0 - 0.01 or rr.size.x < 44.0 - 0.01: fails.append("%s: %s is %s (under 44 px)" % [tag, k, rr.size])
				if not panel.grow(0.5).encloses(rr): fails.append("%s: %s outside the panel" % [tag, k])
				for k2 in rects:
					if k2 != k and rects[k2].intersects(rr): fails.append("%s: %s over %s" % [tag, k, k2])
			if not hud.safe_rect().encloses(panel): fails.append("%s: panel %s off the safe area %s" % [tag, panel, hud.safe_rect()])
			var keep := {"status panel": hud.status_panel.get_global_rect(), "minimap box": hud.minimap_box.get_global_rect(),
				"FPS line": hud.fps_button.get_global_rect(), "top-right block": hud.top_right.get_global_rect(),
				"toast": hud.toast.get_global_rect(), "hero": hero}
			for n in hud.buttons.buttons:
				var b: Dictionary = hud.buttons.buttons[n]
				var r6: float = b.radius + 6.0                 # a touch button reacts 6 px outside its ring
				var rr := Rect2(b.center - Vector2(r6, r6), Vector2(r6, r6) * 2.0)
				if b.note != "": rr = rr.merge(Rect2(b.center.x - 24.0, b.center.y + b.radius, 48.0, 16.0))
				keep["touch " + n] = rr
			var jr := TouchJoystick.RADIUS
			keep["joystick"] = Rect2(hud.joystick.idle_center() - Vector2(jr, jr), Vector2(jr, jr) * 2.0)
			for k in keep:
				if keep[k].intersects(panel): fails.append("%s: panel %s over %s %s" % [tag, panel, k, keep[k]])
			if not hud.blocked_rects().has(panel): fails.append("%s: panel not in blocked_rects" % tag)
			# the stone may only be covered when no spot clears the HUD, the hero and the stone together
			if panel.intersects(stone_r.grow(WaypointList.MARGIN - 0.01)):     # 0.01: float slack on a shared edge
				var all: Array = hud.blocked_rects(false) + [hud.top_right.get_global_rect(), hero, stone_r]
				if WaypointList.spot(panel.size, hud.safe_rect(), all, [], view / 2.0) != Vector2.INF:
					fails.append("%s: panel over the stone though a clear spot exists" % tag)
				else: covered += 1
			for k in rects:
				if hud.joystick.in_zone(rects[k].get_center()): fails.append("%s: a tap on %s starts the joystick" % [tag, k])
	print("    (list over the stone, no clear spot: %d of %d cases; one column sideways: %d)" % [covered, cases, one_col])
	hud.close_waypoints()
	if hud.joystick.ignore_at.call(Vector2(100, 200)): fails.append("joystick still ignores touches with the list shut")
	DisplayServer.window_set_size(size0)
	w.size = size0
	w.content_scale_size = scale0
	hud.queue_free()
	for i in 3: await tree.process_frame
	_clean()
	return "" if fails.is_empty() else "%d problems, e.g. %s" % [fails.size(), fails.slice(0, 4)]

## WaypointList.spot alone: inside the safe rect, clear of the blocked rects, off the hero and his stone when it
## can be (the stone given up first), else on them rather than nowhere; nearest the wanted middle.
func test_spot_rule():
	var safe := Rect2(0, 0, 300, 200)
	var sz := Vector2(100, 60)
	var at := WaypointList.spot(sz, safe, [], [Rect2()], Vector2(150, 100))
	if at != Vector2(100, 70): return "free screen: %s (want centred)" % at
	at = WaypointList.spot(sz, safe, [Rect2(0, 0, 300, 50)], [Rect2(130, 80, 40, 60)], Vector2(150, 100))
	var r := Rect2(at, sz)
	if not safe.encloses(r) or r.intersects(Rect2(0, 0, 300, 50).grow(WaypointList.MARGIN)) or r.intersects(Rect2(130, 80, 40, 60).grow(WaypointList.MARGIN)):
		return "blocked top + hero: %s" % r
	at = WaypointList.spot(sz, safe, [], [Rect2(0, 0, 300, 200)], Vector2(150, 100))
	if at == Vector2.INF: return "a hero over the whole screen left no spot (should fall back to ignoring him)"
	# hero kept, stone dropped: the stone fills the left 2/3, the hero sits top right; the panel goes bottom right
	at = WaypointList.spot(sz, safe, [], [Rect2(250, 0, 50, 60), Rect2(0, 0, 200, 200)], Vector2(150, 100))
	if at == Vector2.INF or Rect2(at, sz).intersects(Rect2(250, 0, 50, 60).grow(WaypointList.MARGIN)): return "hero not kept clear when the stone had to go: %s" % at
	if WaypointList.spot(sz, safe, [Rect2(0, 0, 300, 200)], [], Vector2(150, 100)) != Vector2.INF: return "a full block still found a spot"
	return ""

## A touch (finger `index`) at p (HUD px) pushed into the root viewport; with `mouse` it first sends the emulated
## mouse button Godot makes for the finger it turns into the mouse (device DEVICE_ID_EMULATION, sent just before
## that finger's touch). true when the touch was marked handled.
func _touch(index: int, p: Vector2, pressed: bool, mouse := false) -> bool:
	if mouse:
		var mb := InputEventMouseButton.new()
		mb.device = InputEvent.DEVICE_ID_EMULATION
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		mb.pressed = pressed
		mb.position = p
		mb.global_position = p
		tree.root.push_input(mb, true)
	var st := InputEventScreenTouch.new()
	st.index = index
	st.position = p
	st.pressed = pressed
	tree.root.push_input(st, true)
	return tree.root.is_input_handled()

## Second-finger taps (owner report 2026-11-08): with a thumb held on the joystick (the finger Godot turns into
## the mouse), a tap on a row with another finger chooses it, once; the joystick keeps the thumb and no touch
## button is pressed; the tap is marked handled. Down on one row and up on another chooses nothing. Another
## finger on the close button closes the list. A one-finger tap (emulated mouse + its touch) chooses once.
func test_second_finger_taps_rows():
	_clean()
	var hud := Hud.new()
	hud.settings_path = SETTINGS
	hud.build()
	tree.root.add_child(hud)
	hud.touch_ui.visible = true
	await tree.process_frame
	var view := tree.root.get_visible_rect().size
	hud.buttons.layout(view)
	hud.joystick.view_size = view
	hud.joystick.reset()
	hud.layout(view)
	var entries := []
	for id in ["c1r1", "c0r2", "c2r0", "c2r1"]: entries.append({"id": id, "name": STONES[id]})
	var picked := []
	var shut := [0]
	hud.waypoint_list.chosen.connect(func(id): picked.append(id))
	hud.waypoint_list.closed.connect(func(): shut[0] += 1)
	hud.waypoint_avoid = Rect2(view / 2.0 - Vector2(15, 50), Vector2(30, 55))
	hud.open_waypoints(entries, "c2r0")
	for i in 2: await tree.process_frame
	var row := func(id: String) -> Vector2: return hud.waypoint_list.rows[id].get_global_rect().get_center()
	var r := ""
	# the thumb on the joystick: left half, clear of the list
	var thumb := Vector2(hud.joystick.idle_center().x, hud.joystick.idle_center().y)
	if hud.waypoint_list.get_global_rect().grow(WaypointList.MARGIN).has_point(thumb): r = "setup: the joystick spot is under the list"
	if r == "":
		_touch(0, thumb, true, true)
		if not hud.joystick.active: r = "setup: the thumb did not take the joystick"
	if r == "":
		var down := _touch(1, row.call("c0r2"), true)
		await tree.process_frame
		var up := _touch(1, row.call("c0r2"), false)
		await tree.process_frame
		if picked != ["c0r2"]: r = "second finger on c0r2 chose %s" % [picked]
		elif not down or not up: r = "the second finger's touch was not marked handled (down %s, up %s)" % [down, up]
		elif not hud.joystick.active or hud.joystick._index != 0: r = "the joystick lost the thumb"
		elif not hud.buttons.pressed_names().is_empty(): r = "touch buttons pressed: %s" % [hud.buttons.pressed_names()]
	if r == "":
		picked.clear()
		_touch(1, row.call("c0r2"), true)
		_touch(1, row.call("c2r1"), false)
		await tree.process_frame
		if not picked.is_empty(): r = "down on c0r2, up on c2r1 chose %s" % [picked]
	if r == "":
		_touch(2, hud.waypoint_list.close_button.get_global_rect().get_center(), true)
		_touch(2, hud.waypoint_list.close_button.get_global_rect().get_center(), false)
		await tree.process_frame
		if hud.waypoints_open() or shut[0] != 1: r = "second finger on ปิด: open %s, closed %d" % [hud.waypoints_open(), shut[0]]
	if r == "":
		_touch(0, thumb, false, true)
		await tree.process_frame
		if hud.joystick.active: r = "the joystick kept a lifted thumb"
	if r == "":
		# one finger alone: Godot's emulated mouse presses the button (GUI); the helper must not press it again
		hud.open_waypoints(entries, "c2r0")
		for i in 2: await tree.process_frame
		picked.clear()
		var p: Vector2 = row.call("c1r1")
		var motion := InputEventMouseMotion.new()
		motion.device = InputEvent.DEVICE_ID_EMULATION
		motion.position = p
		motion.global_position = p
		tree.root.push_input(motion, true)
		_touch(0, p, true, true)
		await tree.process_frame
		_touch(0, p, false, true)
		await tree.process_frame
		if picked != ["c1r1"]: r = "one-finger tap on c1r1 chose %s (want exactly once)" % [picked]
	hud.queue_free()
	for i in 2: await tree.process_frame
	_clean()
	return r
