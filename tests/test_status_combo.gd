extends RefCounted
## M5b Task 4: monster statuses for gem combos (docs/superpowers/specs/2026-11-08-gem-combos.md, plan Task 4):
## freeze with a per-target lock, mark, a non-stacking trail burn, zone; each status keeps the ComboCast (per-press
## ledger) of the press that applied it (Review Focus 6, risks.md B25). Owner 2026-11-08: bosses and elites freeze
## like any monster ("บอสแข็งได้เหมือนมอนอื่น").

var tree: SceneTree
const DT := 1.0 / 60.0
const FRUIT := preload("res://scripts/monsters/fruit.gd")

## A stand-in for the hero as a DoT's source: records leech heals.
class Sink extends RefCounted:
	var got := 0.0
	func leech_heal(a: float) -> void:
		got += a

func setup(t: SceneTree) -> void:
	tree = t

func _world() -> Node2D:
	await tree.process_frame
	var w := Node2D.new()
	tree.root.add_child(w)
	return w

func _hero(world: Node2D, pos: Vector2) -> Hero:
	var h: Hero = load("res://scenes/hero.tscn").instantiate()
	h.position = pos
	world.add_child(h)
	h.set_physics_process(false)
	h.health.setup(100000)
	return h

func _pack(world: Node2D, kind: String, home: Vector2, lv := 1, n := 1) -> WolfPack:
	var p := WolfPack.new()
	p.kind = kind
	p.level = lv
	p.count = n
	p.home = home
	world.add_child(p)
	p.set_physics_process(false)
	return p

func _frames(p: WolfPack, h: Hero, n: int, until := Callable()) -> bool:
	for i in n:
		await tree.physics_frame
		h.step(DT, Vector2.ZERO)
		p.step_all(DT, h)
		if until.is_valid() and until.call(): return true
	return false

func _wolf() -> Wolf:
	var w: Wolf = load("res://scenes/wolf.tscn").instantiate()
	w.setup()
	return w

func _count(world: Node2D, script: Script) -> int:
	var c := 0
	for ch in world.find_children("*", "", true, false):
		if ch.get_script() == script and not ch.is_queued_for_deletion(): c += 1
	return c

# ---------- StatusEffects (pure) ----------

func test_freeze_once_per_lock():
	var s := StatusEffects.new()
	if not s.apply_freeze(1.0, 5.0): return "first freeze refused"
	if not s.is_frozen(): return "not frozen after apply"
	s.tick(0.5)
	if s.apply_freeze(1.0, 5.0): return "re-froze while frozen"
	s.tick(0.5)
	if s.is_frozen(): return "still frozen after 1.0 s"
	s.tick(3.9)
	if s.apply_freeze(1.0, 5.0): return "re-froze at 4.9 s (lock is 5 s)"
	s.tick(0.2)
	if not s.apply_freeze(1.0, 5.0): return "lock did not end after 5 s"
	return "" if s.is_frozen() else "second freeze not applied"

func test_frozen_speed_zero():
	var s := StatusEffects.new()
	s.apply_slow()
	s.apply_zone(0.3, 0.0, 10.0)
	s.apply_freeze(1.0, 5.0)
	if s.speed_mult() != 0.0: return "frozen speed ×%s" % s.speed_mult()
	s.tick(1.01)
	s.apply_zone(0.3, 0.0, 10.0)
	if not is_equal_approx(s.speed_mult(), 0.6 * 0.7): return "thawed, slowed and in a zone: ×%s, want 0.42" % s.speed_mult()
	return ""

func test_mark_keeps_highest():
	var s := StatusEffects.new()
	s.apply_mark(0.2, 4.0)
	if not is_equal_approx(s.taken_mult(), 1.2): return "mark 0.2: ×%s" % s.taken_mult()
	s.apply_mark(0.3, 4.0)
	if not is_equal_approx(s.taken_mult(), 1.3): return "mark 0.3: ×%s" % s.taken_mult()
	s.tick(2.0)
	s.apply_mark(0.2, 4.0)         # weaker re-mark: keeps 0.3, refreshes the time
	if not is_equal_approx(s.taken_mult(), 1.3): return "weaker re-mark lowered it to ×%s" % s.taken_mult()
	s.tick(3.9)
	if not s.is_marked(): return "the re-mark did not refresh the time"
	s.tick(0.11)
	return "" if is_equal_approx(s.taken_mult(), 1.0) and not s.is_marked() else "mark left after it ended: ×%s" % s.taken_mult()

func test_trail_does_not_stack():
	var s := StatusEffects.new()
	for i in 3: s.apply_trail(10.0, 0.25, null)
	var got := s.tick(1.0)
	if got != 10: return "3 overlapping trails dealt %d in 1 s, want 10" % got
	var b := StatusEffects.new()
	b.apply_burn(5.0)
	for i in 3: b.apply_trail(10.0, 0.25, null)
	got = b.tick(1.0)
	if got != 15: return "trail + burn dealt %d, want 15" % got
	var c := StatusEffects.new()
	c.apply_trail(10.0, 0.25, null)
	c.apply_trail(6.0, 0.25, null)                 # a weaker overlapping trail keeps the highest
	return "" if c.trail_per_tick == 10.0 else "overlapping trails per tick %s, want 10" % c.trail_per_tick

