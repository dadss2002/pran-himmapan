class_name Hero
extends CharacterBody2D
## Pran: 8-direction walk / idle / shoot. Node origin = feet (for Y-sort).

signal shot(arrow: Arrow)

const MANIFEST := "res://assets/hero/manifest.json"
const ARROW_SCENE := preload("res://scenes/arrow.tscn")
const RELEASE_FRAME := 5   # shoot frame where the string is let go

var facing := 0            # index into Combat.DIRS
var state := "idle"        # idle | walk | shoot
var cooldown := 0.0

@onready var body: AnimatedSprite2D = $Body
@onready var bow: BowLayer = $Bow

var _released := false

func _ready() -> void:
	setup_sprites()

## Safe to call before entering the tree (tests do).
func setup_sprites() -> void:
	if body == null: body = $Body
	if bow == null: bow = $Bow
	if body.sprite_frames != null: return
	body.sprite_frames = HeroSprites.build(MANIFEST)
	body.centered = false
	body.offset = -HeroSprites.anchor(MANIFEST, "idle")
	body.animation_finished.connect(_on_anim_finished)
	_refresh()

func try_shoot() -> bool:
	if cooldown > 0.0: return false
	cooldown = Combat.SHOT_COOLDOWN
	state = "shoot"
	_released = false
	velocity = Vector2.ZERO
	_refresh(true)
	return true

## One simulation step; _physics_process feeds it the input vector.
func step(delta: float, input: Vector2) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	if state == "shoot":
		velocity = Vector2.ZERO
		if not _released and body.frame >= RELEASE_FRAME:
			_release()
		return
	if input.length() > 0.01:
		velocity = input.normalized() * Combat.WALK_SPEED
		facing = Combat.facing_from_vector(input, facing)
		state = "walk"
	else:
		velocity = Vector2.ZERO
		state = "idle"
	if is_inside_tree():
		move_and_slide()
	else:
		position += velocity * delta
	_refresh()

func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("attack"):
		try_shoot()
	step(delta, Input.get_vector("move_left", "move_right", "move_up", "move_down"))

func _release() -> void:
	_released = true
	if not is_inside_tree(): return
	var a: Arrow = ARROW_SCENE.instantiate()
	var v := BowLayer.dir_vector(facing)
	a.position = global_position + BowLayer.CHEST + Vector2(v.x, v.y * 0.6) * 18.0
	a.launch(v)
	get_parent().add_child(a)
	shot.emit(a)

func _on_anim_finished() -> void:
	if state == "shoot":
		if not _released: _release()
		state = "idle"
		_refresh()

func _refresh(restart := false) -> void:
	var name := "%s_%s" % [state, Combat.DIRS[facing]]
	if restart or body.animation != name:
		var keep := body.frame if (not restart and body.animation.get_slice("_", 0) == state) else 0
		body.play(name)
		body.frame = keep
	bow.apply(state, facing)
