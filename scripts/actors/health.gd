class_name Health
extends Node
## Hit points + invulnerability timer, shared by the hero and monsters.

signal damaged(amount: int, crit: bool)
signal died()

var max_hp := 1
var hp := 1
var _invuln := 0.0

func setup(max_value: int) -> void:
	max_hp = max_value
	hp = max_value
	_invuln = 0.0

## Applies a hit; false when invulnerable or already dead.
func take_hit(amount: int, crit: bool) -> bool:
	if is_dead() or is_invulnerable():
		return false
	hp = maxi(0, hp - amount)
	damaged.emit(amount, crit)
	if hp == 0:
		died.emit()
	return true

func set_invulnerable(seconds: float) -> void:
	_invuln = maxf(_invuln, seconds)

func is_invulnerable() -> bool:
	return _invuln > 0.0

func is_dead() -> bool:
	return hp <= 0

func tick(delta: float) -> void:
	_invuln = maxf(0.0, _invuln - delta)

func reset_full() -> void:
	hp = max_hp
