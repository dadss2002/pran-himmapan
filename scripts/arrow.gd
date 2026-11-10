class_name Arrow
extends Node2D
## Basic shot: flies straight, hits the first live enemy within shot.arrow_hit_radius of its
## path (at the enemy's hurt_point), or is spent after shot.range px.

var dir := Vector2.RIGHT
var atk := 0.0
var travelled := 0.0
var spent := false
var targets: Array = []
var mult := 1.0
var pierce := false     # ศรทะลวง: hits every enemy in its line once and keeps flying
var crit_chance := -1.0  # set by the hero from gear; < 0 = base crit numbers
var crit_mult := -1.0
var max_range := 0.0    # px; shot.range unless the skill sets its own
var _hit := {}

signal spawned(arrow: Arrow)   # a ricochet arrow this one created

func launch(direction: Vector2, attack: float, enemies: Array = [], multiplier := 1.0, pierce_all := false, range_px := -1.0) -> void:
	max_range = range_px if range_px > 0.0 else Balance.num("shot.range")
	dir = direction.normalized()
	atk = attack
	targets = enemies
	mult = multiplier
	pierce = pierce_all
	rotation = dir.angle()  # art points east

## M5b combos (plan Task 5): a primary arrow is one the hero's skill press fired (Hero._fire with a build); bounce
## arrows and basic shots are not. Per-line combo effects belong to primary arrows only: the fire trail (FireTrail,
## ศรพัดเพลิง / พรหมาสตร์) and the line-end blast (พรหมาสตร์). Per-bounce effects (Task 6: the lightning combos'
## extra bounce and bolts) belong to every arrow of ONE chain per line per press (claim_lightning_line, owner 2026-11-10). Secondary hits (blasts, bolts) never trigger combo or
## gem on-hit effects: no trail, bounce, element status, bolt, mark or freeze count (Global Constraints).
var primary := false
## Owner 2026-11-10 ("สายฟ้าคอมโบจาก 1 ลูกต่อการกด", "ลูกเด้งไม่แตกสายโซ่"): `line` = the press's line this primary arrow
## belongs to (SkillBuild.line_of: ศรทะลวง 1 line, +split 3; ศรกระจาย's 5 arrows 1 line, +split 7 arrows in 3). Only the
## FIRST arrow of a line that hits a monster AND bounces (a bounce target in range; owner 2026-11-10, Task 6 review 3)
## carries the lightning combo (its +1 bounce and the bolts) for its whole chain, claimed through the press's ledger (build.cast.once("lightning_line", line)); the line's other arrows keep the
## plain ricochet gem's bounces. `is_bounce`: a ricochet arrow (_spawn_bounce); it never fires the lightning gem's own
## ×0.8 chain (only the press's primary hits do).
var line := 0
var is_bounce := false
var _carrier := -1      # lightning combo carrier: -1 not decided yet (decided at the first hit), 0 no, 1 yes
var trail: FireTrail = null
var _trail_checked := false
var _line_ended := false

## Gem behaviour from SkillBuild: pierce_extra, bounces/bounce_mult, homing, leech, element; combo / combo_p / cast
## (the press's ComboCast, Hero._release).
var build := {}
var shooter: Node = null
var _pierce_left := 0
var _bounces_left := 0
var _bounced := false
var _home: Node2D = null
func configure(b: Dictionary, from: Node = null) -> void:
	build = b
	shooter = from
	_pierce_left = int(b.get("pierce_extra", 0))
	_bounces_left = int(b.get("bounces", 0))

func advance(delta: float) -> void:
	if spent: return
	if primary and not _trail_checked: _lay_trail()
	var range_px := max_range if max_range > 0.0 else Balance.num("shot.range")
	var radius := Balance.num("shot.arrow_hit_radius")
	if build.get("homing", false): _steer(delta)
	var stepd := minf(Balance.num("shot.arrow_speed") * delta, range_px - travelled)
	position += dir * stepd
	travelled += stepd
	if trail != null: trail.extend_to(_pos())
	for t in targets:
		if is_instance_valid(t) and t.is_alive() and not _hit.has(t) and _pos().distance_to(t.hurt_point()) <= (t.hurt_radius() if t.has_method("hurt_radius") else radius):
			_hit[t] = true
			_arrow_hit(t)
			if pierce: continue
			if _pierce_left > 0:
				_pierce_left -= 1
				continue
			_finish(t)
			return
	if travelled >= range_px - 0.0001:
		_finish()

