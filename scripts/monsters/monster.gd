class_name Monster
extends Wolf
## A forest monster (M3d): the wolf's body (health, status, knockback, wander, leash, routes, stuck
## rules, respawn via its group) with a kind from Balance "monsters.<kind>" (missing keys fall back to
## "wolf.*"). Temper decides when it fights: aggressive (aggro range), ambush (hidden until close),
## passive (only once hit), flee (never fights, runs from the hero when hit). Attack: lunge (the wolf's
## bite + lunge with this kind's numbers), ring (warned circle round itself), throw (keeps its distance
## and throws fruit), none.

const KINDS := ["deer", "boar", "shroom", "macaque", "viper", "kongkoi"]
const FRUIT_SCENE := preload("res://scripts/monsters/fruit.gd")
const CLOUD_SCENE := preload("res://scripts/monsters/hazard_cloud.gd")

var kind := "boar"
var provoked := false
var _ring_cd := 0.0
var _throw_cd := 0.0
var _flee_left := 0.0
var _ring: Node2D
var _retreating := false
var _hop_dir := Vector2.RIGHT
const HOP_TIME := 0.25
const RING_SCENE := preload("res://scripts/monsters/ring_warning.gd")

func cfg(key: String):
	var path := "monsters.%s.%s" % [kind, key]
	return Balance._lookup(path) if Balance.has(path) else Balance._lookup("wolf." + key)

func n(key: String) -> float:
	return float(cfg(key))

func temper() -> String:
	return String(cfg("temper"))

func attack_kind() -> String:
	return String(cfg("attack"))

## Spec M3d §2: HP/ATK grow per level above 1, DEF/EXP per level.
static func stats_for(k: String, lv: int) -> Dictionary:
	var t := "monsters." + k
	var l := lv - 1
	return Balance.horde_stats({
		"hp": int(Balance.num(t + ".hp_base") + Balance.num(t + ".hp_per_level") * l),
		"atk": int(Balance.num(t + ".atk_base") + Balance.num(t + ".atk_per_level") * l),
		"def": int(Balance.num(t + ".def_base") + Balance.num(t + ".def_per_level") * lv),
		"exp": int(Balance.num(t + ".exp_base") + Balance.num(t + ".exp_per_level") * lv),
	})

func stats() -> Dictionary:
	return stats_for(kind, level)

func manifest_path() -> String:
	return "res://assets/monsters/%s/manifest.json" % kind

func loot_table() -> String:
	return String(cfg("loot")) if Balance.has("monsters.%s.loot" % kind) else "wolf"

func gold_mult() -> float:
	return n("gold_mult") if Balance.has("monsters.%s.gold_mult" % kind) else 1.0

func setup() -> void:
	super.setup()
	_update_hidden()

func revive() -> void:
	provoked = false
	_flee_left = 0.0
	_ring_cd = 0.0
	_throw_cd = 0.0
	super.revive()
	_update_hidden()

# ---------- tempers ----------

func _wants_aggro(dist: float) -> bool:
	match temper():
		"aggressive", "ambush":
			return super._wants_aggro(dist)
		"passive":
			return provoked and super._wants_aggro(dist)
	return false

## A passive monster that was hit fights alone: its group-mates were not hit and stay calm.
func _start_aggro() -> void:
	if temper() == "passive": start_chase(_hero)
	else: super._start_aggro()

func _on_provoked() -> void:
	match temper():
		"flee":
			_start_flee()
		"passive":
			provoked = true
			if _hero: start_chase(_hero)
		_:
			super._on_provoked()

func receive_hit(atk: float, mult: float, from: Vector2, crit_chance := -1.0, crit_mult := -1.0) -> int:
	if temper() == "passive": provoked = true
	var was := state
	var dealt := super.receive_hit(atk, mult, from, crit_chance, crit_mult)
	if is_alive() and temper() == "flee" and was != "idle": _start_flee()   # hit again while fleeing/returning
	return dealt

func _start_flee() -> void:
	_end_lunge()
	state = "flee"
	_t = 0.0
	_flee_left = n("flee_time")

## Back home: a passive monster calms down again.
func _go_home() -> void:
	provoked = false
	super._go_home()

## Ends a flee: walks home, healing only past the leash like any wolf (spec §1), not just for running.
func _walk_home() -> void:
	if _pos().distance_to(home) > n("leash"):
		_go_home()
		return
	_end_lunge()
	provoked = false
	state = "return"
	_t = 0.0

## Backing away from the hero (macaque) is not a stuck chase, even against a wall: no heal-and-reset.
func _stuck(delta: float) -> bool:
	if _retreating:
		_retreating = false
		_stuck_t = 0.0
		_stuck_from = _pos()
		return false
	return super._stuck(delta)

func _fight_states() -> Array:
	return ["chase", "bite", "lunge_warn", "lunge", "ring_warn", "hop"]

# ---------- custom states ----------

func step(delta: float, hero: Hero) -> void:
	_ring_cd = maxf(0.0, _ring_cd - delta)
	_throw_cd = maxf(0.0, _throw_cd - delta)
	super.step(delta, hero)
	_update_hidden()

