extends SceneTree
## Big map Task 3 screenshots (docs/preview/bigmap/game_*.png) of the test ground's big-map path, landscape phone
## 1688x780, plus checks that need a real renderer:
## - ground pixels: the world view (props and hero hidden) equals the ground rebuilt from the atlas + flips pixel
##   for pixel at the start and the wood bridge (no seams, no wrong flips, no missing tiles);
## - canvas culling: draw calls with every prop shown vs. only the props near the view (off-screen props cost none).
## Prints the BigMap build and route-grid times. Exit 1 on a failed check.
## xvfb-run -a godot --path . --rendering-driver opengl3 --script tests/screenshots_bigmap.gd

const OUT := "res://docs/preview/bigmap/"
const SAVE := "user://shots_bigmap_save.json"
const SETTINGS := "user://shots_bigmap_settings.json"
const SIZE := Vector2i(1688, 780)
var g: Node2D
var failed := false

func _initialize() -> void:
	_run()
	_watchdog()

func _watchdog() -> void:
	await create_timer(120.0).timeout
	print("watchdog: giving up")
	quit(1)

func _clean() -> void:
	for f in [SAVE, SETTINGS, SaveGame.marker_path(SAVE)]:
		if FileAccess.file_exists(f): DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

func _snap(name: String) -> void:
	for i in 4: await process_frame
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + name))
	print("saved ", name, " ", img.get_size())

## Hero (physics off) at p; the camera follows.
func _at(p: Vector2) -> void:
	g.hero.global_position = p
	g.hero.reset_physics_interpolation()
	g.cam.reset_physics_interpolation()
	for i in 8: await physics_frame

func _run() -> void:
	_clean()
	DisplayServer.window_set_size(SIZE)
	root.size = SIZE
	g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = SAVE
	g.settings_path = SETTINGS
	g.use_big_map = true
	root.add_child(g)
	_time_parts()
	await process_frame
	g.hero.set_physics_process(false)
	g.hud.touch_ui.visible = true
	g.hud.toast.visible = false
	g.hud.layout(root.get_visible_rect().size)
	var w: BigWorld = g.big
	await _at(w.start())
	_check_ground("start")
	await _snap("game_start.png")
	var deck := _deck(w, "bridge_wood")
	await _at(deck.get_center() + Vector2(0, 4))
	_check_ground("wood bridge")
	await _snap("game_bridge.png")
	await _culling()
	# temple: a stand-in hero behind chedi_01 (feet above its foot line), the hero in front of it
	var chedi := _prop(w, "chedi_01")
	var twin: Hero = g.HERO_SCENE.instantiate()
	g.world.add_child(twin)
	twin.setup_sprites()
	twin.set_physics_process(false)
	twin.global_position = chedi + Vector2(44, -18)     # lower body behind the base, head above it
	twin.facing = 0
	await _at(chedi + Vector2(-20, 26))
	await _snap("game_temple.png")
	twin.queue_free()
	await _at(w.arena_centre() + Vector2(0, 60))
	await _snap("game_arena.png")
	_clean()
	quit(1 if failed else 0)

func _time_parts() -> void:
	var w := BigWorld.open()
	var t0 := Time.get_ticks_usec()
	var bm := BigMap.new()
	bm.build(w)
	var t1 := Time.get_ticks_usec()
	w.make_nav()
	var t2 := Time.get_ticks_usec()
	print("BigWorld: BigMap.build %.0f ms (tiles %d, props %d + floor %d, collider boxes %d), make_nav %.0f ms" %
		[(t1 - t0) / 1000.0, bm.ground.get_used_cells().size(), bm.prop_sprites.size(), bm.floor_sprites.size(), bm.box_count, (t2 - t1) / 1000.0])
	bm.free()

