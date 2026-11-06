class_name Hero
extends CharacterBody2D
## Pran: 8-direction walk / idle / shoot / roll / hurt / dead. Node origin = feet (for Y-sort).
## All timing is driven by step(delta, input) so headless tests can run it without a tree.

signal shot(arrow: Arrow)
signal died()
signal respawned()

const MANIFEST := "res://assets/hero/manifest.json"
const ARROW_SCENE := preload("res://scenes/arrow.tscn")
const SHOOT_FPS := 14.0
const RELEASE_FRAME := 5      # shoot frame where the string is let go
const SHOOT_FRAMES := 9
const HURT_RED := Color(1.0, 0.25, 0.2)

var level := 1
var facing := 0               # index into Combat.DIRS
var state := "idle"           # idle | walk | shoot | roll | hurt | dead
var cooldown := 0.0           # shot cooldown
var spawn_point := Vector2.ZERO
var external_input := Vector2.ZERO   # touch joystick, added to keyboard input
var test_enemies: Array = []  # used instead of the "enemies" group when not in a tree

@onready var body: AnimatedSprite2D = $Body
@onready var bow: BowLayer = $Bow
@onready var health: Health = $Health

var _t := 0.0                 # time in the current timed state
var _released := false
var _aim_target: Node2D = null
var _aim_vec := Vector2.DOWN
var _dodge_cd := 0.0
var _roll_dir := Vector2.RIGHT
var _roll := {}
var _flash := 0.0

func _ready() -> void:
	setup_sprites()

## Safe to call before entering the tree (tests do).
func setup_sprites() -> void:
	if body == null: body = $Body
	if bow == null: bow = $Bow
	if health == null: health = $Health
	if body.sprite_frames != null: return
	body.sprite_frames = SpriteSet.build(MANIFEST)
	body.centered = false
	body.offset = -SpriteSet.anchor(MANIFEST, "idle")
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/flash.gdshader")
	mat.set_shader_parameter("flash_color", HURT_RED)
	body.material = mat
	health.setup(Balance.hero(level).hp)
	health.died.connect(_on_died)
	_refresh()

func dodge_cooldown_left() -> float:
	return _dodge_cd

func stats() -> Dictionary:
	return Balance.hero(level)

# ---------- actions ----------

func try_shoot() -> bool:
	if cooldown > 0.0 or state in ["roll", "hurt", "dead"]:
		return false
	cooldown = Balance.num("shot.cooldown")
	state = "shoot"
	_t = 0.0
	_released = false
	velocity = Vector2.ZERO
	_aim()
	_refresh(true)
	return true

func try_dodge(dir: Vector2) -> bool:
	if state == "dead" or _dodge_cd > 0.0:
		return false
	_roll = Balance.dodge(level)
	_dodge_cd = _roll.cooldown
	_roll_dir = dir.normalized() if dir.length() > 0.01 else BowLayer.dir_vector(facing)
	facing = Combat.facing_from_vector(_roll_dir, facing)
	_released = true          # a shot in progress is cancelled: no arrow later
	state = "roll"
	_t = 0.0
	_refresh(true)
	return true

## Damage from a monster. Returns the damage dealt, 0 when ignored (dead, invulnerable, rolling).
func receive_hit(atk: float, mult: float, from: Vector2) -> int:
	if state == "dead" or health.is_invulnerable():
		return 0
	if state == "roll" and _t < _roll.iframe:
		return 0
	var r := Combat.roll_damage(atk, mult, stats().def, false)
	health.take_hit(r.amount, false)
	if health.is_dead():
		return r.amount
	health.set_invulnerable(Balance.num("hero.hurt_iframe"))
	_knockback(from)
	_flash = Balance.num("hero.hurt_flash")
	_released = true          # getting hit cancels a pending shot
	state = "hurt"
	_t = 0.0
	_refresh(true)
	return r.amount

# ---------- simulation ----------

