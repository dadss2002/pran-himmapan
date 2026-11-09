extends RefCounted
## M5b Task 5 (plan docs/superpowers/plans/2026-11-09-m5b-gem-combos.md, spec 2026-11-08-gem-combos.md): the combo
## FX helper (ComboFx, tinted reuse of manifest effects, 0 gen), primary vs bounce arrows, the fire trail (FireTrail)
## of ศรพัดเพลิง / พัดเพลิงพรหมาสตร์ and พรหมาสตร์'s line-end blast. Secondary hits (blasts) never trigger combo
## effects (Global Constraints "Secondary hits").

var tree: SceneTree
const DT := 1.0 / 60.0
const ATK := 20.0
const STATS := {"crit": 0.05, "element_dmg": 0.0, "skill_cd_cut": 0.0}
const TMP_SAVE := "user://test_arrow_combos_save.json"
var _spawned: Array = []

## A stand-in for the hero as the arrows' shooter: records leech heals.
class Sink extends Node:
	var got := 0.0
	func leech_heal(a: float) -> void:
		got += a

func setup(t: SceneTree) -> void:
	tree = t

func _g(key: String) -> Dictionary:
	var g := {"type": key, "level": 1, "exp": 0, "rarity": "common", "opts": []}
	if key in ["fire", "ice", "lightning"]:
		g["type"] = "element"
		g["element"] = key
	return g

## The build of one press (char Lv10, gem Lv1) with its ledger in b.cast, as Hero._release makes it.
func _build(keys: Array, skill := "piercing") -> Dictionary:
	var gems: Array = []
	for k in keys: gems.append(_g(k))
	var b := SkillBuild.of(skill, 10, gems, STATS)
	b["cast"] = ComboCast.from_build(b)
	return b

func _dummy(hurt_at: Vector2, hp := 100000) -> Node2D:
	var d: Node2D = load("res://tests/dummy_enemy.gd").new()
	d.position = hurt_at + Vector2(0, 14)       # the dummy's hurt_point is 14 px above its feet
	d.hp = hp
	return d

func _arrow(dir: Vector2, enemies: Array, b: Dictionary, primary := true, shooter: Node = null) -> Arrow:
	var a: Arrow = load("res://scenes/arrow.tscn").instantiate()
	a.launch(dir, ATK, enemies, float(b.arrow_mult), bool(b.pierce_all), Balance.num("skills.piercing.range"))
	a.crit_chance = 0.0
	a.crit_mult = 1.0
	a.primary = primary
	a.configure(b, shooter)
	a.spawned.connect(_on_spawned)
	return a

## A bounce arrow's own bounces are listened to as well (as Hero._on_arrow_spawned does), so chains of 2+ bounces
## (ศรอสนีกระโดด, Task 6) are stepped by _step.
func _on_spawned(x: Arrow) -> void:
	_spawned.append(x)
	x.spawned.connect(_on_spawned)

## The hero's fan for a build (Hero._release), from the origin.
func _fan(b: Dictionary, enemies: Array, shooter: Node = null) -> Array:
	var out: Array = []
	var n := int(b.arrows)
	var fan := deg_to_rad(float(b.fan_deg))
	for i in n:
		var dir := Vector2.RIGHT if n == 1 else Vector2.RIGHT.rotated(-fan / 2.0 + fan * i / (n - 1))
		out.append(_arrow(dir, enemies, b, true, shooter))
	return out

## Every arrow's and trail's step, then the dummies' statuses; returns the dummies' damage per frame summed.
func _step(arrows: Array, ds: Array) -> int:
	var dealt := 0
	for a in arrows + _spawned:
		if is_instance_valid(a): a.advance(DT)
	for t in _trails(arrows): t.step(DT)
	for d in ds: dealt += d.tick_status(DT)
	return dealt

func _trails(arrows: Array) -> Array:
	var out: Array = []
	for a in arrows + _spawned:
		if is_instance_valid(a) and a.trail != null and not a.trail in out: out.append(a.trail)
	return out

func _free(list: Array) -> void:
	for x in list:
		if x is Arrow and is_instance_valid(x) and x.trail != null and is_instance_valid(x.trail): x.trail.free()
	for x in list:
		if is_instance_valid(x): x.free()

# ---------- ComboFx ----------

func test_every_recipe_fx_exists():
	var man := FxSprite._manifest()
	var n := 0
	for row in GemCombo.recipes():
		var fx: Dictionary = row.get("fx", {})
		if fx.is_empty(): return "%s has no fx rows" % row.id
		for ev in fx:
			for e in fx[ev]:
				n += 1
				if not man.has(String(e.fx)): return "%s %s: fx %s not in assets/fx/manifest.json" % [row.id, ev, e.fx]
				if not Color.html_is_valid(String(e.tint)): return "%s %s: tint %s is not a colour" % [row.id, ev, e.tint]
	return "" if n >= 16 else "only %d fx entries" % n

func test_combo_fx_plays_tinted_reuse():
	var p := Node2D.new()
	# owner 2026-11-09: the fire line is the PixelFX T2 patch (fire_trail), not recoloured, upright (never turned)
	var got := ComboFx.play(p, "fire_fan", "trail", Vector2(5, 7), Vector2.DOWN)
	var r := ""
	if got.size() != 1: r = "fire_fan trail spawned %d effects, want one fire_trail patch" % got.size()
	elif got[0].animation != "fire_trail" or got[0].modulate != Color.WHITE: r = "trail patch %s tint %s" % [got[0].animation, got[0].modulate]
	elif got[0].position != Vector2(5, 7) or got[0].get_parent() != p: r = "patch not placed in the parent at the point"
	elif got[0].rotation != 0.0: r = "the fire patch turned along the line (%s): flames stand upright" % got[0].rotation
	elif not ComboFx.play(p, "fire_fan", "no_such_event", Vector2.ZERO).is_empty(): r = "an unknown event spawned something"
	elif not ComboFx.play(p, "", "trail", Vector2.ZERO).is_empty(): r = "no combo spawned something"
	elif not ComboFx.play(null, "fire_fan", "trail", Vector2.ZERO).is_empty(): r = "no parent spawned something"
	elif p.get_child_count() != 1: r = "%d children, want 1" % p.get_child_count()
	if r == "":
		var g := ComboFx.play(p, "garuda", "mark", Vector2.ZERO)
		if g.size() != 1 or g[0].animation != "lock_on" or g[0].modulate != Color("#edbb55"): r = "garuda mark should be a gold lock_on"
	if r == "":
		var fs := ComboFx.play(p, "frost_shard", "trail", Vector2.ZERO, Vector2.DOWN)
		if fs.size() != 1 or fs[0].animation != "piercing_trail" or fs[0].modulate != Color("#7fd4ff") or not is_equal_approx(fs[0].rotation, Vector2.DOWN.angle()):
			r = "frost_shard trail should stay a blue streak turned along the line"
	p.free()
	return r

## PerfSaver sheds the decorative extras only (crit glare → its fallback), never the fire trail's patch (it shows
## where the fire is: the hazard) or the line-end blast (a hit effect).
func test_combo_fx_perf_saver_sheds_decor_only():
	var p := Node2D.new()
	PerfSaver.active = true
	var trail := ComboFx.play(p, "brahmastra", "trail", Vector2.ZERO)
	var end := ComboFx.play(p, "brahmastra", "line_end", Vector2.ZERO)
	var crit := ComboFx.play(p, "hawk_eye", "crit", Vector2.ZERO)
	PerfSaver.active = false
	var r := ""
	if trail.size() != 1 or trail[0].animation != "fire_trail": r = "saver on: trail gave %s, want the fire patch" % [trail.map(func(s): return s.animation)]
	elif end.size() != 1 or end[0].animation != "fire_blast": r = "saver on: the line-end blast was shed"
	elif crit.size() != 1 or crit[0].animation != "hit_spark": r = "saver on: crit_hit should fall back to hit_spark"
	elif PerfSaver.decorative("fire_trail") or PerfSaver.decorative("fire_blast"): r = "fire_trail / fire_blast listed as decorative"
	if r == "" and ComboFx.play(p, "brahmastra", "trail", Vector2.ZERO, Vector2.ZERO, false).map(func(s): return String(s.animation)) != ["fire_trail"]:
		r = "decor = false must keep the fire patch (it is the hazard, not decoration)"
	p.free()
	return r

# ---------- fire trail ----------

