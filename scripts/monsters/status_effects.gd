class_name StatusEffects
extends RefCounted
## Statuses on one monster. Pure rules, no scene access (risks.md §3).
## M3a design §5.3 (balance.json "elements"): burn every elements.fire.tick s for elements.fire.duration s; a re-hit
## restarts the duration and keeps the higher per-tick value (no stacking). Slow: speed × (1 − elements.ice.slow).
## M5b Task 4 (docs/superpowers/specs/2026-11-08-gem-combos.md, plan Task 4), all non-stacking:
## - freeze: speed 0 for its time, then a per-target lock (counted from the freeze) during which no press can
##   freeze it again. Bosses and elites freeze like any monster (owner 2026-11-08).
## - mark: damage taken × (1 + taken); keeps the highest taken while active, any re-mark refreshes the time.
## - trail burn (ศรพัดเพลิง's fire line): while held (the trail re-applies a short hold every step), ticks
##   per_tick at the end of each full elements.fire.tick s in the fire, like a burn (review I2: the approved numbers
##   are tools/gem_combo_sim.py's, fire_fan 2 ticks per trail, brahmastra 3; ticking on contact gave one more).
##   The in-fire clock runs on while held (stepping out for less than the hold continues it) and restarts once the
##   hold runs out, so stepping out and back in never brings a tick early and a stationary target in a trail gets
##   exactly round(secs / tick) ticks (as long as hold + the arrow's flight past it < 1 tick: 0.25 + 0.61 s).
##   Overlapping trails keep the highest per_tick, so three lines through one monster burn once a second.
## - zone: speed × (1 − slow), damage taken × (1 + taken) while held; the highest of each.
## taken_mult() = 1 + mark + zone taken (they ADD, owner 2026-11-09) applies to hits AND to burn / trail ticks.
## Ledger (risks.md B25, owner 2026-11-09 "นับทุกแบบ"): every status keeps the ComboCast of the press that applied
## it (*_cast; null = no press, e.g. tests). Burn / trail: the newer application's ledger, like burn_source. A refused
## freeze keeps the first. tick_cast names the ONE ledger that a DoT kill on this step is credited to.
## Leech (review I1): each DoT leeches its own part of a step with its own fraction, to its own source
## (last_burn_* / last_trail_*); a burn's leech and source end with the burn, a trail's with its hold.

var burn_per_tick := 0.0
var burn_left := 0.0
var burn_leech := 0.0
var burn_source: Object = null
var burn_cast: ComboCast = null
var slow_left := 0.0
var freeze_left := 0.0
var freeze_lock := 0.0       # time until this target may freeze again (counts down from the freeze itself)
var freeze_cast: ComboCast = null
var mark_taken := 0.0
var mark_left := 0.0
var mark_cast: ComboCast = null
var trail_per_tick := 0.0
var trail_hold := 0.0
var trail_leech := 0.0
var trail_source: Object = null
var trail_cast: ComboCast = null
var zone_slow := 0.0
var zone_taken := 0.0
var zone_hold := 0.0
var zone_cast: ComboCast = null
## The ledger of the DoT (burn or trail) that dealt damage on the last tick(); null when nothing ticked. Both on
## one step: the larger tick's, ties the burn's. tick_source = that DoT's source (the hero). Valid until the next
## tick(): clear() (on death) leaves both alone, so the kill hook can read them after the killing tick.
var tick_cast: ComboCast = null
var tick_source: Object = null
## This step's DoT parts (× taken_mult, before whole-number carry) with the leech fraction and source each had when it
## ticked; 0 / null when it did not tick. Like tick_cast, set by tick() and left alone by clear().
var last_burn_dmg := 0.0
var last_burn_leech := 0.0
var last_burn_source: Object = null
var last_trail_dmg := 0.0
var last_trail_leech := 0.0
var last_trail_source: Object = null
var _burn_t := 0.0
var _trail_t := 0.0          # seconds in the fire since the last trail tick (restarts when the hold runs out)
var _carry := 0.0

func apply_burn(per_tick: float, leech := 0.0, source: Object = null, cast: ComboCast = null) -> void:
	burn_per_tick = maxf(burn_per_tick if burn_left > 0.0 else 0.0, per_tick)
	burn_left = Balance.num("elements.fire.duration")
	burn_leech = leech
	burn_source = source
	burn_cast = cast

func apply_slow() -> void:
	slow_left = Balance.num("elements.ice.duration")

## Freezes for `secs` and locks this target against any freeze for `lock_secs` (from now). False (and nothing
## changes) while frozen or locked.
func apply_freeze(secs: float, lock_secs: float, cast: ComboCast = null) -> bool:
	if freeze_left > 0.0 or freeze_lock > 0.0 or secs <= 0.0: return false
	freeze_left = secs
	freeze_lock = maxf(lock_secs, secs)
	freeze_cast = cast
	return true

func apply_mark(taken: float, secs: float, cast: ComboCast = null) -> void:
	if mark_left <= 0.0 or taken >= mark_taken:
		mark_taken = taken
		mark_cast = cast
	mark_left = secs

## `per_tick` is the damage per elements.fire.tick (after DEF; Wolf.apply_trail applies it); `hold` = how long it
## keeps burning without being re-applied (the trail re-applies it every step the monster stands in it).
## `leech` = the leech fraction of the press that laid the trail (plan Global Constraints: trail ticks leech; they
## never roll a crit: FireTrail puts the press's expected crit factor in per_tick, Task 5 review I3), newer
## application like source / cast.
func apply_trail(per_tick: float, hold: float, source: Object = null, cast: ComboCast = null, leech := 0.0) -> void:
	trail_per_tick = maxf(trail_per_tick if trail_hold > 0.0 else 0.0, per_tick)
	trail_hold = maxf(trail_hold, hold)
	trail_source = source
	trail_cast = cast
	trail_leech = leech

