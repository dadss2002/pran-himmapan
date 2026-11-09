class_name Arrow
extends Node2D
## Basic shot: flies straight, hits the first live enemy within shot.arrow_hit_radius of its
## path (at the enemy's hurt_point), or is spent after shot.range px.

var dir := Vector2.RIGHT
var atk := 0.0
var travelled := 0.0
var spent := false
var targets: Array = []
var mult := 1.0
var pierce := false     # ศรทะลวง: hits every enemy in its line once and keeps flying
var crit_chance := -1.0  # set by the hero from gear; < 0 = base crit numbers
var crit_mult := -1.0
var max_range := 0.0    # px; shot.range unless the skill sets its own
var _hit := {}

signal spawned(arrow: Arrow)   # a ricochet arrow this one created

func launch(direction: Vector2, attack: float, enemies: Array = [], multiplier := 1.0, pierce_all := false, range_px := -1.0) -> void:
	max_range = range_px if range_px > 0.0 else Balance.num("shot.range")
	dir = direction.normalized()
	atk = attack
	targets = enemies
	mult = multiplier
	pierce = pierce_all
	rotation = dir.angle()  # art points east

## M5b combos (plan Task 5): a primary arrow is one the hero's skill press fired (Hero._fire with a build); bounce
## arrows and basic shots are not. Per-line combo effects belong to primary arrows only: the fire trail (FireTrail,
## ศรพัดเพลิง / พรหมาสตร์) and the line-end blast (พรหมาสตร์). Secondary hits (blast) never trigger combo or gem
## on-hit effects: no trail, bounce, element status, bolt, mark or freeze count (Global Constraints).
var primary := false
var trail: FireTrail = null
var _trail_checked := false
var _line_ended := false

## Gem behaviour from SkillBuild: pierce_extra, bounces/bounce_mult, homing, leech, element; combo / combo_p / cast
## (the press's ComboCast, Hero._release).
var build := {}
var shooter: Node = null
var _pierce_left := 0
var _bounces_left := 0
var _bounced := false
var _home: Node2D = null
func configure(b: Dictionary, from: Node = null) -> void:
	build = b
	shooter = from
	_pierce_left = int(b.get("pierce_extra", 0))
	_bounces_left = int(b.get("bounces", 0))

func advance(delta: float) -> void:
	if spent: return
	if primary and not _trail_checked: _lay_trail()
	var range_px := max_range if max_range > 0.0 else Balance.num("shot.range")
	var radius := Balance.num("shot.arrow_hit_radius")
	if build.get("homing", false): _steer(delta)
	var stepd := minf(Balance.num("shot.arrow_speed") * delta, range_px - travelled)
	position += dir * stepd
	travelled += stepd
	if trail != null: trail.extend_to(_pos())
	for t in targets:
		if is_instance_valid(t) and t.is_alive() and not _hit.has(t) and _pos().distance_to(t.hurt_point()) <= (t.hurt_radius() if t.has_method("hurt_radius") else radius):
			_hit[t] = true
			var amount: int = t.receive_hit(atk, mult, _pos(), crit_chance, crit_mult)
			_after_hit(t, amount)
			if pierce: continue
			if _pierce_left > 0:
				_pierce_left -= 1
				continue
			_finish()
			return
	if travelled >= range_px - 0.0001:
		_finish()

func _after_hit(t: Node2D, amount: int) -> void:
	_leech(amount)
	match String(build.get("element", "")):
		"fire":
			if t.has_method("apply_status"):
				t.apply_status("burn", amount * Balance.num("elements.fire.burn_frac"), float(build.get("leech", 0.0)), shooter)
		"ice":
			if t.has_method("apply_status"): t.apply_status("slow")
		"lightning":
			var other := _nearest(t.hurt_point(), Balance.num("elements.lightning.range"), [t])
			if other:
				_leech(other.receive_hit(atk, mult * Balance.num("elements.lightning.mult"), t.hurt_point(), crit_chance, crit_mult))
				if is_inside_tree():
					var z := FxSprite.make("chain_zap")
					z.position = other.hurt_point()
					get_parent().add_child(z)
					z.play("chain_zap")
	if _bounces_left > 0 and not _bounced:
		var next := _nearest(t.hurt_point(), Balance.num("ricochet.range"), _hit.keys())
		_bounced = pierce              # a piercing arrow tries once, from its first target only
		if next: _spawn_bounce(t.hurt_point(), next)

## The press's combo id ("" for none).
func combo_id() -> String:
	var c = build.get("combo", {})
	return String(c.get("id", "")) if typeof(c) == TYPE_DICTIONARY else ""

## The press's combo number `key` (build.combo_p, copied once per press); 0 when absent.
func _cp(key: String) -> float:
	var cp = build.get("combo_p", {})
	return float(cp.get(key, 0.0)) if typeof(cp) == TYPE_DICTIONARY else 0.0

## A primary arrow of a trail recipe lays one FireTrail from where it starts (once, on its first step).
func _lay_trail() -> void:
	_trail_checked = true
	var secs := _cp("trail_secs")
	if secs <= 0.0: return
	trail = FireTrail.new()
	trail.setup(_pos(), atk, mult, _cp("trail_frac"), secs, targets, shooter, build.get("cast"), float(build.get("leech", 0.0)), combo_id())
	if is_inside_tree(): get_parent().add_child(trail)

