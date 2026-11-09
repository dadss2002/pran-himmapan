extends SceneTree
## M5b owner fire picks 2026-11-09 (T2 fire/campfire trail + B2 grenade line-end blast) in game, for the owner's review.
## xvfb-run -a godot --path . --rendering-driver opengl3 --script tests/screenshots_m5b_fire_fx.gd
## then: python3 -I tools/fire_fx_review.py   (crops at game size and x3, the r32 ring, and the numbered review image)
## Real presses in the test ground (Hero.try_skill, its arrows, FireTrail and line-end blast as the game runs them, 1280x720,
## char Lv10, piercing; only the monsters are held still). Full frames go to /tmp/fire_shots/<case>_<moment>.png with
## /tmp/fire_shots/meta.json (screen positions of the hero, every trail patch and blast, the world -> screen scale);
## the review tool turns them into docs/preview/m5b/fire_t2_b2_*.png.
## Cases:
##   trail_light - ศรพัดเพลิง (split + fire) on the light grass of c1r0, 0.75 s after the release; moments a / b / c are
##     the same lines with every patch 3 frames (0.2 s) further on each (to judge the per-patch frame offsets).
##   trail_dark  - the same on the darker ground of c2r0.
##   fade        - ศรพัดเพลิง's lines in their last FADE s (about half faded).
##   blast_light - พัดเพลิงพรหมาสตร์ (split + fire + multiply) on c1r0: the three line-end blasts at sheet frames 1 / 2 / 5
##     (0.07 / 0.13 / 0.33 s; the sprite frame is set while the tree is paused, the blasts are the real ones), and
##     "none": the same moment with the blasts hidden (what they cover).
##   blast_dark  - the same on c2r0.
##   blast_monster - พรหมาสตร์ with a dark monster (boar, c0r1) standing on the middle line's end.
##   saver       - blast_light with the PerfSaver on (the patches and the blast must all stay).
## FIRE_SET=small (owner 2026-11-09: the trail patches drawn at the sample's size, FireTrail.PATCH_SCALE 0.4) runs the
## trail cases only, into /tmp/fire_shots_small/ (python3 -I tools/fire_fx_review.py --small -> fire_t2_small_*.png):
##   trail_light, trail_dark, fade as above, and trail_saver - trail_light with the PerfSaver on.

var TMP := "/tmp/fire_shots_small/" if OS.get_environment("FIRE_SET") == "small" else "/tmp/fire_shots/"
const SAVE := "user://shots_m5b_fire_save.json"
const DT := 1.0 / 60.0

var g: Node2D
var meta := {}

func _initialize() -> void:
	_run()
	_watchdog()

func _watchdog() -> void:
	await create_timer(300.0).timeout
	print("watchdog: giving up")
	quit(1)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(TMP)
	await _case("trail_light", "c1r0", ["split", "fire"], "trail", false, Vector2(-110, 30), "")
	await _case("trail_dark", "c2r0", ["split", "fire"], "trail", false, Vector2(-170, 120), "")
	await _case("fade", "c1r0", ["split", "fire"], "fade", false, Vector2(-110, 30), "")
	if OS.get_environment("FIRE_SET") == "small":
		await _case("trail_saver", "c1r0", ["split", "fire"], "trail", true, Vector2(-110, 30), "")
		_finish()
		return
	await _case("blast_light", "c1r0", ["split", "fire", "multiply"], "blast", false, Vector2(-110, 30), "")
	await _case("blast_dark", "c2r0", ["split", "fire", "multiply"], "blast", false, Vector2(-170, 120), "")
	await _case("blast_monster", "c0r1", ["split", "fire", "multiply"], "blast", false, Vector2(-110, 40), "boar")
	await _case("saver", "c1r0", ["split", "fire", "multiply"], "blast", true, Vector2(-110, 30), "")
	_finish()

func _finish() -> void:
	var f := FileAccess.open(TMP + "meta.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "  "))
	f.close()
	print("done")
	quit(0)

func _gem(key: String) -> Dictionary:
	var gm := {"type": key, "level": 1, "exp": 0, "rarity": "common", "opts": []}
	if key == "fire":
		gm["type"] = "element"
		gm["element"] = "fire"
	return gm

func _size(s: Vector2i) -> void:
	DisplayServer.window_set_size(s)
	root.size = s
	for i in 6: await process_frame

func _v(p: Vector2) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01)]

