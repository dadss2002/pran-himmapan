extends SceneTree
## M5b gem combos screenshots (plan docs/superpowers/plans/2026-11-09-m5b-gem-combos.md; Task 13 adds the rest).
## xvfb-run -a godot --path . --rendering-driver opengl3 --script tests/screenshots_m5b_combos.gd
## Task 5, in game (test ground, seed 7, room c1r0, 1280x720, the real press: Hero.try_skill, its arrows, trails and
## blasts as the game runs them; only the monsters are held still):
##   docs/preview/m5b/fire_fan_ingame.png - ศรพัดเพลิง (piercing, split + fire, char Lv10): 3 fire lines laid by the
##     primary arrows (fire_trail patches: PixelFX T2 campfire, owner 2026-11-09), 0.75 s after the release.
##   docs/preview/m5b/brahmastra_ingame.png - พัดเพลิงพรหมาสตร์ (split + fire + multiply): the same lines and the
##     fire_blast (PixelFX B2 grenade) at each line end, just after the arrows are spent.
##   docs/preview/m5b/brahmastra_saver_ingame.png - the same moment with the PerfSaver on: the fire patches (where the
##     fire burns) and the line-end blasts all stay. (The owner's review set for the new fire: screenshots_m5b_fire_fx.gd.)
##   *_x3.png - the hero and the lines enlarged x3 (nearest).

const OUT := "res://docs/preview/m5b/"
const SAVE := "user://shots_m5b_combos_save.json"
const DT := 1.0 / 60.0

var g: Node2D

func _initialize() -> void:
	_run()
	_watchdog()

func _watchdog() -> void:
	await create_timer(240.0).timeout
	print("watchdog: giving up")
	quit(1)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	await _case("fire_fan", ["split", "fire"], 0.75, false)
	await _case("brahmastra", ["split", "fire", "multiply"], -1.0, false)
	await _case("brahmastra_saver", ["split", "fire", "multiply"], -1.0, true)
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

## after: seconds after the release to hold the frame; < 0 = the frame after the arrows are spent (line end).
func _case(name: String, keys: Array, after: float, saver: bool) -> void:
	if FileAccess.file_exists(SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	await _size(Vector2i(1280, 720))
	g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = SAVE
	g.layout_seed = 7
	g.watch_fps = false                 # the saver only when asked (xvfb's frame rate is not a phone's)
	root.add_child(g)
	for i in 4: await process_frame
	g.go_to("c1r0", "", false)
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
	print(name, ": combo ", b.combo.get("id", "-"), " arrows ", b.arrows, " mult ", b.arrow_mult)
	var wolves := []
	for p in g.packs:
		p.set_physics_process(false)
		p.set_process(false)
		for w in p.wolves: wolves.append(w)
	var mid: Vector2 = g.layout.size_px() / 2.0
	h.global_position = mid + Vector2(-110, 30)
	# monsters: one in the middle line's path near the hero (aim), two on the outer lines, the rest out of view
	var spots := [mid + Vector2(-20, 20), mid + Vector2(40, -20), mid + Vector2(60, 70)]
	for i in wolves.size():
		var w: Wolf = wolves[i]
		w.set_physics_process(false)
		w.health.setup(100000)
		if i < spots.size(): w.global_position = spots[i]
		else:
			w.visible = false
			w.global_position = mid + Vector2(-2000, -2000)
	for i in 4: await physics_frame
	if not h.try_skill("piercing"): print("WARN: try_skill refused")
	var released := -1
	var frames := 0
	while frames < 200:
		await physics_frame
		h.step(DT, Vector2.ZERO)
		for w in wolves: w.tick_burn(DT)
		frames += 1
		if released < 0 and h._released: released = frames
		if released < 0: continue
		var arrows: Array = g.world.get_children().filter(func(c): return c is Arrow and not c.is_queued_for_deletion())
		if after >= 0.0 and frames - released >= int(round(after / DT)): break
		if after < 0.0 and arrows.is_empty() and frames - released > 5:
			for i in 6: await physics_frame        # the blast a few frames in
			break
	var trails: Array = g.world.get_children().filter(func(c): return c is FireTrail)
	var fx := 0
	for t in trails: fx += t.get_child_count()
	var bursts: int = g.world.get_children().filter(func(c): return c is FxSprite and c.animation == "fire_blast").size()
	print(name, ": ", trails.size(), " trails, ", fx, " trail effects, ", bursts, " line-end bursts, saver ", PerfSaver.active)
	paused = true
	var img: Image = await _snap(name + "_ingame.png")
	var c: Vector2 = g.world_to_screen(mid + Vector2(10, 20))
	var k: float = float(img.get_width()) / root.get_visible_rect().size.x
	var box := Rect2i(Vector2i(c * k + Vector2(-230, -130)), Vector2i(420, 240)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var crop := img.get_region(box)
	crop.resize(crop.get_width() * 3, crop.get_height() * 3, Image.INTERPOLATE_NEAREST)
	crop.save_png(ProjectSettings.globalize_path(OUT + name + "_ingame_x3.png"))
	print("saved ", name, "_ingame_x3.png ", crop.get_size())
	paused = false
	g.queue_free()
	for i in 3: await process_frame
	PerfSaver.active = false

func _snap(file: String) -> Image:
	for i in 4: await process_frame
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + file))
	print("saved ", file, " ", img.get_size())
	return img
