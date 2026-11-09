extends RefCounted
## M5a Task 3f: PixelFX effects (spec docs/superpowers/specs/2026-11-08-pixelfx.md). Seven effects are PixelFX
## sheets (tools/pixelfx_export.py), the PixelLab ones they replace stay in the manifest as pixellab_<id>.

const MANIFEST := "res://assets/fx/manifest.json"
const LICENCE := "res://assets/fx/PIXELFX_LICENSE.txt"
const CREDITS := "res://CREDITS.md"
const HERO_W := 48                                   # CLAUDE.md: hero 48x48
## game id -> PixelFX effect id (the owner's picks ① .. ⑦)
const PICKS := {"hit_spark": "impacts/hit-spark", "crit_hit": "impacts/crit-hit", "poison_mist": "nature/poison-cloud",
	"status_burn": "status/burning", "status_frost": "status/frozen", "pickup_pop": "pickups/collect-burst",
	"warp_blink": "arcane/blink-out"}
const REPLACED := ["hit_spark", "poison_mist", "status_burn", "status_frost", "pickup_pop"]   # were PixelLab
const ONE_SHOTS := ["hit_spark", "crit_hit", "pickup_pop", "warp_blink"]
const TMP_SAVE := "user://test_pixelfx_save.json"

var tree: SceneTree

func setup(t: SceneTree) -> void:
	tree = t

func _man() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))

func _img(e: Dictionary) -> Image:
	var tex: Texture2D = load("res://assets/fx/" + String(e.sheet))
	return tex.get_image()

func _frame(img: Image, e: Dictionary, i: int) -> Image:
	var cols := int(e.get("columns", e.frames))
	return img.get_region(Rect2i((i % cols) * int(e.cell[0]), (i / cols) * int(e.cell[1]), int(e.cell[0]), int(e.cell[1])))

# ---------- manifest ----------

## Every entry: cell, frames, fps, anchor inside the cell, loop, its sheet file, and the sheet is exactly
## columns x rows cells (PixelFX sheets <= 2048 px a side for phones; PixelLab's lunge_warning strip is 2058).
func test_manifest_entries_are_valid():
	var man := _man()
	for id in man:
		if String(id).begins_with("_"): continue
		var e: Dictionary = man[id]
		for k in ["cell", "frames", "fps", "anchor", "loop"]:
			if not e.has(k): return "%s: no %s" % [id, k]
		if int(e.cell[0]) <= 0 or int(e.cell[1]) <= 0 or int(e.frames) <= 0 or float(e.fps) <= 0.0: return "%s: bad numbers" % id
		if not (e.loop is bool): return "%s: loop not a bool" % id
		if float(e.anchor[0]) < 0 or float(e.anchor[1]) < 0 or float(e.anchor[0]) > float(e.cell[0]) or float(e.anchor[1]) > float(e.cell[1]):
			return "%s: anchor %s outside cell %s" % [id, e.anchor, e.cell]
		var path := "res://assets/fx/" + String(e.get("sheet", String(id) + ".png"))
		if not ResourceLoader.exists(path): return "%s: %s missing" % [id, path]
		var tex: Texture2D = load(path)
		var cols := int(e.get("columns", e.frames))
		var rows := ceili(float(e.frames) / cols)
		var want := Vector2i(cols * int(e.cell[0]), rows * int(e.cell[1]))
		if Vector2i(tex.get_size()) != want: return "%s: sheet %s, want %s" % [id, tex.get_size(), want]
		if e.has("pixelfx") and (want.x > 2048 or want.y > 2048): return "%s: sheet %s over 2048 px" % [id, want]
	return ""

