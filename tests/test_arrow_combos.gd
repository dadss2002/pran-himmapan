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
	a.spawned.connect(func(x): _spawned.append(x))
	return a

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
	var got := ComboFx.play(p, "fire_fan", "trail", Vector2(5, 7), Vector2.DOWN)
	var r := ""
	if got.size() != 2: r = "fire_fan trail spawned %d effects, want piercing_trail + status_burn" % got.size()
	elif got[0].animation != "piercing_trail" or got[0].modulate != Color("#ff8a3d"): r = "trail streak %s tint %s" % [got[0].animation, got[0].modulate]
	elif got[1].animation != "status_burn" or got[1].modulate != Color.WHITE: r = "flame %s tint %s" % [got[1].animation, got[1].modulate]
	elif got[0].position != Vector2(5, 7) or got[0].get_parent() != p: r = "streak not placed in the parent at the point"
	elif not is_equal_approx(got[0].rotation, Vector2.DOWN.angle()) or got[1].rotation != 0.0: r = "only the streak turns along the line (%s, %s)" % [got[0].rotation, got[1].rotation]
	elif not ComboFx.play(p, "fire_fan", "no_such_event", Vector2.ZERO).is_empty(): r = "an unknown event spawned something"
	elif not ComboFx.play(p, "", "trail", Vector2.ZERO).is_empty(): r = "no combo spawned something"
	elif not ComboFx.play(null, "fire_fan", "trail", Vector2.ZERO).is_empty(): r = "no parent spawned something"
	elif p.get_child_count() != 2: r = "%d children, want 2" % p.get_child_count()
	if r == "":
		var g := ComboFx.play(p, "garuda", "mark", Vector2.ZERO)
		if g.size() != 1 or g[0].animation != "lock_on" or g[0].modulate != Color("#edbb55"): r = "garuda mark should be a gold lock_on"
	p.free()
	return r

## PerfSaver sheds the decorative extras only (flames, crit glare → its fallback), never the trail streak (it shows
## where the fire is) or the line-end blast.
func test_combo_fx_perf_saver_sheds_decor_only():
	var p := Node2D.new()
	PerfSaver.active = true
	var trail := ComboFx.play(p, "brahmastra", "trail", Vector2.ZERO)
	var end := ComboFx.play(p, "brahmastra", "line_end", Vector2.ZERO)
	var crit := ComboFx.play(p, "hawk_eye", "crit", Vector2.ZERO)
	PerfSaver.active = false
	var r := ""
	if trail.size() != 1 or trail[0].animation != "piercing_trail": r = "saver on: trail gave %s, want the streak only" % [trail.map(func(s): return s.animation)]
	elif end.size() != 1 or end[0].animation != "spread_burst": r = "saver on: the line-end blast was shed"
	elif crit.size() != 1 or crit[0].animation != "hit_spark": r = "saver on: crit_hit should fall back to hit_spark"
	if r == "" and ComboFx.play(p, "brahmastra", "trail", Vector2.ZERO, Vector2.ZERO, false).map(func(s): return String(s.animation)) != ["piercing_trail"]:
		r = "decor = false must skip the flame"
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
## frame), stepping it allocates nothing, and the PerfSaver sheds the flames but never the streak or the damage.
func test_trail_fx_bounded():
	var r := ""
	for saver in [false, true]:
		PerfSaver.active = saver
		var d := _dummy(Vector2(500, 0))
		var t := FireTrail.new()
		t.setup(Vector2.ZERO, ATK, 2.0, 0.3, 3.0, [d], null, null, 0.0, "brahmastra")
		for i in 300: t.extend_to(Vector2(i * 4.0, 0))      # a 1200 px line, extended every frame
		var fx := t.get_children().filter(func(c): return c is FxSprite)
		var flames := fx.filter(func(c): return c.animation == "status_burn").size()
		var streaks := fx.filter(func(c): return c.animation == "piercing_trail").size()
		if fx.size() > FireTrail.MAX_FX: r = "%d effects on one trail, cap %d" % [fx.size(), FireTrail.MAX_FX]
		elif streaks < 3: r = "only %d streaks on a 1200 px line" % streaks
		elif saver and flames != 0: r = "saver on: %d flames" % flames
		elif not saver and flames == 0: r = "saver off: no flames"
		if r == "":
			t.finish()
			var objs := Performance.get_monitor(Performance.OBJECT_COUNT)
			var kids := t.get_child_count()
			for i in 100: t.step(DT)
			if Performance.get_monitor(Performance.OBJECT_COUNT) != objs: r = "step() allocated objects (%d → %d)" % [objs, Performance.get_monitor(Performance.OBJECT_COUNT)]
			elif t.get_child_count() != kids: r = "step() added effects"
			elif not d.status.in_trail(): r = "saver %s: the trail did not burn a monster on its line" % saver
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
	var n := t.get_children().filter(func(c): return c is FxSprite and c.animation == "piercing_trail").size()
	t.free()
	return "" if n == 1 else "a 12 px trail shows %d streaks, want 1" % n

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
