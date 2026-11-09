class_name Wolf
extends CharacterBody2D
## Ghost wolf (หมาป่าผี). Driven by its WolfPack via step(delta, hero); numbers from Balance "wolf.*".
## States: idle (wander) | chase | bite (windup) | lunge_warn | lunge | return | dead.

signal died(wolf: Wolf)

const MANIFEST := "res://assets/wolf/manifest.json"
const HURT_POINT := Vector2(0, -14)       # at full size; hurt_point() scales it (M4d addendum 4)
const TAG_Y := -52.0                      # the elite tag over the head at full size
## M4d addendum 4 (monsters x0.85): numbers measured from the monster's own body (melee reach, lunge hit,
## ring / mist radius) are scaled with it; aggro, leash, wander, speeds, lunge distance and throw range not.
const BODY_KEYS := ["bite_range", "bite_hit_range", "lunge_hit_radius", "ring_radius", "cloud_radius"]

var level := 1
var pack: WolfPack
var home := Vector2.ZERO
var spawn_at := Vector2.INF        # M4d addendum 4: its pile spawn point (respawns there); INF = old jitter
var pile := -1                     # which pile of its pack it belongs to (-1 = the whole pack is one pile)
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
	_apply_size()
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

## M4d addendum 4: every monster (bosses too) is drawn and collides at Balance "monster_scale" (0.85).
static func size_scale() -> float:
	return Balance.num("monster_scale") if Balance.has("monster_scale") else 1.0

## Sprite, collision box (its own copy of the scene's shape) and its offset at size_scale(); the anchor
## offset is in sprite pixels, so the feet stay on the same point.
func _apply_size() -> void:
	var s := size_scale()
	body.scale = Vector2(s, s)
	if shape.shape is RectangleShape2D and not shape.has_meta("scaled"):
		var r: RectangleShape2D = shape.shape.duplicate()
		r.size *= s
		shape.shape = r
		shape.position *= s
		shape.set_meta("scaled", true)

## Width of the collision box (px) after the size scale: "1 body" for pile spacing and pushing apart.
func body_width() -> float:
	return (shape.shape as RectangleShape2D).size.x if shape and shape.shape is RectangleShape2D else 0.0

var status := StatusEffects.new()
const STATUS_FX_SCALE := 1.5
var _burn_fx: FxSprite = null
var _frost_fx: FxSprite = null
## Owner 2026-11-09 (PixelFX decision B): the monster itself is tinted while burning (red-orange) or slowed
## (ice), as well as its PixelFX overlay; both at once: frost wins (one clear colour; the burn keeps its
## flames and damage numbers). Visual only. *_AMOUNT = how far the body's colours go toward the tint (flash.gdshader).
## Owner (after f9058ce): frozen = a brighter ice so the already-blue ice wolf (this wolf) still reads frozen; review:
## burn strong enough that a pale monster reads red-orange, not salmon. Retuned for true colours (B23 fixed, owner
## 2026-11-09): frost #90ccff x 0.92 reads ice-blue on every monster, the dark boar included (not grey stone), and
## lighter than the plain monster; burn x 0.90 keeps hue 16-22 / sat >= 0.75; target brightness 0.65 + 0.8 x luma.
## The shader's numbers (TINT_BASE + TINT_GAIN x luma, outline weight OUTLINE_LO..OUTLINE_HI) are mirrored here.
const BURN_TINT := Color("#ff5a1f")
const FROST_TINT := Color("#90ccff")
const BURN_AMOUNT := 0.9
const FROST_AMOUNT := 0.92
const TINT_BASE := 0.65
const TINT_GAIN := 0.8
const OUTLINE_LO := 0.06
const OUTLINE_HI := 0.16

## CPU mirror of flash.gdshader without flash: the colour it draws for texel src under a white modulate, tinted toward
## tint by amount (amount 0 = the plain body as drawn: the texel itself, true colours since B23). Tests and
## screenshots_m5a_pixelfx (which checks the GPU result against this).
static func tint_preview(src: Color, tint: Color, amount: float) -> Color:
	var c := src
	var l := 0.299 * src.r + 0.587 * src.g + 0.114 * src.b
	var u := clampf((l - OUTLINE_LO) / (OUTLINE_HI - OUTLINE_LO), 0.0, 1.0)
	var w := amount * u * u * (3.0 - 2.0 * u)            # smoothstep: outlines (luma < OUTLINE_LO) untouched
	var k := TINT_BASE + TINT_GAIN * l
	return Color(lerpf(c.r, minf(tint.r * k, 1.0), w), lerpf(c.g, minf(tint.g * k, 1.0), w), lerpf(c.b, minf(tint.b * k, 1.0), w), c.a)

