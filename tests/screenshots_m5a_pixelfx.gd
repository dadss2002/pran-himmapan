extends SceneTree
## M5a Task 3f (PixelFX, spec docs/superpowers/specs/2026-11-08-pixelfx.md) screenshots.
## xvfb-run -a godot --path . --rendering-driver opengl3 --script tests/screenshots_m5a_pixelfx.gd
## Out: docs/preview/m4b/pixelfx_compare.png - rows 1-7 (numbered circles): the old PixelLab effect, for ① and ⑦
##      the first PixelFX export the owner sent back (c685661: whiter spark / warp on the hero's silhouette), and
##      the effect now, three frames each at game scale (1 game px = 1 screen px; status effects over a boar at
##      their in-game scale, tinted now as in game, the warp over the hero), then one frame before / now at 3x.
##      The c685661 sheets are read from PFX_BEFORE (default /tmp/pfxshots: `git show c685661:assets/fx/...`).
##      docs/preview/m4b/pixelfx_ingame.png - the test ground (seed 7, room c1r0) at 1280x720 with a hit spark
##      mirrored (the monster left of the hero), a crit, a burning and a frozen monster (tinted), a poison mist and
##      a pickup burst, each marked with its number; pixelfx_ingame_x3.png - the middle enlarged x3 (nearest).
##      docs/preview/m4b/pixelfx_warp_ingame_x3.png - the warp in game at 0.0 / 0.15 / 0.30 / 0.45 s of the 0.5 s
##      fade-out, with the fade overlay as the game draws it then (tween held, alpha t / FADE_OUT), round the hero x3.

const OUT := "res://docs/preview/m4b/"
var before_dir := OS.get_environment("PFX_BEFORE") if OS.get_environment("PFX_BEFORE") != "" else "/tmp/pfxshots"
const SAVE := "user://shots_m5a_pixelfx_save.json"
const GRASS := Color("#4e6a3a")
## number, label, old id, new id, frame fractions at 1x, frame fraction at 3x, under (""/"monster"/"hero"),
## c685661 sheet shown as "before" ("" = none), tint of the monster now ("" / "burn" / "frost")
const ROWS := [
	[1, "hit spark  impacts/hit-spark  (now: orange/gold, x1.5)", "pixellab_hit_spark", "hit_spark", [0.0, 0.34, 0.67], 0.0, "", "hit_spark", ""],
	[2, "critical  impacts/crit-hit (old: hit spark)", "pixellab_hit_spark", "crit_hit", [0.05, 0.2, 0.45], 0.1, "", "", ""],
	[3, "poison mist  nature/poison-cloud", "pixellab_poison_mist", "poison_mist", [0.0, 0.33, 0.66], 0.3, "", "", ""],
	[4, "burning  status/burning  + red-orange tint", "pixellab_status_burn", "status_burn", [0.0, 0.33, 0.66], 0.0, "monster", "", "burn"],
	[5, "frozen  status/frozen  + ice-blue tint", "pixellab_status_frost", "status_frost", [0.0, 0.33, 0.66], 0.3, "monster", "", "frost"],
	[6, "pickup  pickups/collect-burst", "pixellab_pickup_pop", "pickup_pop", [0.1, 0.3, 0.55], 0.15, "hero_pick", "", ""],
	[7, "warp  arcane/blink-out, sparkle only (old: exit ring)", "warp_ring", "warp_blink", [0.0, 0.34, 0.67], 0.0, "hero", "warp_blink", ""],
]
const W := 1760
const ROW_H := 240
const MSCALE := 0.85                  # Balance monster_scale
const STATUS := 1.5                   # Wolf.STATUS_FX_SCALE

var g: Node2D
var _mode: Window.ContentScaleMode

func _initialize() -> void:
	_run()
	_watchdog()

func _watchdog() -> void:
	await create_timer(240.0).timeout
	print("watchdog: giving up")
	quit(1)

func _size(s: Vector2i) -> void:
	DisplayServer.window_set_size(s)
	root.size = s
	for i in 6: await process_frame

func _snap(name: String) -> Image:
	for i in 4: await process_frame
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + name))
	print("saved ", name, " ", img.get_size())
	return img

