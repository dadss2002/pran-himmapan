class_name ArrowRain
extends Node2D
## ห่าศร (M5b Task 8b; docs/skills.md row ห่าศร approved 2026-11-06, combos spec D2 / D6): a circle on the ground at
## `center` (the feet of the monster the press locked on to, else the hero's feet: Hero.area_point) that hits every
## live monster whose FEET are within `radius` (64 px, × the expand gem) once at each tick_every mark (0.5, 1.0, ...
## for `ticks` whole ticks: 6 in 3 s, 7 in the extend gem's 3.9 s), each for the build's tick damage (40 % × skill
## level × gems) through SkillHit.hit: a primary hit of the press (crit roll, leech, the element gem's status, kills
## to the press's ledger). No hit before the first mark: the half second is the warning. After the last tick it deals
## nothing more (`done`), fades for FADE s and frees itself.
## Never saved, never outlives its room or its hero: halt() (Hero.halt_areas: warp, death; TestGround.go_to) ends it
## at once (risks.md B20).
## Look (0 gen, AI decisions in docs/ai-decisions.md): on the ground (Z, under everyone) the REAL hit circle (thin
## gold outline on a dark line + faint fill, drawn: what is inside it is hit, nothing outside it is) round the yantra
## (warp_ring recoloured #edbb55 by brightness, at an even scale just inside the circle: ring_scale); above everyone,
## ARROWS_PER_TICK arrows of the basic arrow picture per tick fall FALL_PX px with a short streak and stick for a moment. One sound / one chain_zap per tick (SkillHit); the hit sparks are the
## monsters' own (TestGround._on_wolf_hit).
## PerfSaver: the falling arrows are decoration and are not drawn while the saver is on; the circle and the yantra
## are the area marker the player aims and reads, so they are NEVER shed.
## Performance: one node + one sprite + one drawing child per rain; step() and _draw allocate nothing; a tick is one
## distance check per monster. Two rains of one hero never overlap (longest 4.47 s < the shortest cooldown 7 s).

const GOLD := Color("#edbb55")
const Z := -5                      # on the ground, as FireTrail / hazard clouds
const SKY_Z := 35                  # the falling arrows: over every monster, under the hit effects (40)
const FADE := 0.3                  # s the marker takes to fade after the last tick
const ARROWS_PER_TICK := 6         # AI decision (docs/ai-decisions.md): the plan's 3 read as stray sticks, not a rain
const EDGE_DARK := Color("#2c1c08")   # under the gold edge, so the circle also reads on light grass
const FALL_PX := 48.0
const FALL_SECS := 0.2
const STICK_SECS := 0.22           # an arrow stays in the ground this long, fading
const TILT := 1.75                 # rad: the arrows fall a little slanted (art points east; PI / 2 = straight down)
const ARROW_TEX := "res://assets/items/arrow_basic.png"
const ARROW_TIP := Vector2(44, 24) # the arrowhead's tip in the 48 px picture
const ARROW_SCALE := 0.8           # a little larger than a shot arrow (0.6): they must read from the sky
const STREAK := Color(1.0, 0.93, 0.7, 0.55)    # the short line a falling arrow leaves behind it
const STREAK_PX := 14.0
const RING_FX := "warp_ring"

static var made := 0               # rains set up so far (tests)
static var _tex: Texture2D = null

var center := Vector2.ZERO         # in the targets' space (global in a tree)
var radius := 0.0
var tick_every := 0.5
var ticks := 0
var mult := 0.0                    # one tick's damage multiplier (ราหู's bonus folded in by Hero.hit_source)
var src := {}
var targets: Array = []
var ticks_done := 0
var hits_done := 0                 # monster hits dealt so far (tests)
var done := false                  # no further tick (ended or halted)
var _t := 0.0
var _fade := 0.0
var _seed := 0
var _ring: FxSprite = null
var _sky: Node2D = null

## center_: where it falls; b: the press's build (SkillBuild.of kind "rain": radius, tick_every, ticks, arrow_mult);
## src_: Hero.hit_source(b); targets_: the monsters it can hit.
func setup(center_: Vector2, b: Dictionary, src_: Dictionary, targets_: Array) -> void:
	center = center_
	position = center_
	radius = float(b.radius)
	tick_every = maxf(0.01, float(b.tick_every))
	ticks = int(b.ticks)
	mult = float(src_.get("mult", b.arrow_mult))
	src = src_
	targets = targets_
	z_index = Z
	made += 1
	_seed = hash(Vector2i(center_.round())) ^ made

func _ready() -> void:
	global_position = center
	src["fx_parent"] = get_parent()
	_ring = FxSprite.make(RING_FX, true)
	ComboFx.recolor(_ring, GOLD)
	_ring.scale = Vector2.ONE * ring_scale(radius, _ring._cell.x)
	add_child(_ring)
	_ring.play(RING_FX)
	_sky = RainSky.new()
	_sky.rain = self
	_sky.z_as_relative = false
	_sky.z_index = SKY_Z
	add_child(_sky)

