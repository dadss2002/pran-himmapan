class_name Combat
## Pure game-rule functions (docs/spec-numbers.md §2). No scene access, so they are unit-testable.

## Facings, in the order used everywhere (manifest, animation names).
const DIRS := ["south", "south-east", "east", "north-east", "north", "north-west", "west", "south-west"]

## Shared RNG for damage rolls; tests set its seed.
static var rng := RandomNumberGenerator.new()

## Damage = ATK × mult × (1 − DEF/(DEF+100)) × roll, ×1.5 on crit, at least 1.
## `roll` is the 0.9–1.1 random factor, passed in so tests are deterministic.
static func damage(atk: float, mult: float, def: float, crit: bool, roll: float) -> int:
	var d := atk * mult * (1.0 - def / (def + 100.0)) * roll
	if crit:
		d *= Balance.num("crit.mult")
	return max(1, int(round(d)))

## Map a movement vector (screen space, +y is down) to a facing index 0..7.
## A zero vector keeps `last` so the hero does not snap to south when input stops.
static func facing_from_vector(v: Vector2, last: int) -> int:
	if v.length() < 0.01:
		return last
	# angle 0 = south (down), increasing counter-clockwise on screen: south, SE, E, NE, N, ...
	var a := atan2(v.x, v.y)  # south=0, east=+PI/2, north=±PI, west=-PI/2
	var idx := int(round(a / (PI / 4.0)))
	return (idx + 8) % 8

## Roll the 0.9–1.1 factor and crit (5%), then apply `damage`. Monsters pass can_crit = false.
static func roll_damage(atk: float, mult: float, def: float, can_crit: bool = true) -> Dictionary:
	var crit := can_crit and rng.randf() < Balance.num("crit.chance")
	var roll := rng.randf_range(0.9, 1.1)
	return {"amount": damage(atk, mult, def, crit, roll), "crit": crit}

## Index of the nearest target within max_range (ties within 0.5 px → lower hp), or -1.
static func pick_target(origin: Vector2, positions: Array, hps: Array, max_range: float) -> int:
	var best := -1
	var best_d := INF
	for i in positions.size():
		var d: float = origin.distance_to(positions[i])
		if d > max_range:
			continue
		if best == -1 or d < best_d - 0.5 or (absf(d - best_d) <= 0.5 and hps[i] < hps[best]):
			best = i
			best_d = d
	return best
