class_name Wolf
extends CharacterBody2D
## Ghost wolf (หมาป่าผี). Driven by its WolfPack via step(delta, hero); numbers from Balance "wolf.*".
## States: idle (wander) | chase | bite (windup) | lunge_warn | lunge | return | dead.

signal died(wolf: Wolf)

const MANIFEST := "res://assets/wolf/manifest.json"
const HURT_POINT := Vector2(0, -14)

var level := 1
var pack: WolfPack
var home := Vector2.ZERO
var state := "idle"
var facing := 0
var hp: int:
	get: return health.hp if health else 0

@onready var body: AnimatedSprite2D = $Body
@onready var health: Health = $Health
@onready var shape: CollisionShape2D = $Feet

var _t := 0.0
var _bite_cd := 0.0
var _lunge_cd := 0.0
var _lunge_dir := Vector2.RIGHT
var _lunge_from := Vector2.ZERO
var _lunge_hit := false
var _wander_to := Vector2.ZERO
var _flash := 0.0
var _hero: Hero = null
var _telegraph: FxSprite = null
var _setup_done := false
var _anchors := {}

func _ready() -> void:
	setup()

func setup() -> void:
	if _setup_done: return
	_setup_done = true
	if body == null: body = $Body
	if health == null: health = $Health
	if shape == null: shape = $Feet
	body.sprite_frames = SpriteSet.build(MANIFEST)
	body.centered = false
	_anchors = SpriteSet.anchors(MANIFEST)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/flash.gdshader")
	mat.set_shader_parameter("flash_color", Color.WHITE)
	body.material = mat
	health.setup(stats().hp)
	health.died.connect(_on_died)
	add_to_group("enemies")
	_wander_to = home
	_refresh(true)

var status := StatusEffects.new()
const STATUS_FX_SCALE := 1.5
var _burn_fx: FxSprite = null
var _frost_fx: FxSprite = null

func stats() -> Dictionary:
	return Balance.wolf(level)

## Gem element effects: "burn" (damage per tick, leech fraction, source hero) or "slow".
func apply_status(kind: String, value := 0.0, leech := 0.0, source: Object = null) -> void:
	if not is_alive(): return
	if kind == "burn": status.apply_burn(value, leech, source)
	elif kind == "slow": status.apply_slow()

func n(key: String) -> float:
	return Balance.num("wolf." + key)

# ---------- queries used by the hero / arrows ----------

func is_alive() -> bool:
	return state != "dead"

func hurt_point() -> Vector2:
	return _pos() + HURT_POINT

func telegraph_visible() -> bool:
	return _telegraph != null and _telegraph.visible

# ---------- events ----------

## Hit by the hero. Returns damage dealt (0 when dead). Knockback, except during the bite windup.
func receive_hit(atk: float, mult: float, from: Vector2, crit_chance := -1.0, crit_mult := -1.0) -> int:
	if not is_alive(): return 0
	var r := Combat.roll_damage(atk, mult, stats().def, true, crit_chance, crit_mult)
	health.take_hit(r.amount, r.crit)
	if not is_alive(): return r.amount
	_flash = n("hit_flash")
	if state != "bite":
		var away := _pos() - from
		if away.length() > 0.01:
			_push(away.normalized() * n("hit_knockback"))
	if state == "idle" and pack and _hero:
		pack.alert(_hero)
	return r.amount

func start_chase(h: Hero) -> void:
	if state in ["idle"]:
		_hero = h
		state = "chase"
		_t = 0.0

func revive() -> void:
	health.setup(stats().hp)
	status.clear()
	_set_pos(home + Vector2(randf_range(-16, 16), randf_range(-12, 12)))
	state = "idle"
	_t = 0.0
	_bite_cd = 0.0
	_lunge_cd = 0.0
	visible = true
	body.modulate.a = 1.0
	if is_inside_tree(): shape.set_deferred("disabled", false)
	else: shape.disabled = false
	_refresh(true)

## Flames / ice crystals at the feet while burning / slowed (vfx_workbench strips).
func _update_status_fx() -> void:
	if not is_inside_tree(): return
	_burn_fx = _toggle_fx(_burn_fx, "status_burn", status.is_burning() and is_alive())
	_frost_fx = _toggle_fx(_frost_fx, "status_frost", status.is_slowed() and is_alive())