## A monster in the fire ticks once per full second it has been in it (burn-style, at the end of each second), never
## more often, stepping out and back in included. Review I2 (approved numbers = tools/gem_combo_sim.py: fire_fan 2
## ticks, brahmastra 3): the Task 4 version ticked on contact and so gave one tick more per trail; this test was
## changed with it (an approved-number fix, not a weaker check). HOLD = what a FireTrail re-applies every step.
const HOLD := 0.25

func test_trail_ticks_once_a_second_on_reentry():
	var s := StatusEffects.new()
	var total := 0
	for i in 120:                                  # 2 s at the edge: in 0.1 s, out 0.1 s (out < hold: one stay)
		if (i / 6) % 2 == 0: s.apply_trail(10.0, HOLD, null)
		total += s.tick(DT)
	if total != 20: return "2 s flickering in and out dealt %d, want 20 (one tick a second)" % total
	for i in 120: total += s.tick(DT)               # left the fire: nothing more
	if total != 20: return "trail kept burning after the hold ended (%d)" % total
	var r := StatusEffects.new()                    # in 0.6 s, out 0.5 s (> hold), again and again: re-entry
	total = 0                                       # never starts a tick early; each stay is < 1 s → no tick
	for i in 330:
		if i % 66 < 36: r.apply_trail(10.0, HOLD, null)
		total += r.tick(DT)
	return "" if total == 0 else "stepping out and back in dealt %d (each stay < 1 s, want 0)" % total

## The longest flight of any arrow skill: the largest range of shot.range and every skill that flies arrows (no
## `kind`, or kind "arrows"; Task 4 review: not shot.range alone, a skill may set its own range), over the speed.
func _longest_flight() -> float:
	var rng := Balance.num("shot.range")
	var skills: Dictionary = Balance.data().get("skills", {})
	for id in skills:
		var row = skills[id]
		if typeof(row) != TYPE_DICTIONARY or not row.has("range"): continue
		if String(row.get("kind", "arrows")) != "arrows": continue
		rng = maxf(rng, float(row.range))
	return rng / Balance.num("shot.arrow_speed")

## The approved numbers are the sim's: a target standing in one trail gets exactly round(secs / tick) ticks: fire_fan
## 2 s → 2, brahmastra 3 s → 3, counted from the arrow passing it to the trail's end (+ the last hold), with the
## arrow's flight (0 .. the longest arrow skill's range / speed) still inside the line. The margin: hold + that
## flight must stay under one tick, or a stationary target would get one tick more than simulated.
func test_trail_ticks_match_the_sim():
	var flight := _longest_flight()
	if HOLD + flight >= Balance.num("elements.fire.tick"): return "hold %s + longest arrow flight %.2f s ≥ one tick: trails would tick more than the sim" % [HOLD, flight]
	for secs in [2.0, 3.0]:
		for extra in [0.0, flight]:
			var s := StatusEffects.new()
			var ticks := 0
			for i in int(round((secs + extra) / DT)):
				s.apply_trail(10.0, HOLD, null)
				if s.tick(DT) > 0: ticks += 1
			for i in 120:
				if s.tick(DT) > 0: ticks += 1
			var want := int(round(secs / Balance.num("elements.fire.tick")))
			if ticks != want: return "a %s s trail (+%.2f s flight) ticked %d times, want %d (sim)" % [secs, extra, ticks, want]
	return ""

func test_zone_slow_and_taken_keep_highest():
	var s := StatusEffects.new()
	s.apply_zone(0.3, 0.1, 0.25)
	s.apply_zone(0.2, 0.2, 0.25)                 # hellfield over hunter_zone: the highest of each
	if not is_equal_approx(s.speed_mult(), 0.7): return "zone speed ×%s, want 0.7" % s.speed_mult()
	if not is_equal_approx(s.taken_mult(), 1.2): return "zone taken ×%s, want 1.2" % s.taken_mult()
	s.apply_mark(0.3, 4.0)
	# owner 2026-11-09 (Task 5 review, "บวกกัน +50%"): mark and zone ADD (1 + 0.3 + 0.2), they do not multiply (×1.56)
	if not is_equal_approx(s.taken_mult(), 1.5): return "mark + zone ×%s, want 1.5 (they add)" % s.taken_mult()
	s.tick(0.3)
	if not is_equal_approx(s.taken_mult(), 1.3) or not is_equal_approx(s.speed_mult(), 1.0): return "zone left after its hold: taken ×%s speed ×%s" % [s.taken_mult(), s.speed_mult()]
	return ""

## Burn and trail ticks are multiplied by mark / zone too (plan Task 4 interfaces).
func test_dot_ticks_use_taken_mult():
	var s := StatusEffects.new()
	s.apply_mark(0.2, 4.0)
	s.apply_burn(10.0)
	s.apply_trail(5.0, 0.25, null)
	var got := s.tick(1.0)
	return "" if got == 18 else "marked burn 10 + trail 5 dealt %d, want 18" % got