## One primary ศรพัดเพลิง arrow through a DEF-0 dummy: the trail applies 20 % of the arrow's hit per tick, lasts 2 s
## after the arrow is spent, then ends; a monster standing in it takes exactly 2 ticks (= tools/gem_combo_sim.py).
func _trail_case(keys: Array, frac: float, secs: float) -> String:
	_spawned = []
	var b := _build(keys)
	var d := _dummy(Vector2(60, 0))
	var a := _arrow(Vector2.RIGHT, [d], b)
	var ticks := 0
	var r := ""
	var f := 0
	while not a.spent and f < 120:
		if _step([a], [d]) > 0: ticks += 1
		f += 1
	var want := frac * ATK * float(b.arrow_mult)
	if a.trail == null: r = "no FireTrail for %s" % [keys]
	elif not is_equal_approx(d.status.trail_per_tick, want): r = "trail per tick %s, want %s (%.0f%% of the arrow's hit)" % [d.status.trail_per_tick, want, frac * 100]
	if r == "":
		var t: FireTrail = a.trail
		# Frame counting (review M7) assumes: (1) _step advances the arrows BEFORE it steps the trails, so the frame
		# the arrow is spent already stepped the finished trail once (left = secs − DT); (2) secs is a whole number
		# of frames (2.0 / 3.0 s at 1/60 s), so after (secs / DT − 2) more frames left = DT (still on) and the 3
		# below take it to ≤ 0 (FireTrail.step ends it with its 1e-6 tolerance); (3) a "tick" is a frame in which
		# the dummy lost whole HP: the dummy's receive_hit takes no HP, and the fire gem's own burn (0.2 of the
		# dummy's 1-damage hit) starts on the hit frame, the same frame the trail first reaches the dummy, so the two
		# clocks tick together; its lone 3rd tick (fire_fan) adds 0.2 to a carry of ~0.18 and stays under 1 HP. With
		# other numbers (a larger hit, a dummy off the line start) the count could include a burn-only frame.
		# Speed / range / DT changes need this re-checked.
		for i in int(round(secs / DT)) - 2:            # the spent frame stepped it once: secs − 1 frame so far
			if _step([a], [d]) > 0: ticks += 1
		if t.done: r = "trail ended before %s s after the arrow was spent" % secs
		for i in 3:
			if _step([a], [d]) > 0: ticks += 1
		if r == "" and not t.done: r = "trail still on %s s after the arrow was spent" % (secs + 2 * DT)
		for i in 90:                                     # the last hold runs out: no tick after the trail
			if _step([a], [d]) > 0: ticks += 1
		if r == "" and ticks != int(round(secs)): r = "a monster standing in the trail took %d ticks, want %d (sim)" % [ticks, int(round(secs))]
	_free([a, d])
	return r

func test_fire_fan_trail_20pct_2s():
	return _trail_case(["split", "fire"], 0.20, 2.0)

func test_brahmastra_trail_30pct_3s():
	return _trail_case(["split", "fire", "multiply"], 0.30, 3.0)

## Review Focus 2: the 3 split lines of one press each lay a trail; a monster where they cross burns once a second
## (HP loss over 1 s + 1 frame = one trail tick), not three times.
func test_three_trails_burn_once_per_sec():
	_spawned = []
	var b := _build(["split", "fire"])
	var d := _dummy(Vector2(12, 0))
	var arrows := _fan(b, [d])
	var hp0: int = d.hp
	for i in int(round(1.0 / DT)) + 1: _step(arrows, [d])
	var per := 0.20 * ATK * float(b.arrow_mult)
	var burn: float = d.status.burn_per_tick        # the fire gem's own burn (from the arrows' hits) ticks once too
	var want := int(floor(per + burn + 1e-6))
	var r := ""
	if _trails(arrows).size() != 3: r = "%d trails, want one per line (3)" % _trails(arrows).size()
	elif not is_equal_approx(d.status.trail_per_tick, per): r = "per tick %s, want %s (not stacked)" % [d.status.trail_per_tick, per]
	elif hp0 - d.hp != want: r = "HP loss over 1 s = %d, want one trail tick + one burn tick (%d)" % [hp0 - d.hp, want]
	_free(arrows + [d])
	return r

## พัดเพลิงพรหมาสตร์: each line blasts once where it ends: r32, 50 % of the arrow's hit. A dummy 31 px past a line's
## end takes one hit at arrow_mult × 0.5; one 33 px past takes none; 3 blasts in all.
func test_brahmastra_line_end_blast():
	_spawned = []
	var b := _build(["split", "fire", "multiply"])
	var rng := Balance.num("skills.piercing.range")
	var near: Array = []
	var far: Array = []
	var n := int(b.arrows)
	var fan := deg_to_rad(float(b.fan_deg))
	for i in n:
		var dir := Vector2.RIGHT.rotated(-fan / 2.0 + fan * i / (n - 1))
		near.append(_dummy(dir * (rng + 31.0)))
		far.append(_dummy(dir * (rng + 33.0)))
	var ds: Array = near + far
	var arrows := _fan(b, ds)
	for i in 60: _step(arrows, [])
	var r := ""
	var blasts := 0
	for d in near:
		blasts += d.hits.size()
		if d.hits.size() != 1: r = "a dummy 31 px past a line end took %d hits, want 1" % d.hits.size()
		elif not is_equal_approx(float(d.hits[0][1]), float(b.arrow_mult) * 0.5): r = "blast mult %s, want %s" % [d.hits[0][1], float(b.arrow_mult) * 0.5]
		if r != "": break
	if r == "":
		for d in far:
			if not d.hits.is_empty(): r = "a dummy 33 px past a line end was hit"
	if r == "" and blasts != 3: r = "%d blasts, want 3" % blasts
	if r == "":                                      # the line ends once: a second _finish blasts nothing more
		for a in arrows: a._finish()
		var again := 0
		for d in near: again += d.hits.size()
		if again != 3: r = "a second _finish blasted again (%d hits)" % again
	_free(arrows + ds)
	return r

## Secondary hits (blasts) never trigger combo or gem on-hit effects: no bounce arrow, no new trail, no element burn
## (the blast's own `burn` flag only), no further blast. A brahmastra + ricochet primary arrow bounces once, from its
## own first hit only, even when its line-end blast hits two monsters next to each other.
func test_secondary_hits_trigger_nothing():
	_spawned = []
	var b := _build(["split", "fire", "multiply", "ricochet"])
	var r := "" if String(b.combo.get("id", "")) == "brahmastra" and int(b.bounces) > 0 else "setup: build %s bounces %s" % [b.combo, b.bounces]
	var p := Vector2(100, 100)
	var d1 := _dummy(p)
	var d2 := _dummy(p + Vector2(20, 0))
	var a := _arrow(Vector2.RIGHT, [d1, d2], b)
	var made := FireTrail.made
	if r == "":
		var n := a.blast(p, 32.0, 0.5, false)
		if n != 2: r = "blast hit %d, want 2" % n
		elif not _spawned.is_empty(): r = "a blast hit spawned %d bounce arrows" % _spawned.size()
		elif FireTrail.made != made: r = "a blast hit laid a trail"
		elif not d1.statuses.is_empty() or not d2.statuses.is_empty(): r = "a blast without burn applied %s" % [d1.statuses + d2.statuses]
		elif not is_equal_approx(float(d1.hits[0][1]), float(b.arrow_mult) * 0.5): r = "blast mult %s" % d1.hits[0][1]
	if r == "":
		var n := a.blast(p, 32.0, 1.0, true, null, [d2])     # burn = true (D5 / earth_piercer), d2 skipped
		if n != 1 or d2.hits.size() != 1: r = "skip: hit %d, d2 hits %d" % [n, d2.hits.size()]
		elif d1.statuses.size() != 1 or d1.statuses[0][0] != "burn" or not is_same(d1.statuses[0][2], b.cast): r = "burn blast: statuses %s, want one burn with the press's cast" % [d1.statuses]
	if r == "":
		var far := _dummy(p + Vector2(200, 0))
		a.targets = [d1, d2, far]
		var n := a.blast(p, 32.0, 0.5, false, far)           # include: hit even outside the radius
		if n != 3 or far.hits.size() != 1: r = "include: hit %d, far hits %d" % [n, far.hits.size()]
		far.free()
	_free([a, d1, d2])
	if r != "": return r
	# a whole flight: d0 on the line near the start (bounce to db), a pair past the line end (blast)
	_spawned = []
	var rng := Balance.num("skills.piercing.range")
	var d0 := _dummy(Vector2(40, 0))
	var db := _dummy(Vector2(40, 90))
	var e1 := _dummy(Vector2(rng + 14.0, 0))      # past the arrow's own reach (hit radius 10)
	var e2 := _dummy(Vector2(rng + 28.0, 0))
	made = FireTrail.made
	var f := _arrow(Vector2.RIGHT, [d0, db, e1, e2], b)
	for i in 90: _step([f], [])
	if _spawned.size() != 1: r = "%d bounce arrows, want 1 (from the first hit only)" % _spawned.size()
	elif e1.hits.size() != 1 or e2.hits.size() != 1: r = "line-end blast hits %d / %d, want 1 / 1" % [e1.hits.size(), e2.hits.size()]
	elif FireTrail.made - made != 1: r = "%d trails, want 1 (the primary arrow's)" % (FireTrail.made - made)
	_free([f] + _spawned + [d0, db, e1, e2])
	return r

## A bounce arrow (ricochet) is not a primary arrow: it lays no trail and has no line end.
func test_bounce_arrows_lay_no_trail():
	_spawned = []
	var b := _build(["split", "fire", "ricochet"])
	var d0 := _dummy(Vector2(60, 0))
	var d1 := _dummy(Vector2(60, 96))
	var made := FireTrail.made
	var a := _arrow(Vector2.RIGHT, [d0, d1], b)
	for i in 90: _step([a], [d0, d1])
	var r := ""
	if String(b.combo.get("id", "")) != "fire_fan": r = "setup: combo %s" % b.combo
	elif _spawned.size() != 1: r = "%d bounce arrows, want 1" % _spawned.size()
	elif _spawned[0].primary: r = "the bounce arrow is primary"
	elif _spawned[0].trail != null: r = "the bounce arrow laid a trail"
	elif FireTrail.made - made != 1: r = "%d trails, want 1" % (FireTrail.made - made)
	elif d1.hits.size() != 1: r = "the bounce did not hit"
	_free([a] + _spawned + [d0, d1])
	return r

