extends Node2D
## M3h: the elite marker over a monster's head - a gold ★ and a short HP bar (owner's choice).
## Drawn above the sprites and the tree tops; hidden while the monster is dead.

var monster: Node2D
const W := 26.0
const H := 4.0
const GOLD := Color("#ffc83d")
var _shown := -1.0

func _ready() -> void:
	z_as_relative = false
	z_index = 44
	position = Vector2(0, -52)

func _process(_delta: float) -> void:
	if monster == null or not is_instance_valid(monster): return
	var alive: bool = monster.is_alive()
	if visible != (alive and monster.elite): visible = alive and monster.elite
	var f: float = float(monster.health.hp) / maxf(1.0, float(monster.health.max_hp))
	if f != _shown:
		_shown = f
		queue_redraw()

func _draw() -> void:
	var f := clampf(_shown, 0.0, 1.0)
	var x0 := -W / 2.0 + 6.0
	# ★ in front of the bar
	var star := PackedVector2Array()
	for i in 10:
		var r := 5.0 if i % 2 == 0 else 2.2
		star.append(Vector2(x0 - 8.0, 2.0) + Vector2(0, -r).rotated(TAU * i / 10.0))
	draw_colored_polygon(star, GOLD)
	draw_polyline(star + PackedVector2Array([star[0]]), Color(0, 0, 0, 0.8), 1.0)
	draw_rect(Rect2(x0 - 1, 0, W + 2, H + 2), Color(0, 0, 0, 0.85))
	draw_rect(Rect2(x0, 1, W, H), Color("#3a1414"))
	draw_rect(Rect2(x0, 1, W * f, H), Color("#e8453c"))
	draw_rect(Rect2(x0, 1, W * f, 1), Color(1, 1, 1, 0.35))