var _tint_shown := Color(0, 0, 0, 0)
## true while a burn tick's damage goes through health (test_ground shows its number but no hit spark)
var dot_tick := false

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
		_tag.position = Vector2(0, TAG_Y * size_scale())   # over the smaller head (addendum 4)
	if _tag: _tag.visible = on
	if health and is_alive(): health.setup(stats().hp)

func manifest_path() -> String:
	return MANIFEST

# ---------- hooks other monsters override (see Monster) ----------

## Whether the idle wolf starts a chase with the hero this far away.
func _wants_aggro(dist: float) -> bool:
	var walled_off := pack != null and pack.unreachable_for(self).distance_to(_hpos()) < 24.0
	var calm := pack != null and pack.calm > 0.0
	return dist <= n("aggro") and not walled_off and not calm

## The idle wolf saw the hero: its pile joins in (the whole pack when it is one pile).
func _start_aggro() -> void:
	if pack: pack.alert(_hero, self)
	else: start_chase(_hero)

## Hit while idle: its pile joins in.
func _on_provoked() -> void:
	if pack and _hero: pack.alert(_hero, self)

## States that need a live hero (otherwise go home).
func _fight_states() -> Array:
	return ["chase", "bite", "lunge_warn", "lunge"]

## States the base step does not know (flee, ring_warn, ...).
func _step_custom(_delta: float) -> void:
	pass

## Gem element effects: "burn" (damage per tick, leech fraction, source hero) or "slow". `cast` = the ComboCast of
## the press that applied it (M5b: a burn kill refunds through that press's ledger, risks.md B25).
func apply_status(kind: String, value := 0.0, leech := 0.0, source: Object = null, cast: ComboCast = null) -> void:
	if not is_alive(): return
	if kind == "burn": status.apply_burn(value, leech, source, cast)
	elif kind == "slow": status.apply_slow()

# ---------- M5b combo statuses (plan Task 4; StatusEffects has the rules) ----------

## Freezes for `secs` and locks this monster against freezes for `lock_secs`. False while frozen / locked or dead.
## Bosses and elites freeze like any monster (owner 2026-11-08: "บอสแข็งได้เหมือนมอนอื่น"). A freeze during an
## attack windup (bite, lunge warning / lunge, ring warning, hop) ends it: the warning hides, the attack never goes
## off, the monster is back to chasing, its attack cooldowns stay as they were.
func apply_freeze(secs: float, lock_secs: float, cast: ComboCast = null) -> bool:
	if not is_alive(): return false
	if not status.apply_freeze(secs, lock_secs, cast): return false
	if state in _fight_states() and state != "chase":
		_end_lunge()
		_show_telegraph(false)
		state = "chase"
		_t = 0.0
	velocity = Vector2.ZERO
	_update_status_fx()
	return true

func apply_mark(taken: float, secs: float, cast: ComboCast = null) -> void:
	if is_alive(): status.apply_mark(taken, secs, cast)

## raw_per_tick: the trail's damage per tick before DEF (the press's expected crit already in it, FireTrail); this
## monster's DEF applies as for a hit (no roll, no crit roll). leech: the leech fraction of the press that laid the
## trail (its ticks leech that, never a burn's). Called every frame for every monster in a fire line: the DEF
## factor is cached (def_factor), no Balance dictionaries per frame (Task 5 review M2).
func apply_trail(raw_per_tick: float, hold: float, source: Object = null, cast: ComboCast = null, leech := 0.0) -> void:
	if not is_alive(): return
	status.apply_trail(raw_per_tick * def_factor(), hold, source, cast, leech)

var def_builds := 0              # times the DEF factor was (re)built (tests: once per level / elite / kind)
var _df := 1.0
var _df_level := -1
var _df_elite := false
var _df_tag := ""

## 1 − DEF / (DEF + 100) of stats(), cached; rebuilt when the level, the elite flag or stats_tag() changes.
func def_factor() -> float:
	if level != _df_level or elite != _df_elite or stats_tag() != _df_tag:
		var d := float(stats().def)
		_df = 1.0 - d / (d + 100.0)
		_df_level = level
		_df_elite = elite
		_df_tag = stats_tag()
		def_builds += 1
	return _df

## What else stats() depends on besides level and elite ("" for the wolf; a Monster's kind).
func stats_tag() -> String:
	return ""

func apply_zone(slow: float, taken: float, hold: float, cast: ComboCast = null) -> void:
	if is_alive(): status.apply_zone(slow, taken, hold, cast)

func is_frozen() -> bool:
	return is_alive() and status.is_frozen()

## Slowed or frozen (frost combos: bonus / sure crit / shatter vs a chilled target).
func is_chilled() -> bool:
	return is_alive() and (status.is_slowed() or status.is_frozen())

func is_marked() -> bool:
	return is_alive() and status.is_marked()

