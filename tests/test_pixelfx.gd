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
## columns x rows cells, no side over 2048 px (phones' WebGL; review B19: lunge_warning was a 2058 px strip).
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
		if want.x > 2048 or want.y > 2048: return "%s: sheet %s over 2048 px" % [id, want]
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

## Recoloured from the old effect: the ramp handed to PixelFX is the old sheet's colours (dark to light), all of
## them but the lightest post.ramp_drop (owner 2026-11-09: the hit spark less white). The new sheet's mean hue is
## within 35 degrees of the old one and its colour strength is at least MIN_CHROMA[id]: both are taken from the
## alpha-weighted colour wheel, every visible pixel weighted by its alpha, so white and pale pixels count (they
## pull the strength down, as they wash the effect out on screen). Poison stays purple.
## Strength (|sum of a x s x hue vector| / sum of a) measured on the shipped sheets: hit_spark 0.82 (c685661 0.32,
## the "too white" one the owner sent back), crit 0.31 (owner: glare stays), mist 0.31, burn 0.73, frost 0.37,
## pickup 0.16 (owner accepted ⑥ as it is; mostly white sparkles), warp 0.44 (c685661 0.29). The floors are those
## less a margin: a guard against a re-export washing an effect out, and the owner's "less white" for ①.
const MIN_CHROMA := {"hit_spark": 0.6, "crit_hit": 0.25, "poison_mist": 0.25, "status_burn": 0.6, "status_frost": 0.3,
	"pickup_pop": 0.12, "warp_blink": 0.35}

func _wheel(img: Image) -> Vector3:
	var x := 0.0
	var y := 0.0
	var aw := 0.0
	for py in img.get_height():
		for px in img.get_width():
			var c := img.get_pixel(px, py)
			if c.a <= 0.0: continue
			aw += c.a
			x += c.a * c.s * cos(TAU * c.h)
			y += c.a * c.s * sin(TAU * c.h)
	return Vector3(fposmod(rad_to_deg(atan2(y, x)), 360.0), Vector2(x, y).length() / maxf(aw, 0.0001), aw)

func _hue(img: Image) -> float:
	return _wheel(img).x

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
		var post = e.pixelfx.get("post")
		var drop := int(post.get("ramp_drop", 0)) if post is Dictionary else 0
		if ramp.size() != pal.size() - drop: return "%s: ramp %d colours, old sheet %d less %d" % [id, ramp.size(), pal.size(), drop]
		var last := -1.0
		for h in ramp:
			if not pal.has(String(h)): return "%s: ramp colour %s not in %s" % [id, h, e.pixelfx.palette_from]
			var l := Color(String(h)).get_luminance()
			if l < last: return "%s: ramp not dark to light" % id
			last = l
		var ho := _hue(old)
		var wn := _wheel(_img(e))
		var hn := wn.x
		if wn.y < float(MIN_CHROMA[id]): return "%s: colour strength %.2f (min %.2f): too white / washed out" % [id, wn.y, MIN_CHROMA[id]]
		var d := absf(fposmod(hn - ho + 180.0, 360.0) - 180.0)
		if d > 35.0: return "%s: hue %.0f, old %.0f" % [id, hn, ho]
		if id == "poison_mist" and (hn < 260.0 or hn > 340.0): return "poison mist hue %.0f is not purple" % hn
	return ""

## ④ ⑤ sit on our monsters: the body is cut away. Round the feet (the middle of the body) every frame is empty,
## and no frame has a solid upright figure: no column of 12+ opaque pixels in the middle third. Review: an empty
## sheet would pass that, so every frame must also show the effect: at least MIN_STATUS_PX pixels of alpha >= 0.5
## (measured minimum: burn 24, frost 71).
const MIN_STATUS_PX := 20
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
			var shown := _opaque(f)
			if shown < MIN_STATUS_PX: return "%s frame %d: only %d visible pixels round the body (min %d)" % [id, i, shown, MIN_STATUS_PX]
			for y in range(ay - 16, ay - 4):
				for x in range(ax - 5, ax + 6):
					if f.get_pixel(x, y).a > 0.0: return "%s frame %d: pixel at %d,%d on the body" % [id, i, x - ax, y - ay]
			for x in range(int(e.cell[0]) / 3, int(e.cell[0]) * 2 / 3):
				var run := 0
				for y in int(e.cell[1]):
					run = run + 1 if f.get_pixel(x, y).a > 0.9 else 0
					if run >= 12: return "%s frame %d: a solid column at x %d" % [id, i, x]
	return ""