## Advances the rain; callable without a tree (tests). Every tick_every mark passed deals one tick.
func step(delta: float) -> void:
	if done:
		if _fade > 0.0:
			_fade -= delta
			modulate.a = clampf(_fade / FADE, 0.0, 1.0)
			if _fade <= 0.0 and is_inside_tree(): queue_free()
		return
	_t += delta
	while not done and ticks_done < ticks and _t >= tick_every * (ticks_done + 1) - 1e-6:
		_tick()
	if not done and ticks_done >= ticks: _end(true)
	if _sky != null: _sky.queue_redraw()

func _tick() -> void:
	ticks_done += 1
	src["quiet"] = false           # one hit sound and one chain_zap per tick (SkillHit)
	src["zapped"] = false
	var r2 := radius * radius
	for t in targets:
		if done: return            # a hit that ended the rain (the hero died / warped inside a kill's callback)
		if not is_instance_valid(t) or not t.is_alive(): continue
		if SkillHit.feet(t).distance_squared_to(center) > r2: continue
		if SkillHit.hit(t, src, mult, center) > 0: hits_done += 1

## Seconds since the cast (tests, screenshots).
func time() -> float:
	return _t

## Ends it now (warp, room change, the hero's death): no further tick, no fade.
func halt() -> void:
	_end(false)
	if is_inside_tree(): queue_free()

func _end(fade: bool) -> void:
	done = true
	targets = []
	_fade = FADE if fade and is_inside_tree() else 0.0

func _physics_process(delta: float) -> void:
	step(delta)

## The yantra's scale for a circle of `radius`: as wide as the circle, rounded DOWN to a half step (r64: × 2.0 = 116 px
## of the 128; r83.2 with the expand gem: × 2.5) so its pixels stay even; it never reaches past the real edge.
static func ring_scale(radius_px: float, cell_w: float) -> float:
	return maxf(0.5, floorf(2.0 * radius_px / maxf(1.0, cell_w) * 2.0) / 2.0)

## The real hit circle: everything the rain can hit has its feet inside it. A dark line under the gold one keeps the
## edge readable on light and on dark ground.
func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, Color(GOLD, 0.14))
	draw_arc(Vector2.ZERO, radius - 1.0, 0.0, TAU, 96, Color(EDGE_DARK, 0.75), 3.0, false)
	draw_arc(Vector2.ZERO, radius - 1.0, 0.0, TAU, 96, GOLD, 1.0, false)

## Where arrow j of tick k lands (local), inside the circle; the same every frame (from the rain's seed).
func _land(k: int, j: int) -> Vector2:
	var h := hash(Vector3i(_seed, k, j))
	var a := float(h & 0xffff) / 65536.0 * TAU
	var d := sqrt(float((h >> 16) & 0xffff) / 65536.0) * radius * 0.85
	return Vector2(cos(a), sin(a)) * d

## How many arrows _draw_sky draws right now (tests; 0 while the PerfSaver is on).
func arrows_now() -> int:
	if PerfSaver.active or done: return 0
	var n := 0
	for k in range(maxi(0, ticks_done - 1), mini(ticks, ticks_done + 2)):
		for j in ARROWS_PER_TICK:
			var dt := _t - (tick_every * (k + 1) - tick_every * j / ARROWS_PER_TICK)
			if dt >= -FALL_SECS and dt <= STICK_SECS: n += 1
	return n

## Draws the falling / stuck arrows of the ticks around now. Arrow j of tick k lands j thirds of a tick before the
## tick's mark, so the arrows keep coming between ticks. Nothing while the PerfSaver is on (decoration).
func _draw_sky(ci: CanvasItem) -> void:
	if PerfSaver.active or done: return
	if _tex == null: _tex = load(ARROW_TEX)
	var dir := Vector2.from_angle(TILT)
	for k in range(maxi(0, ticks_done - 1), mini(ticks, ticks_done + 2)):
		for j in ARROWS_PER_TICK:
			var lands := tick_every * (k + 1) - tick_every * j / ARROWS_PER_TICK
			var dt := _t - lands
			if dt < -FALL_SECS or dt > STICK_SECS: continue
			var p := _land(k, j)
			var alpha := 1.0
			if dt < 0.0:
				p += dir * (FALL_PX * dt / FALL_SECS)          # still in the air, FALL_PX back along its flight
				alpha = clampf((dt + FALL_SECS) / (FALL_SECS * 0.4), 0.0, 1.0)
				ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				ci.draw_line(p - dir * (ARROW_TIP.x - 4.0) * ARROW_SCALE, p - dir * ((ARROW_TIP.x - 4.0) * ARROW_SCALE + STREAK_PX), Color(STREAK, STREAK.a * alpha), 1.0)
			else:
				alpha = 1.0 - dt / STICK_SECS
			ci.draw_set_transform(p, TILT, Vector2(ARROW_SCALE, ARROW_SCALE))
			ci.draw_texture(_tex, -ARROW_TIP, Color(1, 1, 1, alpha))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

class RainSky extends Node2D:
	var rain: ArrowRain
	func _draw() -> void:
		if rain != null: rain._draw_sky(self)