## A build without a combo: a primary arrow lays no trail and blasts nothing at its line end.
func test_no_combo_arrow_unchanged():
	_spawned = []
	var b := _build(["split"])
	var rng := Balance.num("skills.piercing.range")
	var on := _dummy(Vector2(60, 0))
	var past := _dummy(Vector2(rng + 14.0, 0))
	var made := FireTrail.made
	var a := _arrow(Vector2.RIGHT, [on, past], b)
	for i in 90: _step([a], [on, past])
	var r := ""
	if not b.combo.is_empty(): r = "setup: [split] formed %s" % b.combo
	elif a.trail != null or FireTrail.made != made: r = "a no-combo arrow laid a trail"
	elif not past.hits.is_empty(): r = "a no-combo arrow blasted at its line end"
	elif on.hits.size() != 1 or not is_equal_approx(float(on.hits[0][1]), float(b.arrow_mult)): r = "the arrow's own hit changed: %s" % [on.hits]
	elif on.status.in_trail(): r = "a trail status without a trail"
	_free([a, on, past])
	return r

## B20: halt() (the warp) stops the trail at once (no tick after it) and the line never blasts.
func test_halt_ends_trail_and_skips_blast():
	_spawned = []
	var b := _build(["split", "fire", "multiply"])
	var rng := Balance.num("skills.piercing.range")
	var on := _dummy(Vector2(30, 0))
	var past := _dummy(Vector2(rng + 14.0, 0))
	var a := _arrow(Vector2.RIGHT, [on, past], b)
	for i in 12: _step([a], [on, past])
	var r := ""
	var t: FireTrail = a.trail
	if t == null or not on.status.in_trail(): r = "setup: no trail on the dummy before the warp"
	if r == "":
		var hp0: int = on.hp
		a.halt()
		if not t.done: r = "the trail is still on after halt()"
		for i in 240: _step([a], [on, past])
		if r == "" and on.hp != hp0: r = "the trail burned after the warp (%d)" % (hp0 - on.hp)
		elif r == "" and not past.hits.is_empty(): r = "a halted arrow blasted its line end"
	_free([a, on, past])
	return r

## Performance: a trail lays at most FireTrail.MAX_FX effects however long the line (spaced marks, not one per
## frame), stepping it allocates nothing, and the PerfSaver keeps one patch on every mark (the hazard stays readable)
## and never touches the damage.
## Review M2: the monster in the fire is a real Wolf (its apply_trail + tick_burn every frame, DEF factor cached:
## built once) and the trail is stepped through its fade to its end.
func test_trail_fx_bounded():
	var r := ""
	for saver in [false, true]:
		PerfSaver.active = saver
		var d: Wolf = load("res://scenes/wolf.tscn").instantiate()
		d.setup()
		d.health.setup(1000000)
		d.position += Vector2(500, 0) - d.hurt_point()       # its hurt point on the line
		var t := FireTrail.new()
		t.setup(Vector2.ZERO, ATK, 2.0, 0.3, 3.0, [d], null, null, 0.0, "brahmastra")
		for i in 300: t.extend_to(Vector2(i * 4.0, 0))      # a 1200 px line, extended every frame
		var fx := t.get_children().filter(func(c): return c is FxSprite)
		var patches := fx.filter(func(c): return c.animation == "fire_trail")
		if fx.size() > FireTrail.MAX_FX: r = "%d effects on one trail, cap %d" % [fx.size(), FireTrail.MAX_FX]
		elif patches.size() != FireTrail.MAX_STREAKS: r = "saver %s: %d patches on a 1200 px line, want one on each of its %d marks" % [saver, patches.size(), FireTrail.MAX_STREAKS]
		elif patches.size() != fx.size(): r = "effects other than fire patches on the trail: %s" % [fx.map(func(c): return c.animation)]
		elif not _one_patch_per_mark(t, patches): r = "saver %s: a mark of the line has no patch on it" % saver
		if r == "":
			t.finish()
			t.step(DT)                                    # first contact (and the DEF factor) before counting
			d.tick_burn(DT)
			var objs := Performance.get_monitor(Performance.OBJECT_COUNT)
			var kids := t.get_child_count()
			var hp0: int = d.health.hp
			var burned := false
			for i in int(round(3.0 / DT)) + 30:          # past the fade (last FADE s) and _end
				t.step(DT)
				d.tick_burn(DT)
				burned = burned or d.status.in_trail()
			if Performance.get_monitor(Performance.OBJECT_COUNT) != objs: r = "step() allocated objects (%d → %d)" % [objs, Performance.get_monitor(Performance.OBJECT_COUNT)]
			elif t.get_child_count() != kids: r = "step() added effects"
			elif not burned or d.health.hp >= hp0: r = "saver %s: the trail did not burn a wolf on its line" % saver
			elif not t.done: r = "the trail did not end after its 3 s"
			elif d.def_builds != 1: r = "the wolf's DEF factor was built %d times over the trail, want 1" % d.def_builds
		t.free()
		d.free()
		if r != "": break
	PerfSaver.active = false
	return r

## A very short line (the arrow stopped on a close monster) still shows one streak, so the fire is never invisible.
func test_short_trail_still_shows():
	var t := FireTrail.new()
	t.setup(Vector2.ZERO, ATK, 1.0, 0.2, 2.0, [], null, null, 0.0, "fire_fan")
	t.extend_to(Vector2(12, 0))
	t.finish()
	var n := t.get_children().filter(func(c): return c is FxSprite and c.animation == "fire_trail").size()
	t.free()
	return "" if n == 1 else "a 12 px trail shows %d fire patches, want 1" % n

## True when every recorded mark of trail t has a patch standing on it (t not in a tree: positions are in its space).
func _one_patch_per_mark(t: FireTrail, patches: Array) -> bool:
	for q in t.points():
		if not patches.any(func(c): return c.position.distance_to(q) < 0.01): return false
	return true

## Owner 2026-11-09 ("ย่อให้เท่าภาพตัวอย่าง"): every patch is drawn at FireTrail.PATCH_SCALE = 0.4 in world space
## (the size of the owner's sample, pasted 1 sheet px = 1 screen px on a 2.5x screen), nearest-filtered, with the sheet's
## anchor (the feet) exactly on its mark, i.e. on the path; the patch's drawn box (17.6 x 19.6) stands on the mark.
## A long bent line still lays at most MAX_STREAKS patches, one per SPACING px (44, unchanged), and with the PerfSaver
## on every mark keeps one readable patch (visible, opaque, the same small size). The blast's own 1:1 is checked in
## test_line_end_blast_plays_once_and_frees.
func test_trail_patches_drawn_at_sample_size():
	var r := ""
	if not is_equal_approx(FireTrail.PATCH_SCALE, 0.4): return "PATCH_SCALE %s, want 0.4 (owner: the sample's size)" % FireTrail.PATCH_SCALE
	if FireTrail.SPACING != 44.0 or FireTrail.MAX_STREAKS != 6: return "spacing %s / %d marks changed (owner: unchanged)" % [FireTrail.SPACING, FireTrail.MAX_STREAKS]
	var man: Dictionary = FxSprite._manifest().fire_trail
	var anchor := Vector2(man.anchor[0], man.anchor[1])
	var cell := Vector2(man.cell[0], man.cell[1])
	for saver in [false, true]:
		PerfSaver.active = saver
		var t := FireTrail.new()
		t.setup(Vector2(10, 20), ATK, 1.0, 0.2, 2.0, [], null, null, 0.0, "brahmastra")
		var at := Vector2(10, 20)
		for i in 400:                                   # a 1600 px path that bends (homing-like), extended every frame
			at += Vector2.RIGHT.rotated(i * 0.01) * 4.0
			t.extend_to(at)
		var patches := t.get_children().filter(func(c): return c is FxSprite and c.animation == "fire_trail")
		var marks := t.points()
		if patches.size() != FireTrail.MAX_STREAKS or marks.size() != FireTrail.MAX_STREAKS:
			r = "saver %s: %d patches / %d marks on a 1600 px line, want %d (bounded)" % [saver, patches.size(), marks.size(), FireTrail.MAX_STREAKS]
		elif not _one_patch_per_mark(t, patches): r = "saver %s: a mark has no patch" % saver
		for i in patches.size():
			if r != "": break
			var s: FxSprite = patches[i]
			var feet: Vector2 = s.transform * (s.offset + anchor)        # where the sheet's anchor pixel is drawn
			var box := Rect2(s.transform * s.offset, cell * s.scale)
			if not s.scale.is_equal_approx(Vector2(0.4, 0.4)): r = "saver %s: patch %d drawn at %s, want 0.4" % [saver, i, s.scale]
			elif s.texture_filter != CanvasItem.TEXTURE_FILTER_NEAREST: r = "patch %d not nearest-filtered" % i
			elif feet.distance_to(marks[i]) > 0.01: r = "patch %d's feet at %s, its mark at %s (want on the path)" % [i, feet, marks[i]]
			elif not box.size.is_equal_approx(Vector2(17.6, 19.6)): r = "patch %d box %s, want 17.6 x 19.6 world px" % [i, box.size]
			elif absf(box.end.y - marks[i].y - (cell.y - anchor.y) * 0.4) > 0.01: r = "patch %d box bottom %.2f, want %.2f below its mark" % [i, box.end.y - marks[i].y, (cell.y - anchor.y) * 0.4]
			elif not s.visible or s.modulate.a < 1.0 or t.modulate.a < 1.0: r = "saver %s: patch %d is not readable (visible %s, alpha %.2f)" % [saver, i, s.visible, s.modulate.a]
		if r == "":                                      # the damage reach is not the art's: a monster between two small patches still burns
			var gap: Vector2 = (marks[1] + marks[2]) / 2.0
			if not t._near(gap, 10.0): r = "a point on the line between two patches is not in the fire"
		t.free()
		if r != "": break
	PerfSaver.active = false
	return r