## Every status keeps the ComboCast of the press that applied it (B25: burn / trail kills refund through that
## press's ledger, never the latest press). A refused freeze keeps the first press's ledger.
func test_statuses_carry_their_press_cast():
	var a := ComboCast.new("bloodthirst")
	var b := ComboCast.new("rahu")
	var s := StatusEffects.new()
	s.apply_burn(5.0, 0.0, null, a)
	if not is_same(s.burn_cast, a): return "burn did not keep its press's cast"
	s.apply_burn(3.0, 0.0, null, b)                  # a re-burn takes the newer cast (like burn_source), keeps 5 / tick
	if not is_same(s.burn_cast, b) or s.burn_per_tick != 5.0: return "re-burn: cast %s per tick %s" % [s.burn_cast, s.burn_per_tick]
	s.apply_trail(10.0, 0.25, null, a)
	if not is_same(s.trail_cast, a): return "trail did not keep its press's cast"
	if not s.apply_freeze(1.0, 5.0, a) or not is_same(s.freeze_cast, a): return "freeze cast"
	if s.apply_freeze(1.0, 5.0, b) or not is_same(s.freeze_cast, a): return "a refused freeze replaced the ledger"
	s.apply_mark(0.2, 4.0, a)
	s.apply_zone(0.3, 0.1, 1.0, b)
	if not is_same(s.mark_cast, a) or not is_same(s.zone_cast, b): return "mark / zone casts"
	s.clear()
	for k in ["burn_cast", "trail_cast", "freeze_cast", "mark_cast", "zone_cast"]:
		if s.get(k) != null: return "clear() left %s" % k
	return ""

## tick_cast: the ledger of the DoT that dealt this step's damage (null when nothing ticked), so a burn or trail
## kill is credited to exactly one press (Task 8 hook). Both ticking at once and neither ledger pays: the larger
## tick's ledger, ties = burn (review M4: a paying ledger goes first, test_dot_kill_credits_the_paying_ledger; this
## test used a paying bloodthirst ledger for `a` before M4, now two 0-MP ones).
func test_tick_cast_names_one_ledger():
	var a := ComboCast.new("frost_shard")
	var b := ComboCast.new("fire_fan")
	var s := StatusEffects.new()
	s.apply_burn(4.0, 0.0, null, a)
	s.tick(0.5)
	if s.tick_cast != null: return "tick_cast set on a step with no damage"
	s.tick(0.5)
	if not is_same(s.tick_cast, a): return "burn tick credited %s" % s.tick_cast
	s.apply_trail(9.0, 2.0, null, b)
	s.tick(1.0)                                         # burn 4 and trail 9 tick together → the trail's press
	if not is_same(s.tick_cast, b): return "larger trail tick not credited"
	var c := StatusEffects.new()
	c.apply_burn(5.0, 0.0, null, a)
	c.apply_trail(5.0, 2.0, null, b)
	c.tick(1.0)
	if not is_same(c.tick_cast, a): return "tie should credit the burn's press"
	var src := RefCounted.new()                         # the trail's last tick also ends its hold: source still named
	var d := StatusEffects.new()
	d.apply_trail(5.0, 0.25, src, b)
	d.tick(1.0)
	if not is_same(d.tick_cast, b) or not is_same(d.tick_source, src): return "trail ending on its killing tick lost cast/source"
	d.clear()                                           # death clears the statuses, not the last tick's report
	return "" if is_same(d.tick_cast, b) and is_same(d.tick_source, src) else "clear() dropped tick_cast / tick_source"

## Review M4: a burn and a trail tick on the same step and kill: the kill goes to the ledger that pays (MP on kill
## left, or a heal) over a 0-MP one, whichever tick was larger; only when both or neither pay does the larger tick
## (ties: the burn) decide. One ledger per step, so one kill still pays at most once.
func test_dot_kill_credits_the_paying_ledger():
	var pays := ComboCast.new("bloodthirst")
	var src_b := RefCounted.new()
	var src_t := RefCounted.new()
	var s := StatusEffects.new()
	s.apply_burn(2.0, 0.0, src_b, pays)                  # small burn from a bloodthirst press (+ fire gem)
	s.apply_trail(9.0, 2.0, src_t, ComboCast.new("fire_fan"))   # larger trail tick, 0 MP
	s.tick(1.0)
	if not is_same(s.tick_cast, pays) or not is_same(s.tick_source, src_b): return "larger 0-MP trail tick took the kill from the paying burn"
	var t := StatusEffects.new()
	t.apply_burn(9.0, 0.0, src_b, ComboCast.new("fire_fan"))
	t.apply_trail(2.0, 2.0, src_t, pays)
	t.tick(1.0)
	if not is_same(t.tick_cast, pays) or not is_same(t.tick_source, src_t): return "larger 0-MP burn tick took the kill from the paying trail"
	var spent := ComboCast.new("rahu")                   # rahu at its 9 MP cap pays nothing more (no kill heal)
	for i in 3: spent.refund_kill()
	var u := StatusEffects.new()
	u.apply_burn(2.0, 0.0, src_b, ComboCast.new("bloodthirst"))
	u.apply_trail(9.0, 2.0, src_t, spent)
	u.tick(1.0)
	if u.tick_cast == null or u.tick_cast.id != "bloodthirst": return "a capped ledger beat one that still pays (%s)" % u.tick_cast
	var w := StatusEffects.new()                         # both pay: the larger tick
	var big := ComboCast.new("rahu")
	w.apply_burn(2.0, 0.0, src_b, ComboCast.new("bloodthirst"))
	w.apply_trail(9.0, 2.0, src_t, big)
	w.tick(1.0)
	return "" if is_same(w.tick_cast, big) else "both pay: the larger tick should take it"

## Review I1: a burn's leech and source end with the burn (and in clear()); they never outlive it.
func test_burn_leech_ends_with_the_burn():
	var src := Sink.new()
	var s := StatusEffects.new()
	s.apply_burn(5.0, 0.5, src)
	for i in int(round(3.2 / DT)): s.tick(DT)
	if s.is_burning(): return "burn still on after 3.2 s"
	if s.burn_leech != 0.0 or s.burn_source != null: return "burn ended but leech %s / source %s stayed" % [s.burn_leech, s.burn_source]
	var c := StatusEffects.new()
	c.apply_burn(5.0, 0.5, src)
	c.clear()
	return "" if c.burn_leech == 0.0 and c.burn_source == null else "clear() left the burn's leech / source"

