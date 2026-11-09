extends RefCounted
## Test ground wiring + physics checks that need real frames.

var tree: SceneTree

func setup(t: SceneTree) -> void:
	tree = t

func test_ground_wolf_packs_in_their_rooms():
	var g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = TMP_SAVE          # never touch the player's real save
	if FileAccess.file_exists(TMP_SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))
	g.layout_seed = 7
	g.build()
	var r := ""
	if g.room_id != "c1r1": r = "starts in %s" % g.room_id
	elif g.hero.spawn_point != g.layout.hero_spawn: r = "hero spawn %s" % g.hero.spawn_point
	else:
		# spec M3g §2 counts; M4d addendum: the level is the room's level in this session's layout (wolf is
		# each room's first group, so it has no +1). Seed 7 worked out by hand from its links: c1r2 is next to
		# c1r1 (d 1), c1r0 is d 2 (via c0r1), c2r2 is the farthest forest room (d 5 = D), so with
		# L = round(1 + (d - 1) * 8 / 4) + 1: c1r2 Lv2, c1r0 Lv4, c2r2 Lv10.
		for want in [["c1r0", 4, 10], ["c2r2", 10, 10], ["c1r2", 2, 12]]:
			g.go_to(want[0], "", false)
			var wolves := 0
			var levels := []
			for p in g.packs:
				if p.kind != "wolf": continue      # other forest monsters share some rooms (spec M3d §3)
				levels.append(p.level)
				wolves += p.wolves.size()
			var one_level := not levels.is_empty() and levels.all(func(l): return l == want[1])
			if not one_level or wolves != want[2]:
				r = "%s: pack levels %s, %d wolves" % [want[0], levels, wolves]
				break
	g.free()
	return r

## M4d addendum 2: e0's set is chosen on the first entry of the session from max(hero level, level of the
## room the hero came from) and kept when walking out and back; a new game chooses again.
func test_arena_set_chosen_once_per_session():
	var kinds := func(g) -> Dictionary:
		var out := {}
		for p in g.packs: out[String(p.kind)] = true
		return out
	var r := ""
	for run in 2:
		var g = load("res://scenes/test_ground.tscn").instantiate()
		g.save_path = TMP_SAVE
		if FileAccess.file_exists(TMP_SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))
		g.layout_seed = 7                   # by hand: e0 hangs off c2r2 (Lv10, the farthest forest room)
		g.build()
		if run == 0:
			g.hero.set_progress(3, 0)
			g.go_to("c2r2", "", false)
			g.go_to("e0", "west", false)     # target max(3, 10) = 10 -> the w3 set (kongkoi, macaque)
			var first: Dictionary = kinds.call(g)
			g.go_to("c2r2", "east", false)
			g.hero.set_progress(1, 0)
			g.go_to("e0", "west", false)     # chosen already this session: still the w3 set
			var again: Dictionary = kinds.call(g)
			if first.size() != 2 or not first.has("kongkoi") or not first.has("macaque"): r = "Lv3 hero from c2r2 got %s (want the w3 set)" % first.keys()
			elif again != first: r = "set changed on the second entry: %s then %s" % [first.keys(), again.keys()]
		else:
			# review fix: e0 counts the room it is joined to, so hang it on c1r1 for this check
			g.rooms.use_layout({"pos": {"c1r1": Vector2i(1, 1), "e0": Vector2i(2, 1)},
				"links": [["c1r1", "east", "e0", "west"]], "fallback": false})
			g.hero.set_progress(1, 0)        # new game: chosen again; from c1r1 (Lv1) -> target 1 -> the w1 set
			g.go_to("e0", "west", false)
			var got: Dictionary = kinds.call(g)
			if r == "" and (got.size() != 2 or not got.has("boar") or not got.has("wolf")): r = "new game Lv1 hero got %s (want the w1 set: boar, wolf)" % got.keys()
		g.free()
	return r

## Review nit: the room levels are worked out once per layout, not on every room change.
func test_room_levels_cached_per_layout():
	var rs := RoomSet.open()
	rs.use_layout(RoomLayout.generate(7, rs.exit_table()))
	var a := rs.room_levels()
	var b := rs.room_levels()
	if not is_same(a, b): return "room_levels() worked out again for the same layout"
	rs.use_layout(RoomLayout.generate(42, rs.exit_table()))
	var c := rs.room_levels()
	if is_same(a, c): return "room_levels() kept the old layout's levels after use_layout()"
	return "" if c == RoomLevels.for_layout(rs.active) else "cached levels differ from for_layout()"