func _opaque(f: Image, a_min := 0.5) -> int:
	var n := 0
	for y in f.get_height():
		for x in f.get_width():
			if f.get_pixel(x, y).a >= a_min: n += 1
	return n

## ⑦ owner 2026-11-09: only the green sparkle, no hero ghost. The hero's idle silhouette (idle_south frame 0, his
## feet on the warp's anchor) is laid over every frame; inside its box (+4 px) the frame's pixels of alpha >= 0.5
## must not take his shape: overlap / union with the silhouette (IoU) at most MAX_HERO_IOU. A sparkle ball over his
## chest covers part of him but spills past his outline and leaves the rest; a ghost matches it. Measured: the
## c685661 sheet (blink-out on the hero's own silhouette) 0.79 at its frame 3 (0.61, 0.60 in others); the
## sparkle-only sheet 0.31 at most (its first frame, the spray just after the burst).
const MAX_HERO_IOU := 0.45

func test_warp_sheet_has_no_hero_silhouette():
	var e: Dictionary = _man().warp_blink
	if String(e.pixelfx.options.get("actor", "")).contains("hero idle"): return "warp still rendered on the hero's silhouette"
	var hm: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/hero/manifest.json"))
	var hero: Image = (load("res://assets/hero/idle_south.png") as Texture2D).get_image()
	var hc := Vector2i(int(hm.cell.idle[0]), int(hm.cell.idle[1]))
	var ha := Vector2i(int(hm.anchor.idle[0]), int(hm.anchor.idle[1]))
	var body := {}
	var lo := Vector2i(9999, 9999)
	var hi := Vector2i(-9999, -9999)
	for y in hc.y:
		for x in hc.x:
			if hero.get_pixel(x, y).a <= 0.16: continue
			var p := Vector2i(x, y) - ha
			body[p] = true
			lo = Vector2i(mini(lo.x, p.x), mini(lo.y, p.y))
			hi = Vector2i(maxi(hi.x, p.x), maxi(hi.y, p.y))
	var img := _img(e)
	var anc := Vector2i(int(e.anchor[0]), int(e.anchor[1]))
	var cell := Vector2i(int(e.cell[0]), int(e.cell[1]))
	for i in int(e.frames):
		var f := _frame(img, e, i)
		var both := 0
		var fx := 0
		for y in range(lo.y - 4, hi.y + 5):
			for x in range(lo.x - 4, hi.x + 5):
				var q := Vector2i(x, y) + anc
				if q.x < 0 or q.y < 0 or q.x >= cell.x or q.y >= cell.y or f.get_pixel(q.x, q.y).a < 0.5: continue
				fx += 1
				if body.has(Vector2i(x, y)): both += 1
		var iou := float(both) / float(body.size() + fx - both)
		if iou > MAX_HERO_IOU: return "warp frame %d takes the hero's shape (IoU %.2f, max %.2f)" % [i, iou, MAX_HERO_IOU]
	return ""

## Review: no frame is made that the game never shows. The poison mist lives cloud_time (balance, 2.0 s) and its
## sheet holds that much (within a frame); the warp sparkle lasts the warp fade-out (FADE_OUT, 0.5 s); the hit
## spark, crit and warp end on a frame with something to see (>= 24 pixels of alpha >= 0.5, not a few stray dots).
func test_sheets_hold_only_what_is_shown():
	var man := _man()
	var mist: Dictionary = man.poison_mist
	var ct := Balance.num("monsters.shroom.cloud_time")
	var mt := float(mist.frames) / float(mist.fps)
	if absf(mt - ct) > 1.0 / float(mist.fps) + 0.001: return "mist sheet %.2f s, the cloud lives %.2f s" % [mt, ct]
	var tg = load("res://scripts/dev/test_ground.gd")
	var fade_out: float = tg.FADE_OUT
	var wb: Dictionary = man.warp_blink
	var wt := float(wb.frames) / float(wb.fps)
	if absf(wt - fade_out) > 1.0 / float(wb.fps) + 0.001: return "warp sparkle %.2f s, the fade-out %.2f s" % [wt, fade_out]
	for id in ["hit_spark", "crit_hit", "warp_blink"]:        # ⑥ pickup left as the owner accepted it (fades out)
		var e: Dictionary = man[id]
		var n := _opaque(_frame(_img(e), e, int(e.frames) - 1))
		if n < 24: return "%s: last frame only %d visible pixels (stray dots)" % [id, n]
	return ""