func _circle(parent: Node, at: Vector2, n: int, r := 15.0) -> void:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#ffd36a")
	sb.border_color = Color("#2a1a0a")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(r))
	p.add_theme_stylebox_override("panel", sb)
	p.position = at - Vector2(r, r)
	p.size = Vector2(r, r) * 2
	var l := Label.new()
	l.text = str(n)
	l.add_theme_color_override("font_color", Color("#2a1a0a"))
	l.add_theme_font_size_override("font_size", int(r * 1.2))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = p.size
	p.add_child(l)
	parent.add_child(p)

func _text(parent: Node, at: Vector2, t: String, size := 16, c := Color.WHITE) -> void:
	var l := Label.new()
	l.text = t
	l.position = at
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	parent.add_child(l)

func _tint_mat(tint: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/flash.gdshader")
	m.set_shader_parameter("tint_color", Wolf.BURN_TINT if tint == "burn" else Wolf.FROST_TINT)
	m.set_shader_parameter("tint_amount", Wolf.TINT_AMOUNT)
	return m

## The c685661 export of `id` (the one the owner sent back), as a paused sprite on its anchor; null if missing.
func _before_sprite(id: String, frac: float) -> AnimatedSprite2D:
	var path := before_dir.path_join("c685661_%s.png" % id)
	var mpath := before_dir.path_join("c685661_manifest.json")
	if not FileAccess.file_exists(path) or not FileAccess.file_exists(mpath): return null
	var e: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(mpath))[id]
	var tex := ImageTexture.create_from_image(Image.load_from_file(path))
	var sf := SpriteFrames.new()
	var cols := int(e.get("columns", e.frames))
	for i in int(e.frames):
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2((i % cols) * float(e.cell[0]), floori(float(i) / cols) * float(e.cell[1]), float(e.cell[0]), float(e.cell[1]))
		sf.add_frame("default", at)
	var s := AnimatedSprite2D.new()
	s.sprite_frames = sf
	s.centered = false
	s.offset = -Vector2(e.anchor[0], e.anchor[1])
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.frame = clampi(int(round(frac * (int(e.frames) - 1))), 0, int(e.frames) - 1)
	s.pause()
	return s

func _under(kind: String) -> Node2D:
	var s := Sprite2D.new()
	s.centered = false
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if kind == "monster":
		s.texture = load("res://assets/monsters/boar/pose_south-east.png")
		s.offset = -Vector2(24, 45)
		s.scale = Vector2.ONE * MSCALE
	else:
		var at := AtlasTexture.new()
		at.atlas = load("res://assets/hero/idle_south.png")
		at.region = Rect2(0, 0, 64, 64)
		s.texture = at
		s.offset = -Vector2(32, 54)
	return s

## One effect frame (paused) at `at` (its origin), with what it sits on, all scaled by k. before = the c685661
## sheet of that id instead of today's; tint = the monster's status tint now.
func _cell(parent: Node, at: Vector2, id: String, frac: float, under: String, k: float, before := false, tint := "") -> void:
	var n := Node2D.new()
	n.position = at
	n.scale = Vector2.ONE * k
	parent.add_child(n)
	var fx_at := Vector2.ZERO
	if under == "monster" or under == "hero":
		var u := _under(under)
		if tint != "": u.material = _tint_mat(tint)
		n.add_child(u)
	if under == "hero_pick":
		n.add_child(_under("hero"))
		fx_at = Vector2(0, -20)                # where the game plays the pickup burst
	if before:
		var b := _before_sprite(id, frac)
		if b == null: return
		if id == "hit_spark": b.position = Vector2(0, -12)
		n.add_child(b)
		return
	var f := FxSprite.make(id, true)
	f.position = fx_at
	if under == "monster": f.scale = Vector2.ONE * STATUS * MSCALE
	if id.begins_with("pixellab_hit") or id == "hit_spark" or id == "crit_hit": f.position = Vector2(0, -12)
	n.add_child(f)
	f.animation = id
	f.frame = clampi(int(round(frac * (f.sprite_frames.get_frame_count(id) - 1))), 0, f.sprite_frames.get_frame_count(id) - 1)
	f.pause()