func test_damage_number_crit_style():
	var crit := DamageNumber.make(25, true)
	var normal := DamageNumber.make(17, false)
	var r := ""
	if crit.text != "25!": r = "crit text '%s'" % crit.text
	elif crit.get_theme_color("font_color") != DamageNumber.CRIT_COLOR: r = "crit not gold"
	elif normal.text != "17": r = "normal text '%s'" % normal.text
	elif normal.get_theme_color("font_color") != Color.WHITE: r = "normal not white"
	crit.free(); normal.free()
	return r

func test_roll_stops_at_collider():
	var world := Node2D.new()
	tree.root.add_child(world)
	var post := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(14, 8)
	cs.shape = rect
	cs.position = Vector2(0, -4)
	post.add_child(cs)
	post.position = Vector2(100, 0)
	world.add_child(post)
	var h: Hero = load("res://scenes/hero.tscn").instantiate()
	h.position = Vector2(40, 0)
	world.add_child(h)
	h.set_physics_process(false)
	await tree.physics_frame
	await tree.physics_frame
	h.try_dodge(Vector2.RIGHT)
	for i in 30:
		await tree.physics_frame
		h.step(1.0 / 60.0, Vector2.ZERO)
	var x := h.global_position.x
	world.queue_free()
	await tree.process_frame
	if x <= 40.5: return "hero did not roll at all (x %.1f)" % x
	return "" if x < 84.0 else "rolled into/through the post: x %.1f (post edge 93, hero half-width 10)" % x

const TMP_SAVE := "user://test_ground_save.json"

func test_ground_loads_and_autosaves():
	if FileAccess.file_exists(TMP_SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))
	var inv := Inventory.new()
	inv.add("gold", 77)
	SaveGame.save({"level": 4, "exp": 100, "inventory": inv.to_dict()}, TMP_SAVE)
	var g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = TMP_SAVE
	g.build()
	var r := ""
	if g.hero.level != 4 or g.hero.exp != 100 or g.hero.inventory.gold != 77: r = "loaded L%d exp %d gold %d" % [g.hero.level, g.hero.exp, g.hero.inventory.gold]
	g.hero.inventory.add("gold", 3)
	g.tick_autosave(29.0)
	if r == "" and SaveGame.load_or_new(TMP_SAVE).inventory.gold != 77: r = "saved before 30 s"
	g.tick_autosave(1.1)
	if r == "" and SaveGame.load_or_new(TMP_SAVE).inventory.gold != 80: r = "autosave after 30 s missing"
	g.hero.gain_exp(1000)
	if r == "" and SaveGame.load_or_new(TMP_SAVE).level != g.hero.level: r = "level-up did not save"
	g.hero.inventory.add("gold", 5)
	g._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	if r == "" and SaveGame.load_or_new(TMP_SAVE).inventory.gold != 85: r = "phone pause did not save"
	g.hero.inventory.add("gold", 5)
	g._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	if r == "" and SaveGame.load_or_new(TMP_SAVE).inventory.gold != 90: r = "browser focus-out did not save"
	g.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))
	return r

func test_load_with_hp_gear_starts_full():
	if FileAccess.file_exists(TMP_SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))
	var eq := SaveGame.start_equipped()
	eq.ring = {"base": "ring", "rarity": "rare", "level": 3, "opts": [{"k": "hp", "v": 18}, {"k": "mp", "v": 9}]}
	SaveGame.save({"level": 3, "exp": 0, "inventory": Inventory.new().to_dict(), "equipped": eq}, TMP_SAVE)
	var g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = TMP_SAVE
	g.build()
	var h: Hero = g.hero
	var r := ""
	if h.health.hp != h.health.max_hp or h.health.max_hp != h.stats().hp: r = "HP %d/%d, stats %d" % [h.health.hp, h.health.max_hp, h.stats().hp]
	elif absf(h.mp - h.max_mp()) > 0.01: r = "MP %.1f/%d" % [h.mp, h.max_mp()]
	g.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))
	return r
