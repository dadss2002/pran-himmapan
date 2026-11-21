class_name ThornTrap
extends Node2D
## กับดักหนาม (M5b Task 8c; docs/skills.md row กับดักหนาม approved 2026-11-06, combos spec D2 / D3 / D4 / D6): a trap on
## the ground at `at` (the feet of the monster the press locked on to within 160 px, else the hero's feet:
## Hero.area_point). D4: it waits with NO time limit until a live monster's FEET are within trigger_radius (16 px, ×
## the expand gem). D3: a monster already rooted is ignored (it neither springs the trap nor is hit). Then it fires
## ONCE, on that step: every live, unrooted monster standing in it is rooted for root_secs (2 s, × the extend gem) and
## takes one hit of the build's damage (150 % × skill level × gems) through SkillHit.hit: a primary hit of the press
## (crit roll, leech, the element gem's status, kills to the press's ledger). The root goes on first, so the trap's
## own hit does not knock the monster off it. After that it is spent: it stays closed under the monster for root_secs
## (Task 9: that circle is the zone), fades for FADE s and frees itself.
## AI decision 21 (as the rain): the hit uses the PRESS's numbers (ATK, crit, ราหู's bonus, gems: src, built once by
## Hero.hit_source), however long the trap waited. The press's ledger (src.cast) holds no kill until this trap's first
## damage, and all its hits land on one step, so its damage window starts at the trigger
## (test_respawn_outlasts_every_dot_window).
## The monsters are read LIVE: in a tree the "enemies" group every step (a monster that joins the room after the press
## springs it, and the lightning gem's chain reaches it); outside a tree (tests) the array it was given.
## Never saved, never outlives its room or its hero: halt() (Hero.halt_areas: warp, death; TestGround.go_to) ends it
## at once, also from inside its own trigger (src.halted: SkillHit deals nothing more).
## Look (the owner's pick C3, assets/props/thorn_trap.png, top view, drawn 1:1; else a drawn placeholder): in the
## world's Y-sort, sorted by its BACK edge (SORT_BACK above `at`), so whoever stands on it is drawn over it and it
## still sorts against trees and rocks. Armed: the open ring. Sprung: a burst (spread_burst, brown) and the ring
## pulled tight and dark round the feet for the length of the root. With the expand gem a thin ring shows the wider
## reach. It is the marker of where the trap is: nothing of it is ever shed by the frame-rate saver.
## Performance: one node + one sprite per trap, at most 2 armed per hero (TrapSet) + the sprung ones (≤ root_secs
## each); a step is one distance check per monster and, in a tree, one read of the "enemies" group.
## Client-side only (risks.md S1): online play needs the server to place traps and deal their hits.

const BROWN := Color("#8a6a3a")
const BURST_FX := "spread_burst"
const FADE := 0.3                  # s the closed trap takes to fade after the root
const SORT_BACK := 22.0            # px from the centre to the back edge of the 44 px ring: the Y-sort line
const SNAP := 0.12                 # s the ring takes to pull tight
const SHUT_SCALE := 0.85           # the sprung ring, pulled in round the feet (0.75 hid under the lock-on ring: screenshots)
const SHUT_TINT := Color(1.0, 0.78, 0.55)
const EDGE_DARK := Color("#2c1c08")
const FX_Z := 40                   # the trigger burst: with the hit effects, over everyone

## Where the ground sprite is looked for, in order (plan: placeholder-tolerant). A static var so a test can point it
## at nothing (then forget_art()).
static var art_paths: Array = ["res://assets/props/thorn_trap.png", "res://assets/fx/thorn_trap.png"]
static var made := 0               # traps set up so far (tests)
static var _tex: Texture2D = null
static var _looked := false

var at := Vector2.ZERO             # in the monsters' space (global in a tree)
var trigger_radius := 0.0
var base_radius := 0.0             # the radius without gems (the ring is only drawn when it is wider)
var root_secs := 0.0
var mult := 0.0                    # the hit's multiplier (ราหู's bonus folded in by Hero.hit_source)
var src := {}
var targets: Array = []
var armed := false                 # waiting to be stepped on
var spent := false                 # it has fired; closed for root_secs
var done := false                  # over (faded out or halted)
var caught: Array = []             # the monsters it fired on
var hits_done := 0                 # hits that dealt damage (tests)
var placeholder := false           # no art found: drawn
var _spent_t := 0.0
var _sprite: Sprite2D = null

## at_: where it lies; b: the press's build (SkillBuild.of kind "trap": trigger_radius, root_secs, arrow_mult);
## src_: Hero.hit_source(b); targets_: the monsters that can step on it (read live: see above).
func setup(at_: Vector2, b: Dictionary, src_: Dictionary, targets_: Array) -> void:
	at = at_
	position = at_ + Vector2(0, -SORT_BACK)
	trigger_radius = float(b.trigger_radius)
	base_radius = trigger_radius / maxf(0.01, float(b.get("area_mult", 1.0)))
	root_secs = float(b.root_secs)
	mult = float(src_.get("mult", b.arrow_mult))
	src = src_
	targets = targets_
	armed = true
	made += 1

