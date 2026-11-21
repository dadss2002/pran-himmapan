extends SceneTree
## M5b Task 8c (กับดักหนาม) in game, for the owner's review.
## xvfb-run -a godot --path . --rendering-driver opengl3 --script tests/screenshots_m5b_trap.gd
## The test ground at 1280x720 (world 640x360, x2 on screen), char Lv10, a real press (Hero.try_skill, the release, the
## ThornTrap it places on the locked monster's feet). Monsters are held still (no AI) with lots of HP. Light ground
## (c1r0) and dark (c2r0). Moments: placed (the armed trap, the monster stepped 40 px off it), trigger (2 frames after
## the monster steps on it: burst, hit spark, number), rooted (0.8 s: the closed trap under the rooted monster).
## Each goes to docs/preview/m5b/t8c_trap_<ground>_<moment>.png (the crop as on screen = game size) and _x3.png.
## TRAP_GEMS="expand" sockets gems on กับดักหนาม (keys as tests) and adds "_<gems>" to the names.

const OUT := "res://docs/preview/m5b/"
const SAVE := "user://shots_m5b_t8c_save.json"
const DT := 1.0 / 60.0

var g: Node2D
var tag := ""

func _initialize() -> void:
	_run()
	_watchdog()

func _watchdog() -> void:
	await create_timer(300.0).timeout
	print("watchdog: giving up")
	quit(1)

func _run() -> void:
	var gems := OS.get_environment("TRAP_GEMS")
	tag = "" if gems == "" else "_" + gems.replace(",", "_")
	await _case("light", "c1r0", Vector2(-110, 20))
	await _case("dark", "c2r0", Vector2(-170, 140))
	print("done")
	quit(0)

func _gem(key: String) -> Dictionary:
	var gm := {"type": key, "level": 1, "exp": 0, "rarity": "common", "opts": []}
	if key in ["fire", "ice", "lightning"]:
		gm["type"] = "element"
		gm["element"] = key
	return gm

func _tick(wolves: Array) -> void:
	await physics_frame
	g.hero.step(DT, Vector2.ZERO)
	for w in wolves:
		w.tick_burn(DT)
		w._update_status_fx()

func _snap(name: String, at: Vector2, half: float) -> void:
	for i in 3: await process_frame
	var img := root.get_texture().get_image()
	var ui: float = float(img.get_width()) / float(root.get_visible_rect().size.x)
	var c: Vector2 = g.world_to_screen(at) * ui
	var sc: float = (g.world_to_screen(Vector2(100, 0)).x - g.world_to_screen(Vector2.ZERO).x) / 100.0 * ui
	var r := Rect2i(Vector2i((c - Vector2(half, half) * sc).round()), Vector2i(Vector2(half, half) * 2.0 * sc))
	r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var crop := img.get_region(r)
	crop.save_png(OUT + "t8c_trap_%s%s.png" % [name, tag])
	crop.resize(crop.get_width() * 3, crop.get_height() * 3, Image.INTERPOLATE_NEAREST)
	crop.save_png(OUT + "t8c_trap_%s%s_x3.png" % [name, tag])
	print("saved ", name, tag, " ", r.size, " scale ", sc)

func _case(ground: String, room: String, hero_off: Vector2) -> void:
	if FileAccess.file_exists(SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	for i in 6: await process_frame
	g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = SAVE
	g.layout_seed = 7
	g.watch_fps = false
	root.add_child(g)
	for i in 4: await process_frame
	g.go_to(room, "", false)
	for i in 4: await process_frame
	var h: Hero = g.hero
	h.set_physics_process(false)
	h.set_progress(10, 0)
	var gems: Array = []
	for k in OS.get_environment("TRAP_GEMS").split(",", false): gems.append(_gem(k))
	h.set_skill_gems({"thorn_trap": gems})
	h.mp = h.max_mp()
	var wolves := []
	for p in g.packs:
		p.set_physics_process(false)
		p.set_process(false)
		for w in p.wolves: wolves.append(w)
	var mid: Vector2 = g.layout.size_px() / 2.0
	h.global_position = mid + hero_off
	for w in wolves:
		w.set_physics_process(false)
		w.health.setup(100000)
		w.visible = false
		w.global_position = mid + Vector2(-3000, -3000)
	var at: Vector2 = h.global_position + Vector2(100, -10)
	var off := at + Vector2(40, 6)
	wolves[0].visible = true
	wolves[0].global_position = at
	if wolves.size() > 1:
		wolves[1].visible = true
		wolves[1].global_position = at + Vector2(34, -30)   # farther from the hero: the press locks on to wolves[0]
	for i in 4: await _tick(wolves)
	if not h.try_skill("thorn_trap"): print("WARN: try_skill refused")
	var n := 0
	while n < 120 and h.traps.armed().is_empty():
		await _tick(wolves)
		n += 1
	if h.traps.armed().is_empty():
		print("WARN: no trap")
		g.queue_free()
		return
	var trap: ThornTrap = h.traps.armed()[0]
	wolves[0].global_position = off                # steps off before the trap's first step
	print(ground, ": trap at ", trap.at, " target ", at, " r ", trap.trigger_radius, " placeholder ", trap.placeholder)
	for i in 20: await _tick(wolves)
	paused = true
	await _snap("%s_placed" % ground, trap.at, 56.0)
	paused = false
	wolves[0].global_position = at
	for i in 2: await _tick(wolves)
	paused = true
	await _snap("%s_trigger" % ground, trap.at, 56.0)
	paused = false
	for i in 46: await _tick(wolves)
	paused = true
	await _snap("%s_rooted" % ground, trap.at, 56.0)
	paused = false
	print(ground, ": spent ", trap.spent, " rooted ", wolves[0].is_rooted(), " hp ", wolves[0].hp)
	g.queue_free()