## ① owner 2026-11-09: stronger orange/gold, bigger, less white. Bigger than the c685661 spark (60x50) and still
## smaller than the crit; at most 5 % of its visible pixels near-white (c685661: about 40 %, now 0); its colour is orange/gold
## (alpha-weighted hue 25-50 degrees).
func test_hit_spark_is_stronger_orange():
	var man := _man()
	var e: Dictionary = man.hit_spark
	var c: Dictionary = man.crit_hit
	if int(e.cell[0]) * int(e.cell[1]) <= 60 * 50: return "hit spark cell %s not bigger than the old 60x50" % [e.cell]
	if int(e.cell[0]) > int(c.cell[0]): return "hit spark %d px wide, crit %d" % [e.cell[0], c.cell[0]]
	var img := _img(e)
	var white := 0.0
	var all := 0.0
	for y in img.get_height():
		for x in img.get_width():
			var p := img.get_pixel(x, y)
			if p.a < 0.25: continue
			all += p.a
			if p.s < 0.2 and p.v > 0.88: white += p.a
	if white / all > 0.05: return "hit spark %d %% near-white" % roundi(100 * white / all)
	var h := _wheel(img).x
	if h < 25.0 or h > 50.0: return "hit spark hue %.0f, want orange/gold 25-50" % h
	return ""

# ---------- FxSprite ----------

## Review: a sheet is loaded once and its SpriteFrames made once per effect id; every sprite of that effect shares
## them (the cache keeps the texture alive). Two spawns: same SpriteFrames, same atlas, no second load.
func test_fx_frames_are_cached():
	FxSprite.clear_cache()
	var a := FxSprite.make("hit_spark")
	var loads := FxSprite.sheet_loads
	var b := FxSprite.make("hit_spark")
	var c := FxSprite.make("crit_hit")
	var r := ""
	if a.sprite_frames != b.sprite_frames: r = "two hit sparks with their own SpriteFrames"
	elif (a.sprite_frames.get_frame_texture("hit_spark", 0) as AtlasTexture).atlas != (b.sprite_frames.get_frame_texture("hit_spark", 0) as AtlasTexture).atlas: r = "atlas not shared"
	elif FxSprite.sheet_loads != loads + 1: r = "%d sheet loads for a second hit spark and a crit (want 1, the crit)" % (FxSprite.sheet_loads - loads)
	elif a.sprite_frames == c.sprite_frames: r = "crit shares the hit spark's frames"
	a.free()
	b.free()
	c.free()
	if r == "" and FxSprite.make_frames("hit_spark") == null: r = "cache dropped the frames when its sprites were freed"
	return r


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

## Review: every one-shot effect on the stage belongs to the room it played in: a room change (exit, waypoint,
## new room) frees hit sparks, crits, pickups, level-ups and chain zaps; kept effects (the lock ring) stay.
func test_room_change_frees_one_shots():
	var g = await _ground()
	var r := ""
	for id in ["hit_spark", "crit_hit", "pickup_pop", "level_up", "warp_blink"]:
		var f: FxSprite = g._fx(id, g.hero.global_position)
		if f: f.speed_scale = 0.01           # still playing at the room change
	var z := FxSprite.make("chain_zap")
	g.world.add_child(z)
	z.play("chain_zap")
	var before := _one_shots(g)
	if before < 6: r = "setup: %d one-shots" % before
	g.go_to("c1r0", "", false)
	if r == "" and _one_shots(g) != 0: r = "%d one-shot effects left after the room change" % _one_shots(g)
	elif r == "" and not is_instance_valid(g.lock_ring): r = "the lock ring was freed"
	g.queue_free()
	await tree.process_frame
	return r

func _one_shots(g: Node2D) -> int:
	var n := 0
	for c in g.stage.get_children() + g.world.get_children():
		if c is FxSprite and is_instance_valid(c) and not c.is_queued_for_deletion() and not c.keep: n += 1
	return n