## Forgets the looked-up sprite (tests that change art_paths).
static func forget_art() -> void:
	_tex = null
	_looked = false

static func art() -> Texture2D:
	if not _looked:
		_looked = true
		_tex = null
		for p in art_paths:
			if ResourceLoader.exists(p):
				_tex = load(p)
				break
	return _tex

func _ready() -> void:
	global_position = at + Vector2(0, -SORT_BACK)
	src["fx_parent"] = get_parent()
	var tex := art()
	placeholder = tex == null
	if tex != null:
		_sprite = Sprite2D.new()
		_sprite.texture = tex
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_sprite.position = Vector2(0, SORT_BACK)
		add_child(_sprite)
	_look()

func _physics_process(delta: float) -> void:
	step(delta)

## Advances the trap; callable without a tree (tests).
func step(delta: float) -> void:
	if done: return
	if armed:
		if is_inside_tree():
			targets = get_tree().get_nodes_in_group("enemies")     # live: monsters that joined the room since
			src["targets"] = targets
		var r2 := trigger_radius * trigger_radius
		for t in targets:
			if _steps_on(t, r2):
				_spring(r2)
				break
		return
	_spent_t += delta
	_look()
	if _spent_t >= root_secs + FADE:
		done = true
		targets = []
		if is_inside_tree(): queue_free()

## t is a live monster, not already rooted (D3), with its feet in the trap.
func _steps_on(t, r2: float) -> bool:
	if not is_instance_valid(t) or not t.is_alive(): return false
	if t.has_method("is_rooted") and t.is_rooted(): return false
	return SkillHit.feet(t).distance_squared_to(at) <= r2

## Fires once: everything standing in it now. The ONE place a trap deals damage.
func _spring(r2: float) -> void:
	armed = false
	spent = true
	var inside: Array = []
	for t in targets:
		if _steps_on(t, r2): inside.append(t)
	src["quiet"] = false           # one hit sound and one chain_zap per trigger (SkillHit)
	src["zapped"] = false
	for t in inside:
		if done: break             # a hit that ended the trap (the hero died / left the room inside a kill's callback)
		if not is_instance_valid(t) or not t.is_alive(): continue
		if t.has_method("apply_root"): t.apply_root(root_secs)     # first: a rooted monster is not knocked off the trap
		caught.append(t)
		if SkillHit.hit(t, src, mult, at) > 0: hits_done += 1
	if done or not is_inside_tree(): return
	var f := FxSprite.make(BURST_FX)
	f.modulate = BROWN
	f.z_as_relative = false
	f.z_index = FX_Z
	f.position = at
	get_parent().add_child(f)
	f.play(BURST_FX)
	_look()

## Ends it now (warp, room change, the hero's death, pushed out by a newer trap): nothing more happens, no fade.
func halt() -> void:
	done = true
	armed = false
	src["halted"] = true           # SkillHit deals nothing more for this press's source (also mid-trigger)
	targets = []
	if is_inside_tree(): queue_free()

## Open while armed; sprung: pulled tight and dark, then fading out after the root.
func _look() -> void:
	var shut := clampf(_spent_t / SNAP, 0.0, 1.0) if spent else 0.0
	if _sprite != null:
		var s := lerpf(1.0, SHUT_SCALE, shut)
		_sprite.scale = Vector2(s, s)
		_sprite.modulate = Color.WHITE.lerp(SHUT_TINT, shut)
	if spent:
		modulate.a = clampf(1.0 - (_spent_t - root_secs) / FADE, 0.0, 1.0)
	queue_redraw()

func _draw() -> void:
	var c := Vector2(0, SORT_BACK)
	if armed and trigger_radius > base_radius + 0.5:
		# the expand gem's wider reach: what steps inside this ring springs it
		draw_arc(c, trigger_radius, 0.0, TAU, 48, Color(EDGE_DARK, 0.6), 2.0, false)
		draw_arc(c, trigger_radius, 0.0, TAU, 48, Color(BROWN.lightened(0.35), 0.9), 1.0, false)
	if not placeholder: return
	# PLACEHOLDER (no trap sprite installed): a brown ring and 6 spikes
	var r := 14.0 * (lerpf(1.0, SHUT_SCALE, clampf(_spent_t / SNAP, 0.0, 1.0)) if spent else 1.0)
	draw_arc(c, r, 0.0, TAU, 32, EDGE_DARK, 4.0, false)
	draw_arc(c, r, 0.0, TAU, 32, BROWN, 2.0, false)
	for i in 6:
		var d := Vector2.from_angle(TAU * i / 6.0)
		draw_line(c + d * r, c + d * (r + 7.0), EDGE_DARK, 3.0)
		draw_line(c + d * r, c + d * (r + 6.0), BROWN.lightened(0.3), 1.0)