## Review I1: Wolf.tick_burn leeches each DoT's own part with its own leech, to its own source: the burn's leech
## never applies to trail damage (during or after the burn). Reading (plan Global Constraints: trail ticks are hits
## of their press and leech; Task 8: DoT ticks never crit): a trail leeches with its own press's leech fraction.
func test_wolf_leeches_each_dot_part_only():
	var w := _wolf()
	w.health.setup(100000)
	var burner := Sink.new()
	var trailer := Sink.new()
	w.apply_status("burn", 10.0, 0.5, burner)
	for i in int(round(1.0 / DT)):
		w.apply_trail(40.0, HOLD, trailer)         # no leech on this trail's press
		w.tick_burn(DT)
	var r := ""
	if not is_equal_approx(burner.got, 5.0): r = "burn leech healed %s, want 5 (10 × 0.5; not the trail's part)" % burner.got
	elif trailer.got != 0.0: r = "a trail without leech healed %s" % trailer.got
	if r == "":
		for i in int(round(2.5 / DT)):              # burn ends at 3 s; the trail goes on
			w.apply_trail(40.0, HOLD, trailer)
			w.tick_burn(DT)
		if not is_equal_approx(burner.got, 15.0): r = "after the burn ended its leech still healed (%s, want 15)" % burner.got
	if r == "":                                     # Task 4 review: past 4.0 s, a trail-only tick after the burn ended
		var hp0 := w.health.hp
		for i in int(round(1.0 / DT)):
			w.apply_trail(40.0, HOLD, trailer)
			w.tick_burn(DT)
		if w.health.hp >= hp0: r = "setup: no trail-only tick between 3.5 and 4.5 s"
		elif w.status.is_burning(): r = "setup: still burning at 4.5 s"
		elif not is_equal_approx(burner.got, 15.0): r = "a trail-only tick after the burn healed the burn's source (%s, want 15)" % burner.got
		elif trailer.got != 0.0: r = "a trail-only tick without leech healed %s" % trailer.got
	if r == "":
		var v := _wolf()
		v.health.setup(100000)
		var own := Sink.new()
		var def := float(v.stats().def)
		for i in int(round(1.0 / DT)):
			v.apply_trail(40.0, HOLD, own, null, 0.25)   # a trail whose press has a leech gem: its own fraction
			v.tick_burn(DT)
		var want := 40.0 * (1.0 - def / (def + 100.0)) * 0.25
		if not is_equal_approx(own.got, want): r = "trail with leech 0.25 healed %s, want %s" % [own.got, want]
		v.free()
	w.free()
	return r

## Task 4 review: a DoT part under one whole HP (the carry keeps it for a later tick) still leeches its share: over
## 2 s of a 0.55 / tick trail with leech 1.0 the source gets 2 × 0.55, not only the share of the tick that rounded up.
func test_wolf_leeches_fractional_dot_parts():
	var w := _wolf()
	w.health.setup(100000)
	var own := Sink.new()
	var def := float(w.stats().def)
	var raw := 0.55 / (1.0 - def / (def + 100.0))       # 0.55 per tick after DEF
	for i in int(round(2.0 / DT)):
		w.apply_trail(raw, HOLD, own, null, 1.0)
		w.tick_burn(DT)
	var r := "" if is_equal_approx(own.got, 1.1) else "2 ticks of 0.55 with leech 1.0 healed %s, want 1.1" % own.got
	w.free()
	return r

## The test dummy's tick_status leeches like Wolf.tick_burn (each DoT part with its own fraction, to its own source),
## so the Task 5 / 8 trail-leech tests can see it.
func test_dummy_tick_leeches_like_wolf():
	var d: Node2D = load("res://tests/dummy_enemy.gd").new()
	d.hp = 100000
	var burner := Sink.new()
	var trailer := Sink.new()
	d.apply_status("burn", 10.0, 0.5, burner)
	for i in int(round(1.0 / DT)):
		d.apply_trail(0.55, HOLD, trailer, null, 1.0)
		d.tick_status(DT)
	var r := ""
	if not is_equal_approx(burner.got, 5.0): r = "dummy burn leech %s, want 5" % burner.got
	elif not is_equal_approx(trailer.got, 0.55): r = "dummy trail leech %s, want 0.55 (a part under 1 HP included)" % trailer.got
	d.free()
	return r

## clear() (death, revive, kept room) ends every status including the freeze lock.
func test_clear_ends_everything():
	var s := StatusEffects.new()
	s.apply_freeze(1.0, 5.0)
	s.apply_mark(0.3, 4.0)
	s.apply_trail(5.0, 2.0, null)
	s.apply_zone(0.3, 0.2, 2.0)
	s.clear()
	if s.is_frozen() or s.is_marked() or s.taken_mult() != 1.0 or s.speed_mult() != 1.0: return "status left after clear"
	if s.tick(1.0) != 0: return "trail ticked after clear"
	return "" if s.apply_freeze(1.0, 5.0) else "freeze lock survived clear()"

# ---------- Wolf / Monster ----------