## Owner 2026-11-09 (T2 sample, PHASE 7): the patches of a line never flicker in sync. Every patch plays the fire_trail
## loop from its own frame: neighbours 3..11 frames apart (circular), the same frames every run for the same line
## (deterministic), and another line (another first mark) starts elsewhere; patch_frame stays inside the loop.
func test_trail_patches_start_at_their_own_frames():
	var n := int(FxSprite._manifest().fire_trail.frames)
	var lines: Array = []
	for dir in [Vector2.RIGHT, Vector2.RIGHT, Vector2.RIGHT.rotated(0.5)]:
		var t := FireTrail.new()
		t.setup(Vector2(30, 40), ATK, 1.0, 0.2, 2.0, [], null, null, 0.0, "fire_fan")
		for i in 56: t.extend_to(Vector2(30, 40) + dir * (i * 4.0))     # 220 px, the piercing range: 5 marks
		lines.append(t)
	var frames: Array = []
	for t in lines:
		frames.append(t.get_children().filter(func(c): return c is FxSprite).map(func(c): return c.frame))
	var r := ""
	if frames[0].size() != 5: r = "a 220 px line has %d patches, want 5" % frames[0].size()
	elif frames[0] != frames[1]: r = "the same line twice starts its patches at %s and %s (want the same)" % [frames[0], frames[1]]
	elif frames[0] == frames[2]: r = "two different lines start their patches on the same frames %s" % [frames[0]]
	for f in frames:
		for i in f.size() - 1:
			var d := posmod(int(f[i + 1]) - int(f[i]), n)
			if r == "" and (mini(d, n - d) < 3 or d > 11): r = "neighbouring patches %d frames apart (%s), want 3..11" % [d, f]
	if r == "":
		for seed in [0, 1, -7, 123456789, 4294967295]:
			for i in FireTrail.MAX_STREAKS:
				var k := FireTrail.patch_frame(seed, i, n)
				if k < 0 or k >= n: r = "patch_frame(%d, %d) = %d outside 0..%d" % [seed, i, k, n - 1]
	for t in lines: t.free()
	return r

## The whole line fades out over its last FADE s (the patches stay on their marks until the line ends), then the trail
## is done; before that it is fully visible.
func test_trail_fades_out_at_its_end():
	var t := FireTrail.new()
	t.setup(Vector2.ZERO, ATK, 1.0, 0.2, 2.0, [], null, null, 0.0, "fire_fan")
	for i in 56: t.extend_to(Vector2(i * 4.0, 0))
	t.finish()
	var kids := t.get_child_count()
	var r := ""
	var last := 1.0
	var faded := false
	for i in int(round(2.0 / DT)) + 5:
		t.step(DT)
		if t.done: break
		if t.left >= FireTrail.FADE and t.modulate.a < 1.0: r = "faded %.2f with %.2f s left (fade starts at %.2f)" % [t.modulate.a, t.left, FireTrail.FADE]
		if t.modulate.a > last + 1e-6: r = "the fade went back up"
		last = t.modulate.a
		faded = faded or (t.modulate.a < 0.5 and t.modulate.a > 0.0)
		if t.get_child_count() != kids: r = "patches came or went while the line burned"
		if r != "": break
	if r == "" and not t.done: r = "the trail did not end after its 2 s"
	elif r == "" and not faded: r = "never seen half faded"
	t.free()
	return r

## FxSprite cache: every patch of every line shares one SpriteFrames, so the fire_trail sheet is loaded once (the first
## patch ever), never per shot or per patch; the blast's sheet likewise once.
func test_trail_and_blast_reuse_the_cached_frames():
	FxSprite.clear_cache()
	var loads := FxSprite.sheet_loads
	var lines: Array = []
	for k in 3:
		var t := FireTrail.new()
		t.setup(Vector2.ZERO, ATK, 1.0, 0.2, 2.0, [], null, null, 0.0, "brahmastra")
		for i in 56: t.extend_to(Vector2.RIGHT.rotated(k * 0.4) * (i * 4.0))
		lines.append(t)
	var after_trails := FxSprite.sheet_loads - loads
	var p := Node2D.new()
	for k in 3: ComboFx.play(p, "brahmastra", "line_end", Vector2(k * 10, 0))
	var after_blasts := FxSprite.sheet_loads - loads
	var sfs := {}
	for t in lines:
		for c in t.get_children(): sfs[c.sprite_frames] = true
	var r := ""
	if after_trails != 1: r = "3 lines × 5 patches loaded the trail sheet %d times, want 1" % after_trails
	elif after_blasts != 2: r = "3 blasts loaded %d more sheets, want 1 (the blast's, once)" % (after_blasts - after_trails)
	elif sfs.size() != 1: r = "the patches use %d SpriteFrames, want 1 shared" % sfs.size()
	elif p.get_children().map(func(c): return c.sprite_frames).any(func(f): return f != p.get_child(0).sprite_frames): r = "blasts do not share their frames"
	for t in lines: t.free()
	p.free()
	return r

## พรหมาสตร์ in game: each line end plays fire_blast (B2 grenade, one-shot) once, at 1:1 (its 64 px cell = the r32
## blast's 64 px, as sampled), from its first frame; it frees itself when done; the arrow's end never plays a second
## one; ศรพัดเพลิง (no blast) plays none. Shown with the PerfSaver on too (a hit effect is never shed).
func test_line_end_blast_plays_once_and_frees():
	await tree.process_frame                         # the runner's tree is live (this file runs first: still in _initialize)
	var r := ""
	for saver in [false, true]:
		for keys in [["split", "fire", "multiply"], ["split", "fire"]]:
			PerfSaver.active = saver
			_spawned = []
			var world := Node2D.new()
			tree.root.add_child(world)
			var b := _build(keys)
			var arrows := _fan(b, [])
			for a in arrows:
				a.process_mode = Node.PROCESS_MODE_DISABLED        # stepped by hand below
				world.add_child(a)
			for i in 60:
				for a in arrows:
					if is_instance_valid(a) and not a.spent: a.advance(DT)
			var blasts := world.get_children().filter(func(c): return c is FxSprite and c.animation == "fire_blast")
			var want := 3 if keys.size() == 3 else 0
			if blasts.size() != want: r = "saver %s %s: %d fire_blast, want %d" % [saver, keys, blasts.size(), want]
			for s in blasts:
				if r == "" and (s.sprite_frames.get_animation_loop("fire_blast") or not s.is_playing() or s.frame != 0): r = "a blast is not a one-shot playing from frame 0"
				elif r == "" and s.scale != Vector2.ONE: r = "blast drawn at %s, want 1:1 (64 px = r32)" % s.scale
				elif r == "" and s.modulate != Color.WHITE: r = "the blast is recoloured %s" % s.modulate
			if r == "":
				for a in arrows:
					if is_instance_valid(a): a._end_line()
				var again := world.get_children().filter(func(c): return c is FxSprite and c.animation == "fire_blast").size()
				if again != want: r = "a second line end played %d blasts" % (again - want)
			if r == "":
				for s in blasts: s.speed_scale = 40.0
				for i in 60: await tree.process_frame
				if blasts.any(func(s): return is_instance_valid(s)): r = "a blast is still there after it ended"
			world.queue_free()
			await tree.process_frame
			if r != "": break
		if r != "": break
	PerfSaver.active = false
	return r

## Task 4 review I1 / plan Task 5: a trail tick is credited to the press that laid it (build.cast) and leeches that
## press's own leech (build.leech) to the shooter; the dummy's tick_status leeches like Wolf.tick_burn.
func test_trail_carries_press_cast_and_leech():
	_spawned = []
	var b := _build(["split", "fire", "leech"])
	var sink := Sink.new()
	var d := _dummy(Vector2(60, 0))
	var a := _arrow(Vector2.RIGHT, [d], b, true, sink)
	var r := ""
	if float(b.leech) <= 0.0: r = "setup: no leech in the build"
	for i in 24: _step([a], [d])
	if r != "": pass
	elif not is_same(d.status.trail_cast, b.cast): r = "the trail's ledger is not the press's"
	elif not is_equal_approx(d.status.trail_leech, float(b.leech)): r = "trail leech %s, want the press's %s" % [d.status.trail_leech, b.leech]
	elif d.status.trail_source != sink: r = "trail source is not the shooter"
	if r == "":
		var before := sink.got
		for i in 60: _step([a], [d])
		# one trail tick with the press's leech + the fire gem's own burn tick with its leech (same press, same frame)
		var want: float = 0.20 * ATK * float(b.arrow_mult) * float(b.leech) + d.status.burn_per_tick * d.status.burn_leech
		if not is_equal_approx(sink.got - before, want): r = "one trail tick leeched %s, want %s" % [sink.got - before, want]
	_free([a, d])
	sink.free()
	return r

## Distance from p to the polyline pts.
func _dist_to_path(p: Vector2, pts: PackedVector2Array) -> float:
	var best := INF
	for i in pts.size() - 1:
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, pts[i], pts[i + 1]).distance_to(p))
	return best

