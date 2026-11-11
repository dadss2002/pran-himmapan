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
		var a := _arrow(dir, enemies, b, true, shooter)
		a.line = SkillBuild.line_of(b, i)          # as Hero._release / _fire
		out.append(a)
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
	# owner 2026-11-09/10: the fire line is the PixelFX T2 patch (fire_trail_small, pre-shrunk), not recoloured, upright (never turned)
	var got := ComboFx.play(p, "fire_fan", "trail", Vector2(5, 7), Vector2.DOWN)
	var r := ""
	if got.size() != 1: r = "fire_fan trail spawned %d effects, want one fire_trail_small patch" % got.size()
	elif got[0].animation != "fire_trail_small" or got[0].modulate != Color.WHITE: r = "trail patch %s tint %s" % [got[0].animation, got[0].modulate]
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
	if trail.size() != 1 or trail[0].animation != "fire_trail_small": r = "saver on: trail gave %s, want the fire patch" % [trail.map(func(s): return s.animation)]
	elif end.size() != 1 or end[0].animation != "fire_blast": r = "saver on: the line-end blast was shed"
	elif crit.size() != 1 or crit[0].animation != "hit_spark": r = "saver on: crit_hit should fall back to hit_spark"
	elif PerfSaver.decorative("fire_trail_small") or PerfSaver.decorative("fire_blast"): r = "fire_trail / fire_blast listed as decorative"
	if r == "" and ComboFx.play(p, "brahmastra", "trail", Vector2.ZERO, Vector2.ZERO, false).map(func(s): return String(s.animation)) != ["fire_trail_small"]:
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
		var patches := fx.filter(func(c): return c.animation == "fire_trail_small")
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
	var n := t.get_children().filter(func(c): return c is FxSprite and c.animation == "fire_trail_small").size()
	t.free()
	return "" if n == 1 else "a 12 px trail shows %d fire patches, want 1" % n

## True when every recorded mark of trail t has a patch standing on it (t not in a tree: positions are in its space).
func _one_patch_per_mark(t: FireTrail, patches: Array) -> bool:
	for q in t.points():
		if not patches.any(func(c): return c.position.distance_to(q) < 0.01): return false
	return true

## Owner 2026-11-10 ("ทำชีตย่อใหม่ให้เนียน", "ถี่ขึ้นให้เท่าตัวอย่าง"): the patch is the pre-shrunk sheet
## fire_trail_small (18x20, feet anchor 9,18) drawn at scale 1 (one fire pixel = one world pixel; no runtime PATCH_SCALE
## any more), nearest-filtered, its feet exactly on its mark (on the path), and the marks are SPACING = 20 px apart along
## the path (the sample's density; 18 px patches: one continuous fire). A long bent line still lays at most
## MAX_STREAKS = 12 patches. PerfSaver sheds none (owner: it may never hide the hazard): the same patches, visible and
## opaque. The damage is the recorded path, not the patches: a point between two patches burns, 10 px off the line
## burns, 11 px off does not (the arrow's hit radius), the same with the saver on.
func test_trail_patches_small_sheet_dense():
	var r := ""
	# the script's constants, not a FireTrail.new() probe (an unfreed probe node leaked at exit: "1 RID CanvasItem leaked")
	if (load("res://scripts/combo/fire_trail.gd") as GDScript).get_script_constant_map().has("PATCH_SCALE"): return "FireTrail still scales patches at runtime (PATCH_SCALE)"
	if FireTrail.SPACING != 20.0 or FireTrail.MAX_STREAKS != 12: return "spacing %s / %d marks, want 20 / 12 (owner 2026-11-10)" % [FireTrail.SPACING, FireTrail.MAX_STREAKS]
	var man: Dictionary = FxSprite._manifest().fire_trail_small
	var anchor := Vector2(man.anchor[0], man.anchor[1])
	var cell := Vector2(man.cell[0], man.cell[1])
	if cell != Vector2(18, 20) or anchor != Vector2(9, 18): return "fire_trail_small cell %s anchor %s, want 18x20 / 9,18" % [cell, anchor]
	var counts: Array = []
	for saver in [false, true]:
		PerfSaver.active = saver
		var t := FireTrail.new()
		t.setup(Vector2(10, 20), ATK, 1.0, 0.2, 2.0, [], null, null, 0.0, "brahmastra")
		for i in 56: t.extend_to(Vector2(10, 20) + Vector2(i * 4.0, 0))     # 220 px straight: the longest arrow
		var marks := t.points()
		var patches := t.get_children().filter(func(c): return c is FxSprite and c.animation == "fire_trail_small")
		counts.append(patches.size())
		if marks.size() != 11 or patches.size() != 11: r = "saver %s: a 220 px line has %d marks / %d patches, want 11 / 11 (every 20 px)" % [saver, marks.size(), patches.size()]
		elif marks[0].distance_to(Vector2(30, 20)) > 0.01: r = "the first mark at %s, want 20 px from the start" % marks[0]
		for i in marks.size() - 1:
			if r == "" and absf(marks[i].distance_to(marks[i + 1]) - 20.0) > 0.01: r = "marks %d / %d are %.2f px apart, want 20" % [i, i + 1, marks[i].distance_to(marks[i + 1])]
		for i in patches.size():
			if r != "": break
			var sp: FxSprite = patches[i]
			var feet: Vector2 = sp.transform * (sp.offset + anchor)
			var box := Rect2(sp.transform * sp.offset, cell * sp.scale)
			if sp.scale != Vector2.ONE: r = "saver %s: patch %d drawn at %s, want 1:1" % [saver, i, sp.scale]
			elif sp.texture_filter != CanvasItem.TEXTURE_FILTER_NEAREST: r = "patch %d not nearest-filtered" % i
			elif feet.distance_to(marks[i]) > 0.01: r = "patch %d's feet at %s, its mark at %s (want on the path)" % [i, feet, marks[i]]
			elif box.size != Vector2(18, 20): r = "patch %d box %s, want 18 x 20 world px" % [i, box.size]
			elif not sp.visible or sp.modulate.a < 1.0 or t.modulate.a < 1.0: r = "saver %s: patch %d is not readable (visible %s, alpha %.2f)" % [saver, i, sp.visible, sp.modulate.a]
		if r == "":
			var gap: Vector2 = (marks[3] + marks[4]) / 2.0
			if not t._near(gap, 10.0): r = "a point on the line between two patches is not in the fire"
			elif not t._near(Vector2(117, 30), 10.0) or t._near(Vector2(117, 31.01), 10.0): r = "saver %s: the fire's reach is not the line ± the hit radius" % saver
		if r == "":                                     # bounded: a 1600 px bent path still lays 12
			var u := FireTrail.new()
			u.setup(Vector2.ZERO, ATK, 1.0, 0.2, 2.0, [], null, null, 0.0, "fire_fan")
			var at := Vector2.ZERO
			for i in 400:
				at += Vector2.RIGHT.rotated(i * 0.01) * 4.0
				u.extend_to(at)
			var n := u.get_children().filter(func(c): return c is FxSprite).size()
			if n != FireTrail.MAX_STREAKS or u.points().size() != FireTrail.MAX_STREAKS: r = "saver %s: a 1600 px line laid %d patches / %d marks, want %d" % [saver, n, u.points().size(), FireTrail.MAX_STREAKS]
			u.free()
		t.free()
		if r != "": break
	PerfSaver.active = false
	if r == "" and counts[0] != counts[1]: r = "the PerfSaver changed the patches %d → %d (it may not shed the hazard)" % [counts[0], counts[1]]
	return r