## Review: a burn tick is not a blow: health.damaged fires for it (its number shows), but no directional hit spark
## or crit flies off the monster as if an arrow had hit it.
func test_burn_ticks_show_no_hit_spark():
	var g = await _ground()
	g.go_to("c1r0", "", false)
	for p in g.packs: p.process_mode = Node.PROCESS_MODE_DISABLED
	var w: Wolf = g.packs[0].wolves[0]
	w.health.setup(100000)
	var numbers := [0]
	w.health.damaged.connect(func(_a, _c): numbers[0] += 1)
	w.apply_status("burn", 5.0)
	for i in 200:
		w.tick_burn(1.0 / 60.0)                   # the burn part of Wolf.step (its pack is stopped)
		if numbers[0] >= 2: break
	var r := ""
	if numbers[0] < 2: r = "setup: %d burn ticks" % numbers[0]
	elif not _fx_in(g, "hit_spark").is_empty() or not _fx_in(g, "crit_hit").is_empty(): r = "a burn tick spawned %d hit sparks / %d crits" % [_fx_in(g, "hit_spark").size(), _fx_in(g, "crit_hit").size()]
	if r == "":
		g._on_wolf_hit(w, 5, false)               # a real blow still sparks
		if _fx_in(g, "hit_spark").size() != 1: r = "a blow after the burn ticks: %d sparks" % _fx_in(g, "hit_spark").size()
	g.queue_free()
	await tree.process_frame
	return r

## Review: under load PerfSaver also sheds the decorative extras: status overlays (the tint stays, so the status is
## still readable), the crit glare (a hit spark instead), the warp sparkle; never gameplay telegraphs (lunge
## warning, the poison cloud hazard) nor the plain hit spark.
func test_saver_sheds_extras_not_telegraphs():
	for id in ["roll_dust", "pickup_pop", "status_burn", "status_frost", "crit_hit", "warp_blink"]:
		if not PerfSaver.decorative(id): return "%s not shed by the saver" % id
	for id in ["lunge_warning", "poison_mist", "hit_spark", "level_up", "warp_ring", "lock_on", "chain_zap"]:
		if PerfSaver.decorative(id): return "the saver sheds %s" % id
	if PerfSaver.fallback("crit_hit") != "hit_spark" or PerfSaver.fallback("pickup_pop") != "": return "fallbacks wrong"
	var g = await _ground()
	g.go_to("c1r0", "", false)
	for p in g.packs: p.process_mode = Node.PROCESS_MODE_DISABLED
	g.saver.on = true
	g.apply_saver()
	var w: Wolf = g.packs[0].wolves[0]
	var r := ""
	g.hero.global_position = w.global_position + Vector2(-60, 0)
	g._on_wolf_hit(w, 9, true)
	if _fx_in(g, "crit_hit").size() != 0 or _fx_in(g, "hit_spark").size() != 1: r = "saver crit: %d crits, %d sparks (want 0, 1)" % [_fx_in(g, "crit_hit").size(), _fx_in(g, "hit_spark").size()]
	if r == "":
		w.apply_status("burn", 1.0)
		w._update_status_fx()
		if w._burn_fx != null: r = "burning overlay shown with the saver on"
		elif w.status_tint().a <= 0.0: r = "no tint with the saver on (status unreadable)"
	if r == "":
		g.saver.on = false
		g.apply_saver()
		w._update_status_fx()
		if w._burn_fx == null: r = "burning overlay not back after the saver"
	if r == "":
		g.saver.on = true
		g.apply_saver()
		w._update_status_fx()
		if w._burn_fx != null: r = "overlay kept when the saver came on mid-burn"
	if r == "":
		g.warp_through(g.warps[0])
		if not _fx_in(g, "warp_blink").is_empty(): r = "warp sparkle shown with the saver on"
		elif not g.warping: r = "saver stopped the warp itself"
	g.queue_free()
	await tree.process_frame
	if PerfSaver.active: return "PerfSaver.active left on after the test ground went"
	return r