func n(key: String) -> float:
	var v := Balance.num("wolf." + key)
	return v * size_scale() if key in BODY_KEYS else v

# ---------- queries used by the hero / arrows ----------

func is_alive() -> bool:
	return state != "dead"

func hurt_point() -> Vector2:
	return _pos() + HURT_POINT * size_scale()

## How close an arrow must pass to hurt_point() to hit: shot.arrow_hit_radius on the smaller body (addendum 4).
func hurt_radius() -> float:
	return Balance.num("shot.arrow_hit_radius") * size_scale()

func telegraph_visible() -> bool:
	return _telegraph != null and _telegraph.visible

# ---------- events ----------

## Hit by the hero. Returns damage dealt (0 when dead). Knockback, except during the bite windup, on elites and
## while frozen (owner 2026-11-09: a frozen monster is not knocked back, "ไม่กระเด็น ติดอยู่กับที่").
func receive_hit(atk: float, mult: float, from: Vector2, crit_chance := -1.0, crit_mult := -1.0) -> int:
	if not is_alive(): return 0
	var r := Combat.roll_damage(atk, mult * status.taken_mult(), stats().def, true, crit_chance, crit_mult)   # mark / zone
	var lands := not health.is_dead() and not health.is_invulnerable()
	if lands: Sfx.play("crit_hit" if r.crit else "arrow_hit", _pos())
	health.take_hit(r.amount, r.crit)              # a killing hit cries "die" in _on_died
	if lands and is_alive(): Sfx.play_monster(sound_kind(), "hurt")
	if not is_alive(): return r.amount
	_flash = n("hit_flash")
	if state != "bite" and not elite and not status.is_frozen():   # elites do not get knocked back (M3h)
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
	# M4d addendum 4: a piled monster comes back on its own spawn point (open ground, apart from its pile)
	if spawn_at != Vector2.INF: _set_pos(spawn_at)
	else: _set_pos(home + Vector2(randf_range(-16, 16), randf_range(-12, 12)))
	state = "idle"
	_t = 0.0
	_bite_cd = 0.0
	_lunge_cd = 0.0
	visible = true
	body.modulate.a = 1.0
	if is_inside_tree(): shape.set_deferred("disabled", false)
	else: shape.disabled = false
	_refresh(true)

## Task 4 (M4c §1: walking between rooms keeps every room as you left it): what RoomReset keeps of this monster
## when the hero leaves its room. alive, where it stood, elite, and whether it was busy (anything but idle:
## chasing, attacking, fleeing, walking home). HP, statuses and cooldowns are not kept (restore_kept).
func kept_state() -> Dictionary:
	return {"alive": is_alive(), "pos": _pos(), "elite": elite, "busy": is_alive() and state != "idle"}

## Task 4: back in a kept room. A dead monster stays dead, unseen, with no death cry, loot or EXP (its pack
## restores its respawn time). A living one stands where it was with its elite mark; HP back to full and
## statuses cleared, as when it loses the hero now (_go_home heals); one that was busy walks home ("return"),
## as a fighting monster does now once the hero is gone.
func restore_kept(st: Dictionary) -> void:
	if not bool(st.get("alive", true)):
		_end_lunge()
		status.clear()
		_update_status_fx()
		set_elite(bool(st.get("elite", false)))
		health.hp = 0
		state = "dead"
		_t = 0.0
		velocity = Vector2.ZERO
		visible = false
		body.modulate.a = 0.0
		if is_inside_tree(): shape.set_deferred("disabled", true)
		else: shape.disabled = true
		_refresh(true)
		return
	revive()                              # full HP, statuses and cooldowns cleared, idle on its spawn point
	set_elite(bool(st.get("elite", false)))
	_set_pos(st.pos)
	if bool(st.get("busy", false)) and _pos().distance_to(home) >= 4.0:
		state = "return"
		_t = 0.0
		_refresh(true)

## Flames / frost round the body while burning / slowed (Task 3f: PixelFX burning / frozen with the body cut out,
## drawn at STATUS_FX_SCALE like the PixelLab strips they replaced).
## Task 3f review: under the PerfSaver (PerfSaver.active) the overlays are shed, the tint stays.
func _update_status_fx() -> void:
	_apply_tint(status_tint())
	if not is_inside_tree(): return
	var shed := PerfSaver.active
	_burn_fx = _toggle_fx(_burn_fx, "status_burn", status.is_burning() and is_alive() and not (shed and PerfSaver.decorative("status_burn")))
	_frost_fx = _toggle_fx(_frost_fx, "status_frost", is_chilled() and not (shed and PerfSaver.decorative("status_frost")))