func test_freeze_cancels_windup_and_holds():
	var world: Node2D = await _world()
	var h := _hero(world, Vector2(400, 300))
	var p := _pack(world, "boar", Vector2(300, 300))
	await tree.physics_frame
	var m: Monster = p.wolves[0]
	m.global_position = Vector2(300, 300)
	m.receive_hit(1, 1.0, Vector2(200, 300))         # provoke the passive boar
	m.global_position = Vector2(300, 300)
	var r := ""
	if not await _frames(p, h, 120, func(): return m.state == "lunge_warn"): r = "boar never warned a lunge (state %s)" % m.state
	elif not m.telegraph_visible(): r = "no lunge warning shown"
	# Review M6: the frozen window must be longer than the boar's whole attack (warning + lunge), so "the hero takes
	# no damage" can fail: without the freeze hold the boar (lunge cooldown 0) re-warns at once and lands by ~1.1 s.
	var attack := m.n("lunge_warn") + m.n("lunge_time")
	var secs := attack + 0.5
	if r == "":
		var cd := m._lunge_cd
		if not m.apply_freeze(secs, 5.0): r = "freeze refused"
		elif m.telegraph_visible(): r = "lunge warning still shown while frozen"
		elif m.state in ["lunge_warn", "lunge", "bite", "ring_warn"]: r = "still in attack state %s" % m.state
		elif m._lunge_cd != cd: r = "freeze changed the lunge cooldown"
	if r == "":
		var at := m.global_position
		var hp := h.health.hp
		await _frames(p, h, int((attack + 0.3) / DT))   # longer than warning + lunge, still frozen
		if h.health.hp != hp: r = "the hero was hit by a frozen boar"
		elif not m.is_frozen(): r = "thawed before %.1f s" % secs
		elif m.global_position.distance_to(at) > 0.01: r = "frozen boar moved %s" % (m.global_position - at)
		elif m.velocity != Vector2.ZERO: r = "frozen velocity %s" % m.velocity
		elif m.body.is_playing(): r = "frozen body still animating"
		elif m.telegraph_visible(): r = "warning came back while frozen"
	if r == "":
		await _frames(p, h, int(0.25 / DT))
		var at := m.global_position
		await _frames(p, h, 6)                         # thawed: it acts again (moves or winds up a new attack)
		var moved := m.global_position.distance_to(at) >= 0.5
		if m.is_frozen(): r = "still frozen after %.1f s" % secs
		elif not (moved or m.state in ["lunge_warn", "lunge", "bite"]): r = "thawed boar does nothing (state %s, moved %s)" % [m.state, m.global_position - at]
	world.queue_free()
	return r

## Check ring and throw too (plan Task 4 step 3): a ring stomp's warning hides and never lands; a thrower throws
## nothing while frozen.
func test_freeze_cancels_ring_and_stops_throws():
	var world: Node2D = await _world()
	var h := _hero(world, Vector2(325, 300))
	var p := _pack(world, "kongkoi", Vector2(300, 300), 4)
	await tree.physics_frame
	var m: Monster = p.wolves[0]
	m.global_position = Vector2(300, 300)
	var r := ""
	if not await _frames(p, h, 180, func(): return m.state == "ring_warn"): r = "kongkoi never stomped"
	if r == "":
		var hp := h.health.hp
		m.apply_freeze(1.0, 5.0)
		if m.telegraph_visible(): r = "ring warning shown while frozen"
		await _frames(p, h, 57)
		if r == "" and h.health.hp != hp: r = "a frozen kongkoi's stomp landed"
	world.queue_free()
	if r != "": return r
	world = await _world()
	h = _hero(world, Vector2(410, 300))
	p = _pack(world, "macaque", Vector2(300, 300), 3)
	await tree.physics_frame
	var q: Monster = p.wolves[0]
	q.global_position = Vector2(300, 300)
	await _frames(p, h, 2)                             # it has seen the hero (and may have thrown already)
	q.apply_freeze(1.0, 5.0)
	q._throw_cd = 0.0
	for ch in world.find_children("*", "", true, false):
		if ch.get_script() == FRUIT: ch.queue_free()
	await _frames(p, h, 55)
	if _count(world, FRUIT) != 0: r = "a frozen macaque threw fruit"
	if r == "" and not await _frames(p, h, 120, func(): return _count(world, FRUIT) > 0): r = "the macaque never threw again after the thaw"
	world.queue_free()
	return r

## Owner 2026-11-08: bosses and elites freeze like any monster.
func test_elite_freezes_too():
	var world: Node2D = await _world()
	var p := _pack(world, "wolf", Vector2(300, 300), 3)
	await tree.physics_frame
	var w: Wolf = p.wolves[0]
	w.set_elite(true)
	var ok := w.apply_freeze(1.0, 5.0)
	var r := "" if ok and w.is_frozen() else "elite did not freeze"
	world.queue_free()
	return r

## Every .gd under res://scripts, recursively.
func _scripts(dir := "res://scripts") -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null: return out
	for f in d.get_files():
		if f.ends_with(".gd"): out.append(dir + "/" + f)
	for sub in d.get_directories(): out.append_array(_scripts(dir + "/" + sub))
	return out

## Monster scripts: everything under scripts/monsters (any depth), plus any script anywhere under res://scripts whose
## base-script chain (get_base_script, so `extends Boss` with Boss → Monster → Wolf by class_name is covered, Task 4
## review) reaches wolf.gd.
func _monster_scripts() -> Array:
	var out: Array = []
	for path in _scripts():
		if path.begins_with("res://scripts/monsters/") or _extends_wolf(path): out.append(path)
	return out