## Owner 2026-11-09 (B): a burning monster is tinted red-orange, a slowed one ice-blue, as long as the status lasts;
## both at once: frost wins (one clear colour; the burn still shows its flames and numbers). Off when the status
## ends, the monster dies or comes back.
func test_status_tints_the_monster():
	var w: Wolf = load("res://scenes/wolf.tscn").instantiate()
	tree.root.add_child(w)
	w.setup()
	var mat: ShaderMaterial = w.body.material
	var r := ""
	if _amt(mat) != 0.0: r = "tinted with no status"
	w.apply_status("burn", 1.0)
	w._update_status_fx()
	if r == "" and not _tint_is(mat, Wolf.BURN_TINT): r = "burning: tint %s" % _tint_of(mat)
	if r == "" and absf(_amt(mat) - Wolf.BURN_AMOUNT) > 0.001: r = "burning: amount %.2f, want BURN_AMOUNT %.2f" % [_amt(mat), Wolf.BURN_AMOUNT]
	w.apply_status("slow")
	w._update_status_fx()
	if r == "" and not _tint_is(mat, Wolf.FROST_TINT): r = "burning + slowed: tint %s (frost wins)" % _tint_of(mat)
	if r == "" and absf(_amt(mat) - Wolf.FROST_AMOUNT) > 0.001: r = "frozen: amount %.2f, want FROST_AMOUNT %.2f" % [_amt(mat), Wolf.FROST_AMOUNT]
	w.status.slow_left = 0.0
	w._update_status_fx()
	if r == "" and (not w.status.is_burning() or not _tint_is(mat, Wolf.BURN_TINT)): r = "slow ended, burn left: tint %s" % _tint_of(mat)
	w.status.clear()
	w._update_status_fx()
	if r == "" and _amt(mat) != 0.0: r = "tint left after the status ended"
	w.apply_status("slow")
	w._update_status_fx()
	w.health.take_hit(999999, false)
	if r == "" and _amt(mat) != 0.0: r = "tint left on a dead monster"
	if r == "" and Color(Wolf.BURN_TINT).h > 0.12: r = "burn tint %s is not red-orange" % Wolf.BURN_TINT
	if r == "" and (Color(Wolf.FROST_TINT).h < 0.5 or Color(Wolf.FROST_TINT).h > 0.6): r = "frost tint %s is not ice-blue" % Wolf.FROST_TINT
	w.queue_free()
	await tree.process_frame
	return r

func _amt(mat: ShaderMaterial) -> float:
	var v = mat.get_shader_parameter("tint_amount")
	return 0.0 if v == null else float(v)

func _tint_of(mat: ShaderMaterial) -> String:
	return "%s x %.2f" % [mat.get_shader_parameter("tint_color"), _amt(mat)]

func _tint_is(mat: ShaderMaterial, c: Color) -> bool:
	var t: Color = mat.get_shader_parameter("tint_color")
	return _amt(mat) > 0.2 and Color(t.r, t.g, t.b).is_equal_approx(Color(c.r, c.g, c.b))

## Review Minor #3 (2026-11-09, replaces "fades over the last FADE s of its time"): the cloud is a hazard, so it
## shows at full strength for as long as it can poison (its whole `time`, cloud_time); only then, harmless, it fades
## out over HazardCloud.FADE s (mist held on its last frame) and is freed. A hero who walks in during the fade is
## not poisoned; one who walks in on the last poisonous frame is. Gameplay time and dose unchanged.
func test_mist_full_while_poisonous_then_fades_harmless():
	var h: Hero = load("res://scenes/hero.tscn").instantiate()
	tree.root.add_child(h)
	h.set_physics_process(false)
	h.global_position = Vector2(1000, 1000)                 # out of the cloud
	var r := ""
	var a = load("res://scripts/monsters/hazard_cloud.gd").new()
	tree.root.add_child(a)
	a.set_physics_process(false)
	a.setup(Vector2(100, 100), 32.0, 2.0, 1, 3.0, h)
	var fade: float = a.FADE
	if fade < 0.2 or fade > 0.4: r = "fade %.2f s (want ~0.3)" % fade
	for i in 119:                                           # 1.983 s of its 2.0 s: full alpha all the way
		a.step(1.0 / 60.0)
		if r == "" and absf(a.modulate.a - 1.0) > 0.001: r = "alpha %.2f at %.2f s while it can still poison" % [a.modulate.a, (i + 1) / 60.0]
	if r == "" and not a.is_harmful(): r = "harmless before its time ran out"
	h.global_position = Vector2(100, 100)
	a.step(1.0 / 60.0)                                      # its last poisonous frame
	if r == "" and h.poison_left <= 0.0: r = "no poison on the cloud's last frame"
	if r == "" and absf(a.modulate.a - 1.0) > 0.001: r = "alpha %.2f on its last poisonous frame" % a.modulate.a
	a.free()
	h.poison_left = 0.0
	# a second cloud: the hero walks in just after its time is up
	var b = load("res://scripts/monsters/hazard_cloud.gd").new()
	tree.root.add_child(b)
	b.set_physics_process(false)
	h.global_position = Vector2(1000, 1000)
	b.setup(Vector2(100, 100), 32.0, 2.0, 1, 3.0, h)
	for i in 121: b.step(1.0 / 60.0)                        # 2.017 s: time is up
	if r == "" and b.is_harmful(): r = "still harmful after its time"
	h.global_position = Vector2(100, 100)
	var mist: FxSprite = null
	for ch in b.get_children():
		if ch is FxSprite: mist = ch
	for i in 6:                                             # 0.1 s into the fade, hero inside
		b.step(1.0 / 60.0)
	if r == "" and h.poison_left > 0.0: r = "poisoned during the harmless fade"
	if r == "" and (b.modulate.a <= 0.05 or b.modulate.a >= 0.95): r = "not fading after its time (alpha %.2f)" % b.modulate.a
	if r == "" and b.is_queued_for_deletion(): r = "cloud freed before its fade"
	if r == "" and mist != null:
		var last := mist.sprite_frames.get_frame_count("poison_mist") - 1
		if mist.is_playing() or mist.frame != last: r = "mist not held on its last frame in the fade (frame %d of %d, playing %s)" % [mist.frame, last, mist.is_playing()]
	for i in int(ceil(fade * 60.0)) + 1: b.step(1.0 / 60.0)
	if r == "" and not b.is_queued_for_deletion(): r = "cloud not freed after time + FADE"
	if r == "" and h.poison_left > 0.0: r = "poisoned during the harmless fade"
	if is_instance_valid(b): b.free()
	h.free()
	return r