## The body's status tint now: frost (slowed or frozen), else burn, else none; alpha = its tint amount (0 = none).
## Dead monsters are never tinted.
func status_tint() -> Color:
	if not is_alive(): return Color(0, 0, 0, 0)
	if status.is_slowed() or status.is_frozen(): return Color(FROST_TINT, FROST_AMOUNT)
	if status.is_burning(): return Color(BURN_TINT, BURN_AMOUNT)
	return Color(0, 0, 0, 0)

func _apply_tint(c: Color) -> void:
	if c == _tint_shown or body == null or not (body.material is ShaderMaterial): return   # only when it changes
	_tint_shown = c
	body.material.set_shader_parameter("tint_color", Color(c.r, c.g, c.b))
	body.material.set_shader_parameter("tint_amount", c.a)

func _toggle_fx(fx: FxSprite, fx_name: String, on: bool) -> FxSprite:
	if on and fx == null:
		fx = FxSprite.make(fx_name, true)
		fx.scale = Vector2.ONE * STATUS_FX_SCALE * size_scale()   # drawn small; match the (scaled) body
		add_child(fx)
		fx.play(fx_name)
	elif not on and fx != null:
		fx.queue_free()
		fx = null
	return fx

## Sound spec (receive_hit): an arrow hit plays arrow_hit, a critical crit_hit instead; the monster cries
## "hurt", or, on the killing hit, only its "die" cry (_on_died). Burn ticks are not hits: no hit sound, but a
## burn kill still cries "die". The kind whose cries this monster uses (assets/audio/monsters/<kind>_*).
func sound_kind() -> String:
	var k = get("kind")
	return String(k) if k != null else "wolf"

func _on_died() -> void:
	status.clear()
	_update_status_fx()
	_end_lunge()
	state = "dead"
	_t = 0.0
	velocity = Vector2.ZERO
	if is_inside_tree(): shape.set_deferred("disabled", true)
	else: shape.disabled = true
	Sfx.play_monster(sound_kind(), "die")
	died.emit(self)
	_refresh(true)

# ---------- simulation ----------

## Status timers and the burn / fire-trail damage (a DoT tick: dot_tick is set while it goes through health, so the
## test ground shows its number without a hit spark). Leech (review I1): the burn's part with the burn's leech to the
## burn's source, the trail's part with the trail's own leech to its source; read before the damage, as a killing
## tick clears the statuses. A part under one whole HP (kept in the status's carry for a later tick) still leeches
## its share (Task 4 review), so the heal is leech × the damage the DoT deals over time, not only the ticks that
## round up. status.tick_cast is the ledger a kill by this tick belongs to (M5b Task 8 hook). Nothing is allocated.
func tick_burn(delta: float) -> void:
	var burn := status.tick(delta)
	if status.last_burn_dmg <= 0.0 and status.last_trail_dmg <= 0.0: return
	var bs: Object = status.last_burn_source
	var bh := status.last_burn_dmg * status.last_burn_leech
	var ts: Object = status.last_trail_source
	var th := status.last_trail_dmg * status.last_trail_leech
	if burn > 0:
		dot_tick = true
		health.take_hit(burn, false)
		dot_tick = false
	leech_to(bs, bh)
	leech_to(ts, th)

## Heals `source` (the hero) by `amount` through its leech_heal (fractions carried there); nothing for none / 0.
static func leech_to(source: Object, amount: float) -> void:
	if amount > 0.0 and is_instance_valid(source) and source.has_method("leech_heal"): source.leech_heal(amount)

func step(delta: float, hero: Hero) -> void:
	if hero != null: _hero = hero
	health.tick(delta)
	if is_alive():
		tick_burn(delta)
		if not is_alive(): return
	_update_status_fx()
	_flash = maxf(0.0, _flash - delta)
	_bite_cd = maxf(0.0, _bite_cd - delta)
	_lunge_cd = maxf(0.0, _lunge_cd - delta)
	if status.is_frozen() and is_alive():
		_hold_frozen()            # M5b freeze: no move, no attack, no state change; cooldowns above still run
		return
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

## One frozen step: stands still with its body paused on the current frame (the hit flash still shows).
func _hold_frozen() -> void:
	velocity = Vector2.ZERO
	_wanted_move = false
	_stuck_t = 0.0
	_stuck_from = _pos()
	if body.is_playing(): body.pause()
	_refresh_flash()

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
		if pack: pack.mark_unreachable(self, _hpos())
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

## Every push (hit knockback, the crowd's separation) stops here while frozen: a frozen monster stays put.
func _push(v: Vector2) -> void:
	if status.is_frozen(): return
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
	_refresh_flash()

func _refresh_flash() -> void:
	var fl := 0.85 if _flash > 0.0 else 0.0
	if body.material and fl != _flash_shown:          # only when it changes (M3k)
		_flash_shown = fl
		body.material.set_shader_parameter("flash_amount", fl)
