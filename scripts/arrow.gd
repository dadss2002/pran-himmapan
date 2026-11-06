class_name Arrow
extends Node2D
## Basic shot: flies straight, hits the first live enemy within shot.arrow_hit_radius of its
## path (at the enemy's hurt_point), or is spent after shot.range px.

var dir := Vector2.RIGHT
var atk := 0.0
var travelled := 0.0
var spent := false
var targets: Array = []

func launch(direction: Vector2, attack: float, enemies: Array = []) -> void:
	dir = direction.normalized()
	atk = attack
	targets = enemies
	rotation = dir.angle()  # art points east

func advance(delta: float) -> void:
	if spent: return
	var range_px := Balance.num("shot.range")
	var radius := Balance.num("shot.arrow_hit_radius")
	var stepd := minf(Balance.num("shot.arrow_speed") * delta, range_px - travelled)
	position += dir * stepd
	travelled += stepd
	for t in targets:
		if is_instance_valid(t) and t.is_alive() and _pos().distance_to(t.hurt_point()) <= radius:
			t.receive_hit(atk, 1.0, _pos())
			_finish()
			return
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
