class_name FireTrail
extends Node2D
## The fire line of ศรพัดเพลิง / พัดเพลิงพรหมาสตร์ (M5b plan Task 5, spec 2026-11-08-gem-combos.md §1/§2): a primary
## arrow lays one from where it was shot, grows it as it flies (extend_to) and, when it is spent, leaves it burning
## for trail_secs (finish), then it ends and frees itself. Every step, each live target whose hurt point is within
## its hurt_radius (else shot.arrow_hit_radius, Global Constraints) of the line gets apply_trail(per_tick, HOLD, ...):
## per_tick = trail_frac × the arrow's hit (atk × mult) × the press's expected crit factor (Combat.expected_crit: no
## per-tick roll, as tools/gem_combo_sim.py; Task 5 review I3), credited to the press that laid it (its ComboCast)
## with that press's own leech (Task 4 review I1).
## The line is the path the arrow really flew (Task 5 review I1: a homing arrow curves): every SPACING px of path a
## point is recorded (at most MAX_STREAKS, in a PackedVector2Array allocated once in setup) and a mark is laid there;
## the fire is the polyline from → points → to (the arrow's position). Past the last point the line is the chord to
## `to` (only for a path longer than MAX_STREAKS × SPACING = 264 px; the longest arrow range in balance.json, shot.range
## and every skills.*.range, is 220 px today: tests/test_arrow_combos.gd test_trail_marks_cover_the_longest_range). StatusEffects keeps the highest per_tick on one clock, so overlapping lines
## (3 split lines, back-to-back presses) burn once a second at most; a monster standing in one trail gets exactly
## round(trail_secs) ticks, as simulated (risks.md B26).
## Never saved, never outlives its room: halt() (the warp's dark, Arrow.halt, TestGround) ends it at once (B20).
## Look (owner 2026-11-09, sample T2 in /home/claude/fx_samples/trail_candidates.png): one fire_trail patch (PixelFX
## fire/campfire, logs cut, assets/fx/pfx_fire_trail.png, 45 f @ 15 fps loop) on every mark, i.e. one per SPACING px of
## path as the line grows (not one per frame), so at most MAX_FX = MAX_STREAKS effects per trail. Each patch starts its
## loop at its own frame (patch_frame: PHASE frames on from its neighbour, ± JITTER, from a hash of the line's first mark:
## random-looking but the same every run), so the line never flickers in sync; the whole line fades out over the last
## FADE s. PerfSaver: the patches are the hazard the player reads (one per SPACING px segment), so the saver keeps every
## one of them (fire_trail is not PerfSaver.DECORATIVE); the glow is baked into the sheet (no extra node to shed).
## Performance (risks.md B26): the patches share one cached SpriteFrames (FxSprite); step() allocates nothing. The
## damage never depends on the effects.
## Task 5 review 2: each trail keeps the bounding box of its path (_lo / _hi, grown as extend_to goes; a finished trail
## no longer moves), and a target farther than its hit radius outside that box is skipped before any segment check.

const HOLD := 0.25                 # what one step re-applies (StatusEffects: hold + flight past < 1 tick)
const SPACING := 44.0              # px between marks (a fire_trail patch is 44 px wide: the patches touch)
const MAX_STREAKS := 6             # 6 × 44 = 264 px ≥ the longest arrow range in balance.json (220; tested)
const MAX_FX := MAX_STREAKS        # one patch per mark
const PHASE := 7                   # frames between neighbouring patches' loops (as the owner's sample)
const JITTER := 2                  # ± frames on top, per patch (deterministic): neighbours differ by 3..11 of 45
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
var _pts := PackedVector2Array()  # the recorded path points (marks), MAX_STREAKS slots, _n used
var _n := 0
var _path := 0.0                   # px of path flown so far
var _last := Vector2.ZERO          # the previous extend_to point
var _radius := 10.0
var _lo := Vector2.ZERO            # the path's bounding box (from, every extend_to point): _near's early exit
var _hi := Vector2.ZERO
var seg_checks := 0                # segment distance checks so far (tests: a far target costs none)
var _seed := 0                     # from the first mark's position: each line's patches start at their own frames

