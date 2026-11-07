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
var _path := PackedVector2Array()     # route round trees/water when the straight line is blocked
var _path_goal := Vector2.INF
var _path_t := 0.0
var _no_route := false
var _wanted_move := false          # set by _move this step; stuck checks only count frames spent trying
var _stuck_t := 0.0
var _stuck_from := Vector2.ZERO
var _hero: Hero = null
var _telegraph: FxSprite = null
var _setup_done := false
var _flash_shown := -1.0
var elite := false            # M3h: tougher, worth more, ★ + HP bar over the head
var _tag: Node2D
const ELITE_TAG := preload("res://scripts/monsters/elite_tag.gd")
var _anchors := {}

func _ready() -> void:
	setup()

func setup() -> void:
	if _setup_done: return
	_setup_done = true
	if body == null: body = $Body
	if health == null: health = $Health
	if shape == null: shape = $Feet
	body.sprite_frames = SpriteSet.build(manifest_path())
	body.centered = false
	_anchors = SpriteSet.anchors(manifest_path())
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
	return with_elite(Balance.wolf(level))

## M3h: an elite has elite.* on top of its normal stats.
func with_elite(s: Dictionary) -> Dictionary:
	return Balance.elite_stats(s) if elite else s

## Rolled on every spawn and respawn (elite.chance); shows or hides the ★ + HP tag.
## The test runner turns random elites off so older tests stay deterministic.
static var elites_enabled := true

func roll_elite(rng: RandomNumberGenerator = null) -> void:
	var x := rng.randf() if rng else randf()
	set_elite(elites_enabled and x < Balance.num("elite.chance"))

func set_elite(on: bool) -> void:
	elite = on
	if on and _tag == null:
		_tag = ELITE_TAG.new()
		_tag.monster = self
		add_child(_tag)
	if _tag: _tag.visible = on
	if health and is_alive(): health.setup(stats().hp)

func manifest_path() -> String:
	return MANIFEST

# ---------- hooks other monsters override (see Monster) ----------

## Whether the idle wolf starts a chase with the hero this far away.
func _wants_aggro(dist: float) -> bool:
	var walled_off := pack != null and pack.unreachable_at.distance_to(_hpos()) < 24.0
	var calm := pack != null and pack.calm > 0.0
	return dist <= n("aggro") and not walled_off and not calm

## The idle wolf saw the hero: the whole pack joins in.
func _start_aggro() -> void:
	if pack: pack.alert(_hero)
	else: start_chase(_hero)

## Hit while idle: the whole pack joins in.
func _on_provoked() -> void:
	if pack and _hero: pack.alert(_hero)

## States that need a live hero (otherwise go home).
func _fight_states() -> Array:
	return ["chase", "bite", "lunge_warn", "lunge"]

## States the base step does not know (flee, ring_warn, ...).
func _step_custom(_delta: float) -> void:
	pass

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
	if state != "bite" and not elite:          # elites do not get knocked back (M3h)
		var away := _pos() - from
		if away.length() > 0.01:
			_push(away.normalized() * n("hit_knockback"))
	if state == "idle":
		_on_provoked()
	return r.amount

func start_chase(h: Hero) -> void:
	if state in ["idle"]:
		_hero = h
		state = "chase"
		_t = 0.0

func revive() -> void:
	roll_elite()
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
	_wanted_move = false
	var alive_hero := _hero != null and is_instance_valid(_hero) and _hero.state != "dead"
	if state in _fight_states() and not alive_hero:
		_go_home()
	match state:
		"dead":
			var death_len := _anim_len("death")
			body.modulate.a = 1.0 - clampf((_t - death_len) / n("death_fade"), 0.0, 1.0)
			visible = body.modulate.a > 0.0
		"idle":
			if alive_hero and _wants_aggro(_pos().distance_to(_hpos())):
				_start_aggro()
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
				var aim := _steer(home, delta) - _pos()
				_move(aim.normalized() * n("run"), minf(delta, aim.length() / n("run")))
		_:
			_step_custom(delta)
	# Blocked by water or a trunk: a chase that makes no headway gives up (back home at full HP, so
	# an unreachable hero can't farm the pack); a return that makes no headway snaps home.
	if state in ["chase", "return"] and _stuck(delta):
		if state == "chase":
			_go_home()
		else:
			_set_pos(home)
			state = "idle"
			_wander_to = home
			velocity = Vector2.ZERO
	_refresh()