## One ARROW hit on t: a primary or a bounce arrow (secondary hits, chains and trail ticks never come here). M5b Task 7
## (mark / frost combos), read BEFORE the hit (the ice gem's slow from this very hit does not count for it):
## - sure crit (crit chance 1.0): ศรเนตรพญาครุฑ (sure_crit_marked) on a marked target, ศรผลึกอโนดาต (sure_crit_chilled) on
##   a chilled (slowed or frozen) one;
## - ศรเกล็ดน้ำแข็ง (bonus_vs_chilled): × (1 + 0.25) on a chilled target (this arrow's hit only: its bounce, chain and burn
##   are computed from the arrow's own mult).
## Then the gems' on-hit (_after_hit) and the combo's on-hit (_combo_on_hit). Returns the damage dealt.
func _arrow_hit(t: Node2D) -> int:
	var chilled := _chilled(t)
	var m := mult
	var bonus := _cp("bonus_vs_chilled")
	if bonus > 0.0 and chilled: m *= 1.0 + bonus
	var chance := crit_chance
	if (chilled and _cp("sure_crit_chilled") > 0.0) or (_cp("sure_crit_marked") > 0.0 and t.has_method("is_marked") and t.is_marked()):
		chance = 1.0
	var was: bool = t.is_alive()
	var amount: int = t.receive_hit(atk, m, _pos(), chance, crit_mult)
	_credit(t, was, amount)
	_after_hit(t, amount)
	_combo_on_hit(t, chilled)
	return amount

func _chilled(t: Node2D) -> bool:
	return t.has_method("is_chilled") and t.is_chilled()

## The mark / frost combos' on-hit (Task 7), after an arrow hit on t (was_chilled: before the hit). Arrow hits only:
## a secondary hit never marks, never counts toward the freeze and never shatters (Global Constraints).
## - mark (ศรตาเหยี่ยว +20 % / ครุฑ +30 %, 4 s): every arrow hit marks; the monster shows it (Wolf._update_status_fx).
## - freeze (เกล็ดน้ำแข็ง / อโนดาต): the press's ledger counts this press's arrow hits per target; the 3rd one freezes
##   (1 s, then the monster's own 5 s lock, StatusEffects). Exactly once per target per press (no retry on a 4th hit).
##   Without a ledger (no press) there is no count and no freeze. Its look is the monster's own frost overlay (shown
##   while slowed or frozen), so the recipe's "freeze" row is not played again here.
## - shatter (อโนดาต): a hit on a target that was chilled blasts r32 × 0.50 of this arrow's hit around it, the target
##   included, once per struck target per press (cast.once("shatter"); no ledger = no limit). Owner 2026-11-10 (Task 7
##   review, "โดนแรงแตกได้ตัวละ 1 ครั้งต่อการกด"): each monster TAKES at most one shatter splash per press, its own
##   shatter's included (cast.once("shatter_hit"), like the line-end blast): in a tight pack 5 shatters do not hit a
##   monster 5 times; a monster already splashed this press still shatters (hits the others) when struck while chilled.
##   A secondary hit: it rolls the arrow's own crit chance (no sure crit), no element, no further combo effect. A
##   killing arrow hit on a chilled target still shatters round it (chilled is read before the hit; the dead
##   target itself takes nothing; risks B31).
## The combos' "crit" row (crit_hit) is the hit effect TestGround already plays for every crit; not doubled here.
func _combo_on_hit(t: Node2D, was_chilled: bool) -> void:
	if not is_instance_valid(t): return
	var cast = build.get("cast")
	var ledger: ComboCast = cast if cast is ComboCast else null
	var key := t.get_instance_id()
	var secs := _cp("mark_secs")
	if secs > 0.0 and t.has_method("apply_mark"):
		t.apply_mark(_cp("mark_taken"), secs, ledger)
	var need := int(_cp("freeze_hits"))
	if need > 0 and ledger != null and t.has_method("apply_freeze") and ledger.count_hit(key) == need:
		t.apply_freeze(_cp("freeze_secs"), _cp("freeze_lock_secs"), ledger)
	if _cp("blast_on_chilled") > 0.0 and was_chilled and (ledger == null or ledger.once("shatter", key)):
		var r := _cp("blast_radius")
		var at: Vector2 = t.hurt_point()
		blast(at, r, _cp("blast_frac"), false, t, [], "shatter_hit")
		if is_inside_tree():
			for s in ComboFx.play(get_parent(), combo_id(), "shatter", at):
				s.scale = Vector2.ONE * (2.0 * r / maxf(1.0, s._cell.x))   # as wide as the shatter (r32: 64 px)