## from_p: where the line starts; atk × mult = the arrow's hit; frac / secs_: the recipe's trail_frac / trail_secs;
## targets_: the arrow's targets; source_: the shooter (leech); cast_ / leech_: the press's ledger and leech;
## combo: the recipe id (its "trail" effects); crit_factor: the press's expected crit factor (Combat.expected_crit).
func setup(from_p: Vector2, atk: float, mult: float, frac: float, secs_: float, targets_: Array, source_: Object,
		cast_: ComboCast = null, leech_ := 0.0, combo := "", crit_factor := 1.0) -> void:
	from = from_p
	to = from_p
	_last = from_p
	_lo = from_p
	_hi = from_p
	_pts.resize(MAX_STREAKS)
	_n = 0
	_path = 0.0
	per_tick = frac * atk * mult * crit_factor
	secs = secs_
	targets = targets_
	source = source_
	cast = cast_
	leech = leech_
	combo_id = combo
	z_index = Z
	_radius = Balance.num("shot.arrow_hit_radius")
	made += 1

## The arrow is now at p: the line follows it. Each time the path flown passes another SPACING px, the point on the
## path there is recorded and gets a fire patch, up to MAX_STREAKS. Allocates nothing but the effects.
func extend_to(p: Vector2) -> void:
	if finished: return
	to = p
	_lo = _lo.min(p)                   # the path between extend_to points is straight, so these bound it all
	_hi = _hi.max(p)
	var seg := _last.distance_to(p)
	if seg < 0.001: return
	var d := (p - _last) / seg
	_dir = d
	while _n < MAX_STREAKS and _path + seg >= SPACING * (_n + 1):
		var at := _last + d * (SPACING * (_n + 1) - _path)
		_pts[_n] = at
		_mark(at, d, _n)
		_n += 1
	_path += seg
	_last = p

## Recorded path points so far (tests).
func points() -> PackedVector2Array:
	return _pts.slice(0, _n)

func _mark(p: Vector2, d: Vector2, i: int) -> void:
	if i == 0: _seed = hash(Vector2i(p.round()))
	for s in ComboFx.play(self, combo_id, "trail", to_local(p) if is_inside_tree() else p, d):
		var n: int = s.sprite_frames.get_frame_count(s.animation)
		if s.sprite_frames.get_animation_loop(s.animation) and n > 1:
			s.set_frame_and_progress(patch_frame(_seed, i, n), 0.0)

## The frame patch i of a line (seed: its first mark) starts its n-frame loop on: PHASE frames on from patch i - 1,
## ± JITTER from a hash of (seed, i). Deterministic; neighbours are 3..11 frames apart (never in step).
static func patch_frame(seed: int, i: int, n: int) -> int:
	var j := posmod(hash(Vector2i(seed, i)), 2 * JITTER + 1) - JITTER
	return posmod(posmod(seed, n) + i * PHASE + j, n)

## The arrow is spent: the line stops growing and burns on for `secs`. A line too short for a mark gets a patch at
## its end, so the fire is never invisible.
func finish() -> void:
	if finished: return
	finished = true
	left = secs
	if _n == 0 and from.distance_to(to) > 0.5:
		if _dir == Vector2.ZERO: _dir = (to - from).normalized()
		_mark(to, _dir, 0)
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
		if _near(hp, r): t.apply_trail(per_tick, HOLD, source, cast, leech)

## True when p is within r of the polyline from → recorded points → to. Outside the path's box grown by r: false at
## once (no segment checks).
func _near(p: Vector2, r: float) -> bool:
	if p.x < _lo.x - r or p.x > _hi.x + r or p.y < _lo.y - r or p.y > _hi.y + r: return false
	var r2 := r * r
	var a := from
	seg_checks += _n + 1
	for i in _n:
		if Geometry2D.get_closest_point_to_segment(p, a, _pts[i]).distance_squared_to(p) <= r2: return true
		a = _pts[i]
	return Geometry2D.get_closest_point_to_segment(p, a, to).distance_squared_to(p) <= r2

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