func _extends_wolf(path: String) -> bool:
	if not "extends" in FileAccess.get_file_as_string(path): return false
	var s = load(path)
	if not (s is Script): return false
	var b: Script = (s as Script).get_base_script()
	while b != null:
		if b.resource_path == "res://scripts/monsters/wolf.gd": return true
		b = b.get_base_script()
	return false

## Owner 2026-11-09 (Task 4 review M1): a frozen monster is not knocked back and does not slide ("ไม่กระเด็น
## ติดอยู่กับที่"). Control: the same hit knocks an unfrozen wolf back (so this check can fail).
func test_frozen_monster_is_not_knocked_back():
	var a := _wolf()
	var b := _wolf()
	a.health.setup(100000)
	b.health.setup(100000)
	b.apply_freeze(1.0, 5.0)
	var pa := a.position
	var pb := b.position
	a.receive_hit(5.0, 1.0, pa + Vector2(-40, 0))
	b.receive_hit(5.0, 1.0, pb + Vector2(-40, 0))
	var r := ""
	if a.position.distance_to(pa) < 1.0: r = "control: an unfrozen wolf was not knocked back (%s)" % (a.position - pa)
	elif b.position != pb: r = "a frozen wolf was knocked back by %s" % (b.position - pb)
	a.free()
	b.free()
	return r

## M1: in a crowd (monsters on one spot push apart, WolfPack._separate) a frozen monster is never the one pushed,
## also after a knockback hit; its unfrozen neighbours still move off it (control).
func test_frozen_monster_is_not_pushed_by_the_crowd():
	var world: Node2D = await _world()
	var h := _hero(world, Vector2(900, 900))
	var p := _pack(world, "wolf", Vector2(300, 300), 1, 3)
	await tree.physics_frame
	var r := "" if p.wolves.size() >= 3 else "pack has %d wolves" % p.wolves.size()
	if r == "":
		for w in p.wolves:
			w.global_position = Vector2(300, 300)
			w.health.setup(100000)
		var f: Wolf = p.wolves[0]
		var o: Wolf = p.wolves[1]
		f.apply_freeze(1.0, 5.0)
		f.receive_hit(5.0, 1.0, Vector2(260, 300))      # a hit with knockback, in the crowd
		for i in 30:
			await tree.physics_frame
			p._separate(DT)
		if f.global_position != Vector2(300, 300): r = "frozen wolf pushed to %s" % f.global_position
		elif o.global_position.distance_to(Vector2(300, 300)) < 1.0: r = "control: the crowd did not push the unfrozen wolf"
		if r == "":
			await _frames(p, h, 10)                    # a full step (step_all = wolves + _separate) too
			if f.global_position != Vector2(300, 300): r = "frozen wolf moved during step_all: %s" % f.global_position
	world.queue_free()
	return r

## Guard for the owner's boss rule: no monster script overrides the freeze or the frozen hold, or the push that the
## frozen hold blocks (so a boss added later freezes and stays put too). Review M2: scans scripts/monsters
## recursively and every script elsewhere that extends a monster.
func test_no_monster_opts_out_of_freeze():
	var found := 0
	for path in _monster_scripts():
		if path.get_file() in ["wolf.gd", "status_effects.gd"] and path.get_base_dir() == "res://scripts/monsters": continue
		found += 1
		var text := FileAccess.get_file_as_string(path)
		for f in ["func apply_freeze", "func is_frozen", "func _hold_frozen", "func _push", "func push(", "func tick_burn"]:
			if f in text: return "%s has its own %s (owner: bosses freeze and stay put like others)" % [path, f]
		# Task 4 review: Wolf.step holds a frozen monster; an override must go through it (monster.gd ticks its own
		# cooldowns, then super.step), never replace it.
		if _extends_wolf(path) and "func step(" in text and not "super.step(" in text: return "%s overrides step() without super.step(): a frozen monster would not hold" % path
	return "" if found >= 2 else "scan found only %d monster scripts (monster.gd, ...): the scan is broken" % found

## Review M2: every state a monster script enters, other than the resting / moving-away ones, is one of its
## _fight_states(), so apply_freeze cancels it (a future boss's slam warning hides on freeze too).
const NOT_FIGHT := ["idle", "dead", "return", "flee"]

func test_every_attack_state_is_a_fight_state():
	var assign := RegEx.create_from_string("\\bstate\\s*=\\s*\"(\\w+)\"")
	var checked := 0
	for path in _monster_scripts():
		var s: Script = load(path)
		var chain: Array = []
		var b: Script = s
		while b != null:
			chain.append(b.resource_path)
			b = b.get_base_script()
		if not "res://scripts/monsters/wolf.gd" in chain: continue
		var used := {}
		for p in chain:
			for m in assign.search_all(FileAccess.get_file_as_string(p)): used[m.get_string(1)] = true
		var inst = s.new()
		var fight: Array = inst._fight_states()
		inst.free()
		checked += 1
		for st in used:
			if not st in NOT_FIGHT and not st in fight: return "%s enters state \"%s\" that is not in _fight_states() %s: a freeze would not cancel it" % [path, st, fight]
	return "" if checked >= 2 else "only %d monster scripts checked" % checked