func _compare() -> void:
	_mode = root.content_scale_mode
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED     # 1 board px = 1 screen px
	await _size(Vector2i(W, 60 + ROW_H * ROWS.size()))
	var board := Node2D.new()
	root.add_child(board)
	var bg := ColorRect.new()
	bg.color = GRASS
	bg.size = Vector2(W, 60 + ROW_H * ROWS.size())
	board.add_child(bg)
	_text(board, Vector2(60, 8), "PixelLab (old), game scale", 17)
	_text(board, Vector2(345, 8), "PixelFX c685661 (sent back)", 17)
	_text(board, Vector2(660, 8), "PixelFX now, game scale", 17)
	_text(board, Vector2(1000, 8), "before x3 (c685661 / PixelLab)", 17)
	_text(board, Vector2(1450, 8), "now x3", 17)
	for i in ROWS.size():
		var row: Array = ROWS[i]
		var y := 60 + i * ROW_H
		if i % 2 == 1:
			var stripe := ColorRect.new()
			stripe.color = GRASS.lightened(0.06)
			stripe.position = Vector2(0, y)
			stripe.size = Vector2(W, ROW_H)
			board.add_child(stripe)
		_circle(board, Vector2(28, y + 26), row[0])
		_text(board, Vector2(50, y + 12), row[1], 15)
		var base := y + 150.0                  # the effects' origin line (feet / ground)
		var bid: String = row[7]
		for j in 3:
			_cell(board, Vector2(100 + j * 90, base), row[2], row[4][j], row[6], 1.0)
			if bid != "": _cell(board, Vector2(390 + j * 90, base), bid, row[4][j], row[6], 1.0, true)
			_cell(board, Vector2(700 + j * 90, base), row[3], row[4][j], row[6], 1.0, false, row[8])
		if bid != "": _cell(board, Vector2(1130, base + 60), bid, row[5], row[6], 3.0, true)
		else: _cell(board, Vector2(1130, base + 60), row[2], row[5], row[6], 3.0)
		_cell(board, Vector2(1560, base + 60), row[3], row[5], row[6], 3.0, false, row[8])
	await _snap("pixelfx_compare.png")
	board.queue_free()
	root.content_scale_mode = _mode
	await process_frame