## Review I1: a homing arrow's trail follows the path it really flew: its marks lie on that path and a monster on
## the curve burns, while one on the straight chord from the start to the end (inside the curve) does not, nor does
## one on the first heading. The arrow circles a target inside its turning circle (r = speed / turn ≈ 115 px), so
## its path bends ≥ 90° within its 220 px.
func test_homing_trail_follows_the_path():
	_spawned = []
	var b := _build(["split", "fire", "homing"])
	var h := _dummy(Vector2(40, 100))
	var a := _arrow(Vector2.RIGHT, [h], b)
	var path := PackedVector2Array([a.position])
	var f := 0
	while not a.spent and f < 120:
		_step([a], [])
		path.append(a.position)
		f += 1
	var r := ""
	var t: FireTrail = a.trail
	var turned := rad_to_deg(absf(Vector2.RIGHT.angle_to(a.dir)))
	var on := path[path.size() / 2]
	var chord := (path[0] + path[path.size() - 1]) / 2.0
	var first := Vector2(150, 0)
	if not bool(b.get("homing", false)) or String(b.combo.get("id", "")) != "fire_fan": r = "setup: build %s" % b.combo
	elif t == null or not t.finished: r = "setup: no finished trail"
	elif turned < 90.0: r = "setup: the path bent %.0f°, want ≥ 90" % turned
	elif Geometry2D.get_closest_point_to_segment(on, path[0], path[path.size() - 1]).distance_to(on) < 25.0: r = "setup: the path point is near the chord"
	elif _dist_to_path(chord, path) < 25.0 or _dist_to_path(first, path) < 25.0: r = "setup: a probe is near the path"
	if r == "":
		var streaks := t.get_children().filter(func(c): return c is FxSprite and c.animation == "fire_trail")
		if streaks.size() < 4: r = "%d fire patches on a 220 px path, want ≥ 4" % streaks.size()
		for s in streaks:
			if r == "" and _dist_to_path(s.position, path) > 2.0: r = "a trail mark at %s is %.1f px off the arrow's path" % [s.position, _dist_to_path(s.position, path)]
	if r == "":
		var p_on := _dummy(on)
		var p_chord := _dummy(chord)
		var p_first := _dummy(first)
		t.targets = [p_on, p_chord, p_first]
		var hp0: int = p_on.hp
		for i in int(round(1.0 / DT)) + 1:
			t.step(DT)
			for d in [p_on, p_chord, p_first]: d.tick_status(DT)
			if r == "" and (p_chord.status.in_trail() or p_first.status.in_trail()): r = "a monster off the path (chord / first heading) is in the fire"
		if r == "" and p_on.hp >= hp0: r = "a monster on the curved path did not burn"
		_free([p_on, p_chord, p_first])
	_free([a, h])
	return r

## Review I2: when a line ends on a hit (spread's arrows stop on their first monster), its line-end blast never hits
## that monster (the approved sim gives the single target no blast term); a neighbour inside r32 still takes 50 %.
func test_line_end_blast_skips_the_struck_target():
	_spawned = []
	var b := _build(["split", "fire", "multiply"], "spread")
	var d := _dummy(Vector2(60, 0))
	var nb := _dummy(Vector2(60, 20))            # 20 px off the line: not the arrow's, inside the r32 blast
	var a := _arrow(Vector2.RIGHT, [d, nb], b)
	for i in 40: _step([a], [])
	var r := ""
	if String(b.combo.get("id", "")) != "brahmastra" or bool(b.pierce_all): r = "setup: %s pierce_all %s" % [b.combo, b.pierce_all]
	elif not a.spent: r = "setup: the arrow did not stop on its target"
	elif d.hits.size() != 1: r = "the struck monster took %d hits, want 1 (its arrow only, no line-end blast)" % d.hits.size()
	elif not is_equal_approx(float(d.hits[0][1]), float(b.arrow_mult)): r = "the struck monster's hit mult %s" % d.hits[0][1]
	elif nb.hits.size() != 1 or not is_equal_approx(float(nb.hits[0][1]), float(b.arrow_mult) * 0.5): r = "the neighbour took %s, want one blast at 50 %%" % [nb.hits]
	_free([a, d, nb])
	return r

## Review I3: a trail tick is per_tick = frac × atk × mult × the press's expected crit factor
## (1 + crit_chance × (crit_mult − 1), as tools/gem_combo_sim.py multiplies every hit), with no per-tick roll.
func test_trail_tick_uses_expected_crit():
	var r := ""
	if not is_equal_approx(Combat.expected_crit(0.25, 2.0), 1.25): r = "expected_crit(0.25, 2.0) = %s" % Combat.expected_crit(0.25, 2.0)
	elif not is_equal_approx(Combat.expected_crit(-1.0, -1.0), 1.0 + Balance.num("crit.chance") * (Balance.num("crit.mult") - 1.0)): r = "base numbers: %s" % Combat.expected_crit(-1.0, -1.0)
	elif not is_equal_approx(Combat.expected_crit(1.5, 2.0), 2.0): r = "chance above 1 must clamp: %s" % Combat.expected_crit(1.5, 2.0)
	if r != "": return r
	_spawned = []
	var b := _build(["split", "fire"])
	var d := _dummy(Vector2(60, 0))
	var a := _arrow(Vector2.RIGHT, [d], b)
	a.crit_chance = 0.25
	a.crit_mult = 2.0
	for i in 20: _step([a], [d])
	var want := 0.20 * ATK * float(b.arrow_mult) * 1.25
	if not is_equal_approx(d.status.trail_per_tick, want): r = "trail per tick %s, want %s (× expected crit 1.25)" % [d.status.trail_per_tick, want]
	elif not is_equal_approx(a.trail.per_tick, want): r = "FireTrail.per_tick %s, want %s" % [a.trail.per_tick, want]
	_free([a, d])
	return r

## Review M1: a monster between two line ends (inside both r32 blasts) takes ONE line-end blast per press
## (cast.once("line_end", target)); the next press can blast it again.
func test_line_end_blast_once_per_target_per_press():
	var r := ""
	var rng := Balance.num("skills.piercing.range")
	var d: Node2D = null
	for press in 2:
		_spawned = []
		var b := _build(["split", "fire", "multiply"])     # a new press: a new ledger
		var fan := deg_to_rad(float(b.fan_deg))
		var e0 := Vector2.RIGHT.rotated(-fan / 2.0) * rng   # the ends of lines 0 and 1 (the middle line)
		var e1 := Vector2.RIGHT * rng
		var mid := (e0 + e1) / 2.0
		if d == null: d = _dummy(mid)
		if mid.distance_to(e0) > 31.0 or mid.distance_to(e1) > 31.0: r = "setup: the dummy is %.0f / %.0f px from the line ends" % [mid.distance_to(e0), mid.distance_to(e1)]
		var arrows := _fan(b, [d])
		for i in 60: _step(arrows, [])
		if r == "" and d.hits.size() != press + 1: r = "after press %d: %d hits, want %d (one line-end blast per target per press)" % [press + 1, d.hits.size(), press + 1]
		_free(arrows)
		if r != "": break
	_free([d])
	return r

## Review M5: the fire gem's burn from an arrow hit carries the press's ledger (build.cast), so a burn kill credits
## the press (Task 8).
func test_fire_gem_burn_carries_the_press_cast():
	_spawned = []
	var b := _build(["split", "fire"])
	var d := _dummy(Vector2(60, 0))
	var a := _arrow(Vector2.RIGHT, [d], b)
	for i in 20: _step([a], [d])
	var burns: Array = d.statuses.filter(func(s): return s[0] == "burn")
	var r := ""
	if burns.size() != 1: r = "%d burns, want 1" % burns.size()
	elif not is_same(burns[0][2], b.cast): r = "the hit's burn carries %s, want the press's cast" % [burns[0][2]]
	elif not is_same(d.status.burn_cast, b.cast): r = "the dummy's burn_cast is not the press's"
	_free([a, d])
	return r

# ---------- the hero's press ----------

func _hero(level: int, keys: Array) -> Hero:
	var h: Hero = load("res://scenes/hero.tscn").instantiate()
	h.setup_sprites()
	h.set_progress(level, 0)
	h.inventory.slots.clear()
	var gems: Array = []
	for k in keys: gems.append(_g(k))
	h.set_skill_gems({"piercing": gems})
	h.facing = 2
	_spawned = []
	h.shot.connect(func(a): _spawned.append(a))
	return h

func _press(h: Hero) -> void:
	h.try_skill("piercing")
	for i in 50: h.step(DT, Vector2.ZERO)

func _done(h: Hero) -> void:
	_free(_spawned)
	h.free()

## One ComboCast per press, shared by every arrow of the press (b.cast); the arrows of a skill press are primary.
func test_press_arrows_are_primary_and_share_one_cast():
	var h := _hero(10, ["split", "fire"])
	_press(h)
	var r := ""
	if _spawned.size() != 3: r = "%d arrows, want 3" % _spawned.size()
	else:
		var c = _spawned[0].build.get("cast")
		if not (c is ComboCast) or c.id != "fire_fan": r = "build.cast is %s" % c
		for a in _spawned:
			if r != "": break
			if not a.primary: r = "a skill arrow is not primary"
			elif not is_same(a.build.get("cast"), c): r = "arrows of one press have different ledgers"
	if r == "":
		var c0 = _spawned[0].build.cast
		_free(_spawned)
		_spawned = []
		h._skill_cd.clear()
		h.mp = h.max_mp()
		_press(h)
		if _spawned.is_empty() or is_same(_spawned[0].build.cast, c0): r = "a second press reused the first press's ledger"
	_done(h)
	return r

## ศรราหูอมจันทร์: +30 % damage when HP ≥ 70 % at the press (ComboCast.dmg_bonus multiplies the arrow mult).
func test_rahu_bonus_multiplies_the_arrow():
	var h := _hero(10, ["leech", "multiply", "execute"])
	var b := h.build("piercing")
	var r := "" if String(b.combo.get("id", "")) == "rahu" else "setup: combo %s" % b.combo
	if r == "":
		_press(h)
		if _spawned.size() != 1: r = "%d arrows" % _spawned.size()
		elif not is_equal_approx(_spawned[0].mult, float(b.arrow_mult) * 1.3): r = "full HP: mult %s, want %s × 1.3" % [_spawned[0].mult, b.arrow_mult]
	if r == "":
		_free(_spawned)
		_spawned = []
		h._skill_cd.clear()
		h.mp = h.max_mp()
		h.health.hp = int(h.health.max_hp * 0.69)
		_press(h)
		if _spawned.size() != 1 or not is_equal_approx(_spawned[0].mult, float(b.arrow_mult)): r = "HP 69 %%: mult %s, want %s (no bonus)" % [_spawned[0].mult if _spawned.size() > 0 else -1.0, b.arrow_mult]
	_done(h)
	return r

