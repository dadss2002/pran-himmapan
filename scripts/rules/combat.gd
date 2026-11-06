class_name Combat
## Pure game-rule functions (docs/spec-numbers.md §2). No scene access, so they are unit-testable.

## Facings, in the order used everywhere (manifest, animation names).
const DIRS := ["south", "south-east", "east", "north-east", "north", "north-west", "west", "south-west"]
const WALK_SPEED := 110.0
const SHOT_RANGE := 220.0
const SHOT_COOLDOWN := 0.8
const CRIT_MULT := 1.5

## Damage = ATK × mult × (1 − DEF/(DEF+100)) × roll, ×1.5 on crit, at least 1.
## `roll` is the 0.9–1.1 random factor, passed in so tests are deterministic.
static func damage(atk: float, mult: float, def: float, crit: bool, roll: float) -> int:
	var d := atk * mult * (1.0 - def / (def + 100.0)) * roll
	if crit:
		d *= CRIT_MULT
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