func _toggle_fx(fx: FxSprite, fx_name: String, on: bool) -> FxSprite:
	if on and fx == null:
		fx = FxSprite.make(fx_name, true)
		fx.scale = Vector2.ONE * STATUS_FX_SCALE   # the effects were drawn small; match the 80 px wolf
		add_child(fx)
		fx.play(fx_name)
	elif not on and fx != null:
		fx.queue_free()
		fx = null
	return fx

func _on_died() -> void:
	status.clear()
	_update_status_fx()
	_end_lunge()
	state = "dead"
	_t = 0.0
	velocity = Vector2.ZERO
	if is_inside_tree(): shape.set_deferred("disabled", true)
	else: shape.disabled = true
	died.emit(self)
	_refresh(true)

# ---------- simulation ----------

func step(delta: float, hero: Hero) -> void:
	if hero != null: _hero = hero
	health.tick(delta)
	if is_alive():
		var burn := status.tick(delta)
		if burn > 0:
			health.take_hit(burn, false)
			if status.burn_leech > 0.0 and is_instance_valid(status.burn_source) and status.burn_source.has_method("leech_heal"):
				status.burn_source.leech_heal(burn * status.burn_leech)
			if not is_alive(): return
	_update_status_fx()
	_flash = maxf(0.0, _flash - delta)
	_bite_cd = maxf(0.0, _bite_cd - delta)
	_lunge_cd = maxf(0.0, _lunge_cd - delta)
	_t += delta
	var alive_hero := _hero != null and is_instance_valid(_hero) and _hero.state != "dead"
	if state in ["chase", "bite", "lunge_warn", "lunge"] and not alive_hero:
		_go_home()
	match state:
		"dead":
			var death_len := _anim_len("death")
			body.modulate.a = 1.0 - clampf((_t - death_len) / n("death_fade"), 0.0, 1.0)
			visible = body.modulate.a > 0.0
		"idle":
			if alive_hero and _pos().distance_to(_hpos()) <= n("aggro"):
				if pack: pack.alert(_hero)
				else: start_chase(_hero)
				if state == "chase":
					_chase(delta)   # react on the same frame
			else:
				_wander(delta)
		"chase":
			if _pos().distance_to(home) > n("leash"):
				_go_home()
			else:
				_chase(delta)
		"bite":
			velocity = Vector2.ZERO
			if _t >= n("bite_windup"):
				if _pos().distance_to(_hpos()) <= n("bite_hit_range"):
					_hero.receive_hit(stats().atk, n("bite_mult"), _pos())
				_bite_cd = n("bite_cooldown")
				state = "chase"
				_t = 0.0
		"lunge_warn":
			velocity = Vector2.ZERO
			if _t >= n("lunge_warn"):
				_show_telegraph(false)
				state = "lunge"
				_t = 0.0
				_lunge_hit = false
				_lunge_from = _pos()
		"lunge":
			var speed := n("lunge_distance") / n("lunge_time")
			var dt := minf(delta, n("lunge_time") - (_t - delta))
			_move(_lunge_dir * speed, maxf(dt, 0.0))
			if not _lunge_hit and _pos().distance_to(_hpos()) <= n("lunge_hit_radius"):
				if _hero.receive_hit(stats().atk, n("lunge_mult"), _pos()) > 0:
					_lunge_hit = true
			if _t >= n("lunge_time") - 0.000001:
				_end_lunge()
				_lunge_cd = n("lunge_cooldown")
				state = "chase"
				_t = 0.0
		"return":
			var to_home := home - _pos()
			if to_home.length() < 4.0:
				state = "idle"
				_wander_to = home
				velocity = Vector2.ZERO
			else:
				_move(to_home.normalized() * n("run"), minf(delta, to_home.length() / n("run")))
	_refresh()