func apply_zone(slow: float, taken: float, hold: float, cast: ComboCast = null) -> void:
	var on := zone_hold > 0.0
	zone_slow = maxf(zone_slow if on else 0.0, slow)
	zone_taken = maxf(zone_taken if on else 0.0, taken)
	zone_hold = maxf(zone_hold, hold)
	zone_cast = cast

func speed_mult() -> float:
	if freeze_left > 0.0: return 0.0
	var m := 1.0 - Balance.num("elements.ice.slow") if slow_left > 0.0 else 1.0
	if zone_hold > 0.0: m *= 1.0 - zone_slow
	return m

## Damage taken × this: mark and zone ADD (owner 2026-11-09, "บวกกัน +50%": garuda +30 % and hellfield +20 % = +50 %,
## not ×1.56).
func taken_mult() -> float:
	return 1.0 + (mark_taken if mark_left > 0.0 else 0.0) + (zone_taken if zone_hold > 0.0 else 0.0)

func is_burning() -> bool:
	return burn_left > 0.0

func is_slowed() -> bool:
	return slow_left > 0.0

func is_frozen() -> bool:
	return freeze_left > 0.0

func is_marked() -> bool:
	return mark_left > 0.0

func in_trail() -> bool:
	return trail_hold > 0.0

func in_zone() -> bool:
	return zone_hold > 0.0

## Advances timers; returns whole burn + trail damage dealt this step (× taken_mult(); fractions carry over).
func tick(delta: float) -> int:
	var taken := taken_mult()           # this step's mark / zone, before they run down
	tick_cast = null
	tick_source = null
	last_burn_dmg = 0.0
	last_burn_leech = 0.0
	last_burn_source = null
	last_trail_dmg = 0.0
	last_trail_leech = 0.0
	last_trail_source = null
	var burn_dmg := 0.0
	var trail_dmg := 0.0
	var step := Balance.num("elements.fire.tick")
	slow_left = maxf(0.0, slow_left - delta)
	freeze_left = maxf(0.0, freeze_left - delta)
	freeze_lock = maxf(0.0, freeze_lock - delta)
	mark_left = maxf(0.0, mark_left - delta)
	if mark_left <= 0.0:
		mark_taken = 0.0
		mark_cast = null
	zone_hold = maxf(0.0, zone_hold - delta)
	if zone_hold <= 0.0:
		zone_slow = 0.0
		zone_taken = 0.0
		zone_cast = null
	if freeze_left <= 0.0: freeze_cast = null
	if burn_left > 0.0:
		_burn_t += delta
		burn_left -= delta
		if _burn_t >= step - 1e-6:
			_burn_t -= step
			burn_dmg = burn_per_tick * taken
			last_burn_dmg = burn_dmg
			last_burn_leech = burn_leech
			last_burn_source = burn_source
		if burn_left <= 1e-6:
			burn_left = 0.0
			burn_per_tick = 0.0
			_burn_t = 0.0
	if trail_hold > 0.0:
		_trail_t += delta
		if _trail_t >= step - 1e-6:
			_trail_t -= step
			trail_dmg = trail_per_tick * taken
			last_trail_dmg = trail_dmg
			last_trail_leech = trail_leech
			last_trail_source = trail_source
		trail_hold = maxf(0.0, trail_hold - delta)
		if trail_hold <= 0.0:
			trail_per_tick = 0.0
			_trail_t = 0.0
	if burn_dmg > 0.0 or trail_dmg > 0.0:
		var by_trail := _credit_trail(burn_dmg, trail_dmg)
		tick_cast = trail_cast if by_trail else burn_cast
		tick_source = trail_source if by_trail else burn_source
	if trail_hold <= 0.0:
		trail_cast = null
		trail_source = null
		trail_leech = 0.0
	if burn_left <= 0.0:
		burn_cast = null
		burn_source = null
		burn_leech = 0.0
	_carry += burn_dmg + trail_dmg
	var whole := int(floor(_carry + 1e-6))
	_carry -= whole
	return whole

## Which DoT a kill on this step is credited to (review M4): only one ticked → that one. Both → the one whose ledger
## still pays (MP on kill left under its cap, or a kill heal) over one that pays nothing; both or neither pay → the
## larger tick, ties the burn. One ledger per step, so a kill pays at most once.
func _credit_trail(burn_dmg: float, trail_dmg: float) -> bool:
	if burn_dmg <= 0.0: return true
	if trail_dmg <= 0.0: return false
	var bp := _pays(burn_cast)
	var tp := _pays(trail_cast)
	if bp != tp: return tp
	return trail_dmg > burn_dmg

static func _pays(c: ComboCast) -> bool:
	return c != null and (c.kill_heal_frac > 0.0 or (c.kill_mp > 0 and c.mp_refunded() < c.kill_mp_cap))

func clear() -> void:
	burn_left = 0.0
	burn_per_tick = 0.0
	burn_leech = 0.0
	burn_source = null
	burn_cast = null
	slow_left = 0.0
	freeze_left = 0.0
	freeze_lock = 0.0
	freeze_cast = null
	mark_left = 0.0
	mark_taken = 0.0
	mark_cast = null
	trail_hold = 0.0
	trail_per_tick = 0.0
	trail_source = null
	trail_cast = null
	trail_leech = 0.0
	zone_hold = 0.0
	zone_slow = 0.0
	zone_taken = 0.0
	zone_cast = null
	_burn_t = 0.0
	_trail_t = 0.0
	_carry = 0.0