## The basic shot has no build: not primary, no trail.
func test_basic_shot_is_not_primary():
	var h := _hero(10, ["split", "fire"])
	h._fire(Vector2.ZERO, Vector2.RIGHT, 1.0, false)
	var r := "" if _spawned.size() == 1 and not _spawned[0].primary else "a basic shot is primary"
	_done(h)
	return r

# ---------- in game: warp and room change (B20) ----------

## A trail outlives its arrow by 2-3 s: the warp's dark stops it (no tick on an old-room monster) and the room change
## frees it, like arrows (test_pixelfx test_arrow_in_flight_at_warp_kills_nothing).
func test_trail_stops_at_warp_and_goes_with_the_room():
	if FileAccess.file_exists(TMP_SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))
	var g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = TMP_SAVE
	g.layout_seed = 1
	tree.root.add_child(g)
	await tree.process_frame
	await tree.process_frame
	g.go_to("c1r0", "", false)
	var h: Hero = g.hero
	h.set_physics_process(false)
	for p in g.packs: p.process_mode = Node.PROCESS_MODE_DISABLED
	var r := "" if not g.warps.is_empty() else "setup: no warp in c1r0"
	var b := _build(["split", "fire"])
	if r == "":
		h._fire(h.global_position + Vector2(0, -20), Vector2.RIGHT, float(b.arrow_mult), true, -1.0, b)
		for i in 50: await tree.physics_frame                     # the arrow is spent (0.61 s); its trail burns on
		var trails: Array = g.world.get_children().filter(func(c): return c is FireTrail and not c.is_queued_for_deletion())
		if trails.size() != 1: r = "%d trails in the world after the arrow, want 1" % trails.size()
		elif trails[0].done: r = "setup: the trail already ended"
		if r == "":
			var t: FireTrail = trails[0]
			g.warp_through(g.warps[0])
			g._fade_tween.pause()
			if not t.done: r = "the trail still burns during the warp's dark"
			g._fade_tween.custom_step(g.FADE_OUT + 0.01)
			await tree.process_frame
			if r == "":
				for c in g.world.get_children():
					if c is FireTrail and not c.is_queued_for_deletion(): r = "an old-room trail is left in %s" % g.room_id
	g.queue_free()
	await tree.process_frame
	if FileAccess.file_exists(TMP_SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))
	return r

## Task 5 review 2 (minor 2): the recorded marks (MAX_STREAKS × SPACING px of path) cover the longest arrow an arrow
## skill can fly, read from balance.json (shot.range and every skills.*.range), so the fire past the last mark is never
## a chord across a homing arrow's curve.
func test_trail_marks_cover_the_longest_range():
	var longest := Balance.num("shot.range")
	var skills: Dictionary = Balance.data().get("skills", {})
	for id in skills:
		if skills[id] is Dictionary and skills[id].has("range"): longest = maxf(longest, float(skills[id].range))
	if longest <= 0.0: return "no arrow range found in balance.json"
	if FireTrail.MAX_STREAKS * FireTrail.SPACING < longest:
		return "marks cover %.0f px, the longest arrow range is %.0f px" % [FireTrail.MAX_STREAKS * FireTrail.SPACING, longest]
	return ""

## Task 5 review 2 (minor 3): a target outside the trail's path box (grown by its hit radius) costs no segment check;
## one on the line still burns, one just off the end of the box by less than its radius is still checked.
func test_trail_box_skips_far_targets():
	var near := _dummy(Vector2(21, 7))          # on the first leg (0,0) → (100,30)
	var far := _dummy(Vector2(120, 400))
	var t := FireTrail.new()
	t.setup(Vector2.ZERO, ATK, 1.0, 0.2, 2.0, [far], null)
	t.extend_to(Vector2(100, 30))
	t.extend_to(Vector2(200, 0))
	t.finish()
	var r := ""
	t.step(DT)
	if t.seg_checks != 0: r = "a target 400 px off the line cost %d segment checks" % t.seg_checks
	elif far.status.in_trail(): r = "a far target is in the fire"
	if r == "":
		t.targets = [near]
		t.step(DT)
		if t.seg_checks == 0: r = "a target on the line was skipped by the box"
		elif not near.status.in_trail(): r = "a target on the line is not in the fire"
	if r == "":
		var edge := _dummy(Vector2(205, 0))          # 5 px past `to`, inside the 10 px hit radius
		t.targets = [edge]
		t.step(DT)
		if not edge.status.in_trail(): r = "a target within the hit radius past the box edge is not in the fire"
		edge.free()
	t.free()
	_free([near, far])
	return r

# ---------- lightning combos (Task 6: ศรอสนีกระโดด, ศรอสนีพันสาย) ----------

## Hits on `d` that an arrow dealt directly (the hit's origin is the arrow, within its hit radius of the hurt point),
## not a chain (origin = the struck monster's hurt point) or a bolt (origin = the bouncing arrow, far away).
func _direct(d: Node2D) -> Array:
	return d.hits.filter(func(h): return (h[2] as Vector2).distance_to(d.hurt_point()) <= Balance.num("shot.arrow_hit_radius") + 0.01)

## Flies one primary arrow of build `b` from the origin to the right, frame by frame; returns the names (keys of
## `named`) in the order each first took a direct arrow hit.
func _direct_order(b: Dictionary, named: Dictionary) -> Array:
	_spawned = []
	var order: Array = []
	var a := _arrow(Vector2.RIGHT, named.values(), b)
	for i in 120:
		_step([a], [])
		for k in named:
			if not k in order and not _direct(named[k]).is_empty(): order.append(k)
	_free([a] + _spawned)
	return order

## ศรอสนีกระโดด on ศรทะลวง: the gem's one bounce (a piercing arrow bounces from its first target only) + 1 extra:
## A (on the line) → B → C. Ricochet alone: A → B only (the existing rule).
func test_thunder_hop_two_bounces_on_piercing():
	var b := _build(["ricochet", "lightning"])
	var r := "" if String(b.combo.get("id", "")) == "thunder_hop" and int(b.extra_bounces) == 1 else "setup: combo %s extra %s" % [b.combo, b.get("extra_bounces")]
	var ds := {"A": _dummy(Vector2(60, 0)), "B": _dummy(Vector2(60, 90)), "C": _dummy(Vector2(60, 180))}
	if r == "":
		var order := _direct_order(b, ds)
		if order != ["A", "B", "C"]: r = "thunder_hop direct hits %s, want [A, B, C]" % [order]
	if r == "":
		for k in ds: ds[k].hits.clear()
		var plain := _build(["ricochet"])
		var order := _direct_order(plain, ds)
		if not plain.combo.is_empty(): r = "setup: [ricochet] formed %s" % plain.combo
		elif order != ["A", "B"]: r = "ricochet alone: direct hits %s, want [A, B]" % [order]
	_free(ds.values())
	return r

## Every bounce of ศรอสนีกระโดด bolts the nearest other monster (not the struck one, not the next) for 50 % of the
## press's FIRST hit, flat at every bounce (owner 2026-11-09, Task 6 review: "50% ของนัดแรก คงที่"): D1 by the bounce
## at A (k = 0), D2 by the bounce at B (k = 1: still arrow_mult × 0.50, not × bounce_mult). One bolt per bounce, and
## no chain lands on D1 / D2 (A is 100 px from B; D2 85 px; C 70 px).
func test_thunder_hop_bolt_per_bounce():
	var b := _build(["ricochet", "lightning"])
	var am := float(b.arrow_mult)
	var bm := float(b.bounce_mult)
	var ds := {"A": _dummy(Vector2(60, 0)), "B": _dummy(Vector2(60, 100)), "C": _dummy(Vector2(60, 170)),
		"D1": _dummy(Vector2(60, -110)), "D2": _dummy(Vector2(145, 100))}
	var order := _direct_order(b, ds)
	var r := ""
	if order != ["A", "B", "C"]: r = "setup: direct hits %s, want [A, B, C]" % [order]
	elif ds.D1.hits.size() != 1: r = "D1 (by the bounce at A) took %d hits, want 1 bolt" % ds.D1.hits.size()
	elif ds.D2.hits.size() != 1: r = "D2 (by the bounce at B) took %d hits, want 1 bolt" % ds.D2.hits.size()
	elif not is_equal_approx(float(ds.D1.hits[0][1]), am * 0.5): r = "bolt at the 1st bounce mult %s, want %s × 0.50" % [ds.D1.hits[0][1], am]
	elif not is_equal_approx(float(ds.D2.hits[0][1]), am * 0.5): r = "bolt at the 2nd bounce mult %s, want %s × 0.50 (flat, not × bounce_mult %s)" % [ds.D2.hits[0][1], am, bm]
	elif not is_equal_approx(float(_direct(ds.B)[0][1]), am * bm): r = "setup: the 1st bounce arrow's hit %s, want %s × %s" % [_direct(ds.B)[0][1], am, bm]
	elif not ds.D1.statuses.is_empty() or not ds.D2.statuses.is_empty(): r = "a bolt applied a status"
	_free(ds.values())
	return r