## The seven picks are PixelFX sheets with their metadata (id, commit a841596, the old sheet their palette came
## from), at 14-16 fps; the PixelLab effects they replace are kept as pixellab_<id>.
func test_replaced_effects_are_pixelfx_sheets():
	var man := _man()
	for id in PICKS:
		if not man.has(id): return "%s missing" % id
		var e: Dictionary = man[id]
		if not (e.get("pixelfx") is Dictionary): return "%s: no pixelfx metadata" % id
		if String(e.pixelfx.id) != PICKS[id] or String(e.pixelfx.commit) != "a841596": return "%s: pixelfx %s" % [id, e.pixelfx]
		if not String(e.sheet).begins_with("pfx_"): return "%s: sheet %s" % [id, e.sheet]
		if float(e.fps) < 14.0 or float(e.fps) > 16.0: return "%s: %s fps (want 14-16)" % [id, e.fps]
		if not ResourceLoader.exists("res://assets/fx/" + String(e.pixelfx.palette_from)): return "%s: palette source missing" % id
		if e.has("pixellab"): return "%s: still says pixellab" % id
	for id in REPLACED:
		var old: Dictionary = man.get("pixellab_" + id, {})
		if old.is_empty() or not old.has("pixellab") or String(old.get("replaced_by", "")) != id: return "pixellab_%s not kept" % id
		if String(old.sheet) != id + ".png": return "pixellab_%s sheet %s" % [id, old.get("sheet")]
	if man.get("warp_ring", {}).has("pixelfx"): return "the exit ring should stay PixelLab"
	return ""

## Spec sizes: crit no wider than 2x the hero, poison mist about the old mist's width; none bigger than 2x the hero.
func test_sheet_sizes_within_spec():
	var man := _man()
	if int(man.crit_hit.cell[0]) > 2 * HERO_W: return "crit %d px wide (max %d)" % [man.crit_hit.cell[0], 2 * HERO_W]
	var old_w := float(man.pixellab_poison_mist.cell[0])
	var w := float(man.poison_mist.cell[0])
	if w < old_w * 0.8 or w > old_w * 1.2: return "poison mist %d px wide, old %d" % [w, old_w]
	for id in PICKS:
		var e: Dictionary = man[id]
		var k := 1.5 if String(id).begins_with("status") else 1.0      # status FX are drawn at Wolf.STATUS_FX_SCALE
		if float(e.cell[0]) * k > 2 * HERO_W or float(e.cell[1]) * k > 2 * HERO_W: return "%s cell %s too big" % [id, e.cell]
	return ""

## Recoloured from the old effect: the ramp handed to PixelFX is exactly the old sheet's colours (dark to light),
## and the new sheet's mean hue (weighted by alpha x saturation; PixelFX's light brightens pixels past the ramp)
## is within 35 degrees of the old one. Poison stays purple.
func _hue(img: Image) -> float:
	var x := 0.0
	var y := 0.0
	for py in img.get_height():
		for px in img.get_width():
			var c := img.get_pixel(px, py)
			if c.a <= 0.0: continue
			var w := c.a * c.s
			x += w * cos(TAU * c.h)
			y += w * sin(TAU * c.h)
	return fposmod(rad_to_deg(atan2(y, x)), 360.0)

func test_palette_comes_from_the_old_effect():
	var man := _man()
	for id in PICKS:
		var e: Dictionary = man[id]
		var old: Image = (load("res://assets/fx/" + String(e.pixelfx.palette_from)) as Texture2D).get_image()
		var pal := {}
		for y in old.get_height():
			for x in old.get_width():
				var c := old.get_pixel(x, y)
				if c.a >= 0.63: pal["#" + c.to_html(false)] = true
		var ramp: Array = e.pixelfx.options.palette
		if ramp.size() != pal.size(): return "%s: ramp %d colours, old sheet %d" % [id, ramp.size(), pal.size()]
		var last := -1.0
		for h in ramp:
			if not pal.has(String(h)): return "%s: ramp colour %s not in %s" % [id, h, e.pixelfx.palette_from]
			var l := Color(String(h)).get_luminance()
			if l < last: return "%s: ramp not dark to light" % id
			last = l
		var ho := _hue(old)
		var hn := _hue(_img(e))
		var d := absf(fposmod(hn - ho + 180.0, 360.0) - 180.0)
		if d > 35.0: return "%s: hue %.0f, old %.0f" % [id, hn, ho]
		if id == "poison_mist" and (hn < 260.0 or hn > 340.0): return "poison mist hue %.0f is not purple" % hn
	return ""

