class_name FireTrail
extends Node2D
## The fire line of ศรพัดเพลิง / พัดเพลิงพรหมาสตร์ (M5b plan Task 5, spec 2026-11-08-gem-combos.md §1/§2): a primary
## arrow lays one from where it was shot, grows it as it flies (extend_to) and, when it is spent, leaves it burning
## for trail_secs (finish), then it ends and frees itself. Every step, each live target whose hurt point is within
## its hurt_radius (else shot.arrow_hit_radius, Global Constraints) of the line gets apply_trail(per_tick, HOLD, ...):
## per_tick = trail_frac × the arrow's hit (atk × mult), credited to the press that laid it (its ComboCast) with that
## press's own leech (Task 4 review I1). StatusEffects keeps the highest per_tick on one clock, so overlapping lines
## (3 split lines, back-to-back presses) burn once a second at most; a monster standing in one trail gets exactly
## round(trail_secs) ticks, as simulated (risks.md B26).
## Never saved, never outlives its room: halt() (the warp's dark, Arrow.halt, TestGround) ends it at once (B20).
## Performance (risks.md B26): the look is at most MAX_STREAKS reused piercing_trail streaks (tinted, one per SPACING px
## as the line grows, not one per frame) + a flame (status_burn, decorative: shed by the PerfSaver) on every
## FLAME_EVERY-th mark, so MAX_FX effects per trail; step() allocates nothing. The damage never depends on the effects.

const HOLD := 0.25                 # what one step re-applies (StatusEffects: hold + flight past < 1 tick)
const SPACING := 44.0              # px between streak marks (piercing_trail is 60 px from tail to head)
const MAX_STREAKS := 6             # 6 × 44 = 264 px ≥ any arrow skill's range today (220)
const FLAME_EVERY := 2
const MAX_FX := MAX_STREAKS + MAX_STREAKS / FLAME_EVERY
const FADE := 0.3                  # s: the look fades out over the last FADE s
const Z := -5                      # on the ground: over the map (-10) and exit rings (-9), under everyone (like hazard clouds)

static var made := 0               # trails set up so far (tests: secondary hits lay none)

var from := Vector2.ZERO           # in the targets' space (global in a tree)
var to := Vector2.ZERO
var per_tick := 0.0
var secs := 0.0
var left := 0.0                    # s of burning left after finish()
var targets: Array = []
var source: Object = null
var cast: ComboCast = null
var leech := 0.0
var combo_id := ""
var finished := false
var done := false
var _dir := Vector2.ZERO
var _marks := 0
var _radius := 10.0

## from_p: where the line starts; atk × mult = the arrow's hit; frac / secs_: the recipe's trail_frac / trail_secs;
## targets_: the arrow's targets; source_: the shooter (leech); cast_ / leech_: the press's ledger and leech;
## combo: the recipe id (its "trail" effects).
func setup(from_p: Vector2, atk: float, mult: float, frac: float, secs_: float, targets_: Array, source_: Object,
		cast_: ComboCast = null, leech_ := 0.0, combo := "") -> void:
	from = from_p
	to = from_p
	per_tick = frac * atk * mult
	secs = secs_
	targets = targets_
	source = source_
	cast = cast_
	leech = leech_
	combo_id = combo
	z_index = Z
	_radius = Balance.num("shot.arrow_hit_radius")
	made += 1

## The line now ends at p (the arrow's position). Lays a streak at each new SPACING mark, up to MAX_STREAKS.
func extend_to(p: Vector2) -> void:
	if finished: return
	to = p
	var length := from.distance_to(to)
	if length < 0.001: return
	if _dir == Vector2.ZERO: _dir = (to - from) / length
	while _marks < MAX_STREAKS and length >= SPACING * (_marks + 1):
		_mark(from + _dir * SPACING * (_marks + 1))

func _mark(p: Vector2) -> void:
	# flames on marks 1, 3, 5 (88, 176, 264 px): the split lines are still close together at the first mark, where
	# three flames would stack into one column by the hero (seen in docs/preview/m5b/fire_fan_ingame.png)
	ComboFx.play(self, combo_id, "trail", to_local(p) if is_inside_tree() else p, _dir, _marks % FLAME_EVERY == FLAME_EVERY - 1)
	_marks += 1

## The arrow is spent: the line stops growing and burns on for `secs`. A line too short for a mark gets one at its
## end, so the fire is never invisible.
func finish() -> void:
	if finished: return
	finished = true
	left = secs
	if _marks == 0 and from.distance_to(to) > 0.5:
		if _dir == Vector2.ZERO: _dir = (to - from).normalized()
		_mark(to)
	if secs <= 0.0: _end()

## Burns whatever stands on the line; counts down after finish(). Callable without a tree (tests).
func step(delta: float) -> void:
	if done: return
	if finished:
		left -= delta
		if left <= 1e-6:
			_end()
			return
		if left < FADE: modulate.a = left / FADE
	for t in targets:
		if not is_instance_valid(t) or not t.is_alive() or not t.has_method("apply_trail"): continue
		var hp: Vector2 = t.hurt_point()
		var r: float = t.hurt_radius() if t.has_method("hurt_radius") else _radius
		if Geometry2D.get_closest_point_to_segment(hp, from, to).distance_squared_to(hp) <= r * r:
			t.apply_trail(per_tick, HOLD, source, cast, leech)

## Ends it now (the warp, a room change): no further damage.
func halt() -> void:
	_end()

func _end() -> void:
	done = true
	finished = true
	targets = []
	if is_inside_tree(): queue_free()

func _physics_process(delta: float) -> void:
	step(delta)
