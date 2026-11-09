extends RefCounted
## M5b Task 4: monster statuses for gem combos (docs/superpowers/specs/2026-11-08-gem-combos.md, plan Task 4):
## freeze with a per-target lock, mark, a non-stacking trail burn, zone; each status keeps the ComboCast (per-press
## ledger) of the press that applied it (Review Focus 6, risks.md B25). Owner 2026-11-08: bosses and elites freeze
## like any monster ("บอสแข็งได้เหมือนมอนอื่น").

var tree: SceneTree
const DT := 1.0 / 60.0
const FRUIT := preload("res://scripts/monsters/fruit.gd")

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

func _pack(world: Node2D, kind: String, home: Vector2, lv := 1) -> WolfPack:
	var p := WolfPack.new()
	p.kind = kind
	p.level = lv
	p.count = 1
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

## A monster in the fire ticks at most once a second, even stepping out and back in (no re-entry tick), and the
## first tick lands on contact (a monster crossing a line quickly still burns once).
func test_trail_ticks_once_a_second_on_reentry():
	var s := StatusEffects.new()
	var total := 0
	for i in 120:                                  # 2 s: in the fire on even frames only (edge of the line)
		if i % 2 == 0: s.apply_trail(10.0, DT * 0.5, null)
		total += s.tick(DT)
	if total != 20: return "2 s flickering in and out dealt %d, want 20 (one tick a second)" % total
	for i in 120: total += s.tick(DT)               # left the fire: nothing more
	return "" if total == 20 else "trail kept burning after the hold ended (%d)" % total

func test_zone_slow_and_taken_keep_highest():
	var s := StatusEffects.new()
	s.apply_zone(0.3, 0.1, 0.25)
	s.apply_zone(0.2, 0.2, 0.25)                 # hellfield over hunter_zone: the highest of each
	if not is_equal_approx(s.speed_mult(), 0.7): return "zone speed ×%s, want 0.7" % s.speed_mult()
	if not is_equal_approx(s.taken_mult(), 1.2): return "zone taken ×%s, want 1.2" % s.taken_mult()
	s.apply_mark(0.3, 4.0)
	if not is_equal_approx(s.taken_mult(), 1.3 * 1.2): return "mark + zone ×%s, want 1.56" % s.taken_mult()
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
## kill is credited to exactly one press (Task 8 hook). Both ticking at once: the larger tick's ledger, ties = burn.
func test_tick_cast_names_one_ledger():
	var a := ComboCast.new("bloodthirst")
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
	if r == "":
		var cd := m._lunge_cd
		if not m.apply_freeze(1.0, 5.0): r = "freeze refused"
		elif m.telegraph_visible(): r = "lunge warning still shown while frozen"
		elif m.state in ["lunge_warn", "lunge", "bite", "ring_warn"]: r = "still in attack state %s" % m.state
		elif m._lunge_cd != cd: r = "freeze changed the lunge cooldown"
	if r == "":
		var at := m.global_position
		var hp := h.health.hp
		await _frames(p, h, 30)                        # 0.5 s frozen
		if not m.is_frozen(): r = "thawed before 1 s"
		elif m.global_position.distance_to(at) > 0.01: r = "frozen boar moved %s" % (m.global_position - at)
		elif h.health.hp != hp: r = "the hero was hit by a frozen boar"
		elif m.velocity != Vector2.ZERO: r = "frozen velocity %s" % m.velocity
		elif m.body.is_playing(): r = "frozen body still animating"
		elif m.telegraph_visible(): r = "warning came back while frozen"
	if r == "":
		var at := m.global_position
		await _frames(p, h, 36)                        # thawed: it acts again (moves or winds up a new attack)
		if m.is_frozen(): r = "still frozen after 1.1 s"
		elif m.global_position.distance_to(at) < 0.5 and m.state == "chase": r = "thawed boar does nothing (state %s)" % m.state
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

## Guard for the owner's boss rule: no monster script overrides the freeze (so a boss added later freezes too).
func test_no_monster_opts_out_of_freeze():
	var d := DirAccess.open("res://scripts/monsters")
	for f in d.get_files():
		if not f.ends_with(".gd") or f in ["wolf.gd", "status_effects.gd"]: continue
		var text := FileAccess.get_file_as_string("res://scripts/monsters/" + f)
		if "func apply_freeze" in text or "func is_frozen" in text: return "%s overrides the freeze (owner: bosses freeze like others)" % f
	return ""

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

func test_frozen_tint_is_frost():
	var w := _wolf()
	w.apply_status("burn", 1.0)
	w.apply_freeze(1.0, 5.0)
	var want := Color(Wolf.FROST_TINT, Wolf.FROST_AMOUNT)
	var r := "" if w.status_tint() == want else "frozen + burning tint %s, want frost (frost wins)" % w.status_tint()
	if r == "" and not w.is_chilled(): r = "frozen wolf is not chilled"
	w.free()
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

## A trail tick goes through health like a burn tick (dot_tick, no knockback) and the wolf's cast stays readable.
func test_wolf_trail_tick_damages():
	var w := _wolf()
	w.health.setup(1000)
	var hp := w.health.hp
	var c := ComboCast.new("fire_fan")
	w.apply_trail(40.0, 0.25, null, c)
	w.tick_burn(DT)
	var r := ""
	if w.health.hp >= hp: r = "trail did not damage the wolf"
	elif not is_same(w.status.tick_cast, c): r = "tick_cast is not the trail's press"
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