## hero_off: the hero's place from the room's middle; on_end: a monster kind to stand on the middle line's end ("" none).
func _case(name: String, room: String, keys: Array, mode: String, saver: bool, hero_off: Vector2, on_end: String) -> void:
	if FileAccess.file_exists(SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	await _size(Vector2i(1280, 720))
	g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = SAVE
	g.layout_seed = 7
	g.watch_fps = false                 # the saver only when asked (xvfb's frame rate is not a phone's)
	root.add_child(g)
	for i in 4: await process_frame
	g.go_to(room, "", false)
	for i in 4: await process_frame
	g.saver.on = saver
	g.apply_saver()
	var h: Hero = g.hero
	h.set_physics_process(false)
	var gems: Array = []
	for k in keys: gems.append(_gem(k))
	h.set_progress(10, 0)
	h.set_skill_gems({"piercing": gems})
	h.mp = h.max_mp()
	var b := h.build("piercing")
	var wolves := []
	for p in g.packs:
		p.set_physics_process(false)
		p.set_process(false)
		for w in p.wolves: wolves.append(w)
	var mid: Vector2 = g.layout.size_px() / 2.0
	h.global_position = mid + hero_off
	# the aim: one monster on the middle line close to the hero; the one asked for (on_end) kept for the line end
	var end_mon: Wolf = null
	if on_end != "":
		for w in wolves:
			if end_mon == null and String(w.get("kind")) == on_end: end_mon = w
	var aim: Wolf = null
	for w in wolves:
		if aim == null and w != end_mon: aim = w
	for w in wolves:
		w.set_physics_process(false)
		w.health.setup(100000)
		if w == aim: w.global_position = h.global_position + Vector2(90, -10)
		elif w != end_mon:
			w.visible = false
			w.global_position = mid + Vector2(-3000, -3000)
		else: w.global_position = mid + Vector2(-3000, 3000)       # placed on the line's end after the release
	for i in 4: await physics_frame
	if not h.try_skill("piercing"): print("WARN: try_skill refused")
	print(name, ": combo ", b.combo.get("id", "-"), " arrows ", b.arrows, " saver ", PerfSaver.active)
	var released := -1
	var frames := 0
	var ended := -1
	while frames < 400:
		await physics_frame
		h.step(DT, Vector2.ZERO)
		for w in wolves: w.tick_burn(DT)
		frames += 1
		if released < 0 and h._released: released = frames
		if released < 0: continue
		var arrows: Array = g.world.get_children().filter(func(c): return c is Arrow and not c.is_queued_for_deletion())
		if end_mon != null and end_mon.global_position.x < -1000.0 and arrows.size() == 3:
			arrows.sort_custom(func(p, q): return p.dir.angle() < q.dir.angle())
			var a: Arrow = arrows[1]                      # the middle line
			var rng: float = a.max_range if a.max_range > 0.0 else Balance.num("shot.range")
			var end: Vector2 = a.global_position + a.dir * (rng - a.travelled)
			end_mon.global_position = end + Vector2(-4, -12)   # feet just above the end: the blast draws over it (the arrow's knockback moves it ~10 px on)
		if mode == "trail" and frames - released >= int(round(0.75 / DT)): break
		if mode == "blast" and arrows.is_empty() and frames - released > 5:
			ended = frames
			for i in 2: await physics_frame
			break
		if mode == "fade":
			var ts: Array = g.world.get_children().filter(func(c): return c is FireTrail and c.finished)
			if not ts.is_empty() and ts.all(func(t): return t.left < FireTrail.FADE * 0.5): break
	var trails: Array = g.world.get_children().filter(func(c): return c is FireTrail)
	var blasts: Array = g.world.get_children().filter(func(c): return c is FxSprite and c.animation == "fire_blast")
	var patches: Array = []
	for t in trails:
		for c in t.get_children():
			if c is FxSprite: patches.append(c)
	print(name, ": ", trails.size(), " trails, ", patches.size(), " patches ", patches.map(func(p): return p.frame), ", ", blasts.size(), " blasts, alpha ",
		trails.map(func(t): return snappedf(t.modulate.a, 0.01)))
	paused = true
	var k: float = g.world_to_screen(Vector2(100, 0)).x - g.world_to_screen(Vector2.ZERO).x
	var m := {"room": room, "combo": String(b.combo.get("id", "")), "saver": saver, "scale": k / 100.0,
		"hero": _v(g.world_to_screen(h.global_position)), "aim": _v(g.world_to_screen(aim.global_position)) if aim != null else null,
		"patch_scale": patches.map(func(p): return _v(p.scale)), "patch_visible": patches.map(func(p): return p.is_visible_in_tree()),
		"patches": patches.map(func(p): return _v(g.world_to_screen(p.global_position))),
		"blasts": blasts.map(func(s): return _v(g.world_to_screen(s.global_position))),
		"trail_alpha": trails.map(func(t): return t.modulate.a), "monster": _v(g.world_to_screen(end_mon.global_position)) if end_mon != null else null, "monster_hurt": _v(g.world_to_screen(end_mon.hurt_point())) if end_mon != null else null, "monster_visible": end_mon.is_visible_in_tree() if end_mon != null else null,
		"moments": {}}
	if mode == "trail":
		for step in 3:
			if step > 0:
				for p in patches: p.frame = posmod(p.frame + 3, int(p.sprite_frames.get_frame_count(p.animation)))
			m.moments["abc"[step]] = {"file": await _snap("%s_%s.png" % [name, "abc"[step]]), "frames": patches.map(func(p): return p.frame)}
	elif mode == "blast":
		for s in blasts: s.visible = false              # the same moment without the blasts (what they cover)
		m.moments["none"] = {"file": await _snap("%s_none.png" % name), "frames": patches.map(func(p): return p.frame)}
		for s in blasts: s.visible = true
		for bf in [1, 2, 5]:
			for s in blasts: s.frame = bf
			m.moments["f%d" % bf] = {"file": await _snap("%s_f%d.png" % [name, bf]), "frames": patches.map(func(p): return p.frame)}
	else:
		m.moments["a"] = {"file": await _snap("%s_a.png" % name), "frames": patches.map(func(p): return p.frame)}
	meta[name] = m
	paused = false
	g.queue_free()
	for i in 3: await process_frame
	PerfSaver.active = false

func _snap(file: String) -> String:
	for i in 4: await process_frame
	var img := root.get_texture().get_image()
	img.save_png(TMP + file)
	print("saved ", file, " ", img.get_size())
	return TMP + file