func _after_hit(t: Node2D, amount: int) -> void:
	_leech(amount)
	match String(build.get("element", "")):
		"fire":
			if t.has_method("apply_status"):
				# the press's ledger (build.cast): a burn kill credits this press (Task 8; Task 5 review M5)
				t.apply_status("burn", amount * Balance.num("elements.fire.burn_frac"), float(build.get("leech", 0.0)), shooter, build.get("cast"))
		"ice":
			if t.has_method("apply_status"): t.apply_status("slow")
		"lightning":
			# bounce arrows never chain (owner 2026-11-10 "ลูกเด้งไม่แตกสายโซ่"): only the press's primary hits do
			var other: Node2D = null if is_bounce else _nearest(t.hurt_point(), Balance.num("elements.lightning.range"), [t])
			if other:
				var was: bool = other.is_alive()
				var dealt: int = other.receive_hit(atk, mult * Balance.num("elements.lightning.mult"), t.hurt_point(), crit_chance, crit_mult)
				_credit(other, was, dealt)   # Task 8 (plan note): a chain kill counts too ("นับทุกแบบ")
				_leech(dealt)
				if is_inside_tree():
					var z := FxSprite.make("chain_zap")
					z.position = other.hurt_point()
					get_parent().add_child(z)
					z.play("chain_zap")
	_after_hit_bounce(t)

## The ricochet part of a hit: every arrow tries once, from the first monster it hits.
func _after_hit_bounce(t: Node2D) -> void:
	if _bounces_left > 0 and not _bounced:
		var next := _nearest(t.hurt_point(), Balance.num("ricochet.range"), _hit.keys())
		# every arrow tries once, from the first monster it hits only: a piercing arrow (ศรทะลวง) and, owner 2026-11-09
		# (Task 6 review, "เด้งจากตัวแรกที่โดนเท่านั้น"), an arrow piercing by the pierce gem (ศรกระจาย); a plain
		# ricochet arrow stops at that hit anyway, its chain goes on through the bounce arrows
		_bounced = true
		var carry := claim_lightning_line(next != null)   # claimed only by an arrow that bounces (owner 2026-11-10)
		if next:
			_spawn_bounce(t.hurt_point(), next, carry)
			if carry: _bounce_event(t, next)

## Read-only: true when this arrow's chain carries the press's lightning combo (+1 bounce, bolts) for its line. Never
## claims anything: an arrow that has not hit yet (undecided) answers false and leaves its line free.
func carries_lightning() -> bool:
	return _carrier == 1