## Owner 2026-11-09 (T2 sample, PHASE 7): the patches of a line never flicker in sync. Every patch plays the fire_trail
## loop from its own frame: neighbours 3..11 frames apart (circular), the same frames every run for the same line
## (deterministic), and another line (another first mark) starts elsewhere; patch_frame stays inside the loop.
func test_trail_patches_start_at_their_own_frames():
	var n := int(FxSprite._manifest().fire_trail_small.frames)
	var lines: Array = []
	for dir in [Vector2.RIGHT, Vector2.RIGHT, Vector2.RIGHT.rotated(0.5)]:
		var t := FireTrail.new()
		t.setup(Vector2(30, 40), ATK, 1.0, 0.2, 2.0, [], null, null, 0.0, "fire_fan")
		for i in 56: t.extend_to(Vector2(30, 40) + dir * (i * 4.0))     # 220 px, the piercing range: 11 marks
		lines.append(t)
	var frames: Array = []
	for t in lines:
		frames.append(t.get_children().filter(func(c): return c is FxSprite).map(func(c): return c.frame))
	var r := ""
	if frames[0].size() != 11: r = "a 220 px line has %d patches, want 11 (every 20 px)" % frames[0].size()
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
	if after_trails != 1: r = "3 lines × 11 patches loaded the trail sheet %d times, want 1" % after_trails
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
		var streaks := t.get_children().filter(func(c): return c is FxSprite and c.animation == "fire_trail_small")
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
## bounce and bolt finding a monster. Owner 2026-11-10: the lightning combo (+1 bounce, bolts) rides on ONE arrow per
## line per press; the other arrows keep the plain ricochet bounces (no +1, no bolt). Phase 1 (char Lv10): ศรกระจาย
## 2 slots (skill Lv8) [ricochet, lightning] = ศรอสนีกระโดด, 1 line: the carrier 2 + 1 = 3 bounces / 3 bolts, the other
## 4 arrows 2 bounces each → 11 bounces / 3 bolts (was 15 / 15); ศรทะลวง ศรอสนีพันสาย: 3 lines × 1 bounce (piercing) × 2
## = 3 / 6. Char Lv12 (ศรกระจาย slot 3): + pierce gem → still 11 / 3; + split = ศรอสนีพันสาย, 7 arrows in 3 lines:
## 7 × 2 = 14 bounces, 3 carriers × 2 bounces × 2 bolts = 12 bolts (was 28) = the worst case per press.
func test_lightning_worst_case_bolts_per_press():
	var cases := [
		["spread Lv10 thunder_hop", {"ricochet": 10, "lightning": 1}, "spread", 10, "thunder_hop", 11, 3],
		["piercing Lv10 thousand_bolts", {"ricochet": 10, "lightning": 1, "split": 1}, "piercing", 10, "thousand_bolts", 3, 6],
		["spread Lv12 thunder_hop + pierce", {"ricochet": 10, "lightning": 1, "pierce": 10}, "spread", 12, "thunder_hop", 11, 3],
		["spread Lv12 thousand_bolts", {"ricochet": 10, "lightning": 1, "split": 1}, "spread", 12, "thousand_bolts", 14, 12],
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

# ---------- owner 2026-11-10: lightning combo from one arrow per line, bounce arrows don't chain ----------

## SkillBuild.lines / line_of = the sim's arrow lines (1, 3 with split): ศรทะลวง 1 arrow per line, ศรกระจาย 5 arrows
## in 1 line, +split 7 arrows in 3 lines (2 / 3 / 2, fan order); the hero's press gives each arrow its line.
func test_press_lines_follow_the_sim():
	var cases := [["piercing", [], [0]], ["piercing", ["split"], [0, 1, 2]], ["spread", [], [0, 0, 0, 0, 0]],
		["spread", ["split"], [0, 0, 1, 1, 1, 2, 2]]]
	for c in cases:
		var b := _build(c[1], c[0])
		var got: Array = []
		for i in int(b.arrows): got.append(SkillBuild.line_of(b, i))
		if got != c[2]: return "%s %s: lines %s, want %s" % [c[0], c[1], got, c[2]]
	var h := _hero(12, [])
	h.set_skill_gems({"spread": [_g("ricochet"), _g("lightning"), _g("split")]})
	h.try_skill("spread")
	for i in 50: h.step(DT, Vector2.ZERO)
	var lines: Array = _spawned.map(func(a): return a.line)
	var r := "" if lines == [0, 0, 1, 1, 1, 2, 2] else "the hero's spread + split press: lines %s, want [0, 0, 1, 1, 1, 2, 2]" % [lines]
	_done(h)
	return r

## Owner 2026-11-10 ("สายฟ้าคอมโบจาก 1 ลูกต่อการกด"): on ศรกระจาย + ศรอสนีกระโดด (1 line) only the FIRST arrow to hit
## carries the combo: its chain bounces 1 + 1 and bolts at each bounce; the others bounce once (the plain ricochet
## gem), no bolt. Arrow 3 (fan order) meets its monster first (40 px), so it carries, not arrow 0. The ledger is per
## press: a second press (new ledger) has its own carrier.
func test_lightning_combo_one_arrow_per_line():
	var r := ""
	for press in 2:
		var b := _build(["ricochet", "lightning"], "spread")
		if String(b.combo.get("id", "")) != "thunder_hop": return "setup: combo %s" % b.combo
		var n := int(b.arrows)
		var fan := deg_to_rad(float(b.fan_deg))
		var all: Array = []
		for i in n:
			var dir := Vector2.RIGHT.rotated(-fan / 2.0 + fan * i / (n - 1))
			all.append(_dummy(dir * (40.0 if i == 3 else 80.0)))
		all.append(_dummy(Vector2(150, -40)))
		all.append(_dummy(Vector2(150, 40)))
		_spawned = []
		var arrows := _fan(b, all)
		for i in 150: _step(arrows, [])
		var carriers: Array = []
		for i in n:
			if arrows[i].carries_lightning(): carriers.append(i)
		var am := float(b.arrow_mult)
		var bolts := 0
		for d in all:
			for h in d.hits:
				if is_equal_approx(float(h[1]), am * 0.5): bolts += 1
		var carried := _spawned.filter(func(x): return x.carries_lightning()).size()
		var plain := _spawned.filter(func(x): return not x.carries_lightning())
		if carriers != [3]: r = "press %d: carriers %s, want [3] (the first arrow of the line to hit)" % [press, carriers]
		elif carried != 2: r = "press %d: the carrier's chain bounced %d times, want 1 + 1" % [press, carried]
		elif plain.size() != 4: r = "press %d: %d plain bounce arrows, want 4 (one per other arrow)" % [press, plain.size()]
		elif plain.any(func(x): return int(x.build.get("bounces", -1)) != 0): r = "press %d: a plain arrow's bounce got the +1" % press
		elif bolts != 2: r = "press %d: %d bolts, want 2 (the carrier's 2 bounces only)" % [press, bolts]
		_free(arrows + _spawned + all)
		if r != "": break
	return r

## carries_lightning() is a read-only query (Task 6 review fix): asking an arrow that never hit, before and after its
## flight, never takes its line; only the real hit path (claim_lightning_line, the arrow's first hit) claims. Two arrows
## of one press on line 0: A flies away from every monster and is queried; B then hits and still carries the line.
func test_query_never_claims_the_line():
	var b := _build(["ricochet", "lightning"])
	if String(b.combo.get("id", "")) != "thunder_hop": return "setup: combo %s" % b.combo
	var ds := [_dummy(Vector2(60, 0)), _dummy(Vector2(60, 60))]
	_spawned = []
	var a := _arrow(Vector2.LEFT, ds, b)
	var r := ""
	if a.carries_lightning(): r = "an undecided arrow answered true"
	for i in 150: _step([a], [])
	if r == "" and a.carries_lightning(): r = "an arrow that never hit carries the line"
	var bb := _arrow(Vector2.RIGHT, ds, b)
	for i in 150: _step([bb], [])
	if r == "":
		if ds[0].hits.size() != 1: r = "setup: B hit the first dummy %d times" % ds[0].hits.size()
		elif not bb.carries_lightning(): r = "the arrow that hit lost its line to a query of one that never hit"
		elif a.carries_lightning(): r = "the queried arrow carries after B claimed"
		elif b.cast.once("lightning_line", 0): r = "line 0 is still free after B's hit"
	_free([a, bb] + _spawned + ds)
	return r

## ศรอสนีพันสาย on ศรกระจาย (+split, 3 lines): one carrier per line (arrows 0, 2, 5: the first of each line to hit),
## 2 bolts per carrier bounce; arrows 1 and 3 bounce plain. With the homing gem (char Lv12, slot 3) the arrows turn
## onto other monsters but the ledger still gives exactly one carrier per line.
func test_thousand_bolts_one_carrier_per_line():
	var b := _build(["ricochet", "lightning", "split"], "spread")
	var r := "" if String(b.combo.get("id", "")) == "thousand_bolts" and int(b.lines) == 3 else "setup: combo %s lines %s" % [b.combo, b.get("lines")]
	if r == "":
		var all := _sim_pack_spread(b, [0, 1, 2, 3, 5])
		_spawned = []
		var arrows := _fan(b, all)
		for i in 150: _step(arrows, [])
		var carriers: Array = []
		for i in arrows.size():
			if arrows[i].carries_lightning(): carriers.append(i)
		if carriers != [0, 2, 5]: r = "carriers %s, want [0, 2, 5] (one per line)" % [carriers]
		_free(arrows + _spawned + all)
	if r == "":
		var hb := _build_lv({"ricochet": 1, "lightning": 1, "homing": 1}, "spread", 12)
		if String(hb.combo.get("id", "")) != "thunder_hop" or not bool(hb.homing): return "setup homing: combo %s" % hb.combo
		var all := _ray_grid(hb, [60, 95, 130])
		_spawned = []
		var arrows := _fan(hb, all)
		for i in 150: _step(arrows, [])
		var carriers := arrows.filter(func(x): return x.carries_lightning()).size()
		if carriers != 1: r = "homing thunder_hop: %d carriers, want 1 (1 line)" % carriers
		_free(arrows + _spawned + all)
	return r

## Owner 2026-11-10 (Task 6 review 3, "ลูกแรกที่เด้งได้จริง"): a line's lightning combo goes to the first arrow of the
## line that can actually bounce (a bounce target within ricochet.range when it hits), not merely the first to hit.
## ศรกระจาย + ศรอสนีกระโดด (1 line): arrow 3 hits a lone monster L at 60 px first (nothing within 120 px of it), so it
## does not claim and leaves the line free; arrows 0, 1, 2, 4 then hit the pack (arrow 0 first, at 180 px; the others
## at 200 px) and all can bounce: only arrow 0 claims (two+ bouncers: only the first), its chain bounces 1 + 1 and
## bolts twice; the other three bounce plain.
func test_lightning_line_goes_to_first_arrow_that_bounces():
	var b := _build(["ricochet", "lightning"], "spread")
	if String(b.combo.get("id", "")) != "thunder_hop": return "setup: combo %s" % b.combo
	var n := int(b.arrows)
	var fan := deg_to_rad(float(b.fan_deg))
	var ray := func(i: int) -> Vector2: return Vector2.RIGHT.rotated(-fan / 2.0 + fan * i / (n - 1))
	var lone := _dummy(ray.call(3) * 60.0)
	var all: Array = [lone]
	for i in n:
		if i != 3: all.append(_dummy(ray.call(i) * (180.0 if i == 0 else 200.0)))
	var r := ""
	for d in all:
		if d != lone and d.hurt_point().distance_to(lone.hurt_point()) <= Balance.num("ricochet.range"): r = "setup: a pack monster within ricochet range of L"
	_spawned = []
	var arrows := _fan(b, all)
	for i in 150: _step(arrows, [])
	var carriers: Array = []
	for i in n:
		if arrows[i].carries_lightning(): carriers.append(i)
	var am := float(b.arrow_mult)
	var bolts := 0
	for d in all:
		for h in d.hits:
			if is_equal_approx(float(h[1]), am * 0.5): bolts += 1
	var carried := _spawned.filter(func(x): return x.carries_lightning()).size()
	if r != "": pass
	elif lone.hits.size() != 1 or arrows[3]._hit.keys() != [lone]: r = "setup: L took %d hits, arrow 3 hit %d monsters" % [lone.hits.size(), arrows[3]._hit.size()]
	elif carriers != [0]: r = "carriers %s, want [0] (arrow 3 hit first but cannot bounce; arrow 0 is the first that bounces)" % [carriers]
	elif carried != 2: r = "the carrier's chain bounced %d times, want 1 + 1" % carried
	elif _spawned.size() != 5: r = "%d bounce arrows, want 5 (carrier 2 + 3 plain)" % _spawned.size()
	elif bolts != 2: r = "%d bolts, want 2 (the carrier's 2 bounces)" % bolts
	_free(arrows + _spawned + all)
	return r

## A monster that dies at its first hit (the homing test's weak lone monster).
class FragileDummy extends "res://tests/dummy_enemy.gd":
	func receive_hit(atk: float, mult: float, from: Vector2, c := -1.0, cm := -1.0) -> int:
		alive = false
		return super(atk, mult, from, c, cm)

## Same rule with the homing gem (char Lv12, slot 3): a weak lone monster L at 40 px pulls every homing arrow onto it
## first; the first arrow there kills it and cannot bounce (nothing within 120 px), so it does not claim; the others
## turn onto the pack, and the first of them to hit (and bounce) is the line's one carrier. Exactly one carrier per
## press, and its first hit is not L.
func test_lightning_line_first_bouncer_with_homing():
	var b := _build_lv({"ricochet": 1, "lightning": 1, "homing": 1}, "spread", 12)
	if String(b.combo.get("id", "")) != "thunder_hop" or not bool(b.homing): return "setup homing: combo %s" % b.combo
	var lone := FragileDummy.new()
	lone.position = Vector2.RIGHT.rotated(deg_to_rad(-22.5)) * 40.0 + Vector2(0, 14)
	var all: Array = [lone]
	for p in [Vector2(180, 0), Vector2(185, 35), Vector2(175, 70), Vector2(205, 15), Vector2(200, 55), Vector2(160, 100)]:
		all.append(_dummy(p))
	var r := ""
	for d in all:
		if d != lone and d.hurt_point().distance_to(lone.hurt_point()) <= Balance.num("ricochet.range"): r = "setup: a pack monster within ricochet range of L"
	_spawned = []
	var arrows := _fan(b, all)
	for i in 150: _step(arrows, [])
	var carriers := arrows.filter(func(x): return x.carries_lightning())
	var on_lone := arrows.filter(func(x): return not x._hit.is_empty() and x._hit.keys()[0] == lone).size()
	if r != "": pass
	elif on_lone == 0 or on_lone == arrows.size(): r = "setup: %d of %d arrows hit L first, want some but not all" % [on_lone, arrows.size()]
	elif carriers.size() != 1: r = "%d carriers, want 1 (the first arrow that bounces)" % carriers.size()
	elif carriers[0]._hit.keys()[0] == lone: r = "the carrier's first hit was L, which has no bounce target"
	_free(arrows + _spawned + all)
	return r

## ศรทะลวง unchanged by the rule: its line has one arrow, which bounces only from its first target. A at 60 px has no
## bounce target, so no bounce, no bolt, and the line is never claimed; the arrow pierces on to P (200 px) and does not
## bounce from it to its neighbour Q (a piercing arrow bounces from its first target only), as before the rule. (Q may
## take P's lightning-gem ×0.8 chain: that is the gem, not the combo.)
func test_piercing_first_target_without_bounce_unchanged():
	var b := _build(["ricochet", "lightning"])
	if String(b.combo.get("id", "")) != "thunder_hop": return "setup: combo %s" % b.combo
	var ds := {"A": _dummy(Vector2(60, 0)), "P": _dummy(Vector2(200, 0)), "Q": _dummy(Vector2(200, 60))}
	_spawned = []
	var a := _arrow(Vector2.RIGHT, ds.values(), b)
	for i in 150: _step([a], [])
	var r := ""
	if ds.A.hits.size() != 1 or ds.P.hits.size() < 1: r = "setup: A %d / P %d hits" % [ds.A.hits.size(), ds.P.hits.size()]
	elif not _spawned.is_empty(): r = "%d bounce arrows, want 0" % _spawned.size()
	elif ds.values().any(func(d): return d.hits.any(func(h): return is_equal_approx(float(h[1]), float(b.arrow_mult) * 0.5))): r = "a bolt was fired without a bounce"
	elif a.carries_lightning(): r = "the arrow carries without bouncing"
	elif not b.cast.once("lightning_line", 0): r = "line 0 was claimed by an arrow that never bounced"
	_free([a] + _spawned + ds.values())
	return r

## Owner 2026-11-10 ("ลูกเด้งไม่แตกสายโซ่"): a bounce arrow's hit never fires the lightning gem's own ×0.8 chain; the
## press's primary hits still do. ศรทะลวง + ศรอสนีกระโดด through A, P (on the line): 2 primary hits → 2 chains (from A
## and from P); the bounce arrows' hits on B and C → no chain from B or C.
func test_bounce_arrows_never_chain():
	var b := _build(["ricochet", "lightning"])
	var ds := {"A": _dummy(Vector2(60, 0)), "P": _dummy(Vector2(160, 0)), "B": _dummy(Vector2(60, 90)), "C": _dummy(Vector2(60, 180))}
	var order := _direct_order(b, ds)
	var from_pt := func(k): return ds[k].hurt_point()
	var chains := {}
	for k in ds:
		chains[k] = 0
		for d in ds.values():
			if d == ds[k]: continue
			chains[k] += d.hits.filter(func(h): return h[2] == from_pt.call(k)).size()
	var r := ""
	if not order in [["A", "B", "C", "P"], ["A", "B", "P", "C"], ["A", "P", "B", "C"]]: r = "setup: direct hits %s" % [order]
	elif chains.A != 1 or chains.P != 1: r = "primary hits chained A %d / P %d times, want 1 / 1" % [chains.A, chains.P]
	elif chains.B != 0 or chains.C != 0: r = "bounce arrows chained: from B %d, from C %d, want 0" % [chains.B, chains.C]
	_free(ds.values())
	return r

## Dummies for the sim's spread pack: one on each ray `hit_rays` of b's fan at 80 px (those arrows hit once each), plus
## one behind ray 0 at 140 px (a 6-monster pack: never in a primary arrow's way).
func _sim_pack_spread(b: Dictionary, hit_rays: Array) -> Array:
	var n := int(b.arrows)
	var fan := deg_to_rad(float(b.fan_deg))
	var out: Array = []
	for i in hit_rays: out.append(_dummy(Vector2.RIGHT.rotated(-fan / 2.0 + fan * i / (n - 1)) * 80.0))
	out.append(_dummy(Vector2.RIGHT.rotated(-fan / 2.0) * 140.0))
	if hit_rays.size() == 4: out.append(_dummy(Vector2.RIGHT.rotated(-fan / 2.0 + fan / (n - 1)) * 140.0))
	return out

## tools/gem_combo_sim.py, pack of 6, per press in units of the press's first hit (cast(...) pack / hit, crit off, gem
## Lv1): ศรทะลวง กระโดด 3 + 0.8×3 + 0.8 + 1.8 = 8.0 · ศรกระจาย กระโดด 4 + 0.8×4 + 0.8×4 + 1.8 = 12.2 · ศรทะลวง พันสาย
## 7 + 0.8×7 + 0.8×3 + 0.5×3×2 = 18.0 · ศรกระจาย พันสาย 5 + 0.8×5 + 0.8×5 + 3.0 = 16.0 (`python3 tools/gem_combo_sim.py
## --press` prints them). ศรกระจาย's ricochet term counts every arrow that hits (owner 2026-11-10 "คงไว้ แก้ตัวเลขอนุมัติ
## ให้นับทุกลูก"; was 1 per line: 9.8 / 14.4).
const SIM_PRESS := {"piercing thunder_hop": 8.0, "spread thunder_hop": 12.2, "piercing thousand_bolts": 18.0, "spread thousand_bolts": 16.0}

## One press of build b into `all` (crit off; the dummies record each hit's multiplier): [total / first hit, primary
## direct hits, chains, bounce arrows, bolts, plain (non-carrier) bounce arrows].
func _press_total(b: Dictionary, all: Array) -> Array:
	_spawned = []
	var arrows := _fan(b, all)
	for i in 150: _step(arrows, [])
	var am := float(b.arrow_mult)
	var total := 0.0
	var direct := 0
	var chains := 0
	var bolts := 0
	var pts := all.map(func(d): return d.hurt_point())
	for d in all:
		for h in d.hits:
			total += float(h[1])
			if is_equal_approx(float(h[1]), am * 0.5): bolts += 1
			elif h[2] in pts and h[2] != d.hurt_point(): chains += 1
			elif is_equal_approx(float(h[1]), am): direct += 1
	var plain := _spawned.filter(func(x): return not x.carries_lightning()).size()
	var out := [total / am, direct, chains, _spawned.size(), bolts, plain]
	_free(arrows + _spawned + all)
	return out

## Owner 2026-11-10 goal: per-press pack totals in game = tools/gem_combo_sim.py. Real arrows of a press (crit off,
## gem Lv1, char Lv10/12) into a 6-monster pack laid out to the sim's hit counts (ศรทะลวง line 3 hits; +split 7 hits on 5;
## ศรกระจาย 4 arrows hit; +split 5), every chain / bounce / bolt finding a monster. Every case, ศรกระจาย included: the
## raw total (plain bounces of the line's other arrows counted, as the corrected sim does, owner 2026-11-10) within
## ±3 % of the sim; the hit counts equal the sim's.
func test_lightning_pack_press_matches_sim():
	var lines: Array = []
	var r := ""
	var cases := [["piercing thunder_hop", ["ricochet", "lightning"], "piercing", 10],
		["spread thunder_hop", ["ricochet", "lightning"], "spread", 10],
		["piercing thousand_bolts", ["ricochet", "lightning", "split"], "piercing", 10],
		["spread thousand_bolts", ["ricochet", "lightning", "split"], "spread", 12]]
	for c in cases:
		var lv := {}
		for k in c[1]: lv[k] = 1
		var b := _build_lv(lv, c[2], c[3])
		var all: Array
		var want: Array      # [primary direct hits, chains, bounce arrows, bolts, plain bounce arrows] (the sim's counts)
		match c[0]:
			"piercing thunder_hop":
				all = [_dummy(Vector2(60, 0)), _dummy(Vector2(110, 0)), _dummy(Vector2(160, 0)), _dummy(Vector2(60, 60)), _dummy(Vector2(110, -60)), _dummy(Vector2(160, 60))]
				want = [3, 3, 2, 2, 0]
			"spread thunder_hop":
				all = _sim_pack_spread(b, [0, 1, 2, 3])
				want = [4, 4, 5, 2, 3]
			"piercing thousand_bolts":
				var up := Vector2.RIGHT.rotated(deg_to_rad(12.0)) * 130.0
				all = [_dummy(Vector2(40, 0)), _dummy(Vector2(130, 0)), _dummy(up), _dummy(Vector2(up.x, -up.y)), _dummy(Vector2(180, 0)), _dummy(Vector2(40, -60))]
				want = [7, 7, 3, 6, 0]
			_:
				all = _sim_pack_spread(b, [0, 1, 2, 3, 5])
				want = [5, 5, 5, 6, 2]
		var got := _press_total(b, all)
		var sim: float = SIM_PRESS[c[0]]
		var total: float = float(got[0])
		lines.append("%s: game %.2f vs sim %.2f = %+.1f %%" % [c[0], total, sim, (total / sim - 1.0) * 100.0])
		if got.slice(1) != want: r = "%s: [direct, chains, bounces, bolts, plain] %s, want %s (the sim's hit counts)" % [c[0], got.slice(1), want]
		elif absf(total / sim - 1.0) > 0.03: r = "%s: %.3f vs sim %.3f (> ±3 %%)" % [c[0], total, sim]
		elif c[2] == "piercing" and got[5] != 0: r = "%s: plain bounces on a piercing press" % c[0]
		if r != "": break
	print("  lightning pack per press (units of the first hit):\n    " + "\n    ".join(lines))
	return r

# ---------- mark / frost combos (Task 7: ศรตาเหยี่ยว, ศรเนตรพญาครุฑ, ศรเกล็ดน้ำแข็ง, ศรผลึกอโนดาต) ----------

## One primary arrow of build b flown from the origin to the right into `ds` (its crit chance = the build's, crit
## multiplier crit.mult, as Hero._fire); returns the arrow (not freed). line: its line of the press.
func _shoot(b: Dictionary, ds: Array, line := 0, dir := Vector2.RIGHT) -> Arrow:
	var a := _arrow(dir, ds, b)
	a.crit_chance = float(b.crit)
	a.crit_mult = Balance.num("crit.mult")
	a.line = line
	for i in 120: _step([a], [])
	return a

## ศรตาเหยี่ยว: an arrow hit marks the target for 4 s (+20 % taken from everything), credited to the press's ledger.
func test_hawk_eye_marks_20pct_4s():
	var b := _build(["homing", "execute"])
	if String(b.combo.get("id", "")) != "hawk_eye": return "setup: combo %s" % b.combo
	var d := _dummy(Vector2(60, 0))
	_spawned = []
	var a := _shoot(b, [d])
	var r := ""
	if d.hits.size() != 1: r = "setup: %d hits" % d.hits.size()
	elif not d.is_marked(): r = "not marked after the hit"
	elif not is_equal_approx(d.status.taken_mult(), 1.2): r = "taken_mult %s, want 1.2" % d.status.taken_mult()
	elif not is_same(d.status.mark_cast, b.cast): r = "the mark is not credited to the press's ledger"
	if r == "":
		d.tick_status(3.99)
		if not d.is_marked(): r = "mark gone before 4 s"
		d.tick_status(0.02)
		if r == "" and (d.is_marked() or not is_equal_approx(d.status.taken_mult(), 1.0)): r = "still marked after 4.01 s"
	_free([a, d] + _spawned)
	return r

## ศรเนตรพญาครุฑ: the first hit rolls the build's crit (0.05 + execute 0.15 + 0.15 = 0.35) and marks +30 %; the next
## press's hit on the marked target is a sure crit (crit chance 1.0). ศรตาเหยี่ยว has no sure crit: its hit on a marked
## target keeps the build's chance.
func test_garuda_marks_30pct_and_sure_crit():
	var b := _build(["homing", "execute", "multiply"])
	if String(b.combo.get("id", "")) != "garuda": return "setup: combo %s" % b.combo
	var d := _dummy(Vector2(60, 0))
	_spawned = []
	var a1 := _shoot(b, [d])
	var r := ""
	if d.hits.size() != 1: r = "setup: %d hits" % d.hits.size()
	elif not is_equal_approx(float(d.crit_chances[0]), float(b.crit)) or not is_equal_approx(float(b.crit), 0.35): r = "first hit crit chance %s, want the build's %s (0.35)" % [d.crit_chances[0], b.crit]
	elif not d.is_marked() or not is_equal_approx(d.status.taken_mult(), 1.3): r = "after the first hit: marked %s taken %s, want true / 1.3" % [d.is_marked(), d.status.taken_mult()]
	var b2 := _build(["homing", "execute", "multiply"])        # the next press: a new ledger
	var a2 := _shoot(b2, [d])
	if r == "" and (d.hits.size() != 2 or float(d.crit_chances[1]) != 1.0): r = "next press on the marked target: crit chance %s, want 1.0" % [d.crit_chances.slice(1)]
	var h := _build(["homing", "execute"])
	var e := _dummy(Vector2(60, 0))
	e.apply_mark(0.2, 4.0)
	var a3 := _shoot(h, [e])
	if r == "" and not is_equal_approx(float(e.crit_chances[0]), float(h.crit)): r = "ศรตาเหยี่ยว on a marked target: crit chance %s, want the build's %s (no sure crit)" % [e.crit_chances[0], h.crit]
	_free([a1, a2, a3, d, e] + _spawned)
	return r

## ศรเกล็ดน้ำแข็ง: 3 arrows of ONE press (3 split lines) on one target: the freeze (1 s, lock 5 s) lands on the 3rd hit,
## once; after 2 hits there is none.
func test_frost_freezes_once_on_third_hit():
	var b := _build(["ice", "split"])
	if String(b.combo.get("id", "")) != "frost_shard": return "setup: combo %s" % b.combo
	var d := _dummy(Vector2(60, 0))
	_spawned = []
	var arrows: Array = []
	var r := ""
	for i in 3:
		arrows.append(_shoot(b, [d], i))
		if d.hits.size() != i + 1: r = "setup: %d hits after %d arrows" % [d.hits.size(), i + 1]
		elif i < 2 and (d.freezes != 0 or d.is_frozen()): r = "frozen after %d hits, want the 3rd" % (i + 1)
		if r != "": break
	if r == "" and (d.freezes != 1 or not d.is_frozen()): r = "after 3 hits: %d freezes, frozen %s; want 1, true" % [d.freezes, d.is_frozen()]
	if r == "" and not (is_equal_approx(d.status.freeze_left, 1.0) and is_same(d.status.freeze_cast, b.cast)): r = "freeze %s s / cast %s, want 1 s by this press" % [d.status.freeze_left, d.status.freeze_cast]
	if r == "":
		arrows.append(_shoot(b, [d], 0))           # a 4th hit of the same press: no second try
		if d.freezes != 1: r = "a 4th hit froze again"
	_free(arrows + [d] + _spawned)
	return r

## The 5 s lock is per monster: a second press 2 s later (3 hits) does not freeze; a press 5.1 s after the freeze does.
func test_frost_lock_5s():
	var d := _dummy(Vector2(60, 0))
	_spawned = []
	var arrows: Array = []
	var press := func():
		var b := _build(["ice", "split"])
		for i in 3: arrows.append(_shoot(b, [d], i))
	press.call()
	var r := "" if d.is_frozen() else "setup: the first press did not freeze"
	d.tick_status(2.0)
	press.call()
	if r == "" and (d.is_frozen() or d.freezes != 1): r = "a press 2 s later froze again (lock 5 s)"
	d.tick_status(3.1)
	press.call()
	if r == "" and (not d.is_frozen() or d.freezes != 2): r = "a press 5.1 s after the freeze did not freeze (frozen %s, %d freezes)" % [d.is_frozen(), d.freezes]
	_free(arrows + [d] + _spawned)
	return r

## ศรเกล็ดน้ำแข็ง's arrows deal +25 % to a chilled (slowed or frozen) target, read before the hit: a fresh target's
## first hit is plain (the ice gem slows it after), the next arrow's hit gets the bonus.
func test_frost_bonus_vs_chilled():
	var b := _build(["ice", "split"])
	var am := float(b.arrow_mult)
	var slowed := _dummy(Vector2(60, 0))
	slowed.apply_status("slow")
	var frozen := _dummy(Vector2(60, 0))
	frozen.apply_freeze(1.0, 5.0)
	var fresh := _dummy(Vector2(60, 0))
	_spawned = []
	var arrows := [_shoot(b, [slowed]), _shoot(b, [frozen]), _shoot(b, [fresh]), _shoot(b, [fresh], 1)]
	var r := ""
	if not is_equal_approx(float(slowed.hits[0][1]), am * 1.25): r = "slowed: mult %s, want %s × 1.25" % [slowed.hits[0][1], am]
	elif not is_equal_approx(float(frozen.hits[0][1]), am * 1.25): r = "frozen: mult %s, want %s × 1.25" % [frozen.hits[0][1], am]
	elif not is_equal_approx(float(fresh.hits[0][1]), am): r = "fresh first hit: mult %s, want %s" % [fresh.hits[0][1], am]
	elif not is_equal_approx(float(fresh.hits[1][1]), am * 1.25): r = "second hit after the ice gem's slow: mult %s, want × 1.25" % fresh.hits[1][1]
	_free(arrows + [slowed, frozen, fresh] + _spawned)
	return r

## ศรผลึกอโนดาต: an arrow hit on a chilled (slowed or frozen) target is a sure crit; on a fresh one it rolls the build's
## chance (0.05 + execute 0.15 = 0.20).
func test_anodard_sure_crit_vs_chilled():
	var b := _build(["ice", "split", "execute"])
	if String(b.combo.get("id", "")) != "anodard": return "setup: combo %s" % b.combo
	var slowed := _dummy(Vector2(60, 0))
	slowed.apply_status("slow")
	var frozen := _dummy(Vector2(60, 0))
	frozen.apply_freeze(1.0, 5.0)
	var fresh := _dummy(Vector2(60, 0))
	_spawned = []
	var arrows := [_shoot(b, [slowed]), _shoot(b, [frozen], 1), _shoot(b, [fresh], 2)]
	var r := ""
	if float(slowed.crit_chances[0]) != 1.0: r = "slowed: crit chance %s, want 1.0" % slowed.crit_chances[0]
	elif float(frozen.crit_chances[0]) != 1.0: r = "frozen: crit chance %s, want 1.0" % frozen.crit_chances[0]
	elif not is_equal_approx(float(fresh.crit_chances[0]), float(b.crit)): r = "fresh: crit chance %s, want the build's %s" % [fresh.crit_chances[0], b.crit]
	_free(arrows + [slowed, frozen, fresh] + _spawned)
	return r

## ศรผลึกอโนดาต's shatter: 3 lines into one frozen target D → exactly ONE shatter per target per press (r32, × 0.50 of
## the arrow's hit, D itself included); a dummy 31 px from D's hurt point takes it, one at 33 px does not. The shatter
## is a secondary hit: it rolls the arrow's own crit chance (Global Constraints), never the sure crit. The next press
## shatters again.
func test_anodard_shatters_once_per_target_per_press():
	var d := _dummy(Vector2(60, 0))
	var near := _dummy(Vector2(60, 31))
	var far := _dummy(Vector2(60, -33))
	d.apply_freeze(1.0, 5.0)
	var all := [d, near, far]
	_spawned = []
	var arrows: Array = []
	var r := ""
	for press in 2:
		var b := _build(["ice", "split", "execute"])
		var am := float(b.arrow_mult)
		for i in 3: arrows.append(_shoot(b, all, i))
		var shatter_d: Array = d.hits.filter(func(h): return is_equal_approx(float(h[1]), am * 0.5))
		var direct_d: Array = d.hits.filter(func(h): return is_equal_approx(float(h[1]), am))
		if direct_d.size() != 3 * (press + 1): r = "press %d setup: %d arrow hits on D" % [press, direct_d.size()]
		elif shatter_d.size() != press + 1: r = "press %d: D took %d shatters in all, want %d (once per target per press)" % [press, shatter_d.size(), press + 1]
		elif near.hits.size() != press + 1 or not is_equal_approx(float(near.hits[-1][1]), am * 0.5): r = "press %d: the dummy 31 px away took %s, want one × 0.50 per press" % [press, near.hits]
		elif not far.hits.is_empty(): r = "the dummy 33 px away was hit"
		elif not is_equal_approx(float(near.crit_chances[-1]), float(b.crit)): r = "shatter crit chance %s, want the arrow's %s" % [near.crit_chances[-1], b.crit]
		if r != "": break
	_free(arrows + all + _spawned)
	return r

## Owner 2026-11-10 (Task 7 review, "โดนแรงแตกได้ตัวละ 1 ครั้งต่อการกด"): a monster takes at most ONE shatter splash per
## press, however many chilled monsters near it shatter. 5 slowed dummies within 32 px of each other (every hurt point
## within r32 of every other), one ศรผลึกอโนดาต press (3 split lines): several of them shatter (each struck one once),
## yet each takes exactly one splash (× 0.50); the next press (a new ledger) splashes each once again.
func test_anodard_splash_once_per_monster_in_a_cluster():
	var offs := [Vector2(0, 0), Vector2(0, 9), Vector2(0, -9), Vector2(9, 4), Vector2(9, -4)]
	var all: Array = []
	for o in offs: all.append(_dummy(Vector2(60, 0) + o))
	for i in all.size():
		for j in all.size():
			if all[i].hurt_point().distance_to(all[j].hurt_point()) > 32.0: return "setup: dummies %d and %d more than 32 px apart" % [i, j]
	_spawned = []
	var arrows: Array = []
	var r := ""
	for press in 2:
		for d in all: d.apply_status("slow")
		var b := _build(["ice", "split", "execute"])
		if String(b.combo.get("id", "")) != "anodard": return "setup: combo %s" % b.combo
		var am := float(b.arrow_mult)
		var before: Array = all.map(func(d): return d.hits.size())
		var fan := _fan(b, all)
		for a in fan:
			a.crit_chance = 0.0
		for i in 150: _step(fan, [])
		arrows += fan
		var struck := 0
		for k in all.size():
			var d = all[k]
			var mine: Array = d.hits.slice(before[k])
			var splashes: Array = mine.filter(func(h): return is_equal_approx(float(h[1]), am * 0.5))
			if mine.any(func(h): return is_equal_approx(float(h[1]), am)): struck += 1
			if splashes.size() != 1: r = "press %d: dummy %d took %d shatter splashes, want exactly 1 (hits %s)" % [press, k, splashes.size(), mine]
			if r != "": break
		if r == "" and struck < 2: r = "setup press %d: only %d dummies struck by arrows (want several shatters)" % [press, struck]
		if r != "": break
	_free(arrows + all + _spawned)
	return r

## Owner 2026-11-10 ("นับเฉพาะน้ำแข็ง"): "ช้า" for ศรเกล็ดน้ำแข็ง's +25 % and ศรผลึกอโนดาต's sure crit / shatter is the ice
## slow and the freeze only. A monster slowed by อาณาเขตพราน's zone (apply_zone) is not chilled: a plain hit (no × 1.25),
## the build's crit chance (no sure crit) and no shatter. The real Wolf agrees (is_chilled false, speed still cut).
## (The trap root, Task 8c, must stay out of is_chilled too: plan Task 8c note.)
func test_zone_slow_is_not_chilled():
	var r := ""
	var fb := _build(["ice", "split"])
	var d := _dummy(Vector2(60, 0))
	d.apply_zone(0.3, 0.1, 5.0)
	_spawned = []
	if d.is_chilled(): r = "the zone made the dummy chilled"
	var a1 := _shoot(fb, [d])
	if r != "": pass
	elif d.hits.size() != 1 or not is_equal_approx(float(d.hits[0][1]), float(fb.arrow_mult)): r = "frost_shard on a zone-slowed target: mult %s, want %s (no × 1.25)" % [d.hits, fb.arrow_mult]
	var ab := _build(["ice", "split", "execute"])
	var e := _dummy(Vector2(60, 0))
	var near := _dummy(Vector2(60, 20))
	e.apply_zone(0.3, 0.1, 5.0)
	var a2 := _shoot(ab, [e, near])
	if r == "" and (e.hits.size() != 1 or not is_equal_approx(float(e.crit_chances[0]), float(ab.crit))): r = "anodard on a zone-slowed target: hits %s crit %s, want 1 hit at the build's %s" % [e.hits, e.crit_chances, ab.crit]
	elif r == "" and not near.hits.is_empty(): r = "anodard on a zone-slowed target shattered (neighbour hit %s)" % [near.hits]
	var w: Wolf = load("res://scenes/wolf.tscn").instantiate()
	w.setup()
	w.apply_zone(0.3, 0.1, 5.0)
	if r == "" and (w.is_chilled() or w.status.speed_mult() >= 1.0): r = "wolf in the zone: chilled %s speed %s (want false, < 1)" % [w.is_chilled(), w.status.speed_mult()]
	_free([a1, a2, d, e, near, w] + _spawned)
	return r

## The tier-3 row replaces its base (owner ②, rows read literally): ศรผลึกอโนดาต has no +25 % vs chilled.
func test_anodard_has_no_frost_bonus():
	var b := _build(["ice", "split", "execute"])
	var d := _dummy(Vector2(60, 0))
	d.apply_status("slow")
	_spawned = []
	var a := _shoot(b, [d])
	var r := "" if is_equal_approx(float(d.hits[0][1]), float(b.arrow_mult)) else "mult %s, want arrow_mult %s (no × 1.25)" % [d.hits[0][1], b.arrow_mult]
	_free([a, d] + _spawned)
	return r

## Bosses / elites freeze like any monster (owner 2026-11-08 "บอสแข็งได้เหมือนมอนอื่น"): an elite wolf hit by 3
## ศรเกล็ดน้ำแข็ง arrows of one press is frozen.
func test_boss_size_target_freezes():
	var w: Wolf = load("res://scenes/wolf.tscn").instantiate()
	w.setup()
	w.set_elite(true)
	w.health.setup(100000)
	w.position = Vector2(60, 0) - Wolf.HURT_POINT * Wolf.size_scale()
	var b := _build(["ice", "split"])
	_spawned = []
	var arrows: Array = []
	for i in 3: arrows.append(_shoot(b, [w], i))
	var r := ""
	if w.health.hp >= 100000: r = "setup: the elite was not hit"
	elif not w.is_frozen(): r = "an elite hit 3 times by ศรเกล็ดน้ำแข็ง is not frozen"
	_free(arrows + [w] + _spawned)
	return r

## Secondary hits (blasts, bolts, shatters) never mark and never count toward the freeze (Global Constraints); bounce
## arrows' hits do both (plan Task 7: "a primary or bounce arrow hit"). Bolts and the shatter checked too (Task 7 review).
func test_secondary_hits_never_mark_or_count_freeze():
	var r := ""
	var hb := _build(["homing", "execute"])
	var d := _dummy(Vector2(60, 0))
	var a := _arrow(Vector2.RIGHT, [d], hb)
	a.blast(d.hurt_point(), 32.0, 0.5, false)
	if d.is_marked(): r = "a blast marked"
	var fb := _build(["ice", "split"])
	var e := _dummy(Vector2(60, 0))
	var f := _arrow(Vector2.RIGHT, [e], fb)
	for i in 3: f.blast(e.hurt_point(), 32.0, 0.5, false)
	if r == "" and (e.freezes != 0 or e.hits.size() != 3): r = "3 blasts froze (%d) or missed (%d hits)" % [e.freezes, e.hits.size()]
	# lightning bolts (the lightning combos' secondary hits) never mark and never count either
	var bd := _dummy(Vector2(60, 0))
	a.targets = [bd]
	a.bolts(Vector2(40, 0), 1, 0.5, [])
	if r == "" and (bd.hits.size() != 1 or bd.is_marked()): r = "a bolt marked (%d hits, marked %s)" % [bd.hits.size(), bd.is_marked()]
	var be := _dummy(Vector2(60, 0))
	f.targets = [be]
	for i in 3: f.bolts(Vector2(40, 0), 1, 0.5, [])
	if r == "" and (be.freezes != 0 or be.hits.size() != 3): r = "3 bolts froze (%d) or missed (%d hits)" % [be.freezes, be.hits.size()]
	_free([a, d, f, e, bd, be])
	# the อโนดาต shatter: N is splashed by D's shatter, then takes 2 arrow hits of the same press: 2 counted, no
	# freeze (the splash did not count); the 3rd arrow hit freezes it
	if r == "":
		var ab := _build(["ice", "split", "execute"])
		var dd := _dummy(Vector2(60, 0))
		var nn := _dummy(Vector2(60, 20))
		dd.apply_status("slow")
		_spawned = []
		var xs := [_shoot(ab, [dd, nn])]
		if nn.hits.size() != 1: r = "setup: N took %d hits from D's shatter, want 1 splash" % nn.hits.size()
		var to_n: Vector2 = nn.hurt_point().normalized()
		for i in 2: xs.append(_shoot(ab, [nn], i + 1, to_n))
		if r == "" and (nn.hits.size() < 3 or nn.freezes != 0): r = "splash + 2 arrow hits: %d hits, %d freezes (want ≥ 3 hits, 0: a shatter counted)" % [nn.hits.size(), nn.freezes]
		xs.append(_shoot(ab, [nn], 0, to_n))
		if r == "" and nn.freezes != 1: r = "the 3rd arrow hit did not freeze N (%d freezes)" % nn.freezes
		_free(xs + [dd, nn] + _spawned)
	if r == "":
		var bounce := _arrow(Vector2.RIGHT, [], hb, false)     # a bounce arrow (not primary) of a hawk_eye press
		bounce.crit_chance = 0.0
		var g := _dummy(Vector2(60, 0))
		bounce.targets = [g]
		for i in 120: bounce.advance(DT)
		if g.hits.size() != 1: r = "setup: the bounce arrow hit %d times" % g.hits.size()
		elif not g.is_marked(): r = "a bounce arrow's hit did not mark"
		var fb2 := _build(["ice", "split"])
		var k := _dummy(Vector2(60, 0))
		var xs: Array = []
		for i in 3:
			var x := _arrow(Vector2.RIGHT, [k], fb2, i == 0)       # 1 primary + 2 bounce arrows of one press
			for j in 120: x.advance(DT)
			xs.append(x)
		if r == "" and k.freezes != 1: r = "1 primary + 2 bounce hits of one press: %d freezes, want 1" % k.freezes
		_free(xs + [bounce, g, k])
	return r

## The mark shows on the monster while it lasts (Wolf._update_status_fx): the recipe's "mark" effect (lock_on; ครุฑ
## gold #edbb55, ตาเหยี่ยว red #ff3050 so it never reads as the plain targeting ring, owner 2026-11-10), one per monster, swapped when a stronger mark from the other recipe takes over,
## gone when the mark ends or the monster dies; never shed by the PerfSaver (it tells the player where +20/30 % lands).
func test_wolf_shows_the_mark_while_marked():
	var w: Wolf = load("res://scenes/wolf.tscn").instantiate()
	tree.root.add_child(w)
	w.setup()
	var r := ""
	w.apply_mark(0.2, 4.0, ComboCast.new("hawk_eye"))
	w._update_status_fx()
	if w._mark_fx.size() != 1 or w._mark_fx[0].animation != "lock_on" or not w._mark_fx[0].modulate.is_equal_approx(Color("#ff3050")): r = "hawk_eye mark fx %s (want one red #ff3050 lock_on)" % [w._mark_fx]
	w.apply_mark(0.3, 4.0, ComboCast.new("garuda"))
	PerfSaver.active = true
	w._update_status_fx()
	if r == "" and (w._mark_fx.size() != 1 or not w._mark_fx[0].modulate.is_equal_approx(Color("#edbb55"))): r = "garuda mark fx %s (want one, gold, kept under the saver)" % [w._mark_fx]
	PerfSaver.active = false
	var shown: Node = w._mark_fx[0] if not w._mark_fx.is_empty() else null
	w.status.tick(4.01)
	w._update_status_fx()
	if r == "" and (not w._mark_fx.is_empty() or (shown != null and not shown.is_queued_for_deletion())): r = "mark fx left after the mark ended"
	w.queue_free()
	await tree.process_frame
	return r

## ศรเกล็ดน้ำแข็ง / ผลึกอโนดาต: a primary arrow carries the recipe's "trail" streak (piercing_trail tinted #7fd4ff) as
## a child, in place of the test ground's plain streak (has_combo_streak); fire recipes lay a FireTrail instead and keep
## the plain streak; no combo, no streak.
func test_frost_streak_rides_the_arrow():
	var p := Node2D.new()
	tree.root.add_child(p)
	var r := ""
	var fb := _build(["ice", "split"])
	var a := _arrow(Vector2.RIGHT, [], fb)
	p.add_child(a)
	a.advance(DT)
	var streaks := a.get_children().filter(func(c): return c is FxSprite and c.animation == "piercing_trail")
	if not a.has_combo_streak(): r = "a frost arrow has no combo streak"
	elif streaks.size() != 1 or not streaks[0].modulate.is_equal_approx(Color("#7fd4ff")): r = "frost streak %s, want one #7fd4ff piercing_trail" % [streaks]
	for keys in [["split", "fire"], ["split"]]:
		if r != "": break
		var x := _arrow(Vector2.RIGHT, [], _build(keys), true)
		if x.has_combo_streak(): r = "%s has a combo streak" % [keys]
		x.free()
	var bounce := _arrow(Vector2.RIGHT, [], fb, false)
	if r == "" and bounce.has_combo_streak(): r = "a bounce arrow has a combo streak"
	bounce.free()
	p.queue_free()
	await tree.process_frame
	return r

## tools/gem_combo_sim.py `--press` (mark / frost rows): ศรทะลวง Lv10 on a single target (the sim's boss: every split
## line hits it), per press, units of the press's first hit, crit counted as expected value (hero crit 0.05 + the
## build's, crit.mult 1.5): ตาเหยี่ยว 1.175 · ครุฑ 1.500 (owner 2026-11-10 "รับได้ คงไว้": the 4 s mark outlasts the
## 3.64 s cooldown, every press after the first lands on a marked target; was the 15/85 mix 1.451) · เกล็ดน้ำแข็ง 3.613
## (3 hits, 70 % of them +25 %) · อโนดาต 4.550 (3 hits + shatter 0.5, half the presses sure crit). Pack of 6 (7 hits on
## 5), corrected to the game (owner 2026-11-10 "แก้ตัวเลขอนุมัติตามเกม": only the near monster's 2 repeat hits are on a
## chilled target; 1 shatter, splash capped once per monster): เกล็ดน้ำแข็ง 7.687 (was 8.072) · อโนดาต 9.050 (was 12.350).
const SIM_PRESS7 := {"hawk_eye": 1.175, "garuda": 1.500, "frost_shard": 3.613, "anodard": 4.550, "frost_shard pack": 7.687, "anodard pack": 9.050}

## Σ mult × (1 + crit chance × (crit.mult − 1)) of every hit on `ds` / am (the expected damage, no roll).
func _expected(ds: Array, am: float) -> float:
	var cm := Balance.num("crit.mult")
	var s := 0.0
	for d in ds:
		for i in d.hits.size(): s += float(d.hits[i][1]) * (1.0 + clampf(float(d.crit_chances[i]), 0.0, 1.0) * (cm - 1.0))
	return s / am

## Game vs the sim per press. Single target, fresh (unchilled, unmarked: ศรทะลวง's cooldown 3.64 s at Lv10 outlasts the
## ice gem's 3 s slow, so each frost press starts on an unchilled target): ตาเหยี่ยว, เกล็ดน้ำแข็ง, อโนดาต within ±3 %.
## ครุฑ: the first press is unmarked (1.175); every press after it is marked (1.5) = the sim (owner 2026-11-10), ±3 %.
## Pack (7 hits on 5): เกล็ดน้ำแข็ง / อโนดาต within ±3 % of the corrected sim, and the game's hit counts.
func test_mark_frost_press_matches_sim():
	var lines: Array = []
	var r := ""
	for id in ["hawk_eye", "garuda", "frost_shard", "anodard"]:
		var keys: Array = {"hawk_eye": ["homing", "execute"], "garuda": ["homing", "execute", "multiply"], "frost_shard": ["ice", "split"], "anodard": ["ice", "split", "execute"]}[id]
		var b := _build(keys)
		var am := float(b.arrow_mult)
		var d := _dummy(Vector2(60, 0))
		_spawned = []
		var arrows: Array = []
		for i in int(b.arrows): arrows.append(_shoot(b, [d], i))
		var game := _expected([d], am)
		var sim: float = SIM_PRESS7[id]
		if id == "garuda":
			var b2 := _build(keys)
			d.hits.clear()
			d.crit_chances.clear()
			arrows.append(_shoot(b2, [d]))             # the next press, on the marked target
			var marked := _expected([d], am)
			lines.append("garuda: first (unmarked) press %.3f · marked press %.3f vs sim %.3f = %+.1f %%" % [game, marked, sim, (marked / sim - 1.0) * 100.0])
			if not is_equal_approx(snappedf(game, 0.001), 1.175): r = "garuda first press %.4f, want 1.175 (unmarked)" % game
			elif absf(marked / sim - 1.0) > 0.03: r = "garuda marked press %.3f vs sim %.3f (> ±3 %%)" % [marked, sim]
		else:
			lines.append("%s: game %.3f vs sim %.3f = %+.1f %%" % [id, game, sim, (game / sim - 1.0) * 100.0])
			if absf(game / sim - 1.0) > 0.03: r = "%s: game %.3f vs sim %.3f (> ±3 %%)" % [id, game, sim]
		_free(arrows + [d] + _spawned)
		if r != "": break
	if r == "":
		for id in ["frost_shard", "anodard"]:
			var keys: Array = {"frost_shard": ["ice", "split"], "anodard": ["ice", "split", "execute"]}[id]
			var b := _build(keys)
			var am := float(b.arrow_mult)
			# the sim's pack for a split ศรทะลวง: 7 hits on 5 monsters (the near one on all 3 lines), a 6th untouched
			var up := Vector2.RIGHT.rotated(deg_to_rad(12.0)) * 130.0
			var all := [_dummy(Vector2(40, 0)), _dummy(Vector2(130, 0)), _dummy(up), _dummy(Vector2(up.x, -up.y)), _dummy(Vector2(180, 0)), _dummy(Vector2(40, -60))]
			_spawned = []
			var arrows := _fan(b, all)
			for a in arrows:
				a.crit_chance = float(b.crit)
				a.crit_mult = Balance.num("crit.mult")
			for i in 150: _step(arrows, [])
			var hits := 0
			for d in all: hits += d.hits.size()
			var game := _expected(all, am)
			var sim: float = SIM_PRESS7[id + " pack"]
			lines.append("%s pack: game %.3f vs sim %.3f = %+.1f %% (%d hits)" % [id, game, sim, (game / sim - 1.0) * 100.0, hits])
			var want_hits := 7 if id == "frost_shard" else 8       # อโนดาต: + 1 shatter (only the near monster is hit twice)
			if hits != want_hits: r = "%s pack: %d hits, want %d" % [id, hits, want_hits]
			elif absf(game / sim - 1.0) > 0.03: r = "%s pack: game %.3f vs sim %.3f (> ±3 %%)" % [id, game, sim]
			_free(arrows + all + _spawned)
			if r != "": break
	print("  mark / frost per press (units of the first hit, expected crit):\n    " + "\n    ".join(lines))
	return r

# ---------- sustain combos (Task 8: ศรกระหายเลือด, ศรราหูอมจันทร์) and the one kill hook ----------

## A stand-in shooter / DoT source that records what the one kill hook (Hero.combo_hit) credits to it.
class KillSink extends Node:
	var kills: Array = []        # the ledger of each credited kill
	var crits: Array = []        # the ledger of each credited crit
	var healed := 0.0
	func leech_heal(a: float) -> void:
		healed += a
	func on_combo_kill(c: ComboCast, _at := Vector2.INF) -> int:
		kills.append(c)
		return 0
	func on_combo_crit(c: ComboCast) -> void:
		crits.append(c)

var _rel_frames := 0

## A hero (char Lv`level`) with `keys` on `skill`, at the origin facing east (its arrows start at (18, -24)); the
## arrows of its presses and their bounces go to _spawned.
func _sus_hero(skill: String, keys: Array, level := 10) -> Hero:
	var h: Hero = load("res://scenes/hero.tscn").instantiate()
	h.setup_sprites()
	h.set_progress(level, 0)
	h.inventory.slots.clear()
	var gems: Array = []
	for k in keys: gems.append(_g(k))
	h.set_skill_gems({skill: gems})
	h.facing = 2
	_spawned = []
	h.shot.connect(func(a): _spawned.append(a))
	return h

## Dummies on the rays of a press of `skill`: rays[i] = distances along fan arrow i from the arrow start (the centre ray
## due east). The centre ray's nearest dummy is the hero's nearest target, so the press aims due east. die: die at the
## first hit. Sets the hero's targets.
func _rays(h: Hero, skill: String, rays: Array, die := true) -> Array:
	var b := h.build(skill)
	var n := int(b.arrows)
	var fan := deg_to_rad(float(b.fan_deg))
	var start := h._arrow_origin()
	var out: Array = []
	for i in rays.size():
		var dir := Vector2.RIGHT if n == 1 else Vector2.RIGHT.rotated(-fan / 2.0 + fan * i / (n - 1))
		for dist in rays[i]:
			var d := _dummy(start + dir * float(dist))
			d.die_on_hit = die
			out.append(d)
	h.test_enemies = out
	return out

## Presses `skill`, steps the hero until the press's arrows are out (_rel_frames frames), then flies them (bounces,
## trails, `ds`' statuses) for `secs` without stepping the hero again (no MP regen in what is measured). Returns the
## hero's MP right after the release (-1 when the press did not fire).
func _sus_press(h: Hero, skill: String, ds: Array, secs := 2.5) -> float:
	var had := _spawned.size()
	if not h.try_skill(skill): return -1.0
	_rel_frames = 0
	while _spawned.size() == had and _rel_frames < 60:
		h.step(DT, Vector2.ZERO)
		_rel_frames += 1
	if _spawned.size() == had: return -1.0
	var mp_rel := h.mp
	for i in int(round(secs / DT)): _step([], ds)
	return mp_rel

func _sus_done(h: Hero, ds: Array) -> void:
	_free(_spawned + ds)
	_spawned = []
	h.free()

## The press's ledger (the arrows' build.cast).
func _cast_of(i := 0) -> ComboCast:
	return _spawned[i].build.get("cast") if _spawned.size() > i else null

## ศรกระหายเลือด: +2 MP per kill, at most 6 per press. ศรกระจาย [leech, multiply] (char Lv10, MP 12 × 1.2 × 1.5 =
## 21.6): its 5 arrows kill 5 monsters → +6, not +10.
func test_bloodthirst_mp_cap_6_per_press():
	var h := _sus_hero("spread", ["leech", "multiply"])
	var b := h.build("spread")
	var ds := _rays(h, "spread", [[90], [90], [60], [90], [90]])
	h.mp = 40.0
	var r := "" if String(b.combo.get("id", "")) == "bloodthirst" else "setup: combo %s" % b.combo
	if r == "":
		var mp_rel := _sus_press(h, "spread", ds)
		var dead := ds.filter(func(d): return not d.alive).size()
		var regen := float(h.stats().mp_regen) * _rel_frames * DT
		if mp_rel < 0.0: r = "the press did not fire"
		elif not is_equal_approx(float(b.mp), 21.6): r = "press MP %.2f, want 21.6" % b.mp
		elif absf(40.0 + regen - 21.6 - mp_rel) > 1e-3: r = "MP at release %.3f, want 40 − 21.6 + regen %.3f" % [mp_rel, regen]
		elif dead != 5: r = "%d of 5 monsters killed" % dead
		elif not is_equal_approx(h.mp - mp_rel, 6.0): r = "MP +%.2f from 5 kills, want +6 (cap 6 per press, not +10)" % (h.mp - mp_rel)
		elif _cast_of().mp_refunded() != 6: r = "the ledger refunded %d" % _cast_of().mp_refunded()
	_sus_done(h, ds)
	return r

## A new press is a new ledger: after the first press's 6, a second press that kills 3 refunds +6 again.
func test_cap_resets_each_press():
	var h := _sus_hero("spread", ["leech", "multiply"])
	var ds := _rays(h, "spread", [[90], [90], [60], [90], [90]])
	h.mp = 60.0
	var r := ""
	var mp1 := _sus_press(h, "spread", ds)
	if mp1 < 0.0 or not is_equal_approx(h.mp - mp1, 6.0): r = "setup: first press +%.2f" % (h.mp - mp1)
	var c1 := _cast_of()
	if r == "":
		_free(_spawned + ds)
		_spawned = []
		h.state = "idle"
		h._skill_cd.clear()
		ds = _rays(h, "spread", [[], [90], [60], [90], []])
		var mp2 := _sus_press(h, "spread", ds)
		var dead := ds.filter(func(d): return not d.alive).size()
		if mp2 < 0.0: r = "the second press did not fire"
		elif dead != 3: r = "second press killed %d, want 3" % dead
		elif is_same(_cast_of(), c1): r = "the second press reused the first press's ledger"
		elif not is_equal_approx(h.mp - mp2, 6.0): r = "second press +%.2f MP from 3 kills, want +6 again" % (h.mp - mp2)
		elif c1.mp_refunded() != 6: r = "the first press's ledger changed (%d)" % c1.mp_refunded()
	_sus_done(h, ds)
	return r

## ศรกระหายเลือด: a kill heals 3 % of max HP (through leech_heal, with the press's leech of the killing hit's 1 damage:
## 0.06 HP, carried) and refunds +2 MP.
func test_bloodthirst_kill_heals_3pct():
	var h := _sus_hero("piercing", ["leech", "multiply"])
	var b := h.build("piercing")
	var ds := _rays(h, "piercing", [[60]])
	h.health.hp = h.health.max_hp / 2
	h.mp = 40.0
	var hp0 := h.health.hp
	var carry0 := h._leech_carry
	var r := "" if String(b.combo.get("id", "")) == "bloodthirst" and is_equal_approx(float(b.leech), 0.06) else "setup: %s leech %s" % [b.combo, b.leech]
	if r == "":
		var mp_rel := _sus_press(h, "piercing", ds)
		var want := int(floor(carry0 + 0.03 * h.health.max_hp + 0.06 * 1 + 1e-6))
		if ds[0].alive: r = "not killed"
		elif h.health.hp - hp0 != want: r = "healed %d HP, want %d (3 %% of %d + leech)" % [h.health.hp - hp0, want, h.health.max_hp]
		elif not is_equal_approx(h.mp - mp_rel, 2.0): r = "MP +%.2f, want +2" % (h.mp - mp_rel)
	_sus_done(h, ds)
	return r

## ศรราหูอมจันทร์: +3 MP per kill, at most 9 per press (5 kills in the piercing line → +9, not +15).
func test_rahu_mp_cap_9():
	var h := _sus_hero("piercing", ["leech", "multiply", "execute"])
	var b := h.build("piercing")
	var ds := _rays(h, "piercing", [[60, 85, 110, 135, 160]])
	h.mp = 40.0
	var r := "" if String(b.combo.get("id", "")) == "rahu" else "setup: combo %s" % b.combo
	if r == "":
		var mp_rel := _sus_press(h, "piercing", ds)
		var dead := ds.filter(func(d): return not d.alive).size()
		if dead != 5: r = "%d of 5 killed" % dead
		elif not is_equal_approx(h.mp - mp_rel, 9.0): r = "MP +%.2f from 5 kills, want +9 (cap)" % (h.mp - mp_rel)
	_sus_done(h, ds)
	return r

## ราหู's +30 % at exactly 70 % HP (the smallest whole HP ≥ 70 %), none one HP below (checked at the release).
func test_rahu_bonus_only_at_70pct_hp():
	var h := _hero(10, ["leech", "multiply", "execute"])
	var b := h.build("piercing")
	var at70 := int(ceil(0.70 * h.health.max_hp - 1e-9))
	var r := "" if String(b.combo.get("id", "")) == "rahu" else "setup: combo %s" % b.combo
	if r == "":
		h.health.hp = at70
		_press(h)
		if _spawned.size() != 1 or not is_equal_approx(_spawned[0].mult, float(b.arrow_mult) * 1.3): r = "HP %d/%d (≥ 70 %%): mult %s, want × 1.3" % [at70, h.health.max_hp, _spawned[0].mult if _spawned.size() > 0 else -1.0]
	if r == "":
		_free(_spawned)
		_spawned = []
		h._skill_cd.clear()
		h.mp = h.max_mp()
		h.health.hp = at70 - 1
		_press(h)
		if _spawned.size() != 1 or not is_equal_approx(_spawned[0].mult, float(b.arrow_mult)): r = "HP %d/%d (< 70 %%): mult %s, want no bonus" % [at70 - 1, h.health.max_hp, _spawned[0].mult if _spawned.size() > 0 else -1.0]
	_done(h)
	return r

## ราหู: a crit hit heals 1 % of max HP (on_combo_crit; the dummy reports a sure crit as a crit); a hit that does not
## crit heals only its leech.
func test_rahu_crit_heals_1pct():
	var h := _sus_hero("piercing", ["leech", "multiply", "execute"])
	var b := h.build("piercing")
	b["cast"] = ComboCast.from_build(b, 0.5)
	var d := _dummy(Vector2(60, 0))
	var e := _dummy(Vector2(60, 0))
	h.health.hp = h.health.max_hp / 2
	var r := ""
	var hp0 := h.health.hp
	var carry0 := h._leech_carry
	var a := _arrow(Vector2.RIGHT, [d], b, true, h)
	a.crit_chance = 1.0
	for i in 60: _step([a], [])
	var want := int(floor(carry0 + 0.01 * h.health.max_hp + float(b.leech) * 1 + 1e-6))
	if d.hits.size() != 1: r = "setup: %d hits" % d.hits.size()
	elif h.health.hp - hp0 != want: r = "a crit healed %d HP, want %d (1 %% of %d + leech)" % [h.health.hp - hp0, want, h.health.max_hp]
	var a2 := _arrow(Vector2.RIGHT, [e], b, true, h)
	if r == "":
		var hp1 := h.health.hp
		var carry1 := h._leech_carry
		for i in 60: _step([a2], [])
		var want2 := int(floor(carry1 + float(b.leech) * 1 + 1e-6))
		if h.health.hp - hp1 != want2: r = "a hit that did not crit healed %d HP, want %d (leech only)" % [h.health.hp - hp1, want2]
	_free([a, a2, d, e])
	h.free()
	return r

## MP never goes above max MP (and HP never above max HP): MP max − 1, HP max − 1, 3 kills → both exactly at max, and
## the ledger counts only the 1 MP really gained (owner 2026-11-11, "นับเฉพาะ MP ที่ได้จริง").
func test_refund_never_exceeds_max_mp():
	var h := _sus_hero("piercing", ["leech", "multiply"])
	var b := h.build("piercing")
	b["cast"] = ComboCast.from_build(b)
	var ds := [_dummy(Vector2(60, 0)), _dummy(Vector2(90, 0)), _dummy(Vector2(120, 0))]
	for d in ds: d.die_on_hit = true
	h.mp = h.max_mp() - 1.0
	h.health.hp = h.health.max_hp - 1
	var a := _arrow(Vector2.RIGHT, ds, b, true, h)
	for i in 60: _step([a], ds)
	var r := ""
	if ds.filter(func(d): return d.alive).size() > 0: r = "setup: not all killed"
	elif h.mp != float(h.max_mp()): r = "MP %.2f, want max %d" % [h.mp, h.max_mp()]
	elif h.health.hp != h.health.max_hp: r = "HP %d, want max %d" % [h.health.hp, h.health.max_hp]
	elif b.cast.mp_refunded() != 1.0: r = "ledger refunded %.2f, want 1: only the MP really gained (owner 2026-11-11)" % b.cast.mp_refunded()
	_free([a] + ds)
	h.free()
	return r

## Owner "นับทุกแบบ": burn kills count, through the press that applied the burn, sharing its cap. ศรทะลวง [leech,
## multiply, element fire] (bloodthirst, slot 3 at skill Lv10): 4 monsters in the line, 2 die to the hit (+4), 2 burn and
## die to their first burn tick 1 s later (+2, then +0: cap 6). Every kill heals 3 % of max HP (+ the press's leech of
## the hits and of the burn ticks).
func test_burn_kill_counts_and_shares_cap():
	var h := _sus_hero("piercing", ["leech", "multiply", "fire"])
	var b := h.build("piercing")
	var ds := _rays(h, "piercing", [[60, 90, 120, 150]])
	for i in [1, 3]:
		ds[i].die_on_hit = false
		ds[i].deal = 10                    # burn 10 × 0.2 = 2 per tick
		ds[i].hp = 2
	h.health.hp = h.health.max_hp / 2
	h.mp = 40.0
	var hp0 := h.health.hp
	var carry0 := h._leech_carry
	var r := "" if String(b.combo.get("id", "")) == "bloodthirst" else "setup: combo %s" % b.combo
	if r == "":
		var mp_rel := _sus_press(h, "piercing", ds, 0.8)
		if ds[0].alive or ds[2].alive: r = "the hit did not kill"
		elif not ds[1].alive or not ds[3].alive: r = "a burner died before its first tick"
		elif not is_equal_approx(h.mp - mp_rel, 4.0): r = "two hit kills: +%.2f MP, want +4" % (h.mp - mp_rel)
		if r == "":
			for i in int(round(1.7 / DT)): _step([], ds)
			var leech := float(b.leech)
			var want := int(floor(carry0 + 4 * 0.03 * h.health.max_hp + leech * (1 + 10 + 1 + 10) + leech * (2 + 2) + 1e-6))
			if ds[1].alive or ds[3].alive: r = "the burns did not kill"
			elif not is_equal_approx(h.mp - mp_rel, 6.0): r = "after the burn kills: +%.2f MP, want +6 (+2 then +0)" % (h.mp - mp_rel)
			elif _cast_of().mp_refunded() != 6: r = "ledger %d" % _cast_of().mp_refunded()
			elif h.health.hp - hp0 != want: r = "healed %d HP, want %d (4 kills × 3 %% + leech)" % [h.health.hp - hp0, want]
	_sus_done(h, ds)
	return r

## A fire-trail tick that kills calls the hook once, with the trail's press ledger (a dummy and a real Wolf). A trail
## only comes from ศรพัดเพลิง / พรหมาสตร์, never with a sustain combo on the same skill, so it pays 0: the hook is for
## consistency ("นับทุกแบบ").
func test_trail_kill_calls_hook():
	var sink := KillSink.new()
	var c := ComboCast.new("fire_fan")
	var d := _dummy(Vector2(60, 0), 1)
	for i in 90:
		d.apply_trail(5.0, 0.25, sink, c)
		d.tick_status(DT)
	var r := ""
	if d.alive: r = "setup: the dummy survived"
	elif sink.kills.size() != 1 or not is_same(sink.kills[0], c): r = "dummy: hook got %s, want [the trail's cast] once" % [sink.kills]
	var w: Wolf = load("res://scenes/wolf.tscn").instantiate()
	w.setup()
	w.health.hp = 1
	var c2 := ComboCast.new("brahmastra")
	if r == "":
		for i in 90:
			w.apply_trail(50.0, 0.25, sink, c2)
			if w.is_alive(): w.tick_burn(DT)
		if w.is_alive(): r = "setup: the wolf survived"
		elif sink.kills.size() != 2 or not is_same(sink.kills[1], c2): r = "wolf: hook got %s, want the trail's cast once more" % [sink.kills]
	w.free()
	d.free()
	sink.free()
	return r

## A press that already refunded its 6 gives 0 MP for a later burn kill of the same press; the kill still heals 3 %.
func test_dot_kill_after_cap_gives_nothing():
	var h := _sus_hero("piercing", ["leech", "multiply"])
	var b := h.build("piercing")
	var c := ComboCast.from_build(b)
	for i in 3: c.refund_kill()
	var d := _dummy(Vector2(60, 0), 1)
	d.apply_status("burn", 5.0, 0.0, h, c)
	h.mp = 40.0
	h.health.hp = h.health.max_hp / 2
	var hp0 := h.health.hp
	var carry0 := h._leech_carry
	for i in 70: d.tick_status(DT)
	var r := ""
	var want := int(floor(carry0 + 0.03 * h.health.max_hp + 1e-6))
	if d.alive: r = "setup: the burn did not kill"
	elif h.mp != 40.0: r = "MP %.2f after a capped press's burn kill, want 40" % h.mp
	elif h.health.hp - hp0 != want: r = "healed %d, want %d (3 %%)" % [h.health.hp - hp0, want]
	elif c.mp_refunded() != 6: r = "ledger %d" % c.mp_refunded()
	d.free()
	h.free()
	return r

## Kills by bounce arrows count toward the press's same 6 (ศรทะลวง [leech, multiply, ricochet]: the line kills L1 and
## L2, L1's bounce kills B: +6, not +4). Bolt kills too: a thunder_hop press's bolts carrying that same ledger (only a
## 4-slot skill could hold both recipes, one combo per skill: the ledger is shared to test the hook) give 0 more.
func test_bounce_and_bolt_kills_share_cap():
	var h := _sus_hero("piercing", ["leech", "multiply", "ricochet"])
	var b := h.build("piercing")
	b["cast"] = ComboCast.from_build(b)
	var l1 := _dummy(Vector2(60, 0))
	var l2 := _dummy(Vector2(150, 0))
	var bb := _dummy(Vector2(60, 70))
	var ds := [l1, l2, bb]
	for d in ds: d.die_on_hit = true
	h.mp = 40.0
	var r := "" if String(b.combo.get("id", "")) == "bloodthirst" and int(b.bounces) > 0 else "setup: %s bounces %s" % [b.combo, b.get("bounces")]
	_spawned = []
	var a := _arrow(Vector2.RIGHT, ds, b, true, h)
	for i in 90: _step([a], ds)
	if r != "": pass
	elif ds.filter(func(d): return d.alive).size() > 0: r = "setup: not all 3 killed"
	elif bb.hits.size() != 1 or _spawned.size() != 1: r = "setup: B was not killed by the bounce arrow"
	elif not is_equal_approx(h.mp, 46.0): r = "MP %.2f: the bounce kill did not count (+%.0f, want +6)" % [h.mp, h.mp - 40.0]
	var tb := _build(["ricochet", "lightning"])
	tb["cast"] = b.cast
	var x := _dummy(Vector2(60, 0))
	var y := _dummy(Vector2(60, 40))
	var e := _dummy(Vector2(60, -60))
	e.die_on_hit = true
	var a2 := _arrow(Vector2.RIGHT, [x, y, e], tb, true, h)
	if r == "":
		for i in 90: _step([a2], [])
		if e.alive or e.hits.size() != 1 or not is_equal_approx(float(e.hits[0][1]), float(tb.arrow_mult) * 0.5): r = "setup: E was not killed by a bolt (%s)" % [e.hits]
		elif not is_equal_approx(h.mp, 46.0): r = "a bolt kill on a capped ledger gave MP (%.2f)" % h.mp
		elif b.cast.mp_refunded() != 6: r = "ledger %d" % b.cast.mp_refunded()
	_free([a, a2, x, y, e] + ds + _spawned)
	_spawned = []
	h.free()
	return r

## Plan note (Task 6 review): the lightning gem's own chain hit (Arrow._after_hit calls receive_hit directly) goes through
## the same hook: a chain kill by a [leech, multiply, element lightning] press refunds +2 within the press's cap.
func test_lightning_chain_kill_refunds_mp():
	var h := _sus_hero("piercing", ["leech", "multiply", "lightning"])
	var b := h.build("piercing")
	b["cast"] = ComboCast.from_build(b)
	var a_ := _dummy(Vector2(60, 0))
	var c := _dummy(Vector2(60, 50))
	c.die_on_hit = true
	h.mp = 40.0
	var r := "" if String(b.combo.get("id", "")) == "bloodthirst" else "setup: combo %s" % b.combo
	var a := _arrow(Vector2.RIGHT, [a_, c], b, true, h)
	for i in 60: _step([a], [])
	if r != "": pass
	elif c.alive or c.hits.size() != 1 or not is_equal_approx(float(c.hits[0][1]), float(b.arrow_mult) * Balance.num("elements.lightning.mult")): r = "setup: C was not killed by the chain (%s)" % [c.hits]
	elif not is_equal_approx(h.mp, 42.0): r = "chain kill: MP %.2f, want 42" % h.mp
	elif b.cast.mp_refunded() != 2: r = "ledger %d" % b.cast.mp_refunded()
	_free([a, a_, c])
	h.free()
	return r

## The one kill hook for every damage source: primary, bounce, bolt, gem chain, line-end blast, shatter, burn tick and
## trail tick each credit the press's ledger exactly once for the monster they kill (KillSink as the shooter).
func test_every_source_kills_through_one_hook():
	var r := ""
	for src in ["primary", "bounce", "bolt", "chain", "line_end", "shatter", "burn", "trail"]:
		var sink := KillSink.new()
		var keys: Array = {"primary": [], "bounce": ["ricochet"], "bolt": ["ricochet", "lightning"], "chain": ["lightning"],
			"line_end": ["split", "fire", "multiply"], "shatter": ["ice", "split", "execute"], "burn": ["fire"], "trail": ["split", "fire"]}[src]
		var b := _build(keys)
		var ds: Array = []
		var victim: Node2D
		match src:
			"primary":
				victim = _dummy(Vector2(60, 0))
				ds = [victim]
			"bounce":
				victim = _dummy(Vector2(60, 70))
				ds = [_dummy(Vector2(60, 0)), victim]
			"bolt":
				victim = _dummy(Vector2(60, -60))
				ds = [_dummy(Vector2(60, 0)), _dummy(Vector2(60, 40)), victim]
			"chain":
				victim = _dummy(Vector2(60, 50))
				ds = [_dummy(Vector2(60, 0)), victim]
			"line_end":
				victim = _dummy(Vector2(Balance.num("skills.piercing.range"), 20))
				ds = [victim]
			"shatter":
				var s := _dummy(Vector2(60, 0))
				s.status.apply_slow()
				victim = _dummy(Vector2(60, 30))
				ds = [s, victim]
			"burn":
				victim = _dummy(Vector2(60, 0), 2)
				victim.deal = 10
				ds = [victim]
			"trail":
				victim = _dummy(Vector2(100, 0), 1)
		if src not in ["burn", "trail"]: victim.die_on_hit = true
		_spawned = []
		var arrows := _fan(b, ds, sink)
		for i in 45: _step(arrows, ds)
		if src == "trail": ds.append(victim)        # in the fire only after the arrows are gone: no direct hit
		for i in 120: _step(arrows, ds)
		var why := ""
		if victim.alive: why = "the victim survived"
		elif src == "trail" and victim.hits.size() > 0: why = "setup: the trail victim was hit directly"
		elif src == "bolt" and (victim.hits.size() != 1 or not is_equal_approx(float(victim.hits[0][1]), float(b.arrow_mult) * 0.5)): why = "setup: not a bolt kill (%s)" % [victim.hits]
		elif sink.kills.size() != 1: why = "%d kills credited, want 1" % sink.kills.size()
		elif not is_same(sink.kills[0], b.cast): why = "credited to %s, not the press's ledger" % [sink.kills[0]]
		if why != "": r = "%s: %s" % [src, why]
		_free(arrows + _spawned + ds + ([victim] if not victim in ds else []))
		_spawned = []
		sink.free()
		if r != "": break
	return r

## The hook itself (Hero.combo_hit): once per kill per ledger, only for a hit that kills (alive before, dead after,
## damage > 0), safe with freed targets / sources and with no ledger.
func test_kill_hook_once_per_kill_and_safe():
	var sink := KillSink.new()
	var c := ComboCast.new("bloodthirst")
	var d := _dummy(Vector2(60, 0))
	d.alive = false
	var r := ""
	Hero.combo_hit(sink, c, d, true, 5)
	Hero.combo_hit(sink, c, d, true, 5)          # a second source on the same kill (same frame, same press)
	if sink.kills.size() != 1: r = "same kill credited %d times" % sink.kills.size()
	Hero.combo_hit(sink, ComboCast.new("bloodthirst"), d, false, 5)   # another press's hit on the already dead target
	if r == "" and sink.kills.size() != 1: r = "a hit on a target already dead was credited"
	var e := _dummy(Vector2(60, 0))
	e.alive = false
	Hero.combo_hit(sink, c, e, true, 0)
	if r == "" and sink.kills.size() != 1: r = "a 0-damage hit was credited"
	Hero.combo_hit(sink, null, e, true, 5)
	Hero.combo_hit(sink, {}, e, true, 5)
	if r == "" and sink.kills.size() != 1: r = "a hit with no ledger was credited"
	var gone := _dummy(Vector2(60, 0))
	gone.free()
	Hero.combo_hit(sink, c, gone, true, 5)       # freed target: no error, nothing
	var gone_src := KillSink.new()
	gone_src.free()
	Hero.combo_hit(gone_src, c, e, true, 5)      # freed source: no error, nothing
	if r == "" and sink.kills.size() != 1: r = "a freed target / source was credited"
	e.last_hit_crit = true
	var alive := _dummy(Vector2(60, 0))
	Hero.combo_hit(sink, c, alive, true, 5, true)
	if r == "" and (sink.crits.size() != 1 or sink.kills.size() != 1): r = "a crit that does not kill: crits %d kills %d, want 1 / 1" % [sink.crits.size(), sink.kills.size()]
	_free([d, e, alive])
	sink.free()
	return r

## Two sources the same frame on a real Wolf (a burn of press A ticking and press B's arrow): one kill, one credit,
## whichever lands first (B's arrow skips the dead wolf; A's tick never runs on it).
func test_dot_and_hit_same_frame_credit_once():
	var r := ""
	for arrow_first in [true, false]:
		var sink := KillSink.new()
		var w: Wolf = load("res://scenes/wolf.tscn").instantiate()
		w.setup()
		w.position = Vector2(60, 0) - Wolf.HURT_POINT * Wolf.size_scale()   # hurt point at (60, 0)
		var ca := ComboCast.new("bloodthirst")
		w.apply_status("burn", 50.0, 0.0, sink, ca)
		for i in 59: w.tick_burn(DT)               # the burn's first tick is due on the next step
		w.health.hp = 1
		var bb := _build([])
		bb["cast"] = ComboCast.new("bloodthirst")
		var a := _arrow(Vector2.RIGHT, [w], bb, true, sink)
		var guard := 0
		while a.travelled + Balance.num("shot.arrow_speed") * DT < 60.0 - 12.0 and guard < 60:   # the frame before it reaches the wolf
			a.advance(DT)
			guard += 1
		if arrow_first:
			a.advance(DT)
			a.advance(DT)
			if w.is_alive(): w.tick_burn(DT)
		else:
			if w.is_alive(): w.tick_burn(DT)
			a.advance(DT)
			a.advance(DT)
		var who := "arrow" if arrow_first else "burn"
		if w.is_alive(): r = "%s first: setup: the wolf survived" % who
		elif sink.kills.size() != 1: r = "%s first: %d credits for one kill, want 1" % [who, sink.kills.size()]
		elif not is_same(sink.kills[0], bb.cast if arrow_first else ca): r = "%s first: credited to the wrong press" % who
		_free([a])
		w.free()
		sink.free()
		if r != "": break
	return r

## Many fire trails of ONE press share its cap: three trails carrying one bloodthirst ledger kill 5 monsters → +6.
func test_many_trails_one_press_share_cap():
	var h := _sus_hero("piercing", ["leech", "multiply"])
	var c := ComboCast.new("bloodthirst")
	var ds := [_dummy(Vector2(50, 0), 1), _dummy(Vector2(150, 0), 1), _dummy(Vector2(100, 15), 1), _dummy(Vector2(100, -15), 1), _dummy(Vector2(180, -27), 1)]
	var trails: Array = []
	for end in [Vector2(200, 0), Vector2(200, 30), Vector2(200, -30)]:
		var t := FireTrail.new()
		t.setup(Vector2.ZERO, 5.0, 1.0, 1.0, 2.0, ds, h, c, 0.0, "bloodthirst")
		t.extend_to(end)
		t.finish()
		trails.append(t)
	h.mp = 40.0
	for i in 90:
		for t in trails: t.step(DT)
		for d in ds: d.tick_status(DT)
	var r := ""
	if ds.filter(func(d): return d.alive).size() > 0: r = "setup: not all 5 killed by the trails"
	elif not is_equal_approx(h.mp, 46.0): r = "MP +%.2f from 5 trail kills of one press, want +6" % (h.mp - 40.0)
	_free(trails + ds)
	h.free()
	return r

## A ledger is never reused across presses: press 1's burn kills after press 2 was fired → credited to press 1 (capped:
## 0 MP), press 2's ledger untouched.
func test_late_burn_kill_credits_its_own_press():
	var h := _sus_hero("piercing", ["leech", "multiply", "fire"])
	var ds := _rays(h, "piercing", [[60, 90, 120, 150]])
	ds[3].die_on_hit = false
	ds[3].deal = 10
	ds[3].hp = 2
	h.mp = 60.0
	var r := ""
	var mp1 := _sus_press(h, "piercing", ds, 0.6)
	var c1 := _cast_of()
	if mp1 < 0.0 or c1 == null or c1.mp_refunded() != 6 or not ds[3].alive or not ds[3].status.is_burning(): r = "setup: press 1 refunded %s, burner alive %s" % [c1.mp_refunded() if c1 else -1, ds[3].alive]
	if r == "":
		h.state = "idle"
		h._skill_cd.clear()
		h.test_enemies = []
		var mp2 := _sus_press(h, "piercing", [], 0.0)
		var c2 := _cast_of(_spawned.size() - 1)
		if mp2 < 0.0 or is_same(c2, c1): r = "setup: press 2"
		else:
			for i in int(round(1.5 / DT)): _step([], ds)
			if ds[3].alive: r = "setup: the burn did not kill"
			elif c2.mp_refunded() != 0: r = "press 2's ledger was credited %d for press 1's burn" % c2.mp_refunded()
			elif h.mp != mp2: r = "MP %.2f → %.2f: a capped press's burn kill gave MP" % [mp2, h.mp]
			elif c1.mp_refunded() != 6: r = "press 1's ledger %d" % c1.mp_refunded()
	_sus_done(h, ds)
	return r

## tools/gem_combo_sim.py `--press` (sustain rows): ศรทะลวง Lv10, crit counted (hero 0.05 + execute 0.15, crit.mult
## 1.5), units of the press's first hit before ราหู's bonus: ศรกระหายเลือด single 1.025 · ราหู 1.331 (the sim mixes
## HP ≥ 70 % on 70 % of the presses: 1.1 × (1 + 0.3 × 0.7)) · a pack press (3 hits, ~2 kills) costs MP − refund:
## กระหายเลือด 14.4 − 4 = 10.40 · ราหู 17.28 − 6 = 11.28.
const SIM_SUSTAIN := {"bloodthirst": 1.025, "rahu": 1.331, "bloodthirst mp": 10.40, "rahu mp": 11.28, "bloodthirst refund": 4, "rahu refund": 6}

## Game vs the sim per press: single target (the dummy records each hit's multiplier; ราหู's two presses at HP ≥ 70 %
## and < 70 % mixed 70 / 30 as the sim) and the pack press's net MP (a real hero press into the sim's pack: 3 hits in
## the line, 2 kills) within ±3 %; the refund equals the sim's.
func test_sustain_press_matches_sim():
	var lines: Array = []
	var r := ""
	for id in ["bloodthirst", "rahu"]:
		var keys: Array = ["leech", "multiply"] if id == "bloodthirst" else ["leech", "multiply", "execute"]
		var b := _build(keys)
		var am := float(b.arrow_mult)
		var game := 0.0
		for hp_mix in ([[1.0, 1.0]] if id == "bloodthirst" else [[1.0, 0.7], [0.5, 0.3]]):
			var bp: Dictionary = b.duplicate()
			bp["cast"] = ComboCast.from_build(b, float(hp_mix[0]))
			var d := _dummy(Vector2(60, 0))
			_spawned = []
			var a := _arrow(Vector2.RIGHT, [d], bp)
			a.mult = am * (1.0 + bp.cast.dmg_bonus())     # as Hero._release
			a.crit_chance = float(b.crit)
			a.crit_mult = Balance.num("crit.mult")
			for i in 60: _step([a], [])
			game += float(hp_mix[1]) * _expected([d], am)
			_free([a, d])
		var sim: float = SIM_SUSTAIN[id]
		lines.append("%s single: game %.3f vs sim %.3f = %+.1f %%" % [id, game, sim, (game / sim - 1.0) * 100.0])
		if absf(game / sim - 1.0) > 0.03: r = "%s single: game %.3f vs sim %.3f (> ±3 %%)" % [id, game, sim]
		if r != "": break
		var h := _sus_hero("piercing", keys)
		var hb := h.build("piercing")
		var ds := _rays(h, "piercing", [[60, 90, 120]])
		ds[2].die_on_hit = false
		h.mp = 60.0
		var mp_rel := _sus_press(h, "piercing", ds)
		var refund := h.mp - mp_rel
		var net := float(hb.mp) - refund
		var sim_mp: float = SIM_SUSTAIN[id + " mp"]
		lines.append("%s pack press: MP %.2f − refund %.0f = %.2f vs sim %.2f = %+.1f %%" % [id, hb.mp, refund, net, sim_mp, (net / sim_mp - 1.0) * 100.0])
		if ds.filter(func(x): return not x.alive).size() != 2: r = "%s pack: setup: 2 kills wanted" % id
		elif not is_equal_approx(refund, float(SIM_SUSTAIN[id + " refund"])): r = "%s pack: refund %.2f, want the sim's %d" % [id, refund, SIM_SUSTAIN[id + " refund"]]
		elif absf(net / sim_mp - 1.0) > 0.03: r = "%s pack: net MP %.3f vs sim %.3f (> ±3 %%)" % [id, net, sim_mp]
		_sus_done(h, ds)
		if r != "": break
	print("  sustain per press:\n    " + "\n    ".join(lines))
	return r

## The recipe's "kill" effect (pickup_pop, red for กระหายเลือด) plays at the monster when a kill pays (heal or MP), in the
## hero's parent like his arrows; a kill that pays nothing (ราหู at its 9 MP cap: no kill heal) plays nothing.
func test_kill_fx_plays_when_paid():
	var world := Node2D.new()
	tree.root.add_child(world)
	var h: Hero = load("res://scenes/hero.tscn").instantiate()
	world.add_child(h)
	h.set_physics_process(false)
	var count := func(): return world.get_children().filter(func(c): return c is FxSprite and not c.is_queued_for_deletion()).size()
	var r := ""
	var n0: int = count.call()
	h.on_combo_kill(ComboCast.new("bloodthirst"), Vector2(40, 0))
	var n1: int = count.call()
	if n1 != n0 + 1: r = "a paying kill played %d effects, want 1" % (n1 - n0)
	var spent := ComboCast.new("rahu")
	for i in 3: spent.refund_kill()
	h.on_combo_kill(spent, Vector2(40, 0))
	if r == "" and count.call() != n1: r = "a kill that paid nothing played an effect"
	world.queue_free()
	await tree.process_frame
	return r

# ---------- Task 8 review (owner 2026-11-11): real Wolf crit flag, tinted hit spark ----------

## A REAL Wolf (and a Monster: Monster.receive_hit goes through Wolf's) reports its crit roll in last_hit_crit, and a
## ราหู press's arrow heals 1 % of max HP on that crit (+ its leech): crit chance 1.0 → true and the heal; crit chance 0
## → false and the leech only; a hit on a dead wolf → false (reset before the dead check) and no heal.
func test_real_wolf_crit_flag_heals_rahu():
	var r := ""
	for scene in ["res://scenes/wolf.tscn", "res://scenes/monster.tscn"]:
		for row in [[1.0, true], [0.0, false]]:
			var h := _sus_hero("piercing", ["leech", "multiply", "execute"])
			var b := h.build("piercing")
			b["cast"] = ComboCast.from_build(b, 0.5)
			if b.cast.id != "rahu": r = "setup: combo %s, want rahu" % b.cast.id
			var w: Wolf = load(scene).instantiate()
			if w is Monster: w.kind = "boar"
			w.setup()
			w.health.setup(100000)
			w.position = Vector2(60, 0) - Wolf.HURT_POINT * Wolf.size_scale()
			w.last_hit_crit = not row[1]                  # stale opposite value: the hit must set it
			h.health.hp = h.health.max_hp / 2
			var hp0 := h.health.hp
			var carry0 := h._leech_carry
			var a := _arrow(Vector2.RIGHT, [w], b, true, h)
			a.crit_chance = row[0]
			a.crit_mult = 1.5
			for i in 60: _step([a], [])
			var dealt := 100000 - w.health.hp
			var heal := (0.01 * h.health.max_hp if row[1] else 0.0) + float(b.leech) * dealt
			var want := int(floor(carry0 + heal + 1e-6))
			var tag := "%s crit chance %.0f" % [scene.get_file(), row[0]]
			if r == "" and dealt <= 0: r = "%s: setup: the arrow did not hit" % tag
			elif r == "" and w.last_hit_crit != row[1]: r = "%s: last_hit_crit %s, want %s" % [tag, w.last_hit_crit, row[1]]
			elif r == "" and h.health.hp - hp0 != want: r = "%s: healed %d, want %d (crit 1 %% of %d: %s + leech of %d)" % [tag, h.health.hp - hp0, want, h.health.max_hp, row[1], dealt]
			if r == "" and row[1]:
				w.health.take_hit(1000000, false)          # dead now; a sure crit on the corpse
				var hp1 := h.health.hp
				var amount := w.receive_hit(20.0, 1.0, Vector2.ZERO, 1.0, 1.5)
				Hero.combo_hit(h, b.cast, w, false, amount, w.last_hit_crit)
				if w.is_alive(): r = "%s: setup: the wolf did not die" % tag
				elif amount != 0 or w.last_hit_crit: r = "%s: a hit on a dead wolf dealt %d, last_hit_crit %s (want 0, false)" % [tag, amount, w.last_hit_crit]
				elif h.health.hp != hp1: r = "%s: a hit on a dead wolf healed" % tag
			_free([a])
			w.free()
			h.free()
			if r != "": return r
	return r

## Owner 2026-11-11 ("ย้อมสีประกายตีแทน"): a sustain press's hits carry its recipe's spark tint (balance.json fx "hit" row:
## กระหายเลือด #ff4a4a, ราหู #6a2a8a) for exactly that hit — primary arrows, bounce arrows, the lightning gem's chain,
## bolts and blasts (_secondary_hit) — and the target is back to WHITE after; another recipe's or a plain press's hits
## carry WHITE. ศรทะลวง [leech, multiply, ricochet] (bounce) and [leech, multiply, lightning] (chain) for กระหายเลือด.
func test_sustain_hits_carry_the_spark_tint():
	var red := Color("#ff4a4a")
	var purple := Color("#6a2a8a")
	var r := ""
	if ComboFx.spark_tint("bloodthirst") != red or ComboFx.spark_tint("rahu") != purple: r = "spark tints %s / %s, want the recipes' #ff4a4a / #6a2a8a" % [ComboFx.spark_tint("bloodthirst"), ComboFx.spark_tint("rahu")]
	for id in ["", "thunder_hop", "hawk_eye", "fire_fan", "nope"]:
		if r == "" and ComboFx.spark_tint(id) != Color.WHITE: r = "%s has a spark tint %s, want none" % [id, ComboFx.spark_tint(id)]
	# primary + bounce (ricochet) and the lightning gem's chain
	for row in [[["leech", "multiply", "ricochet"], red, "bounce"], [["leech", "multiply", "lightning"], red, "chain"], [["leech", "multiply", "execute"], purple, "primary"], [["ricochet", "multiply"], Color.WHITE, "plain bounce"]]:
		if r != "": break
		_spawned = []
		var b := _build(row[0])
		var d := _dummy(Vector2(60, 0))
		var e := _dummy(Vector2(60, 50))
		var a := _arrow(Vector2.RIGHT, [d, e], b, true)
		for i in 60: _step([a], [d, e])
		var tints: Array = d.spark_tints + e.spark_tints
		if row[2] != "primary" and e.hits.is_empty(): r = "%s: setup: the second dummy took no %s hit" % [row[2], row[2]]
		elif tints.is_empty(): r = "%s: setup: no hit" % row[2]
		for t in tints:
			if r == "" and t != row[1]: r = "%s %s: a hit carried %s, want %s" % [row[0], row[2], t, row[1]]
		if r == "" and (d.spark_tint != Color.WHITE or e.spark_tint != Color.WHITE): r = "%s: the tint stayed on the target after the hit" % row[2]
		_free([a, d, e] + _spawned)
	# secondary hits (blasts / bolts: _secondary_hit) of a sustain press
	if r == "":
		var b := _build(["leech", "multiply"])
		var f := _dummy(Vector2(100, 0))
		var g := _dummy(Vector2(110, 0))
		var a := _arrow(Vector2.RIGHT, [f, g], b, true)
		a.blast(Vector2(100, 0), 32.0, 0.5, false)
		if f.hits.size() != 1 or g.hits.size() != 1: r = "setup: the blast hit %d / %d" % [f.hits.size(), g.hits.size()]
		elif f.spark_tints != [red] or g.spark_tints != [red]: r = "blast hits carried %s / %s, want red" % [f.spark_tints, g.spark_tints]
		_free([a, f, g])
	return r

## In game (TestGround): a sustain press's hit on a real monster plays the normal hit spark recoloured to the recipe's tint
## (ComboFx.recolor, shaders/recolor.gdshader), a plain press's hit an unrecoloured one; with the PerfSaver on the spark
## still plays (never hidden) and is still recoloured; a crit keeps its crit_hit glare (the saver's fallback spark is
## recoloured).
func test_hit_spark_recoloured_in_game():
	if FileAccess.file_exists(TMP_SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))
	var g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = TMP_SAVE
	g.layout_seed = 1
	tree.root.add_child(g)
	await tree.process_frame
	await tree.process_frame
	var h: Hero = g.hero
	h.set_physics_process(false)
	for p in g.packs: p.process_mode = Node.PROCESS_MODE_DISABLED
	var w: Wolf = null
	for p in g.packs:
		for x in p.wolves:
			if w == null and x.is_alive(): w = x
	var r := "" if w != null else "setup: no monster in the room"
	var sparks := func():
		return g.stage.find_children("*", "", true, false).filter(func(c): return c is FxSprite and c.animation in ["hit_spark", "crit_hit"] and not c.is_queued_for_deletion())
	var cases := [[["leech", "multiply"], 0.0, false, "hit_spark", Color("#ff4a4a")], [["leech", "multiply", "execute"], 0.0, true, "hit_spark", Color("#6a2a8a")],
		[["split"], 0.0, false, "hit_spark", Color.WHITE], [["leech", "multiply", "execute"], 1.0, false, "crit_hit", Color.WHITE],
		[["leech", "multiply", "execute"], 1.0, true, "hit_spark", Color("#6a2a8a")]]
	for c in cases:
		if r != "": break
		g.saver.on = c[2]
		g.apply_saver()
		w.health.setup(100000)
		w.process_mode = Node.PROCESS_MODE_ALWAYS     # kept in the physics space (a knockback moves it) but never stepped
		w.set_physics_process(false)
		var from: Vector2 = w.hurt_point() - Vector2(60, 0)
		for s in sparks.call(): s.free()
		var gems: Array = []
		for k in c[0]: gems.append(_g(k))
		var b := SkillBuild.of("piercing", 10, gems, STATS)
		b["cast"] = ComboCast.from_build(b, 0.5)
		b["crit"] = c[1]
		var a: Arrow = load("res://scenes/arrow.tscn").instantiate()   # as Hero._fire, aimed at this monster only
		a.position = from
		a.launch(Vector2.RIGHT, h.stats().atk, [w], float(b.arrow_mult), false, 70.0)
		a.crit_chance = c[1]
		a.crit_mult = h.stats().crit_mult
		a.primary = true
		a.configure(b, h)
		h.get_parent().add_child(a)
		for i in 40:
			await tree.physics_frame
			if w.health.hp < 100000: break
		var got: Array = sparks.call()
		var tag := "%s crit %.0f saver %s" % [c[0], c[1], c[2]]
		if w.health.hp >= 100000: r = "%s: setup: the arrow did not hit the monster" % tag
		elif got.size() != 1: r = "%s: %d sparks, want 1 (never hidden)" % [tag, got.size()]
		elif got[0].animation != c[3]: r = "%s: %s played, want %s" % [tag, got[0].animation, c[3]]
		elif c[4] == Color.WHITE and got[0].material != null: r = "%s: the spark was recoloured" % tag
		elif c[4] != Color.WHITE and not (got[0].material is ShaderMaterial and got[0].material.get_shader_parameter("tint") == c[4]): r = "%s: spark material %s, want the recolour to %s" % [tag, got[0].material, c[4].to_html(false)]
		elif got[0].modulate != Color.WHITE: r = "%s: spark modulate %s (the recolour is the shader's)" % [tag, got[0].modulate]
		elif w.spark_tint != Color.WHITE: r = "%s: the monster kept the tint after the hit" % tag
	g.saver.on = false
	g.apply_saver()
	Sfx.stop_all()                                   # the hits' sounds: none left playing at exit
	g.queue_free()
	for i in 10: await tree.process_frame             # the audio server lets go of the stopped playbacks
	if FileAccess.file_exists(TMP_SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))
	return r