## Review Minor #5: clear_cache() also drops the cached manifest (a re-exported manifest is read again).
func test_clear_cache_drops_the_manifest():
	FxSprite.make_frames("hit_spark")
	if FxSprite._cache.is_empty(): return "setup: manifest not cached"
	FxSprite.clear_cache()
	var r := ""
	if not FxSprite._cache.is_empty(): r = "manifest cache kept by clear_cache()"
	elif not FxSprite._frames.is_empty(): r = "frames cache kept by clear_cache()"
	elif not FxSprite._manifest().has("hit_spark"): r = "manifest not read again after clear_cache()"
	return r

# ---------- owner 2026-11-09 (after f9058ce): warp ease-in, whiter frost; review Important #1 ----------

## Owner: the warp fade darkens slowly at first and fast at the end ("ให้จอมืดช้าตอนต้น เร็วตอนท้าย"), still FADE_OUT
## (0.5 s) in total. The real fade tween, held and stepped: alpha rises every step, at half time it is at most 0.2
## (a straight fade is 0.5) and the second half darkens more than the first; the room is unchanged until FADE_OUT and
## changes right after it.
func test_warp_fade_eases_in():
	var g = await _ground()
	g.hero.set_physics_process(false)
	for i in 4: await tree.process_frame
	var from: String = g.room_id
	g.warp_through(g.warps[0])
	var tw: Tween = g._fade_tween
	tw.pause()
	var r := ""
	if absf(g.FADE_OUT - 0.5) > 0.0001: r = "fade out %.2f s (owner: 0.5)" % g.FADE_OUT
	var alphas := [g.fade.color.a]
	var step: float = g.FADE_OUT / 10.0
	for i in 9:                                             # up to 0.45 s
		tw.custom_step(step)
		alphas.append(g.fade.color.a)
		if r == "" and alphas[-1] <= alphas[-2]: r = "alpha not rising at %.2f s (%.3f -> %.3f)" % [(i + 1) * step, alphas[-2], alphas[-1]]
	if r == "" and alphas[5] > 0.2: r = "alpha %.2f at half time (ease-in wants <= 0.2; straight 0.5)" % alphas[5]
	if r == "" and alphas[5] - alphas[0] >= alphas[9] - alphas[5]: r = "first half darkens as much as the second (%s)" % str(alphas)
	if r == "" and (g.room_id != from or not g.warping): r = "room changed before FADE_OUT"
	tw.custom_step(step + 0.001)                            # FADE_OUT reached
	if r == "" and (g.room_id == from or g.warping): r = "room not changed at FADE_OUT"
	g.queue_free()
	await tree.process_frame
	return r