## ④ ⑤ sit on our monsters: the body is cut away. Round the feet (the middle of the body) every frame is empty,
## and no frame has a solid upright figure: no column of 12+ opaque pixels in the middle third.
func test_status_effects_have_no_body():
	var man := _man()
	for id in ["status_burn", "status_frost"]:
		var e: Dictionary = man[id]
		if not bool(e.pixelfx.body_cut): return "%s: body not cut" % id
		var img := _img(e)
		var ax := int(e.anchor[0])
		var ay := int(e.anchor[1])
		for i in int(e.frames):
			var f := _frame(img, e, i)
			for y in range(ay - 16, ay - 4):
				for x in range(ax - 5, ax + 6):
					if f.get_pixel(x, y).a > 0.0: return "%s frame %d: pixel at %d,%d on the body" % [id, i, x - ax, y - ay]
			for x in range(int(e.cell[0]) / 3, int(e.cell[0]) * 2 / 3):
				var run := 0
				for y in int(e.cell[1]):
					run = run + 1 if f.get_pixel(x, y).a > 0.9 else 0
					if run >= 12: return "%s frame %d: a solid column at x %d" % [id, i, x]
	return ""

# ---------- FxSprite ----------

## FxSprite reads "sheet" and "columns": frame i is cell (i % columns, i / columns) of that file.
func test_fx_sprite_reads_sheet_and_grid():
	var man := _man()
	for id in ["poison_mist", "pickup_pop", "lock_on"]:
		var e: Dictionary = man[id]
		var s := FxSprite.make(id)
		var sf := s.sprite_frames
		if sf.get_frame_count(id) != int(e.frames): s.free(); return "%s: %d frames" % [id, sf.get_frame_count(id)]
		if absf(sf.get_animation_speed(id) - float(e.fps)) > 0.01 or sf.get_animation_loop(id) != bool(e.loop): s.free(); return "%s: speed/loop" % id
		var cols := int(e.get("columns", e.frames))
		for i in [0, int(e.frames) - 1]:
			var at: AtlasTexture = sf.get_frame_texture(id, i)
			var want := Rect2((i % cols) * float(e.cell[0]), (i / cols) * float(e.cell[1]), float(e.cell[0]), float(e.cell[1]))
			if at.region != want: s.free(); return "%s frame %d region %s, want %s" % [id, i, at.region, want]
			if at.atlas.resource_path != "res://assets/fx/" + String(e.get("sheet", id + ".png")): s.free(); return "%s: atlas %s" % [id, at.atlas.resource_path]
		if s.offset != -Vector2(e.anchor[0], e.anchor[1]): s.free(); return "%s offset %s" % [id, s.offset]
		s.free()
	if not FxSprite.is_pixelfx("hit_spark") or FxSprite.is_pixelfx("warp_ring"): return "is_pixelfx wrong"
	return ""

## A flipped one-shot mirrors round its anchor (the hit flies along the blow).
func test_flipped_effect_keeps_its_anchor():
	var e: Dictionary = _man().hit_spark
	var s := FxSprite.make("hit_spark")
	s.face(true)
	var r := ""
	if not s.flip_h: r = "not flipped"
	elif s.offset != Vector2(-(float(e.cell[0]) - float(e.anchor[0])), -float(e.anchor[1])): r = "flipped offset %s" % s.offset
	s.face(false)
	if r == "" and (s.flip_h or s.offset != -Vector2(e.anchor[0], e.anchor[1])): r = "unflipped offset %s" % s.offset
	s.free()
	return r

