extends SceneTree
## M5b Task 7 (mark and frost combos) in game, for the owner's review.
## xvfb-run -a godot --path . --rendering-driver opengl3 --script tests/screenshots_m5b_mark_frost.gd
## then: python3 -I tools/mark_frost_review.py   (crops at game size and x3, the r32 ring, the numbered review image)
## The test ground at 1280x720, char Lv10, ศรทะลวง; real presses (Hero.try_skill, its arrows and the combo's own on-hit
## path) except the slowed / frozen pair, which gets the ice gem's slow (apply_status "slow") and the combo's freeze
## (apply_freeze 1 s / lock 5 s) directly, as the arrows apply them. Monsters are held still (no AI); their status
## look is refreshed every frame as Wolf.step does (_update_status_fx). Frames go to /tmp/t7_shots/<case>_<moment>.png
## with /tmp/t7_shots/meta.json (screen positions, world -> screen scale).
## Cases:
##   mark_hawk   - ศรตาเหยี่ยว (homing + execute) on monster A (c1r0). a: A is marked and is the hero's target (the
##                 targeting ring at its feet); b: B, the same kind, moved nearer the hero takes the ring, A keeps the mark.
##   mark_garuda - ศรเนตรพญาครุฑ (homing + execute + multiply): the same two moments (gold mark).
##   frost_light - three monsters of one kind side by side on c1r0: plain / slowed / frozen (targeting ring hidden).
##   frost_dark  - the same on the darker ground of c2r0.
##   shatter     - ศรผลึกอโนดาต (ice + split + execute) into a slowed monster: the shatter (spread_burst #7fd4ff, r32)
##                 at sheet frames 1 / 2 / 5 (0.07 / 0.13 / 0.33 s; frame set while paused), as played (f*) and with
##                 the other hit effects (crit glare, hit sparks, damage numbers) hidden (o*: the shatter alone).
##   streak      - ศรเกล็ดน้ำแข็ง (ice + split): the three arrows in flight 0.25 s after the release with their frost
##                 streaks (piercing_trail #7fd4ff).
## Task 7 review fix (owner 2026-11-10: red ตาเหยี่ยว mark, ice block on a frozen monster), for t7_fix_review.png
## (python3 -I tools/mark_frost_review.py --fix):
##   mark_hawk_dark - mark_hawk on the darker ground of c2r0.
##   marks_pair     - c1r0: A with the ตาเหยี่ยว mark (red), B with the ครุฑ mark (gold) side by side, C nearest the hero
##                 with the targeting ring; the marks are put on directly (apply_mark with each recipe's ledger, as an
##                 arrow hit does), no press.
## T7_FIX=1 runs only the cases the fix review needs (mark_hawk, mark_hawk_dark, frost_light, frost_dark, marks_pair).

const TMP := "/tmp/t7_shots/"
const SAVE := "user://shots_m5b_t7_save.json"
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
	var fix := OS.get_environment("T7_FIX") == "1"
	await _mark("mark_hawk", ["homing", "execute"])
	if fix: await _mark("mark_hawk_dark", ["homing", "execute"], "c2r0", Vector2(-90, 150))
	if not fix: await _mark("mark_garuda", ["homing", "execute", "multiply"])
	await _frost("frost_light", "c1r0", Vector2(0, 20))
	await _frost("frost_dark", "c2r0", Vector2(-60, 140))
	if fix: await _pair()
	if not fix:
		await _shatter()
		await _streak()
	var f := FileAccess.open(TMP + "meta.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "  "))
	f.close()
	print("done")
	quit(0)

func _gem(key: String) -> Dictionary:
	var gm := {"type": key, "level": 1, "exp": 0, "rarity": "common", "opts": []}
	if key in ["fire", "ice", "lightning"]:
		gm["type"] = "element"
		gm["element"] = key
	return gm

func _size(s: Vector2i) -> void:
	DisplayServer.window_set_size(s)
	root.size = s
	for i in 6: await process_frame

func _v(p: Vector2) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01)]

func _scr(p: Vector2) -> Array:
	return _v(g.world_to_screen(p))