func _stuck(delta: float) -> bool:
	if not _wanted_move:
		_stuck_t = 0.0
		_stuck_from = _pos()
		return false
	_stuck_t += delta
	if _stuck_t < n("stuck_time"): return false
	var moved := _pos().distance_to(_stuck_from)
	_stuck_t = 0.0
	_stuck_from = _pos()
	return moved < n("stuck_distance")

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
	var goal := _hpos() + slot
	if (goal - _pos()).length() < 1.0: goal = _hpos()
	var to := _steer(goal, delta) - _pos()
	if _no_route:
		# no way round (hero walled in or across water): go home healed, and don't re-aggro on
		# the same spot, so a walled-off hero can't farm the pack
		if pack: pack.unreachable_at = _hpos()
		_go_home()
		return
	if to.length() < 1.0: to = _hpos() - _pos()
	_move(to.normalized() * n("run"), minf(delta, maxf(to.length(), d - stop) / n("run")))

## The point to run at on the way to goal: goal itself when the straight line is open, else the next
## corner of a grid route (pack.nav, built from the map). No map or no route: goal (the stuck check
## then sends the wolf home).
func _steer(goal: Vector2, delta: float) -> Vector2:
	_no_route = false
	var nav: AStarGrid2D = pack.nav if pack != null else null
	if nav == null or not is_inside_tree(): return goal
	var from := _pos()
	if _line_clear(nav, from, goal):
		_path.clear()
		return goal
	_path_t -= delta
	if _path.is_empty() or _path_t <= 0.0 or _path_goal.distance_to(goal) > 24.0:
		_path_t = 0.3
		_path_goal = goal
		var a := _open_cell(nav, from)
		var b := _open_cell(nav, goal)
		_path = nav.get_point_path(a, b) if a.x >= 0 and b.x >= 0 else PackedVector2Array()
		_no_route = _path.is_empty()
	while _path.size() > 1 and (from.distance_to(_path[0]) < 6.0 or _line_clear(nav, from, _path[1])):
		_path.remove_at(0)
	return _path[0] if not _path.is_empty() else goal

static func _line_clear(nav: AStarGrid2D, a: Vector2, b: Vector2) -> bool:
	var steps := int(a.distance_to(b) / 4.0) + 1
	for i in steps + 1:
		var c := Vector2i((a.lerp(b, float(i) / steps) / nav.cell_size).floor())
		if not nav.is_in_boundsv(c) or nav.is_point_solid(c): return false
	return true

## The cell under p, or the nearest open one within 3 cells (a wolf brushing a trunk stands in a
## cell that is too tight to be open). Vector2i(-1, -1) when none.
static func _open_cell(nav: AStarGrid2D, p: Vector2) -> Vector2i:
	var c := Vector2i((p / nav.cell_size).floor())
	for r in 4:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var q := c + Vector2i(dx, dy)
				if nav.is_in_boundsv(q) and not nav.is_point_solid(q): return q
	return Vector2i(-1, -1)

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

## Teleports only (revive, return home): M3k drops the physics-interpolation blend so the
## monster does not slide across the map on a 120 Hz screen.
func _set_pos(p: Vector2) -> void:
	if is_inside_tree():
		global_position = p
		reset_physics_interpolation()
	else: position = p

func _move(v: Vector2, dt: float) -> void:
	v *= status.speed_mult()         # ice gem slow: walk, run and lunge
	velocity = v
	_face(v)
	if v.length() > 1.0: _wanted_move = true
	if is_inside_tree():
		var hit := move_and_collide(v * dt)
		if hit:                                    # slide along trunks and shores instead of stopping dead
			move_and_collide(hit.get_remainder().slide(hit.get_normal()))
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
	var fl := 0.85 if _flash > 0.0 else 0.0
	if body.material and fl != _flash_shown:          # only when it changes (M3k)
		_flash_shown = fl
		body.material.set_shader_parameter("flash_amount", fl)