## THE one place that decides who carries a line's lightning combo (owner 2026-11-10: one arrow per line per press).
## Called only from the real hit path (_after_hit_bounce, the arrow's first hit), with can_bounce = a bounce target was
## found in ricochet.range. Owner 2026-11-10 (Task 6 review 3, "ลูกแรกที่เด้งได้จริง"): the line goes to the FIRST arrow
## of the line that can actually bounce, not merely the first to hit: an arrow whose first hit has no bounce target
## never claims (it never bounces later either: every arrow tries once, from its first hit) and leaves the line free
## for the next arrow of the line that bounces. Decided once per arrow, through the press's ledger
## (cast.once("lightning_line", line); no ledger = no limit), in hit order (deterministic, homing too). Bounce arrows
## inherit the result (_spawn_bounce). Builds without a lightning combo never carry.
func claim_lightning_line(can_bounce := true) -> bool:
	if _carrier < 0:
		var lightning := _cp("bolts") > 0.0 or int(build.get("extra_bounces", 0)) > 0
		var cast = build.get("cast")
		_carrier = 1 if lightning and can_bounce and (not (cast is ComboCast) or cast.once("lightning_line", line)) else 0
	return _carrier == 1

## The press's combo id ("" for none).
func combo_id() -> String:
	var c = build.get("combo", {})
	return String(c.get("id", "")) if typeof(c) == TYPE_DICTIONARY else ""

## The press's combo number `key` (build.combo_p, copied once per press); 0 when absent.
func _cp(key: String) -> float:
	var cp = build.get("combo_p", {})
	return float(cp.get(key, 0.0)) if typeof(cp) == TYPE_DICTIONARY else 0.0

## True for a primary arrow whose recipe has a "trail" look but no fire line (ศรเกล็ดน้ำแข็ง / ผลึกอโนดาต: a
## piercing_trail streak tinted #7fd4ff riding the arrow). TestGround then skips its plain white streak for it.
func has_combo_streak() -> bool:
	return primary and _cp("trail_secs") <= 0.0 and ComboFx.has(combo_id(), "trail")

## A primary arrow of a trail recipe lays one FireTrail from where it starts (once, on its first step); a streak
## recipe (has_combo_streak) puts its streak on the arrow instead (a child: it turns and goes with the arrow).
func _lay_trail() -> void:
	_trail_checked = true
	var secs := _cp("trail_secs")
	if secs <= 0.0:
		if is_inside_tree() and has_combo_streak():
			for s in ComboFx.play(self, combo_id(), "trail", Vector2.ZERO): s.show_behind_parent = true
		return
	trail = FireTrail.new()
	# per tick × the press's expected crit factor (no per-tick roll; the approved sim, Task 5 review I3)
	trail.setup(_pos(), atk, mult, _cp("trail_frac"), secs, targets, shooter, build.get("cast"), float(build.get("leech", 0.0)), combo_id(),
		Combat.expected_crit(crit_chance, crit_mult))
	if is_inside_tree(): get_parent().add_child(trail)

## The line ends (spent by range, or by its last hit on `struck`): the trail burns on for its time, พรหมาสตร์ blasts
## once at the end. Primary arrows only; once per arrow. The blast never hits `struck` (the approved sim gives a single
## target no blast term; Task 5 review I2) and hits each monster at most once per press however many line ends it
## stands by (cast.once("line_end"), review M1). (ฝนดาวไฟ's on-hit blast, Task 9, is another path: it hits the target.)
func _end_line(struck: Node2D = null) -> void:
	if _line_ended or not primary: return
	_line_ended = true
	if trail != null: trail.finish()
	if _cp("blast_on_line_end") > 0.0:
		var r := _cp("blast_radius")
		blast(_pos(), r, _cp("blast_frac"), false, null, [struck] if struck != null else [], "line_end")
		if is_inside_tree():
			for s in ComboFx.play(get_parent(), combo_id(), "line_end", position):
				s.scale = Vector2.ONE * (2.0 * r / maxf(1.0, s._cell.x))   # as wide as the blast: fire_blast's 64 px cell at r32 = 1:1, as sampled

## The multiplier of the hit that started this arrow's bounce chain: the press's primary arrow (build.root_mult, set
## on every bounce arrow by _spawn_bounce), or this arrow's own when it is not a bounce arrow.
func root_mult() -> float:
	return float(build.get("root_mult", mult))

