class_name BowLayer
extends Sprite2D
## The bow is its own layer (the PixelLab hero is drawn without one).
## Source art (assets/items/bow_*.png) is vertical with the belly facing +x, i.e. aimed east,
## so rotation = aim angle. Positions are relative to the hero's feet (node origin).

const SCALE := 0.6
const CHEST := Vector2(0, -24)      # chest height above the feet
const HOLD_DIST := 13.0             # how far in front of the chest the bow is held while shooting
const BACK_POS := Vector2(-2, -22)  # carried on the back
const BACK_ROT := deg_to_rad(-35.0)

func _init() -> void:
	scale = Vector2(SCALE, SCALE)
	centered = true

## Facing index (Combat.DIRS order) -> unit aim vector on screen.
static func dir_vector(facing: int) -> Vector2:
	# 0 south = +y, counter-clockwise on screen through east (+x)
	var a := PI / 2.0 - facing * PI / 4.0
	return Vector2(cos(a), sin(a)).normalized()

## true = draw over the body. 0,1,7 face the camera (south-ish); 3,4,5 face away (north-ish).
func draws_in_front(state: String, facing: int) -> bool:
	var away := facing in [3, 4, 5]
	if state == "shoot":
		return not away
	return away

func apply(state: String, facing: int) -> void:
	z_index = 1 if draws_in_front(state, facing) else -1
	if state == "shoot":
		var v := dir_vector(facing)
		rotation = v.angle()
		# squash the vertical reach a little: low top-down view
		position = CHEST + Vector2(v.x, v.y * 0.6) * HOLD_DIST
		flip_v = false
	else:
		var side := -1.0 if facing in [1, 2, 3] else 1.0  # keep the bow on the far shoulder when side-on
		position = Vector2(BACK_POS.x * side, BACK_POS.y)
		rotation = BACK_ROT * side