## One-shots free themselves when they end; loops stay until their owner frees them. No leak.
func test_effects_play_and_free_themselves():
	var holder := Node2D.new()
	tree.root.add_child(holder)
	var shots := []
	for id in ONE_SHOTS:
		var s := FxSprite.make(id)
		s.speed_scale = 40.0
		holder.add_child(s)
		s.play(id)
		shots.append(s)
	var loops := []
	for id in ["status_burn", "status_frost", "poison_mist"]:
		var s := FxSprite.make(id, true)
		s.speed_scale = 40.0
		holder.add_child(s)
		s.play(id)
		loops.append(s)
	for i in 60: await tree.process_frame
	var r := ""
	for s in shots:
		if is_instance_valid(s): r = "%s still there after it ended" % s.animation
	for s in loops:
		if r == "" and (not is_instance_valid(s) or not s.is_playing()): r = "a loop stopped"
	if r == "" and holder.get_child_count() != loops.size(): r = "%d children left (want %d)" % [holder.get_child_count(), loops.size()]
	holder.queue_free()
	await tree.process_frame
	return r

# ---------- in game ----------

func _ground() -> Node2D:
	if FileAccess.file_exists(TMP_SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))
	var g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = TMP_SAVE
	g.layout_seed = 1
	tree.root.add_child(g)
	await tree.process_frame
	await tree.process_frame
	return g

func _fx_in(g: Node2D, id: String) -> Array:
	var out := []
	for c in g.stage.get_children():
		if c is FxSprite and c.animation == id: out.append(c)
	return out

## ① ②: a normal hit shows the hit spark, a critical shows the crit instead, at the hurt point, flipped when the
## blow goes left (hero on the right).
func test_hit_and_crit_at_the_hurt_point():
	var g = await _ground()
	g.go_to("c1r0", "", false)
	var w: Wolf = g.packs[0].wolves[0]
	var r := ""
	g.hero.global_position = w.global_position + Vector2(-60, 0)
	g._on_wolf_hit(w, 5, false)
	var hs := _fx_in(g, "hit_spark")
	if hs.size() != 1 or not _fx_in(g, "crit_hit").is_empty(): r = "normal hit: %d sparks, %d crits" % [hs.size(), _fx_in(g, "crit_hit").size()]
	elif hs[0].position != w.hurt_point(): r = "spark at %s, hurt point %s" % [hs[0].position, w.hurt_point()]
	elif hs[0].flip_h: r = "spark flipped for a blow going right"
	if r == "":
		g.hero.global_position = w.global_position + Vector2(60, 0)
		g._on_wolf_hit(w, 9, true)
		var cs := _fx_in(g, "crit_hit")
		if cs.size() != 1 or _fx_in(g, "hit_spark").size() != 1: r = "crit: %d crits, %d sparks (want 1, the old 1)" % [cs.size(), _fx_in(g, "hit_spark").size()]
		elif cs[0].position != w.hurt_point(): r = "crit at %s" % cs[0].position
		elif not cs[0].flip_h: r = "crit not flipped for a blow going left"
	g.queue_free()
	await tree.process_frame
	return r

## ④ ⑤ on a monster: the PixelFX loops at its feet, at STATUS_FX_SCALE x size, gone when the status ends.
func test_burn_and_frost_on_a_monster():
	var w: Wolf = load("res://scenes/wolf.tscn").instantiate()
	tree.root.add_child(w)
	w.setup()
	w.apply_status("burn", 1.0)
	w.apply_status("slow")
	w._update_status_fx()
	var r := ""
	for pair in [[w._burn_fx, "status_burn"], [w._frost_fx, "status_frost"]]:
		var fx: FxSprite = pair[0]
		if r != "": break
		if fx == null: r = "%s not shown" % pair[1]
		elif fx.animation != pair[1] or not fx.is_playing(): r = "%s: playing %s" % [pair[1], fx.animation]
		elif fx.position != Vector2.ZERO: r = "%s not at the feet" % pair[1]
		elif not fx.scale.is_equal_approx(Vector2.ONE * Wolf.STATUS_FX_SCALE * Wolf.size_scale()): r = "%s scale %s" % [pair[1], fx.scale]
		elif (fx.sprite_frames.get_frame_texture(pair[1], 0) as AtlasTexture).atlas.resource_path.get_file() != "pfx_%s.png" % pair[1]: r = "%s not the PixelFX sheet" % pair[1]
	w.status.clear()
	w._update_status_fx()
	if r == "" and (w._burn_fx != null or w._frost_fx != null): r = "status effects left after the status ended"
	w.queue_free()
	await tree.process_frame
	return r