## One bounce, from `struck` to `next` (Task 6): the recipe's "bounce" effect at the bounce point, and the lightning
## combos' bolts (ศรอสนีกระโดด 1, ศรอสนีพันสาย 2) at the nearest others, never the struck monster or the bounce's own
## target. Every bounce event of a carrier chain bolts (bounce arrows too; claim_lightning_line: one chain per line per
## press, owner 2026-11-10). Owner 2026-11-09 (Task 6 review, "50% ของนัดแรก
## คงที่"): each bolt is bolt_frac of the press's FIRST hit (root_mult), flat at every bounce, not of the bouncing arrow.
func _bounce_event(struck: Node2D, next: Node2D) -> void:
	var at: Vector2 = struck.hurt_point()
	if is_inside_tree(): ComboFx.play(get_parent(), combo_id(), "bounce", at)
	var n := int(_cp("bolts"))
	if n > 0: bolts(at, n, _cp("bolt_frac"), [struck, next], root_mult())

## Lightning bolts of this press from `from`: the n nearest distinct live targets within elements.lightning.range,
## skipping `skip`, each a secondary hit for frac of `base` (the chain's first-hit multiplier; < 0 = this arrow's own)
## (_secondary_hit: no bounce, no element, no combo on-hit) with the recipe's "bolt" effect on it (พันสาย: one
## chain_zap per bolt). Returns how many were hit.
func bolts(from: Vector2, n: int, frac: float, skip: Array, base := -1.0) -> int:
	if n <= 0: return 0
	var reach := Balance.num("elements.lightning.range")
	var done := skip.duplicate()
	var hit := 0
	while hit < n:
		var t := _nearest(from, reach, done)
		if t == null: break
		done.append(t)
		_secondary_hit(t, frac, base)
		hit += 1
		if is_inside_tree(): ComboFx.play(get_parent(), combo_id(), "bolt", t.hurt_point())
	return hit

## Secondary hits of this press at `at`: every live target whose hurt point is within `radius`, plus `include` (hit
## even outside the radius: meteor_rain's own target), minus `skip`; each takes frac of this arrow's hit
## (_secondary_hit), and with `burn` the fire burn (elements.fire.burn_frac of that hit, the press's leech / ledger).
## once_tag: when set, each target is hit at most once per press for that tag (build.cast.once; no cast = no limit).
## Returns how many were hit. Never spawns arrows, trails or further blasts, never applies the arrow's element.
func blast(at: Vector2, radius: float, frac: float, burn: bool, include: Node2D = null, skip: Array = [], once_tag := "") -> int:
	var n := 0
	var r2 := radius * radius
	var cast = build.get("cast")
	for t in targets:
		if not is_instance_valid(t) or not t.is_alive() or t in skip: continue
		if t != include and at.distance_squared_to(t.hurt_point()) > r2: continue
		if once_tag != "" and cast is ComboCast and not cast.once(once_tag, t.get_instance_id()): continue
		var amount := _secondary_hit(t, frac)
		n += 1
		if burn and t.has_method("apply_status"):
			t.apply_status("burn", amount * Balance.num("elements.fire.burn_frac"), float(build.get("leech", 0.0)), shooter, build.get("cast"))
	return n

## One secondary hit (blast, bolt): frac of this arrow's hit (of `base` when >= 0: a bolt's first-hit multiplier), with
## its crit chance; leeches and goes through the kill / crit hook (Task 8). Never _after_hit (no element, no bounce, no
## combo on-hit).
func _secondary_hit(t: Node2D, frac: float, base := -1.0) -> int:
	var was: bool = t.is_alive()
	var amount: int = t.receive_hit(atk, (base if base >= 0.0 else mult) * frac, _pos(), crit_chance, crit_mult)
	_credit(t, was, amount)
	_leech(amount)
	return amount

