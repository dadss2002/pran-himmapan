extends SceneTree
## M5b Task 8b (ห่าศร) in game, for the owner's review.
## xvfb-run -a godot --path . --rendering-driver opengl3 --script tests/screenshots_m5b_rain.gd
## The test ground at 1280x720 (world 640x360, x2 on screen), char Lv10, a real press (Hero.try_skill, the release, the
## ArrowRain it lays, its own ticks). Monsters are held still (no AI) with lots of HP: one under the rain's centre (the
## D2 target), one 50 px from it (inside r64) and one 80 px above it (outside). Light ground (c1r0) and dark (c2r0).
## Moments: warn (0.42 s: the marker and the first arrows, before any hit), tick (just after the 1.0 s tick: hit sparks
## and numbers), fall (1.38 s: arrows in the air between ticks); `saver` = the same with the PerfSaver on (light only).
## Each goes to docs/preview/m5b/t8b_rain_<ground>_<moment>.png (the crop as on screen = game size) and _x3.png.
## RAIN_GEMS="expand,fire" sockets gems on ห่าศร (keys as tests: fire / ice / lightning = element gems).

const OUT := "res://docs/preview/m5b/"
const SAVE := "user://shots_m5b_t8b_save.json"
const DT := 1.0 / 60.0

var g: Node2D

func _initialize() -> void:
	_run()
	_watchdog()

func _watchdog() -> void:
	await create_timer(300.0).timeout
	print("watchdog: giving up")
	quit(1)

func _run() -> void:
	await _case("light", "c1r0", Vector2(-110, 20), false)
	await _case("dark", "c2r0", Vector2(-170, 140), false)
	await _case("light_saver", "c1r0", Vector2(-110, 20), true)
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
	var ui: float = float(img.get_width()) / float(root.get_visible_rect().size.x)     # the UI scale (ScreenFit)
	var c: Vector2 = g.world_to_screen(at) * ui
	var sc: float = (g.world_to_screen(Vector2(100, 0)).x - g.world_to_screen(Vector2.ZERO).x) / 100.0 * ui
	var r := Rect2i(Vector2i((c - Vector2(half, half) * sc).round()), Vector2i(Vector2(half, half) * 2.0 * sc))
	r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var crop := img.get_region(r)
	crop.save_png(OUT + "t8b_rain_%s.png" % name)
	crop.resize(crop.get_width() * 3, crop.get_height() * 3, Image.INTERPOLATE_NEAREST)
	crop.save_png(OUT + "t8b_rain_%s_x3.png" % name)
	print("saved ", name, " ", r.size, " scale ", sc)

func _case(ground: String, room: String, hero_off: Vector2, saver: bool) -> void:
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
	g.saver.on = saver
	g.apply_saver()
	var h: Hero = g.hero
	h.set_physics_process(false)
	h.set_progress(10, 0)
	var gems: Array = []
	for k in OS.get_environment("RAIN_GEMS").split(",", false): gems.append(_gem(k))
	h.set_skill_gems({"arrow_rain": gems})
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
	var at: Vector2 = h.global_position + Vector2(120, -10)
	var spots := [at, at + Vector2(40, 30), at + Vector2(0, -80)]
	for i in mini(3, wolves.size()):
		wolves[i].visible = true
		wolves[i].global_position = spots[i]
	for i in 4: await _tick(wolves)
	if not h.try_skill("arrow_rain"): print("WARN: try_skill refused")
	var n := 0
	while n < 120 and h.rains.is_empty():
		await _tick(wolves)
		n += 1
	if h.rains.is_empty():
		print("WARN: no rain")
		g.queue_free()
		return
	var rain: ArrowRain = h.rains[0]
	print(ground, ": centre ", rain.center, " target feet ", spots[0], " r ", rain.radius, " ticks ", rain.ticks)
	var half := rain.radius + 56.0
	for m in [["warn", 0.42], ["tick", 1.03], ["fall", 1.38]]:
		while is_instance_valid(rain) and rain.time() < float(m[1]) - 1e-6: await _tick(wolves)
		paused = true
		await _snap("%s_%s" % [ground, m[0]], rain.center, half)
		paused = false
	print(ground, ": hits ", rain.hits_done, " after ", rain.ticks_done, " ticks; outside monster hp ", wolves[2].hp if wolves.size() > 2 else -1)
	g.queue_free()
	for i in 3: await process_frame
	PerfSaver.active = false
