class_name Arrow
extends Node2D
## A basic shot: flies straight along its direction, gone after Balance.num("shot.range") px.


var dir := Vector2.RIGHT
var travelled := 0.0
var spent := false

func launch(direction: Vector2) -> void:
	dir = direction.normalized()
	rotation = dir.angle()  # art points east

func advance(delta: float) -> void:
	if spent: return
	var stepd := minf(Balance.num("shot.arrow_speed") * delta, Balance.num("shot.range") - travelled)
	position += dir * stepd
	travelled += stepd
	if travelled >= Balance.num("shot.range") - 0.0001:
		spent = true
		if is_inside_tree():
			queue_free()

func _physics_process(delta: float) -> void:
	advance(delta)