func test_dead_monster_ignores_freeze():
	var w := _wolf()
	w.health.take_hit(100000, false)
	var r := ""
	if w.is_alive(): r = "wolf did not die"
	elif w.apply_freeze(1.0, 5.0): r = "a dead wolf froze"
	elif w.is_frozen(): r = "dead wolf reports frozen"
	elif w.status_tint().a != 0.0: r = "dead wolf tinted"
	w.apply_mark(0.2, 4.0)
	w.apply_trail(10.0, 1.0, null)
	w.apply_zone(0.3, 0.1, 1.0)
	if r == "" and (w.is_marked() or w.status.trail_per_tick > 0.0 or w.status.taken_mult() != 1.0): r = "a dead wolf took a status"
	w.free()
	return r

func test_marked_wolf_takes_20pct_more():
	var a := _wolf()
	var b := _wolf()
	b.apply_mark(0.2, 4.0)
	Combat.rng.seed = 4242
	var plain := a.receive_hit(40.0, 1.0, Vector2(-50, 0), 0.0)
	Combat.rng.seed = 4242
	var marked := b.receive_hit(40.0, 1.0, Vector2(-50, 0), 0.0)
	a.free()
	b.free()
	return "" if absi(marked - int(round(plain * 1.2))) <= 1 else "marked hit %d vs plain %d (want ≈ ×1.2)" % [marked, plain]

## Owner 2026-11-10 (Task 7 review): frozen reads differently from slowed: a paler, whiter ice (FROZEN_TINT) over a burn
## and over the ice slow; slowed alone keeps the frost tint; back to frost when the freeze ends and the slow lasts.
func test_frozen_tint_is_paler_than_slowed():
	var w := _wolf()
	w.apply_status("burn", 1.0)
	w.apply_status("slow")
	w.apply_freeze(1.0, 5.0)
	var want := Color(Wolf.FROZEN_TINT, Wolf.FROZEN_AMOUNT)
	var r := "" if w.status_tint() == want else "frozen + slowed + burning tint %s, want frozen (paler ice)" % w.status_tint()
	if r == "" and not w.is_chilled(): r = "frozen wolf is not chilled"
	var fz := Color(Wolf.FROZEN_TINT)
	var fr := Color(Wolf.FROST_TINT)
	if r == "" and not (fz.s < fr.s and fz.v >= fr.v and fz.h > 0.5 and fz.h < 0.6): r = "frozen tint %s is not a paler ice than %s" % [Wolf.FROZEN_TINT.to_html(false), Wolf.FROST_TINT.to_html(false)]
	w.status.tick(1.01)
	if r == "" and w.status_tint() != Color(Wolf.FROST_TINT, Wolf.FROST_AMOUNT): r = "thawed but still slowed: tint %s, want frost" % w.status_tint()
	w.free()
	return r

## Owner 2026-11-10 (Task 7 review): a frozen monster wears an ice block (assets/fx/ice_block.png nine-patch, 0 gen) sized
## to its body: the kind's body box for its direction × size_scale, + inset + pad, enclosing the hurt point and the feet;
## shown on the step the freeze starts, gone on the step it ends (not a frame later), kept under the PerfSaver
## (gameplay information), none while only slowed, none after death. Every monster kind has a box for all 8 directions.
func test_frozen_wears_ice_block_sized_to_body():
	var r := ""
	var meta := Wolf._ice_meta()
	for k in ["wolf", "boar", "deer", "kongkoi", "macaque", "shroom", "viper"]:
		var per: Dictionary = meta.get("boxes", {}).get(k, {})
		if per.size() != 8: return "ice_block_boxes.json: %s has %d directions, want 8" % [k, per.size()]
	var w: Wolf = load("res://scenes/wolf.tscn").instantiate()
	tree.root.add_child(w)
	w.setup()
	w.apply_status("slow")
	w._update_status_fx()
	if w._ice_block != null: r = "a slowed-only wolf wears an ice block"
	PerfSaver.active = true
	w.apply_freeze(1.0, 5.0)
	var blk := w._ice_block
	if r == "" and (blk == null or not blk.visible or blk.texture == null or blk.texture.resource_path != "res://assets/fx/ice_block.png"): r = "no ice block on the step of the freeze (saver on)"
	if r == "":
		var rect := Rect2(blk.position, blk.size)
		var want := w.ice_block_rect()
		var box: Array = meta.boxes.wolf[String(w.body.animation).split("_", true, 1)[1]]
		var body := Rect2(Vector2(box[0], box[1]) * Wolf.size_scale(), Vector2(box[2], box[3]) * Wolf.size_scale())
		if rect != want: r = "ice block rect %s, want %s" % [rect, want]
		elif not rect.encloses(body): r = "ice block %s does not enclose the body box %s" % [rect, body]
		elif rect.size.x > body.size.x + 14 or rect.size.y > body.size.y + 14: r = "ice block %s far bigger than the body %s" % [rect, body]
		elif not rect.has_point(Wolf.HURT_POINT * Wolf.size_scale()) or not rect.has_point(Vector2(0, -1)): r = "ice block misses the hurt point / feet"
		elif blk.patch_margin_left != int(meta.nine) or blk.texture_filter != CanvasItem.TEXTURE_FILTER_NEAREST: r = "ice block nine-patch %d / filter %d" % [blk.patch_margin_left, blk.texture_filter]
	w.status.tick(0.99)
	w._update_status_fx()
	if r == "" and w._ice_block != blk: r = "ice block gone or swapped before the freeze ended (saver on)"
	w.status.tick(0.02)
	w._update_status_fx()
	if r == "" and (w._ice_block != null or not blk.is_queued_for_deletion() or blk.visible): r = "ice block left on the step the freeze ended"
	PerfSaver.active = false
	w.status.freeze_lock = 0.0
	w.apply_freeze(1.0, 5.0)
	var blk2 := w._ice_block
	w.health.take_hit(999999, false)
	if r == "" and (w._ice_block != null or blk2 == null or not blk2.is_queued_for_deletion()): r = "ice block left on a dead monster"
	w.queue_free()
	await tree.process_frame
	return r