func _ingame() -> void:
	if FileAccess.file_exists(SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	await _size(Vector2i(1280, 720))
	g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = SAVE
	g.layout_seed = 7
	root.add_child(g)
	for i in 4: await process_frame
	g.go_to("c1r0", "", false)
	for i in 4: await process_frame
	var wolves := []
	for p in g.packs:
		p.set_physics_process(false)
		p.set_process(false)
		for w in p.wolves: wolves.append(w)
	g.hero.set_physics_process(false)
	var mid: Vector2 = g.layout.size_px() / 2.0
	g.hero.global_position = mid + Vector2(-90, 40)
	var spots := [mid + Vector2(-20, -20), mid + Vector2(40, -20), mid + Vector2(-20, 40), mid + Vector2(40, 40)]
	for i in wolves.size():
		var w: Wolf = wolves[i]
		w.set_physics_process(false)
		if i < 4: w.global_position = spots[i]
		else: w.visible = false              # only the four shown monsters
	if wolves.size() >= 2:
		wolves[0].global_position = mid + Vector2(-150, -10)   # left of the hero: its spark flies left (mirrored)
		wolves[1].global_position = mid + Vector2(50, -40)
	for i in 6: await process_frame
	var marks := []            # [number, world point]
	if wolves.size() >= 4:
		g._on_wolf_hit(wolves[0], 7, false)
		g._on_wolf_hit(wolves[1], 15, true)
		marks.append([1, wolves[0].hurt_point() + Vector2(-8, -40)])
		marks.append([2, wolves[1].hurt_point() + Vector2(34, -18)])
		wolves[2].apply_status("burn", 1.0)
		wolves[3].apply_status("slow")
		wolves[2]._update_status_fx()
		wolves[3]._update_status_fx()
		marks.append([4, wolves[2].global_position + Vector2(-28, -14)])
		marks.append([5, wolves[3].global_position + Vector2(28, -14)])
	for w in wolves: w._update_status_fx()                 # tints as the game sets them
	var cloud = load("res://scripts/monsters/hazard_cloud.gd").new()
	cloud.setup(mid + Vector2(110, 90), 32.0, 99.0, 1, 3.0, null)
	cloud.set_physics_process(false)
	g.world.add_child(cloud)
	marks.append([3, cloud.position + Vector2(-50, -8)])
	g._fx("pickup_pop", g.hero.global_position + Vector2(0, -20))
	marks.append([6, g.hero.global_position + Vector2(-36, -24)])
	# freeze every effect on a telling frame
	for c in g.stage.get_children() + g.world.get_children():
		_freeze(c)
	for w in wolves:
		_freeze(w)
	_freeze(cloud)
	await process_frame
	var layer := CanvasLayer.new()
	layer.layer = 100
	root.add_child(layer)
	for m in marks:
		var s: Vector2 = g.world_to_screen(m[1])
		_circle(layer, s, m[0], 12.0)
	var img: Image = await _snap("pixelfx_ingame.png")
	var c: Vector2 = g.world_to_screen(mid)
	var k: float = float(img.get_width()) / root.get_visible_rect().size.x
	var box := Rect2i(Vector2i(c * k + Vector2(-260, -190)), Vector2i(460, 300)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	var crop := img.get_region(box)                     # image px round the middle, enlarged x3
	crop.resize(crop.get_width() * 3, crop.get_height() * 3, Image.INTERPOLATE_NEAREST)
	crop.save_png(ProjectSettings.globalize_path(OUT + "pixelfx_ingame_x3.png"))
	print("saved pixelfx_ingame_x3.png ", crop.get_size())
	layer.queue_free()

## The warp in game: the hero on an exit ring of c1r0, warp_through, the fade tween held; for each moment t the fade
## overlay alpha is t / FADE_OUT (the tween is linear) and the sparkle shows its frame at t; the region round the
## hero (x3) of four shots side by side, each labelled with its time and the overlay alpha.
func _warp_moments() -> void:
	for c in g.stage.get_children():
		if c is FxSprite and not c.keep: c.free()
	var w: Warp = g.warps[0]
	g.hero.global_position = w.position + Vector2(0, 0)
	g.hero.reset_physics_interpolation()
	for i in 4: await process_frame
	g.warp_through(w)
	if g._fade_tween: g._fade_tween.pause()
	var fx: FxSprite = g._warp_fx
	var tiles: Array = []
	for t in [0.0, 0.15, 0.30, 0.45]:
		g.fade.color.a = t / g.FADE_OUT
		if fx:
			fx.pause()
			fx.frame = mini(int(t * fx.sprite_frames.get_animation_speed("warp_blink") + 0.0001), fx.sprite_frames.get_frame_count("warp_blink") - 1)
		for i in 3: await process_frame
		var img := root.get_texture().get_image()
		var c: Vector2 = g.world_to_screen(g.hero.global_position + Vector2(0, -24))
		var k: float = float(img.get_width()) / root.get_visible_rect().size.x
		var box := Rect2i(Vector2i(c * k) - Vector2i(110, 100), Vector2i(220, 170)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		var crop := img.get_region(box)
		crop.resize(crop.get_width() * 3, crop.get_height() * 3, Image.INTERPOLATE_NEAREST)
		tiles.append([t, crop])
	var tw: int = tiles[0][1].get_width()
	var th: int = tiles[0][1].get_height()
	var out := Image.create(tw * 4 + 30, th, false, Image.FORMAT_RGBA8)
	out.fill(Color("#202020"))
	for i in tiles.size(): out.blit_rect(tiles[i][1], Rect2i(Vector2i.ZERO, tiles[i][1].get_size()), Vector2i(i * (tw + 10), 0))
	out.save_png(ProjectSettings.globalize_path(OUT + "pixelfx_warp_ingame_x3.png"))
	print("saved pixelfx_warp_ingame_x3.png ", out.get_size(), " times ", tiles.map(func(x): return x[0]), " frame shown ",
		[0.0, 0.15, 0.30, 0.45].map(func(t): return int(t * 14 + 0.0001)))

func _freeze(n: Node) -> void:
	if n is FxSprite:
		var id: String = n.animation
		var cnt: int = n.sprite_frames.get_frame_count(id)
		var frac: float = {"hit_spark": 0.15, "crit_hit": 0.12, "pickup_pop": 0.2}.get(id, 0.3)
		n.frame = int(frac * (cnt - 1))
		n.pause()
	for c in n.get_children(): _freeze(c)

func _run() -> void:
	await process_frame
	await _compare()
	await _ingame()
	await _warp_moments()
	quit(0)
