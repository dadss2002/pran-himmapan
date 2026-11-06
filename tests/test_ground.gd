extends RefCounted
## Test ground wiring + physics checks that need real frames.

var tree: SceneTree

func setup(t: SceneTree) -> void:
	tree = t

func test_ground_spawns_three_packs():
	var g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = TMP_SAVE          # never touch the player's real save
	if FileAccess.file_exists(TMP_SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))
	g.build()
	var levels := []
	var total := 0
	for p in g.packs:
		levels.append(p.level)
		total += p.wolves.size()
	var r := ""
	if levels != [1, 3, 5]: r = "pack levels %s" % [levels]
	elif total != 11: r = "%d wolves, expected 11" % total
	elif g.hero.spawn_point != Vector2(960, 560): r = "hero spawn %s" % g.hero.spawn_point
	g.free()
	return r

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