## The frost overlay shows while frozen (not only while slowed); the PerfSaver sheds the overlay, the tint stays.
func test_frozen_shows_frost_overlay_and_saver_sheds_it():
	var w: Wolf = load("res://scenes/wolf.tscn").instantiate()
	tree.root.add_child(w)
	w.setup()
	w.apply_freeze(1.0, 5.0)
	w._update_status_fx()
	var r := ""
	if w._frost_fx == null or w._frost_fx.animation != "status_frost": r = "no frost overlay while frozen"
	PerfSaver.active = true
	w._update_status_fx()
	if r == "" and w._frost_fx != null: r = "frost overlay kept under the saver"
	if r == "" and w.status_tint().a <= 0.0: r = "no tint under the saver"
	PerfSaver.active = false
	w.status.tick(1.01)
	w._update_status_fx()
	if r == "" and (w._frost_fx != null or w.status_tint().a != 0.0): r = "frost left after the thaw"
	w.queue_free()
	await tree.process_frame
	return r

## Wolf.apply_trail takes the raw per-tick damage and applies the monster's own DEF (as a hit would, no roll).
func test_wolf_trail_applies_def():
	var w := _wolf()
	var def := float(w.stats().def)
	w.apply_trail(10.0, 0.25, null)
	var want := 10.0 * (1.0 - def / (def + 100.0))
	var r := "" if is_equal_approx(w.status.trail_per_tick, want) else "trail per tick %s, want %s (DEF %s)" % [w.status.trail_per_tick, want, def]
	w.free()
	return r

## Task 5 review M2: Wolf.apply_trail runs every frame for every monster in a fire line, so its DEF factor is cached
## (stats() builds Balance dictionaries): one build however many frames, rebuilt only when the level, the elite flag
## or (Monster) the kind changes, always equal to 1 − def / (def + 100) of the current stats().
func test_wolf_trail_def_factor_cached():
	var w := _wolf()
	var r := ""
	var f := func() -> float:
		var d := float(w.stats().def)
		return 1.0 - d / (d + 100.0)
	for i in 120: w.apply_trail(10.0, HOLD, null)
	if w.def_builds != 1: r = "120 trail frames built the DEF factor %d times, want 1" % w.def_builds
	elif not is_equal_approx(w.def_factor(), f.call()): r = "factor %s, want %s" % [w.def_factor(), f.call()]
	if r == "":
		w.level = 30
		w.apply_trail(10.0, HOLD, null)
		if w.def_builds != 2 or not is_equal_approx(w.def_factor(), f.call()): r = "level change: builds %d, factor %s want %s" % [w.def_builds, w.def_factor(), f.call()]
	if r == "":
		w.set_elite(true)
		w.def_factor()
		if w.def_builds != 3: r = "elite change did not rebuild (%d)" % w.def_builds
	w.free()
	if r != "": return r
	var m: Monster = load("res://scenes/monster.tscn").instantiate()
	m.kind = "deer"
	m.setup()
	var a := m.def_factor()
	m.kind = "boar"
	var dd := float(m.stats().def)
	if not is_equal_approx(m.def_factor(), 1.0 - dd / (dd + 100.0)): r = "kind change: factor %s (deer %s), want boar's %s" % [m.def_factor(), a, 1.0 - dd / (dd + 100.0)]
	m.free()
	return r

## A trail tick goes through health like a burn tick (dot_tick, no knockback) and the wolf's cast stays readable.
## Review I2: the first tick lands after a full second in the fire (was: on contact).
func test_wolf_trail_tick_damages():
	var w := _wolf()
	w.health.setup(1000)
	var hp := w.health.hp
	var c := ComboCast.new("fire_fan")
	var r := ""
	var at := w.position
	for i in int(round(1.0 / DT)):
		if r == "" and w.health.hp != hp: r = "trail ticked before a full second (frame %d)" % i
		w.apply_trail(40.0, HOLD, null, c)
		w.tick_burn(DT)
	if r != "": pass
	elif w.health.hp >= hp: r = "trail did not damage the wolf after 1 s"
	elif not is_same(w.status.tick_cast, c): r = "tick_cast is not the trail's press"
	elif w.position != at: r = "a trail tick knocked the wolf back"
	w.free()
	return r

## The test dummy has the same status API as Wolf (later combo tests use it).
func test_dummy_has_status_api():
	var d: Node2D = load("res://tests/dummy_enemy.gd").new()
	for m in ["apply_status", "apply_freeze", "apply_mark", "apply_trail", "apply_zone", "is_frozen", "is_chilled", "is_marked"]:
		if not d.has_method(m): return "dummy has no %s" % m
	var r := ""
	if not d.apply_freeze(1.0, 5.0) or d.apply_freeze(1.0, 5.0) or d.freezes != 1: r = "dummy freeze lock"
	d.apply_trail(10.0, 0.25, null)
	if r == "" and not is_equal_approx(d.status.trail_per_tick, 10.0): r = "dummy (DEF 0) trail %s" % d.status.trail_per_tick
	if r == "" and not d.is_chilled(): r = "frozen dummy not chilled"
	d.free()
	return r