## The line ends (spent by range or by its last hit): the trail burns on for its time, พรหมาสตร์ blasts once at the
## end. Primary arrows only; once per arrow.
func _end_line() -> void:
	if _line_ended or not primary: return
	_line_ended = true
	if trail != null: trail.finish()
	if _cp("blast_on_line_end") > 0.0:
		var r := _cp("blast_radius")
		blast(_pos(), r, _cp("blast_frac"), false)
		if is_inside_tree():
			for s in ComboFx.play(get_parent(), combo_id(), "line_end", position):
				s.scale = Vector2.ONE * (2.0 * r / maxf(1.0, s._cell.x))   # the burst as wide as the blast (r32 → 64 px)

## Secondary hits of this press at `at`: every live target whose hurt point is within `radius`, plus `include` (hit
## even outside the radius: meteor_rain's own target), minus `skip`; each takes frac of this arrow's hit
## (_secondary_hit), and with `burn` the fire burn (elements.fire.burn_frac of that hit, the press's leech / ledger).
## Returns how many were hit. Never spawns arrows, trails or further blasts, never applies the arrow's element.
func blast(at: Vector2, radius: float, frac: float, burn: bool, include: Node2D = null, skip: Array = []) -> int:
	var n := 0
	var r2 := radius * radius
	for t in targets:
		if not is_instance_valid(t) or not t.is_alive() or t in skip: continue
		if t != include and at.distance_squared_to(t.hurt_point()) > r2: continue
		var amount := _secondary_hit(t, frac)
		n += 1
		if burn and t.has_method("apply_status"):
			t.apply_status("burn", amount * Balance.num("elements.fire.burn_frac"), float(build.get("leech", 0.0)), shooter, build.get("cast"))
	return n

## One secondary hit: frac of this arrow's hit, with its crit chance; leeches. Never _after_hit (no element, no bounce,
## no combo on-hit). Task 8: the kill hook (MP / heal on kill through build.cast) goes here too.
func _secondary_hit(t: Node2D, frac: float) -> int:
	var amount: int = t.receive_hit(atk, mult * frac, _pos(), crit_chance, crit_mult)
	_leech(amount)
	return amount

func _leech(amount: int) -> void:
	var frac := float(build.get("leech", 0.0))
	if frac > 0.0 and amount > 0 and is_instance_valid(shooter) and shooter.has_method("leech_heal"):
		shooter.leech_heal(amount * frac)

## Nearest live target within max_dist of `from`, skipping `skip`.
func _nearest(from: Vector2, max_dist: float, skip: Array) -> Node2D:
	var best: Node2D = null
	var best_d := max_dist
	for t in targets:
		if not is_instance_valid(t) or not t.is_alive() or t in skip: continue
		var d: float = from.distance_to(t.hurt_point())
		if d <= best_d:
			best_d = d
			best = t
	return best

func _spawn_bounce(from: Vector2, to: Node2D) -> void:
	var a: Arrow = load("res://scenes/arrow.tscn").instantiate()
	a.position = from
	var d: float = from.distance_to(to.hurt_point())
	a.launch((to.hurt_point() - from).normalized(), atk, targets, mult * float(build.get("bounce_mult", 1.0)), false, d + Balance.num("shot.arrow_hit_radius"))
	a.crit_chance = crit_chance
	a.crit_mult = crit_mult
	var b := build.duplicate()
	b["bounces"] = 0 if pierce else _bounces_left - 1
	b["pierce_extra"] = 0
	b["homing"] = false
	a.configure(b, shooter)
	for k in _hit: a._hit[k] = true
	if is_inside_tree(): get_parent().add_child(a)
	_bounces_left = 0 if pierce else _bounces_left
	spawned.emit(a)

## Ricochet arrows inherit the parent's spawned listeners through the hero (Hero._fire).

## Turns toward the nearest live target not yet hit (homing.turn_deg per second).
func _steer(delta: float) -> void:
	if not (is_instance_valid(_home) and _home.is_alive() and not _hit.has(_home)):
		_home = _nearest(_pos(), Balance.num("homing.search"), _hit.keys())
	if _home == null: return
	var want: Vector2 = (_home.hurt_point() - _pos()).normalized()
	var turn := deg_to_rad(Balance.num("homing.turn_deg")) * delta
	var ang := clampf(dir.angle_to(want), -turn, turn)
	dir = dir.rotated(ang).normalized()
	rotation = dir.angle()

## Global position in the scene, plain position when not in a tree (tests).
func _pos() -> Vector2:
	return global_position if is_inside_tree() else position

## Stops the arrow where it is for good: it moves and hits nothing more (the warp fade, review Important #1; the
## room change then frees it).
func halt() -> void:
	spent = true
	targets = []
	_line_ended = true                  # no line-end blast after the warp
	if trail != null and is_instance_valid(trail): trail.halt()   # its fire stops at once (B20)

func _finish() -> void:
	spent = true
	_end_line()
	if is_inside_tree():
		queue_free()

func _physics_process(delta: float) -> void:
	advance(delta)