## Review Important #1: an arrow in flight when the warp fade starts used to fly on for the 0.5 s and could kill a
## monster of the room being left (EXP given, loot dropped into a room about to be freed: lost). Now the hero's
## arrows stop where they are at the warp's start (the old room stops, as its packs do) and the room change frees
## them. Control first: the same shot without a warp kills and gives EXP.
func test_arrow_in_flight_at_warp_kills_nothing():
	var g = await _ground()
	g.go_to("c1r0", "", false)
	var h: Hero = g.hero
	h.set_physics_process(false)
	for p in g.packs: p.process_mode = Node.PROCESS_MODE_DISABLED
	var ws: Array = []
	for p in g.packs:
		for w in p.wolves: ws.append(w)
	if ws.size() < 2 or g.warps.is_empty():
		g.queue_free()
		await tree.process_frame
		return "setup: %d monsters, %d warps in c1r0" % [ws.size(), g.warps.size()]
	var r := ""
	# control: no warp, the arrow kills
	var w0: Wolf = ws[0]
	w0.health.setup(1)
	var exp0 := h.exp + h.level * 100000
	h._fire(w0.hurt_point() + Vector2(-40, 0), Vector2.RIGHT, 1.0, false)
	for i in 20: await tree.physics_frame
	if w0.is_alive() or h.exp + h.level * 100000 == exp0: r = "setup: the control arrow did not kill (alive %s)" % w0.is_alive()
	# the warp starts with an arrow 40 px from a 1-hp monster
	var w1: Wolf = ws[1]
	w1.health.setup(1)
	var exp1 := h.exp + h.level * 100000
	var drops1: int = g.drops.size()
	var from: String = g.room_id
	h._fire(w1.hurt_point() + Vector2(-40, 0), Vector2.RIGHT, 1.0, false)
	g.warp_through(g.warps[0])
	g._fade_tween.pause()                                   # stay in the fade
	for i in 30: await tree.physics_frame                   # 0.5 s: the arrow would have hit at ~0.1 s
	if r == "" and not w1.is_alive(): r = "an arrow in flight at the warp's start killed an old-room monster"
	elif r == "" and h.exp + h.level * 100000 != exp1: r = "EXP given after the warp started"
	elif r == "" and g.drops.size() != drops1: r = "loot dropped after the warp started"
	g._fade_tween.custom_step(g.FADE_OUT + 0.01)
	await tree.process_frame
	if r == "" and g.room_id == from: r = "setup: never left c1r0"
	if r == "":
		for c in g.world.get_children():
			if c is Arrow and not c.is_queued_for_deletion(): r = "an old-room arrow is left in %s" % g.room_id
	g.queue_free()
	await tree.process_frame
	return r

## Mean colour of a sprite's lit pixels (texel luma > 0.15) as the game draws them plain and tinted (Wolf.tint_preview,
## the CPU mirror of flash.gdshader; screenshots_m5a_pixelfx checks it against the GPU); and the largest change of any
## outline pixel (texel luma < 0.06) and its luma when tinted.
func _tint_stats(path: String, tint: Color, amount: float) -> Dictionary:
	var img: Image = (load(path) as Texture2D).get_image()
	img.decompress()
	var a := Vector3.ZERO
	var b := Vector3.ZERO
	var n := 0
	var outline := 0.0
	var outline_luma := 0.0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a < 0.5: continue
			var l := 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
			var p := Wolf.tint_preview(c, tint, 0.0)        # the plain body as the game draws it
			var t := Wolf.tint_preview(c, tint, amount)
			if l < 0.06:
				outline = maxf(outline, maxf(absf(t.r - p.r), maxf(absf(t.g - p.g), absf(t.b - p.b))))
				outline_luma = maxf(outline_luma, 0.299 * t.r + 0.587 * t.g + 0.114 * t.b)
			elif l > 0.15:
				a += Vector3(p.r, p.g, p.b)
				b += Vector3(t.r, t.g, t.b)
				n += 1
	return {"before": Color(a.x / n, a.y / n, a.z / n), "after": Color(b.x / n, b.y / n, b.z / n), "outline": outline, "outline_luma": outline_luma}

## The south pose sheet of monster kind k (the wolf has its own folder).
func _pose(k: String) -> String:
	return "res://assets/wolf/pose_south.png" if k == "wolf" else "res://assets/monsters/%s/pose_south.png" % k