## M5b Task 8: every hit this arrow deals (_arrow_hit, the lightning gem's chain, _secondary_hit: bolts, line-end and
## shatter blasts) reports to THE one kill / crit hook (Hero.combo_hit) with the press's ledger (build.cast) and the
## shooter: a kill (alive before, dead after) refunds / heals once, through the press that fired it, under its cap; a
## crit heals for ราหู. A target that reports no crit flag (last_hit_crit) never counts as a crit.
func _credit(t: Node2D, was_alive: bool, amount: int) -> void:
	var crit: bool = is_instance_valid(t) and t.get("last_hit_crit") == true
	Hero.combo_hit(shooter, build.get("cast"), t, was_alive, amount, crit)

func _leech(amount: int) -> void:
	var frac := float(build.get("leech", 0.0))
	if frac > 0.0 and amount > 0 and is_instance_valid(shooter) and shooter.has_method("leech_heal"):
		shooter.leech_heal(amount * frac)

## Nearest live target within max_dist of `from`, skipping `skip`.
func _nearest(from: Vector2, max_dist: float, skip: Array) -> Node2D:
	var best: Node2D = null
	var best_d := max_dist
	for t in targets:
		if not is_instance_valid(t) or not t.is_alive() or t in skip: continue
		var d: float = from.distance_to(t.hurt_point())
		if d <= best_d:
			best_d = d
			best = t
	return best

func _spawn_bounce(from: Vector2, to: Node2D, carry := true) -> void:
	var a: Arrow = load("res://scenes/arrow.tscn").instantiate()
	a.position = from
	var d: float = from.distance_to(to.hurt_point())
	a.launch((to.hurt_point() - from).normalized(), atk, targets, mult * float(build.get("bounce_mult", 1.0)), false, d + Balance.num("shot.arrow_hit_radius"))
	a.crit_chance = crit_chance
	a.crit_mult = crit_mult
	var b := build.duplicate()
	# the chain's own bounces (a piercing arrow bounces from its first target only) + the lightning combo's extra
	# bounce (ศรอสนีกระโดด +1), handed to the first bounce only: exactly +1 per chain, piercing lines included (Task 6),
	# and only on the line's carrier chain (owner 2026-11-10: one arrow per line per press)
	b["bounces"] = (0 if pierce else _bounces_left - 1) + (int(build.get("extra_bounces", 0)) if carry else 0)
	b["extra_bounces"] = 0
	b["root_mult"] = root_mult()       # the press's first hit, for the lightning combos' flat bolts (owner 2026-11-09)
	b["pierce_extra"] = 0
	b["homing"] = false
	a.configure(b, shooter)
	a.is_bounce = true
	a.line = line
	a._carrier = 1 if carry else 0
	for k in _hit: a._hit[k] = true
	if is_inside_tree(): get_parent().add_child(a)
	spawned.emit(a)

## Ricochet arrows inherit the parent's spawned listeners through the hero (Hero._fire).

## Turns toward the nearest live target not yet hit (homing.turn_deg per second).
func _steer(delta: float) -> void:
	if not (is_instance_valid(_home) and _home.is_alive() and not _hit.has(_home)):
		_home = _nearest(_pos(), Balance.num("homing.search"), _hit.keys())
	if _home == null: return
	var want: Vector2 = (_home.hurt_point() - _pos()).normalized()
	var turn := deg_to_rad(Balance.num("homing.turn_deg")) * delta
	var ang := clampf(dir.angle_to(want), -turn, turn)
	dir = dir.rotated(ang).normalized()
	rotation = dir.angle()

## Global position in the scene, plain position when not in a tree (tests).
func _pos() -> Vector2:
	return global_position if is_inside_tree() else position

## Stops the arrow where it is for good: it moves and hits nothing more (the warp fade, review Important #1; the
## room change then frees it).
func halt() -> void:
	spent = true
	targets = []
	_line_ended = true                  # no line-end blast after the warp
	if trail != null and is_instance_valid(trail): trail.halt()   # its fire stops at once (B20)

func _finish(struck: Node2D = null) -> void:
	spent = true
	_end_line(struck)
	if is_inside_tree():
		queue_free()

func _physics_process(delta: float) -> void:
	advance(delta)
