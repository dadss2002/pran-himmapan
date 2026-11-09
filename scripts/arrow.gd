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

## Gem behaviour from SkillBuild: pierce_extra, bounces/bounce_mult, homing, leech, element.
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
	var range_px := max_range if max_range > 0.0 else Balance.num("shot.range")
	var radius := Balance.num("shot.arrow_hit_radius")
	if build.get("homing", false): _steer(delta)
	var stepd := minf(Balance.num("shot.arrow_speed") * delta, range_px - travelled)
	position += dir * stepd
	travelled += stepd
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

func _finish() -> void:
	spent = true
	if is_inside_tree():
		queue_free()

func _physics_process(delta: float) -> void:
	advance(delta)
