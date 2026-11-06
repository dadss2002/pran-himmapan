extends Node2D
## A fruit thrown by a macaque: flies straight at fruit_speed toward where the hero stood, hits the
## hero within HIT px, stops at trees/water (blocked) or after its range.

const HIT := 12.0

var vel := Vector2.ZERO
var left := 0.0
var atk := 0.0
var mult := 1.0
var hero: Hero
var blocked := Callable()
var done := false

func setup(from: Vector2, at: Vector2, speed: float, range_px: float, atk_: float, mult_: float, hero_: Hero, blocked_: Callable) -> void:
	position = from
	vel = (at - from).normalized() * speed
	left = range_px
	atk = atk_
	mult = mult_
	hero = hero_
	blocked = blocked_
	z_index = 5
	var dot := Polygon2D.new()            # a small red fruit (no art needed at 4 px)
	dot.color = Color("#d8463a")
	dot.polygon = PackedVector2Array([Vector2(-3, 0), Vector2(0, -3), Vector2(3, 0), Vector2(0, 3)])
	add_child(dot)

func _physics_process(delta: float) -> void:
	step(delta)

func step(delta: float) -> void:
	if done: return
	var move := vel * delta
	position += move
	left -= move.length()
	var feet := position + Vector2(0, 14)          # thrown at chest height; its shadow line is the feet
	if hero and is_instance_valid(hero) and hero.global_position.distance_to(feet) <= HIT:
		hero.receive_hit(atk, mult, position)
		_finish()
	elif left <= 0.0 or (blocked.is_valid() and blocked.call(feet)):
		_finish()

func _finish() -> void:
	done = true
	queue_free()