func _luma(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b

## Owner (after f9058ce): a frozen monster turns a brighter, whiter ice so the already-blue ice wolf still reads frozen
## ("มอนที่ติดแข็งให้สว่างขาวเย็นกว่าเดิม"); outlines stay dark. On the wolf's own sprite: the frozen mean colour is far
## from the plain one (distance >= 0.3), clearly lighter (+0.15 luma) and whiter (saturation down >= 0.15); on every
## monster no outline pixel changes and frost reads ice (pale: sat <= 0.2, light: luma up >= 0.15).
func test_frost_tint_reads_on_the_ice_wolf():
	var s := _tint_stats(_pose("wolf"), Wolf.FROST_TINT, Wolf.FROST_AMOUNT)
	var a: Color = s.before
	var b: Color = s.after
	var d := Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()
	if d < 0.3: return "frozen ice wolf mean %s vs plain %s: distance %.2f (want >= 0.3)" % [b.to_html(false), a.to_html(false), d]
	if _luma(b) - _luma(a) < 0.15: return "frozen ice wolf only %.2f lighter" % (_luma(b) - _luma(a))
	if a.s - b.s < 0.15: return "frozen ice wolf not whiter (sat %.2f -> %.2f)" % [a.s, b.s]
	for k in ["boar", "deer", "kongkoi", "macaque", "shroom", "viper"]:
		var m := _tint_stats(_pose(k), Wolf.FROST_TINT, Wolf.FROST_AMOUNT)
		var mb: Color = m.after
		if mb.s > 0.2 or _luma(mb) - _luma(m.before) < 0.15: return "frozen %s mean %s does not read ice" % [k, mb.to_html(false)]
	for k in ["wolf", "boar", "deer", "kongkoi", "macaque", "shroom", "viper"]:
		for pair in [[Wolf.FROST_TINT, Wolf.FROST_AMOUNT], [Wolf.BURN_TINT, Wolf.BURN_AMOUNT]]:
			var o := _tint_stats(_pose(k), pair[0], pair[1])
			if o.outline > 0.001 or o.outline_luma >= 0.06: return "%s outline lifted by %.3f under tint %s" % [k, o.outline, pair[0].to_html(false)]
	return ""

## Burn stays red-orange, also on a light monster (review: at 0.6 x (0.7 + luma) the pale wolf went salmon, sat 0.47):
## every monster's burning mean colour has hue 8-30 degrees and saturation >= 0.6.
func test_burn_tint_is_red_orange_not_salmon():
	for k in ["wolf", "boar", "deer", "kongkoi", "macaque", "shroom", "viper"]:
		var s := _tint_stats(_pose(k), Wolf.BURN_TINT, Wolf.BURN_AMOUNT)
		var b: Color = s.after
		if b.h * 360.0 < 8.0 or b.h * 360.0 > 30.0 or b.s < 0.6: return "burning %s mean %s (hue %.0f, sat %.2f) is not red-orange" % [k, b.to_html(false), b.h * 360.0, b.s]
	return ""

## The CPU mirror (Wolf.tint_preview) and flash.gdshader share their numbers: the shader's consts equal Wolf's
## TINT_BASE / TINT_GAIN / OUTLINE_LO / OUTLINE_HI (the GPU result itself is compared in screenshots_m5a_pixelfx).
func test_tint_shader_matches_its_mirror():
	var code: String = (load("res://shaders/flash.gdshader") as Shader).code
	for pair in [["TINT_BASE", Wolf.TINT_BASE], ["TINT_GAIN", Wolf.TINT_GAIN], ["OUTLINE_LO", Wolf.OUTLINE_LO], ["OUTLINE_HI", Wolf.OUTLINE_HI]]:
		var re := RegEx.create_from_string("const float %s = ([0-9.]+);" % pair[0])
		var m := re.search(code)
		if m == null: return "flash.gdshader has no const %s" % pair[0]
		if absf(float(m.get_string(1)) - float(pair[1])) > 0.00001: return "%s: shader %s, Wolf %s" % [pair[0], m.get_string(1), pair[1]]
	return ""

# ---------- licence ----------

## MIT notice kept (LICENSE + NOTICE), in the export, and a line in the game's credits; no Patch Pixel font. The web
## export ships the licence, CREDITS.md and the file it points to (assets/audio/CREDITS.md).
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
	var inc := ""
	for line in cfg.split("\n"):
		if line.begins_with("include_filter="): inc = line
	if inc == "": return "no include_filter in export_presets.cfg"
	var files := []
	for f in inc.trim_prefix("include_filter=").trim_prefix("\"").trim_suffix("\"").split(","): files.append(f.strip_edges())
	for f in ["assets/fx/PIXELFX_LICENSE.txt", "CREDITS.md", "assets/audio/CREDITS.md"]:
		if not f in files: return "%s not in the export include_filter %s" % [f, files]
	for d in ["res://assets/fonts", "res://assets/fx"]:
		for f in DirAccess.get_files_at(d):
			if f.to_lower().contains("patch"): return "Patch font file %s/%s" % [d, f]
	return ""