## The world view with props and hero hidden must equal the ground rebuilt from the atlas, pixel for pixel.
func _check_ground(where: String) -> void:
	var bm: BigMap = g.big_map
	bm.floor_layer.visible = false
	for s in bm.prop_sprites: s.visible = false
	g.hero.visible = false
	g.lock_ring.visible = false
	RenderingServer.force_draw(false)
	var img: Image = g.world_vp.get_texture().get_image()
	bm.floor_layer.visible = true
	for s in bm.prop_sprites: s.visible = true
	g.hero.visible = true
	img.convert(Image.FORMAT_RGBA8)
	# where the renderer put the view (snap_2d_transforms_to_pixel rounds a half-pixel camera; try both ways)
	var o: Vector2 = -g.world_vp.canvas_transform.origin
	var best := []
	for origin in ([o] if o == o.round() else [o.floor(), o.ceil()]):
		var res := _ground_diff(img, origin)
		if best.is_empty() or res[0] < best[0]: best = res + [origin]
	if best[0] > 0:
		print("FAIL ground %s: %d of %d pixels differ, e.g. %s" % [where, best[0], img.get_width() * img.get_height(), best[1]])
		failed = true
	else:
		print("ground %s: %d px match the atlas rebuild (view %s at %s, camera origin %s)" % [where, img.get_width() * img.get_height(), img.get_size(), best[2], o])

## [pixels differing from the atlas rebuild, the first difference] for the view image img whose top-left is origin.
func _ground_diff(img: Image, origin: Vector2) -> Array:
	var w: BigWorld = g.big
	var atlas: Image = (load(String(w.atlas().file)) as Texture2D).get_image()
	atlas.convert(Image.FORMAT_RGBA8)
	var cols: int = w.atlas().cols
	var ground := w.ground()
	var flip := w.flip()
	var tiles := {}
	var bad := 0
	var first := ""
	for y in img.get_height():
		for x in img.get_width():
			var wp := Vector2i(int(origin.x) + x, int(origin.y) + y)
			var i := (wp.y / 32) * 128 + wp.x / 32
			var key := ground[i] * 4 + flip[i]
			if not tiles.has(key):
				var t := atlas.get_region(Rect2i((ground[i] % cols) * 32, (ground[i] / cols) * 32, 32, 32))
				if flip[i] & 1: t.flip_x()
				if flip[i] & 2: t.flip_y()
				tiles[key] = t
			var want: Color = tiles[key].get_pixel(wp.x % 32, wp.y % 32)
			var got := img.get_pixel(x, y)
			if not want.is_equal_approx(got):
				bad += 1
				if first == "": first = "world %s got %s want %s" % [wp, got, want]
	return [bad, first]

## Draw calls in the world view with all props shown vs. with only the props whose rect meets the view shown.
func _culling() -> void:
	var bm: BigMap = g.big_map
	var view := Rect2(g._view_origin(), Vector2(g.world_vp.size)).grow(8)
	var near := 0
	var calls := []
	for mode in ["all", "near only", "none"]:
		near = 0
		for s in bm.prop_sprites:
			var r := Rect2(s.position + s.offset, s.texture.get_size())
			var on := r.intersects(view)
			if on: near += 1
			s.visible = mode == "all" or (mode == "near only" and on)
		for i in 3: await process_frame
		calls.append(RenderingServer.viewport_get_render_info(g.world_vp.get_viewport_rid(),
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
	for s in bm.prop_sprites: s.visible = true
	print("culling at the bridge: %d props near the view of %d; world-view draw calls all props %d, near only %d, none %d" %
		[near, bm.prop_sprites.size(), calls[0], calls[1], calls[2]])
	if calls[0] > calls[1] + 2:
		print("FAIL culling: off-screen props add draw calls")
		failed = true

static func _deck(w: BigWorld, prefix: String) -> Rect2:
	for p in w.props():
		if String(p.name).begins_with(prefix) and p.get("deck") != null:
			return Rect2(p.deck[0], p.deck[1], p.deck[2], p.deck[3])
	return Rect2()

static func _prop(w: BigWorld, n: String) -> Vector2:
	for p in w.props():
		if p.name == n: return Vector2(p.x, p.y)
	return Vector2.INF