## Loads `room`, holds every monster still with lots of HP, puts the hero at mid + hero_off with `keys` on ศรทะลวง.
## Returns the monsters of the room's most common kind first (the kind is in meta).
func _setup(room: String, keys: Array, hero_off: Vector2) -> Array:
	if FileAccess.file_exists(SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	await _size(Vector2i(1280, 720))
	g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = SAVE
	g.layout_seed = 7
	g.watch_fps = false
	root.add_child(g)
	for i in 4: await process_frame
	g.go_to(room, "", false)
	for i in 4: await process_frame
	g.saver.on = false
	g.apply_saver()
	var h: Hero = g.hero
	h.set_physics_process(false)
	var gems: Array = []
	for k in keys: gems.append(_gem(k))
	h.set_progress(10, 0)
	h.set_skill_gems({"piercing": gems})
	h.mp = h.max_mp()
	var wolves := []
	for p in g.packs:
		p.set_physics_process(false)
		p.set_process(false)
		for w in p.wolves: wolves.append(w)
	var counts := {}
	for w in wolves:
		var k := String(w.get("kind")) if w.get("kind") != null else "wolf"
		counts[k] = int(counts.get(k, 0)) + 1
	var best := ""
	for k in counts:
		if best == "" or counts[k] > counts[best]: best = k
	var kind_of := func(w): return String(w.get("kind")) if w.get("kind") != null else "wolf"
	wolves.sort_custom(func(p, q): return int(kind_of.call(p) == best) > int(kind_of.call(q) == best))
	var mid: Vector2 = g.layout.size_px() / 2.0
	h.global_position = mid + hero_off
	for w in wolves:
		w.set_physics_process(false)
		w.health.setup(100000)
		w.visible = false
		w.global_position = mid + Vector2(-3000, -3000)
	print(room, ": kind ", best, " x", counts[best], " of ", wolves.size())
	return [wolves, best]

func _show(w: Wolf, at: Vector2) -> void:
	w.visible = true
	w.global_position = at

## One physics frame of the held scene: the hero's press and arrows run, monsters only tick their statuses and refresh
## their look (as Wolf.step does).
func _tick(wolves: Array) -> void:
	await physics_frame
	g.hero.step(DT, Vector2.ZERO)
	for w in wolves:
		w.tick_burn(DT)
		w._update_status_fx()

func _snap(file: String) -> String:
	for i in 4: await process_frame
	var img := root.get_texture().get_image()
	img.save_png(TMP + file)
	print("saved ", file, " ", img.get_size())
	return TMP + file

func _scale() -> float:
	return (g.world_to_screen(Vector2(100, 0)).x - g.world_to_screen(Vector2.ZERO).x) / 100.0

func _close() -> void:
	paused = false
	g.queue_free()
	for i in 3: await process_frame
	PerfSaver.active = false

func _press(wolves: Array) -> int:
	if not g.hero.try_skill("piercing"): print("WARN: try_skill refused")
	var frames := 0
	while frames < 120 and not g.hero._released:
		await _tick(wolves)
		frames += 1
	return frames

func _mark(name: String, keys: Array, room := "c1r0", hero_off := Vector2(-110, 30)) -> void:
	var s: Array = await _setup(room, keys, hero_off)
	var wolves: Array = s[0]
	var h: Hero = g.hero
	var a: Wolf = wolves[0]
	var b: Wolf = wolves[1]
	_show(a, h.global_position + Vector2(90, -10))
	for i in 4: await _tick(wolves)
	var bd := h.build("piercing")
	print(name, ": combo ", bd.combo.get("id", "-"))
	await _press(wolves)
	var frames := 0
	while frames < 90 and not a.is_marked():
		await _tick(wolves)
		frames += 1
	for i in 30: await _tick(wolves)           # the hit spark is gone; the mark loops on
	var m := {"room": room, "kind": s[1], "combo": String(bd.combo.get("id", "")), "scale": _scale(), "moments": {}}
	paused = true
	m.moments["a"] = {"file": await _snap(name + "_a.png"), "marked": a.is_marked(), "target_a": h.current_target() == a,
		"a_feet": _scr(a.global_position), "a_hurt": _scr(a.hurt_point()), "hero": _scr(h.global_position),
		"ring": _scr(g.lock_ring.global_position), "ring_visible": g.lock_ring.visible}
	paused = false
	_show(b, h.global_position + Vector2(50, 45))
	for i in 6: await _tick(wolves)
	paused = true
	m.moments["b"] = {"file": await _snap(name + "_b.png"), "marked": a.is_marked(), "target_b": h.current_target() == b,
		"a_feet": _scr(a.global_position), "a_hurt": _scr(a.hurt_point()), "b_feet": _scr(b.global_position),
		"b_hurt": _scr(b.hurt_point()), "b_marked": b.is_marked(), "hero": _scr(h.global_position),
		"ring": _scr(g.lock_ring.global_position), "ring_visible": g.lock_ring.visible}
	print(name, ": ", m.moments.a.marked, " ", m.moments.a.target_a, " / ", m.moments.b.marked, " ", m.moments.b.target_b)
	meta[name] = m
	await _close()

func _frost(name: String, room: String, at: Vector2) -> void:
	var s: Array = await _setup(room, [], at + Vector2(-260, 0))
	var wolves: Array = s[0]
	var mid: Vector2 = g.layout.size_px() / 2.0
	var trio: Array = [wolves[0], wolves[1], wolves[2]]
	for i in 3: _show(trio[i], mid + at + Vector2(-60 + 60 * i, 0))
	trio[1].apply_status("slow")
	var froze: bool = trio[2].apply_freeze(1.0, 5.0)
	for i in 20: await _tick(wolves)
	paused = true
	g.lock_ring.visible = false
	var ir: Rect2 = trio[2].ice_block_rect()
	var m := {"room": room, "kind": s[1], "scale": _scale(), "froze": froze,
		"ice_block": [trio[0]._ice_block != null, trio[1]._ice_block != null, trio[2]._ice_block != null],
		"ice_rect": [ir.position.x, ir.position.y, ir.size.x, ir.size.y],
		"slowed": [trio[0].is_chilled(), trio[1].status.is_slowed(), trio[2].status.is_slowed()],
		"frozen": [trio[0].is_frozen(), trio[1].is_frozen(), trio[2].is_frozen()],
		"feet": trio.map(func(w): return _scr(w.global_position)), "hurt": trio.map(func(w): return _scr(w.hurt_point())),
		"moments": {"a": {"file": await _snap(name + "_a.png")}}}
	print(name, ": kind ", s[1], " slowed ", m.slowed, " frozen ", m.frozen)
	meta[name] = m
	await _close()

## marks_pair: A (ตาเหยี่ยว, red) and B (ครุฑ, gold) side by side, C nearest the hero wears the targeting ring.
func _pair() -> void:
	var s: Array = await _setup("c1r0", [], Vector2(-110, 30))
	var wolves: Array = s[0]
	var h: Hero = g.hero
	var a: Wolf = wolves[0]
	var b: Wolf = wolves[1]
	var c: Wolf = wolves[2]
	_show(a, h.global_position + Vector2(100, -20))
	_show(b, h.global_position + Vector2(160, -20))
	_show(c, h.global_position + Vector2(55, 40))
	a.apply_mark(0.2, 4.0, ComboCast.new("hawk_eye"))
	b.apply_mark(0.3, 4.0, ComboCast.new("garuda"))
	for i in 20: await _tick(wolves)
	paused = true
	var m := {"room": "c1r0", "kind": s[1], "scale": _scale(), "marked": [a.is_marked(), b.is_marked(), c.is_marked()],
		"target_c": h.current_target() == c, "ring": _scr(g.lock_ring.global_position), "ring_visible": g.lock_ring.visible,
		"feet": [a, b, c].map(func(w): return _scr(w.global_position)), "hurt": [a, b, c].map(func(w): return _scr(w.hurt_point())),
		"tints": [a, b].map(func(w): return w._mark_fx[0].modulate.to_html(false) if not w._mark_fx.is_empty() else "-"),
		"moments": {"a": {"file": await _snap("marks_pair_a.png")}}}
	print("marks_pair: marked ", m.marked, " target_c ", m.target_c, " tints ", m.tints)
	meta["marks_pair"] = m
	await _close()

func _shatter() -> void:
	var s: Array = await _setup("c1r0", ["ice", "split", "execute"], Vector2(-110, 30))
	var wolves: Array = s[0]
	var h: Hero = g.hero
	var a: Wolf = wolves[0]
	_show(a, h.global_position + Vector2(90, -10))
	a.apply_status("slow")
	for i in 4: await _tick(wolves)
	var bd := h.build("piercing")
	print("shatter: combo ", bd.combo.get("id", "-"), " chilled ", a.is_chilled())
	await _press(wolves)
	var burst: FxSprite = null
	var frames := 0
	while frames < 90 and burst == null:
		await _tick(wolves)
		frames += 1
		for c in g.world.get_children():
			if c is FxSprite and c.animation == "spread_burst" and not c.is_queued_for_deletion(): burst = c
	if burst == null:
		print("ERROR: no shatter")
		await _close()
		return
	paused = true
	g.lock_ring.visible = false
	# the other hit effects of the same moment: TestGround's crit glare / hit sparks (stage), other world effects, and
	# the damage numbers (overlay); hidden for the "shatter only" frames
	var others: Array = (g.world.get_children() + g.stage.get_children()).filter(func(c): return c is FxSprite and c != burst and c != g.lock_ring)
	var numbers: Array = g.overlay.get_children().filter(func(c): return c is DamageNumber)
	var m := {"room": "c1r0", "kind": s[1], "combo": String(bd.combo.get("id", "")), "scale": _scale(),
		"burst": _scr(burst.global_position), "burst_scale": _v(burst.scale), "burst_tint": burst.modulate.to_html(false),
		"others": others.map(func(c): return String(c.animation)), "numbers": numbers.size(), "a_kind": String(a.get("kind")) if a.get("kind") != null else "wolf", "a_feet": _scr(a.global_position), "a_hurt": _scr(a.hurt_point()),
		"moments": {}}
	for bf in [1, 2, 5]:
		burst.frame = bf
		m.moments["f%d" % bf] = {"file": await _snap("shatter_f%d.png" % bf)}
	for c in others + numbers: c.visible = false
	for bf in [1, 2, 5]:
		burst.frame = bf
		m.moments["o%d" % bf] = {"file": await _snap("shatter_o%d.png" % bf)}
	print("shatter: scale ", burst.scale, " tint ", m.burst_tint, " others ", m.others, " numbers ", m.numbers, " on ", m.a_kind)
	meta["shatter"] = m
	await _close()

func _streak() -> void:
	var s: Array = await _setup("c1r0", ["ice", "split"], Vector2(-110, 30))
	var wolves: Array = s[0]
	var h: Hero = g.hero
	var a: Wolf = wolves[0]
	_show(a, h.global_position + Vector2(205, -10))
	for i in 4: await _tick(wolves)
	var bd := h.build("piercing")
	await _press(wolves)
	for i in int(round(0.25 / DT)): await _tick(wolves)
	paused = true
	g.lock_ring.visible = false
	var arrows: Array = g.world.get_children().filter(func(c): return c is Arrow and not c.is_queued_for_deletion())
	var streaks: Array = []
	for x in arrows:
		for c in x.get_children():
			if c is FxSprite: streaks.append(c)
	var m := {"room": "c1r0", "kind": s[1], "combo": String(bd.combo.get("id", "")), "scale": _scale(),
		"arrows": arrows.map(func(x): return _scr(x.global_position)), "streaks": streaks.size(),
		"streak_tint": streaks.map(func(c): return c.modulate.to_html(false)), "hero": _scr(h.global_position),
		"moments": {"a": {"file": await _snap("streak_a.png")}}}
	print("streak: combo ", m.combo, " arrows ", arrows.size(), " streaks ", streaks.size())
	meta["streak"] = m
	await _close()