func _chase(delta: float) -> void:
	var d := _pos().distance_to(_hpos())
	if d <= n("bite_range") and _bite_cd <= 0.0:
		state = "bite"
		_t = 0.0
		_face(_hpos() - _pos())
		return
	if d >= n("lunge_min") and d <= n("lunge_max") and _lunge_cd <= 0.0 and (pack == null or pack.request_lunge(self)):
		state = "lunge_warn"
		_t = 0.0
		var target := _hpos()
		_lunge_dir = (target - _pos()).normalized()
		_face(_lunge_dir)
		_show_telegraph(true, target)
		return
	# run toward a slot around the hero (inside bite range) so the pack spreads out;
	# stop by the distance to the hero itself, never short of bite range
	var slot := Vector2.ZERO
	if pack and pack.wolves.size() > 1:
		slot = Vector2(n("chase_slot"), 0).rotated(TAU * pack.wolves.find(self) / pack.wolves.size())
	var stop := n("bite_range") * n("stop_factor")
	if d <= stop:
		velocity = Vector2.ZERO
		_face(_hpos() - _pos())
		return
	var to := _hpos() + slot - _pos()
	if to.length() < 1.0: to = _hpos() - _pos()
	_move(to.normalized() * n("run"), minf(delta, maxf(to.length(), d - stop) / n("run")))

func _wander(delta: float) -> void:
	var to := _wander_to - _pos()
	if to.length() < 2.0:
		velocity = Vector2.ZERO
		if _t > n("wander_pause"):
			_t = 0.0
			var r := n("wander_radius")
			_wander_to = home + Vector2(randf_range(-r, r), randf_range(-r * 0.6, r * 0.6))
	else:
		_move(to.normalized() * n("wander_speed"), minf(delta, to.length() / n("wander_speed")))

func _go_home() -> void:
	_end_lunge()
	state = "return"
	_t = 0.0
	health.reset_full()

func _end_lunge() -> void:
	_show_telegraph(false)
	if pack: pack.end_lunge(self)

func _show_telegraph(on: bool, at := Vector2.ZERO) -> void:
	if on:
		if _telegraph == null:
			_telegraph = FxSprite.make("lunge_warning", true)
			_telegraph.show_behind_parent = true   # under the wolf, above the floor
			_telegraph.modulate = Color(1.25, 0.75, 0.75)
			add_child(_telegraph)
		_telegraph.position = at - _pos()
		_telegraph.visible = true
		_telegraph.frame = 0
		_telegraph.play("lunge_warning")
	elif _telegraph:
		_telegraph.visible = false
		_telegraph.stop()

# ---------- movement helpers ----------

func _pos() -> Vector2:
	return global_position if is_inside_tree() else position

func _hpos() -> Vector2:
	if _hero == null or not is_instance_valid(_hero): return _pos()
	return _hero.global_position if _hero.is_inside_tree() else _hero.position

func _set_pos(p: Vector2) -> void:
	if is_inside_tree(): global_position = p
	else: position = p

func _move(v: Vector2, dt: float) -> void:
	v *= status.speed_mult()         # ice gem slow: walk, run and lunge
	velocity = v
	_face(v)
	if is_inside_tree(): move_and_collide(v * dt)
	else: position += v * dt

func push(v: Vector2) -> void:
	_push(v)

func _push(v: Vector2) -> void:
	if is_inside_tree(): move_and_collide(v)
	else: position += v

func _face(v: Vector2) -> void:
	facing = Combat.facing_from_vector(v, facing)

# ---------- visuals ----------

func _anim_len(anim: String) -> float:
	var name := "%s_%s" % [anim, Combat.DIRS[facing]]
	if not body.sprite_frames.has_animation(name): return 0.0
	return body.sprite_frames.get_frame_count(name) / body.sprite_frames.get_animation_speed(name)

func _anim_for() -> Array:
	# [animation, speed_scale]; falls back to the still pose until an animation exists
	var want: String = {"idle": "run", "chase": "run", "return": "run", "bite": "bite",
		"lunge_warn": "lunge", "lunge": "lunge", "dead": "death"}[state]
	var scale := 0.4 if state == "idle" else 1.0
	var name := "%s_%s" % [want, Combat.DIRS[facing]]
	if not body.sprite_frames.has_animation(name):
		name = "pose_%s" % Combat.DIRS[facing]
	return [name, scale]

func _refresh(restart := false) -> void:
	var a := _anim_for()
	if restart or body.animation != a[0]:
		body.play(a[0])
		body.offset = -_anchors.get(String(a[0]).get_slice("_", 0), Vector2(32, 54))
	body.speed_scale = a[1]
	if state == "lunge_warn":
		body.pause()
		body.frame = 0
	elif state == "idle" and velocity == Vector2.ZERO and body.animation.begins_with("run"):
		body.pause()
		body.frame = 0
	elif not body.is_playing():
		body.play()
	if body.material:
		body.material.set_shader_parameter("flash_amount", 0.85 if _flash > 0.0 else 0.0)
