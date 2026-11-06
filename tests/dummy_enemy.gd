extends Node2D
## Minimal enemy for hero/arrow tests: same interface as Wolf (is_alive, hurt_point, receive_hit).

var alive := true
var hp := 40
var hits: Array = []   # [atk, mult, from]

func is_alive() -> bool:
	return alive

func hurt_point() -> Vector2:
	return position + Vector2(0, -14)

func receive_hit(atk: float, mult: float, from: Vector2) -> int:
	hits.append([atk, mult, from])
	return 1