## ศรอสนีพันสาย (ricochet + lightning + split) on ศรทะลวง: all 3 lines bounce, once each (the tier-3 row replaces its
## base: no extra bounce), and every bounce bolts the 2 nearest distinct others (X, Y; Z, 3rd nearest, never) at 50 %.
func test_thousand_bolts_two_bolts_no_extra():
	var b := _build(["ricochet", "lightning", "split"])
	var r := "" if String(b.combo.get("id", "")) == "thousand_bolts" and int(b.extra_bounces) == 0 and int(b.arrows) == 3 else "setup: combo %s extra %s arrows %s" % [b.combo, b.get("extra_bounces"), b.get("arrows")]
	var t := _dummy(Vector2(40, 0))          # all 3 lines (±12°) pass within the hit radius here
	var nb := _dummy(Vector2(40, 60))        # the bounce target (nearest)
	var x := _dummy(Vector2(40, -70))
	var y := _dummy(Vector2(-35, 0))
	var z := _dummy(Vector2(40, -115))
	var all := [t, nb, x, y, z]
	_spawned = []
	var arrows := _fan(b, all)
	if r == "":
		for i in 120: _step(arrows, [])
		var am := float(b.arrow_mult)
		if _direct(t).size() != 3: r = "%d lines hit the first target, want 3" % _direct(t).size()
		elif _spawned.size() != 3: r = "%d bounce arrows, want 3 (one per line, no extra)" % _spawned.size()
		elif _spawned.any(func(s): return int(s.build.get("bounces", -1)) != 0): r = "a bounce arrow can bounce again"
		elif _direct(nb).size() != 3: r = "the bounce target took %d bounce hits, want 3" % _direct(nb).size()
		elif x.hits.size() != 3 or y.hits.size() != 3: r = "bolts: X %d, Y %d, want 3 each (2 per bounce, 3 bounces)" % [x.hits.size(), y.hits.size()]
		elif not z.hits.is_empty(): r = "the 3rd nearest took %d bolts (only 2 per bounce)" % z.hits.size()
		else:
			for h in x.hits + y.hits:
				if not is_equal_approx(float(h[1]), am * 0.5): r = "bolt mult %s, want %s × 0.50" % [h[1], am]
	_free(arrows + _spawned + all)
	return r

## bolts() with nothing to hit is safe and hits nothing: a lone target (skipped), n = 0, a dead or freed target.
func test_bolt_without_target_is_safe():
	var b := _build(["ricochet", "lightning"])
	var t := _dummy(Vector2(60, 0))
	var a := _arrow(Vector2.RIGHT, [t], b)
	var r := ""
	if a.bolts(t.hurt_point(), 1, 0.5, [t]) != 0: r = "a lone target: bolted something"
	elif a.bolts(t.hurt_point(), 0, 0.5, []) != 0: r = "n = 0 bolted"
	elif not t.hits.is_empty(): r = "the lone target was hit"
	if r == "":
		var dead := _dummy(Vector2(60, 40))
		dead.alive = false
		var gone := _dummy(Vector2(60, 50))
		a.targets = [t, dead, gone]
		gone.free()
		if a.bolts(t.hurt_point(), 2, 0.5, [t]) != 0: r = "bolted a dead or freed target"
		dead.free()
		a.targets = [t]
	if r == "":
		_spawned = []
		for i in 90: _step([a], [])                  # a whole flight past a lone target: no bounce, no bolt, no error
		if not _spawned.is_empty(): r = "a lone target: %d bounce arrows" % _spawned.size()
		elif _direct(t).size() != 1 or t.hits.size() != 1: r = "the lone target took %s, want one direct hit" % [t.hits]
	_free([a, t])
	return r

## bolts() hits the n nearest distinct live targets within elements.lightning.range (120), skipping `skip`, each a
## secondary hit (no bounce arrow, no element chain or status from the bolt target, no trail).
func test_bolts_nearest_in_range_and_secondary():
	var b := _build(["ricochet", "lightning", "split"])
	var from := Vector2(100, 100)
	var s := _dummy(from)
	var n1 := _dummy(from + Vector2(30, 0))
	var n2 := _dummy(from + Vector2(0, 50))
	var n3 := _dummy(from + Vector2(-80, 0))
	var out := _dummy(from + Vector2(0, -125))      # past 120 px
	var close := _dummy(from + Vector2(30, 10))     # 31.6 px from from, 10 from n1 (a chain would land here)
	var all := [s, n1, n2, n3, out, close]
	var a := _arrow(Vector2.RIGHT, all, b)
	_spawned = []
	var made := FireTrail.made
	var r := ""
	var n: int = a.bolts(from, 2, 0.5, [s, close])
	if n != 2: r = "bolts hit %d, want 2" % n
	elif n1.hits.size() != 1 or n2.hits.size() != 1: r = "the 2 nearest took %d / %d, want 1 / 1" % [n1.hits.size(), n2.hits.size()]
	elif not n3.hits.is_empty() or not out.hits.is_empty() or not s.hits.is_empty(): r = "bolted past the 2 nearest, out of range or a skipped target"
	elif not close.hits.is_empty(): r = "a bolt hit chained (lightning gem) to the target next to it"
	elif not _spawned.is_empty() or FireTrail.made != made: r = "a bolt spawned an arrow or a trail"
	elif not n1.statuses.is_empty(): r = "a bolt applied a status"
	if r == "" and a.bolts(from, 9, 0.5, [s]) != 4: r = "n larger than the targets in range should hit all 4 in range"
	_free([a] + all)
	return r

## The lightning gem's own chain (+1 target within 120 px at ×0.8) still happens on the arrows' hits with the combo
## on (gems keep working): B, the nearest other to A, takes a chain hit whose origin is A.
func test_lightning_gem_chain_still_works():
	var b := _build(["ricochet", "lightning"])
	var a_ := _dummy(Vector2(60, 0))
	var b_ := _dummy(Vector2(60, 60))
	var order := _direct_order(b, {"A": a_, "B": b_})
	var chain: Array = b_.hits.filter(func(h): return h[2] == a_.hurt_point())
	var r := ""
	if order != ["A", "B"]: r = "setup: direct hits %s" % [order]
	elif chain.size() != 1: r = "B took %d chain hits from A, want 1 (hits %s)" % [chain.size(), b_.hits]
	elif not is_equal_approx(float(chain[0][1]), float(b.arrow_mult) * Balance.num("elements.lightning.mult")): r = "chain mult %s, want %s × 0.8" % [chain[0][1], b.arrow_mult]
	_free([a_, b_])
	return r

## In game: each bounce plays the recipe's "bounce" effect (hit_spark #7fd4ff) at the bounce point, each bolt its
## "bolt" effect (chain_zap) on the bolted monster: พันสาย plays chain_zap once per bolt. Hit effects, not shed by
## PerfSaver.
func test_bounce_and_bolt_fx():
	var r := ""
	for saver in [false, true]:
		PerfSaver.active = saver
		var world := Node2D.new()
		tree.root.add_child(world)
		var b := _build(["ricochet", "lightning", "split"])
		var from := Vector2(100, 100)
		var s := _dummy(from)
		var n1 := _dummy(from + Vector2(30, 0))
		var n2 := _dummy(from + Vector2(0, 50))
		var a := _arrow(Vector2.RIGHT, [s, n1, n2], b)
		world.add_child(a)
		var n: int = a.bolts(from, 2, 0.5, [s])
		var zaps := world.get_children().filter(func(c): return c is FxSprite and c.animation == "chain_zap")
		if n != 2 or zaps.size() != 2: r = "saver %s: %d bolts played %d chain_zap, want 2 / 2" % [saver, n, zaps.size()]
		elif not zaps.any(func(z): return z.position == n1.hurt_point()) or not zaps.any(func(z): return z.position == n2.hurt_point()): r = "a chain_zap is not on its bolted monster"
		if r == "":
			a._bounce_event(s, n1)
			var sparks := world.get_children().filter(func(c): return c is FxSprite and c.animation == "hit_spark")
			if sparks.size() != 1 or sparks[0].position != s.hurt_point() or sparks[0].modulate != Color("#7fd4ff"): r = "saver %s: the bounce played %d hit_spark, want one light-blue spark at the bounce point" % [saver, sparks.size()]
		world.free()
		_free([s, n1, n2])
		if r != "": break
	PerfSaver.active = false
	return r

## A build without the combo (ricochet + fire) gets no extra bounce and no bolt, on piercing and on spread.
func test_no_lightning_combo_no_bolt():
	var r := ""
	for skill in ["piercing", "spread"]:
		var b := _build(["ricochet", "fire"], skill)
		if not b.combo.is_empty() or int(b.extra_bounces) != 0: r = "%s [ricochet, fire]: combo %s extra %s" % [skill, b.combo, b.extra_bounces]
		if r != "": break
		var ds := {"A": _dummy(Vector2(60, 0)), "B": _dummy(Vector2(60, 90)), "C": _dummy(Vector2(60, 180)), "D": _dummy(Vector2(60, -110))}
		var order := _direct_order(b, ds)
		if order != ["A", "B"]: r = "%s [ricochet, fire]: direct hits %s, want [A, B]" % [skill, order]
		elif not ds.D.hits.is_empty() or not ds.C.hits.is_empty(): r = "%s: a no-combo bounce bolted" % skill
		_free(ds.values())
		if r != "": break
	return r

## ศรอสนีกระโดด on ศรกระจาย (not piercing): the gem's bounce chain (1 at gem Lv1) + 1 = 2 bounces per arrow.
func test_thunder_hop_on_spread_adds_one():
	var b := _build(["ricochet", "lightning"], "spread")
	var r := "" if String(b.combo.get("id", "")) == "thunder_hop" else "setup: spread combo %s" % b.combo
	var ds := {"A": _dummy(Vector2(60, 0)), "B": _dummy(Vector2(60, 90)), "C": _dummy(Vector2(60, 180)), "E": _dummy(Vector2(60, 270))}
	if r == "":
		var order := _direct_order(b, ds)
		if order != ["A", "B", "C"]: r = "spread thunder_hop direct hits %s, want [A, B, C] (1 + 1 bounces, not 3)" % [order]
	_free(ds.values())
	return r

