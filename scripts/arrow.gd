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

func launch(direction: Vector2, attack: float, enemies: Array = [], multiplier := 1.0, pierce_all := false, range_px := -1.0) -> void:
	max_range = range_px if range_px > 0.0 else Balance.num("shot.range")
	dir = direction.normalized()
	atk = attack
	targets = enemies
	mult = multiplier
	pierce = pierce_all
	rotation = dir.angle()  # art points east

## Gem behaviour from SkillBuild (pierce_extra, bounces, homing, leech, element); see Task 5.
var build := {}
var shooter: Node = null
func configure(b: Dictionary, from: Node = null) -> void:
	build = b
	shooter = from

func advance(delta: float) -> void:
	if spent: return
	var range_px := max_range if max_range > 0.0 else Balance.num("shot.range")
	var radius := Balance.num("shot.arrow_hit_radius")
	var stepd := minf(Balance.num("shot.arrow_speed") * delta, range_px - travelled)
	position += dir * stepd
	travelled += stepd
	for t in targets:
		if is_instance_valid(t) and t.is_alive() and not _hit.has(t) and _pos().distance_to(t.hurt_point()) <= radius:
			t.receive_hit(atk, mult, _pos(), crit_chance, crit_mult)
			if not pierce:
				_finish()
				return
			_hit[t] = true
	if travelled >= range_px - 0.0001:
		_finish()

## Global position in the scene, plain position when not in a tree (tests).
func _pos() -> Vector2:
	return global_position if is_inside_tree() else position

func _finish() -> void:
	spent = true
	if is_inside_tree():
		queue_free()

func _physics_process(delta: float) -> void:
	advance(delta)