func step(delta: float, input: Vector2) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	_dodge_cd = maxf(0.0, _dodge_cd - delta)
	health.tick(delta)
	_flash = maxf(0.0, _flash - delta)
	_t += delta
	match state:
		"dead":
			velocity = Vector2.ZERO
			if _t >= Balance.num("hero.death_delay"):
				_respawn()
		"roll":
			var speed: float = _roll.distance / _roll.duration
			var dt := minf(delta, _roll.duration - (_t - delta))
			_move(_roll_dir * speed, maxf(dt, 0.0))
			if _t >= _roll.duration - 0.000001:
				state = "idle"
		"hurt":
			velocity = Vector2.ZERO
			if _t >= Balance.num("hero.hurt_lock"):
				state = "idle"
		"shoot":
			velocity = Vector2.ZERO
			if not _released and _t >= RELEASE_FRAME / SHOOT_FPS:
				_release()
			if _t >= SHOOT_FRAMES / SHOOT_FPS:
				state = "idle"
		_:
			if input.length() > 0.01:
				facing = Combat.facing_from_vector(input, facing)
				state = "walk"
				_move(input.normalized() * Balance.num("hero.walk"), delta)
			else:
				velocity = Vector2.ZERO
				state = "idle"
	_refresh()

func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down") + external_input
	input = input.limit_length(1.0)
	if Input.is_action_just_pressed("dodge"):
		try_dodge(input)
	if Input.is_action_pressed("attack"):
		try_shoot()
	step(delta, input)

func _move(v: Vector2, dt: float) -> void:
	velocity = v
	if is_inside_tree():
		move_and_collide(v * dt)
	else:
		position += v * dt

func _knockback(from: Vector2) -> void:
	var away := (_pos() - from)
	if away.length() < 0.01: away = -BowLayer.dir_vector(facing)
	var push := away.normalized() * Balance.num("hero.hurt_knockback")
	if is_inside_tree(): move_and_collide(push)
	else: position += push

func _pos() -> Vector2:
	return global_position if is_inside_tree() else position

func _on_died() -> void:
	state = "dead"
	_t = 0.0
	_released = true
	velocity = Vector2.ZERO
	died.emit()
	_refresh(true)

func _respawn() -> void:
	if is_inside_tree(): global_position = spawn_point
	else: position = spawn_point
	health.reset_full()
	health.set_invulnerable(Balance.num("hero.respawn_iframe"))
	state = "idle"
	_t = 0.0
	respawned.emit()
	_refresh(true)

# ---------- aiming & arrows ----------

func _enemies() -> Array:
	return get_tree().get_nodes_in_group("enemies") if is_inside_tree() else test_enemies

func _arrow_origin() -> Vector2:
	var v := BowLayer.dir_vector(facing)
	return _pos() + BowLayer.CHEST + Vector2(v.x, v.y * 0.6) * 18.0

## Lock on to the nearest live enemy within shot.range and turn to face it.
func _aim() -> void:
	var live: Array = []
	var pts: Array = []
	var hps: Array = []
	for e in _enemies():
		if is_instance_valid(e) and e.is_alive():
			live.append(e)
			pts.append(e.hurt_point())
			hps.append(e.hp if "hp" in e else 0)
	var i := Combat.pick_target(_pos(), pts, hps, Balance.num("shot.range"))
	_aim_target = live[i] if i >= 0 else null
	if _aim_target != null:
		facing = Combat.facing_from_vector(pts[i] - _pos(), facing)
		_aim_vec = (pts[i] - _arrow_origin()).normalized()
	else:
		_aim_vec = BowLayer.dir_vector(facing)

func _release() -> void:
	_released = true
	var start := _arrow_origin()
	var v := _aim_vec
	if is_instance_valid(_aim_target) and _aim_target.is_alive():
		v = (_aim_target.hurt_point() - start).normalized()
	var a: Arrow = ARROW_SCENE.instantiate()
	a.position = start
	a.launch(v, stats().atk, _enemies())
	if is_inside_tree():
		get_parent().add_child(a)
	shot.emit(a)

# ---------- visuals ----------

func _anim_for(s: String) -> String:
	var name := "%s_%s" % [s, Combat.DIRS[facing]]
	if body.sprite_frames.has_animation(name):
		return name
	# fallbacks until the art exists: hurt/roll show idle/walk
	return "%s_%s" % [("walk" if s == "roll" else "idle"), Combat.DIRS[facing]]

func _refresh(restart := false) -> void:
	var name := _anim_for(state)
	if restart or body.animation != name:
		var keep := body.frame if (not restart and body.animation == name) else 0
		body.play(name)
		body.frame = keep
	if body.material:
		body.material.set_shader_parameter("flash_amount", 0.75 if _flash > 0.0 else 0.0)
	bow.visible = state != "dead"
	bow.apply("shoot" if state == "shoot" else "walk", facing)