func _step_custom(delta: float) -> void:
	match state:
		"flee":
			_flee_left -= delta
			if _flee_left <= 0.0 or _hero == null:
				_walk_home()
				return
			var away := _pos() - _hpos()
			var goal := _pos() + (away.normalized() if away.length() > 0.1 else Vector2.RIGHT) * 48.0
			var aim := _steer(goal, delta) - _pos()
			_move(aim.normalized() * n("flee_speed"), delta)
		"hop":
			# one quick hop away from the hero: hop_back px in HOP_TIME, then back to keeping distance
			_move(_hop_dir * n("hop_back") / HOP_TIME, delta)
			if _t >= HOP_TIME:
				state = "chase"
				_t = 0.0
		"ring_warn":
			velocity = Vector2.ZERO
			if _t >= n("ring_warn"):
				_show_telegraph(false)
				if _hero and _pos().distance_to(_hpos()) <= n("ring_radius"):
					var dealt := _hero.receive_hit(stats().atk, n("ring_mult"), _pos())
					var frac := n("poison_frac") if Balance.has("monsters.%s.poison_frac" % kind) else 0.0
					if dealt > 0 and frac > 0.0:
						_hero.apply_poison(maxi(1, int(round(dealt * frac))), n("poison_time"))
				_ring_cd = n("ring_cooldown")
				state = "chase"
				_t = 0.0

func _chase(delta: float) -> void:
	match attack_kind():
		"ring": _chase_ring(delta)
		"throw": _chase_throw(delta)
		"none": _go_home()
		_: super._chase(delta)

func _chase_ring(delta: float) -> void:
	var d := _pos().distance_to(_hpos())
	if d <= n("ring_radius") * 0.8 and _ring_cd <= 0.0:
		state = "ring_warn"
		_t = 0.0
		velocity = Vector2.ZERO
		_show_telegraph(true, _pos())
		return
	if d <= n("ring_radius") * 0.6:
		velocity = Vector2.ZERO
		return
	var aim := _steer(_hpos(), delta) - _pos()
	if _no_route:
		if pack: pack.unreachable_at = _hpos()
		_go_home()
		return
	_move(aim.normalized() * n("run"), minf(delta, aim.length() / maxf(n("run"), 1.0)))

func _chase_throw(delta: float) -> void:
	var to_hero := _hpos() - _pos()
	var d := to_hero.length()
	_face(to_hero)
	if d < n("hop_back_under"):
		_hop_dir = -to_hero.normalized() if d > 0.1 else Vector2.RIGHT
		state = "hop"
		_t = 0.0
		return
	if d > n("keep_max"):
		var aim := _steer(_hpos(), delta) - _pos()
		if _no_route:
			if pack: pack.unreachable_at = _hpos()
			_go_home()
			return
		_move(aim.normalized() * n("run"), delta)
	elif d < n("keep_min"):
		_retreating = true
		_move(-to_hero.normalized() * n("run") * 0.6, delta)
	else:
		velocity = Vector2.ZERO
	if _throw_cd <= 0.0 and d <= n("fruit_range"):
		_throw_cd = n("throw_every")
		_throw()

func _throw() -> void:
	if not is_inside_tree(): return
	var f: Node2D = FRUIT_SCENE.new()
	f.setup(_pos() + Vector2(0, -16), _hpos() + Vector2(0, -14), n("fruit_speed"), n("fruit_range"),
		stats().atk, n("throw_mult"), _hero, pack.blocked if pack else Callable())
	get_parent().add_child(f)

func _on_died() -> void:
	super._on_died()
	if Balance.has("monsters.%s.cloud_radius" % kind) and is_inside_tree():
		var c: Node2D = CLOUD_SCENE.new()
		var dmg := maxi(1, int(round(stats().atk * n("ring_mult") * n("poison_frac"))))
		c.setup(_pos(), n("cloud_radius"), n("cloud_time"), dmg, n("poison_time"), _hero)
		get_parent().add_child(c)

## Ring attacks draw their own warning: the hit ellipse filling up over the warning time (poison
## rings purple, plain stomps red). Lunges keep the wolf's warning.
func _show_telegraph(on: bool, at := Vector2.ZERO) -> void:
	if attack_kind() != "ring":
		super._show_telegraph(on, at)
		return
	if on:
		if _ring == null:
			_ring = RING_SCENE.new()
			_ring.show_behind_parent = true
			add_child(_ring)
		var poison := Balance.has("monsters.%s.poison_frac" % kind) and n("poison_frac") > 0.0
		_ring.start(n("ring_radius"), n("ring_warn"), Color(0.75, 0.35, 0.95) if poison else Color(1.0, 0.3, 0.25))
	elif _ring:
		_ring.visible = false

func telegraph_visible() -> bool:
	return super.telegraph_visible() or (_ring != null and _ring.visible)

## Ambushers stay faint until the hero is within their aggro range (or they are already fighting).
func _update_hidden() -> void:
	if body == null: return
	if temper() == "ambush" and state in ["idle", "return"] and is_alive():
		var near := _hero != null and is_instance_valid(_hero) and _pos().distance_to(_hpos()) <= n("aggro")
		body.self_modulate.a = 1.0 if near else n("hidden_alpha")
	else:
		body.self_modulate.a = 1.0

func is_hidden() -> bool:
	return body != null and body.self_modulate.a < 1.0

# ---------- visuals ----------

func _anim_for() -> Array:
	var want := "attack" if state in ["bite", "lunge_warn", "lunge", "ring_warn"] else "run"
	if attack_kind() == "throw" and _throw_cd > n("throw_every") - 0.4: want = "attack"
	if state == "dead": want = "pose"
	var scale := 0.4 if state == "idle" else 1.0
	var name := "%s_%s" % [want, Combat.DIRS[facing]]
	if not body.sprite_frames.has_animation(name):
		name = "pose_%s" % Combat.DIRS[facing]
	return [name, scale]