## ③ the poison cloud's mist and ⑥ the pickup are the PixelFX sheets through their old ids.
func test_mist_and_pickup_use_pixelfx():
	var c = load("res://scripts/monsters/hazard_cloud.gd").new()
	c.setup(Vector2(100, 100), 32.0, 2.0, 1, 3.0, null)
	var r := "no mist"
	for ch in c.get_children():
		if ch is FxSprite and ch.animation == "poison_mist":
			var p: String = (ch.sprite_frames.get_frame_texture("poison_mist", 0) as AtlasTexture).atlas.resource_path
			r = "" if p.get_file() == "pfx_poison_mist.png" else "mist sheet %s" % p
	c.free()
	if r != "": return r
	var s := FxSprite.make("pickup_pop")
	r = "" if (s.sprite_frames.get_frame_texture("pickup_pop", 0) as AtlasTexture).atlas.resource_path.get_file() == "pfx_pickup_pop.png" else "pickup not PixelFX"
	s.free()
	return r

## ⑦ walking into an exit: the blink-out plays on the hero's feet as the screen fades, and is gone in the new room.
## The exit ring itself stays the PixelLab warp_ring.
func test_warp_blinks_the_hero_out():
	var g = await _ground()
	var h: Hero = g.hero
	h.set_physics_process(false)
	for i in 4: await tree.process_frame
	var r := ""
	if g.warps.is_empty() or g.warps[0].ring == null or g.warps[0].ring.animation != "warp_ring": r = "exit ring changed"
	var w: Warp = g.warps[0]
	var from: String = g.room_id
	g.warp_through(w)
	var b := _fx_in(g, "warp_blink")
	if r == "" and b.size() != 1: r = "%d blink effects on warping" % b.size()
	elif r == "" and b[0].position != h.global_position: r = "blink at %s, hero at %s" % [b[0].position, h.global_position]
	elif r == "" and not b[0].is_playing(): r = "blink not playing"
	for i in 90:
		await tree.physics_frame
		if g.room_id != from and not g.warping: break
	if r == "" and g.room_id == from: r = "never warped"
	if r == "":
		await tree.process_frame
		if not _fx_in(g, "warp_blink").is_empty(): r = "blink still in the new room"
	g.queue_free()
	await tree.process_frame
	return r

# ---------- licence ----------

## MIT notice kept (LICENSE + NOTICE), in the export, and a line in the game's credits; no Patch Pixel font.
func test_licence_and_credits():
	if not FileAccess.file_exists(LICENCE): return "no " + LICENCE
	var t := FileAccess.get_file_as_string(LICENCE)
	for s in ["MIT License", "Copyright (c) 2026 Patch", "Copyright (c) 2026 Hugo Duprez", "Permission is hereby granted",
			"Sprite Fusion", "Hollow Crown", "rehan-remade", "a841596"]:
		if not t.contains(s): return "licence file lacks '%s'" % s
	if not FileAccess.file_exists(CREDITS): return "no " + CREDITS
	var c := FileAccess.get_file_as_string(CREDITS)
	for s in ["PixelFX", "MIT", "assets/fx/PIXELFX_LICENSE.txt", "Kenney"]:
		if not c.contains(s): return "credits lack '%s'" % s
	var cfg := FileAccess.get_file_as_string("res://export_presets.cfg")
	if not cfg.contains("assets/fx/PIXELFX_LICENSE.txt"): return "licence not in the export include_filter"
	for d in ["res://assets/fonts", "res://assets/fx"]:
		for f in DirAccess.get_files_at(d):
			if f.to_lower().contains("patch"): return "Patch font file %s/%s" % [d, f]
	return ""