# ---------- Task 6 review fixes (owner 2026-11-09: flat bolts, pierce gem bounces from the first target only) ----------

## A dummy that also records the crit chance / crit multiplier each hit was given (the bolt passes the arrow's).
class CritDummy extends "res://tests/dummy_enemy.gd":
	var crits: Array = []
	func receive_hit(atk: float, mult: float, from: Vector2, c := -1.0, cm := -1.0) -> int:
		crits.append([c, cm])
		return super(atk, mult, from, c, cm)

## The build of one press with gems at the given levels ({key: level}), char level `char_lv`, its ledger in b.cast.
func _build_lv(gems_lv: Dictionary, skill: String, char_lv: int) -> Dictionary:
	var gems: Array = []
	for k in gems_lv:
		var g := _g(k)
		g.level = int(gems_lv[k])
		gems.append(g)
	var b := SkillBuild.of(skill, char_lv, gems, STATS)
	b["cast"] = ComboCast.from_build(b)
	return b

## Owner 2026-11-09 (Task 6 review, "เด้งจากตัวแรกที่โดนเท่านั้น"): a pierce gem on ศรกระจาย (not a piercing skill)
## starts a bounce chain only from the first monster the arrow hits, like ศรทะลวง. [ricochet, pierce] Lv1: the arrow
## hits A, pierces on to P; only A bounces (to B). Q, 80 px from P and out of ricochet range of A, is never hit (the old
## rule bounced again at P, to Q).
func test_spread_pierce_gem_bounces_from_first_target_only():
	var b := _build(["ricochet", "pierce"], "spread")
	var r := "" if b.combo.is_empty() and int(b.pierce_extra) == 2 and int(b.bounces) == 1 and not bool(b.pierce_all) else "setup: combo %s pierce_extra %s bounces %s" % [b.combo, b.pierce_extra, b.bounces]
	var ds := {"A": _dummy(Vector2(60, 0)), "P": _dummy(Vector2(150, 0)), "B": _dummy(Vector2(60, 80)), "Q": _dummy(Vector2(150, 80))}
	if r == "":
		var order := _direct_order(b, ds)
		order.sort()
		if order != ["A", "B", "P"]: r = "direct hits %s, want A, P (pierced) and B (A's bounce) only" % [order]
		elif not ds.Q.hits.is_empty(): r = "Q took %d hits: the arrow bounced from the target it pierced" % ds.Q.hits.size()
		elif _direct(ds.B).size() != 1: r = "B took %d bounce hits, want 1" % _direct(ds.B).size()
	_free(ds.values())
	return r

## Dummies on the rays of build b's fan from the origin, at each distance in `dists`.
func _ray_grid(b: Dictionary, dists: Array) -> Array:
	var out: Array = []
	var n := int(b.arrows)
	var fan := deg_to_rad(float(b.fan_deg))
	for i in n:
		var dir := Vector2.RIGHT if n == 1 else Vector2.RIGHT.rotated(-fan / 2.0 + fan * i / (n - 1))
		for d in dists: out.append(_dummy(dir * float(d)))
	return out

## One press of build b into a dense pack (dummies on every ray at `dists`): [bounce events, bolts]. A bounce event
## spawns one bounce arrow; a bolt is the only hit at arrow_mult × bolt_frac (flat; owner 2026-11-09).
func _press_counts(b: Dictionary, dists: Array) -> Array:
	var all := _ray_grid(b, dists)
	_spawned = []
	var arrows := _fan(b, all)
	for i in 150: _step(arrows, [])
	var want := float(b.arrow_mult) * float(b.combo_p.get("bolt_frac", 0.0))
	var bolted := 0
	for d in all:
		for h in d.hits:
			if is_equal_approx(float(h[1]), want): bolted += 1
	var out := [_spawned.size(), bolted]
	_free(arrows + _spawned + all)
	return out

## The worst case of bolts per press (risks B29), gems at Lv10 (ricochet: 2 bounces; pierce: 3 more targets), every
## bounce and bolt finding a monster. Phase 1 (char Lv10): ศรกระจาย has 2 slots (skill Lv8) → [ricochet, lightning]
## = ศรอสนีกระโดด, 5 arrows × (2 + 1) = 15 bounces / 15 bolts; ศรทะลวง (skill Lv10, 3 slots) ศรอสนีพันสาย: 3 lines ×
## 1 bounce (piercing) × 2 = 6. Char Lv12 (ศรกระจาย slot 3): + pierce gem → still 15 / 15 (the old rule bounced at
## every pierced monster: 5 × 4 × 3 = 60); + split = ศรอสนีพันสาย: 7 arrows × 2 bounces × 2 bolts = 28.
func test_lightning_worst_case_bolts_per_press():
	var cases := [
		["spread Lv10 thunder_hop", {"ricochet": 10, "lightning": 1}, "spread", 10, "thunder_hop", 15, 15],
		["piercing Lv10 thousand_bolts", {"ricochet": 10, "lightning": 1, "split": 1}, "piercing", 10, "thousand_bolts", 3, 6],
		["spread Lv12 thunder_hop + pierce", {"ricochet": 10, "lightning": 1, "pierce": 10}, "spread", 12, "thunder_hop", 15, 15],
		["spread Lv12 thousand_bolts", {"ricochet": 10, "lightning": 1, "split": 1}, "spread", 12, "thousand_bolts", 14, 28],
	]
	for c in cases:
		var b := _build_lv(c[1], c[2], c[3])
		if String(b.combo.get("id", "")) != c[4]: return "%s: combo %s" % [c[0], b.combo]
		var got := _press_counts(b, [60, 95, 130, 165])
		if got != [c[5], c[6]]: return "%s: %d bounces / %d bolts per press, want %d / %d" % [c[0], got[0], got[1], c[5], c[6]]
	return ""

## Ricochet gem Lv10 (2 bounces) + ศรอสนีกระโดด on ศรกระจาย: 2 + 1 = 3 bounces (A → B → C → D, E never); on ศรทะลวง a
## piercing arrow still bounces once from its first target, + 1 (A → B → C).
func test_thunder_hop_ricochet_lv10_two_plus_one():
	var r := ""
	for c in [["spread", ["A", "B", "C", "D"]], ["piercing", ["A", "B", "C"]]]:
		var b := _build_lv({"ricochet": 10, "lightning": 1}, c[0], 12)
		if String(b.combo.get("id", "")) != "thunder_hop" or int(b.bounces) != 2: r = "setup %s: combo %s bounces %s" % [c[0], b.combo, b.bounces]
		var ds := {"A": _dummy(Vector2(60, 0)), "B": _dummy(Vector2(60, 90)), "C": _dummy(Vector2(60, 180)), "D": _dummy(Vector2(60, 270)), "E": _dummy(Vector2(60, 360))}
		if r == "":
			var order := _direct_order(b, ds)
			if order != c[1]: r = "%s ricochet Lv10 + thunder_hop: direct hits %s, want %s" % [c[0], order, c[1]]
		_free(ds.values())
		if r != "": break
	return r

## A bolt is a hit like any other: it gets the arrow's crit chance / crit multiplier (bounce arrows copy them, so the
## 2nd bounce's bolt too) and leeches through the shooter (the press's leech, here the leech gem's 3 %).
func test_bolt_can_crit_and_leeches():
	var b := _build(["ricochet", "lightning", "leech"])
	var r := "" if String(b.combo.get("id", "")) == "thunder_hop" and float(b.leech) > 0.0 else "setup: combo %s leech %s" % [b.combo, b.leech]
	var sink := Sink.new()
	var ds := {}
	for k in ["A", "B", "C", "D1", "D2"]: ds[k] = CritDummy.new()
	var at := {"A": Vector2(60, 0), "B": Vector2(60, 100), "C": Vector2(60, 170), "D1": Vector2(60, -110), "D2": Vector2(145, 100)}
	for k in ds: ds[k].position = at[k] + Vector2(0, 14)
	if r == "":
		_spawned = []
		var a := _arrow(Vector2.RIGHT, ds.values(), b, true, sink)
		a.crit_chance = 1.0
		a.crit_mult = 1.5
		for i in 120: _step([a], [])
		var am := float(b.arrow_mult)
		var total := 0
		for k in ds: total += ds[k].hits.size()
		if ds.D1.hits.size() != 1 or ds.D2.hits.size() != 1: r = "setup: D1 / D2 took %d / %d bolts, want 1 / 1" % [ds.D1.hits.size(), ds.D2.hits.size()]
		elif not is_equal_approx(float(ds.D2.hits[0][1]), am * 0.5): r = "the 2nd bounce's bolt mult %s, want %s × 0.50" % [ds.D2.hits[0][1], am]
		elif ds.D1.crits[0] != [1.0, 1.5] or ds.D2.crits[0] != [1.0, 1.5]: r = "bolts got crit %s / %s, want the arrow's [1, 1.5]" % [ds.D1.crits[0], ds.D2.crits[0]]
		elif not is_equal_approx(sink.got, total * float(b.leech)): r = "leech %s for %d hits, want %s (bolts leech too)" % [sink.got, total, total * float(b.leech)]
		if r == "":
			var before := sink.got
			if a.bolts(ds.A.hurt_point(), 2, 0.5, [ds.A]) != 2: r = "bolts() hit fewer than 2"
			elif not is_equal_approx(sink.got - before, 2 * float(b.leech)): r = "2 bolts leeched %s, want %s" % [sink.got - before, 2 * float(b.leech)]
		_free([a] + _spawned)
	_free(ds.values() + [sink])
	return r
