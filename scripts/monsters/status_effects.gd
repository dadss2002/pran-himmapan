class_name StatusEffects
extends RefCounted
## Burn and slow on a monster (M3a design §5.3, balance.json "elements").
## Burn: every elements.fire.tick s for elements.fire.duration s; a re-hit restarts the duration and
## keeps the higher per-tick value (no stacking). Slow: speed × (1 − elements.ice.slow) for its duration.

var burn_per_tick := 0.0
var burn_left := 0.0
var burn_leech := 0.0
var burn_source: Object = null
var slow_left := 0.0
var _burn_t := 0.0
var _carry := 0.0

func apply_burn(per_tick: float, leech := 0.0, source: Object = null) -> void:
	burn_per_tick = maxf(burn_per_tick if burn_left > 0.0 else 0.0, per_tick)
	burn_left = Balance.num("elements.fire.duration")
	burn_leech = leech
	burn_source = source

func apply_slow() -> void:
	slow_left = Balance.num("elements.ice.duration")

func speed_mult() -> float:
	return 1.0 - Balance.num("elements.ice.slow") if slow_left > 0.0 else 1.0

func is_burning() -> bool:
	return burn_left > 0.0

func is_slowed() -> bool:
	return slow_left > 0.0

## Advances timers; returns whole burn damage dealt this step (fractions carry over).
func tick(delta: float) -> int:
	slow_left = maxf(0.0, slow_left - delta)
	if burn_left <= 0.0: return 0
	_burn_t += delta
	burn_left -= delta
	var dmg := 0.0
	var step := Balance.num("elements.fire.tick")
	if _burn_t >= step - 1e-6:
		_burn_t -= step
		dmg += burn_per_tick
	if burn_left <= 1e-6:
		burn_left = 0.0
		burn_per_tick = 0.0
		_burn_t = 0.0
	_carry += dmg
	var whole := int(floor(_carry + 1e-6))
	_carry -= whole
	return whole

func clear() -> void:
	burn_left = 0.0
	burn_per_tick = 0.0
	slow_left = 0.0
	_burn_t = 0.0
	_carry = 0.0
