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
##   per_tick on contact and then every elements.fire.tick s, never more often (stepping out and back in included);
##   overlapping trails keep the highest per_tick, so three lines through one monster burn once a second.
## - zone: speed × (1 − slow), damage taken × (1 + taken) while held; the highest of each.
## taken_mult() = (1 + mark) × (1 + zone taken) applies to hits AND to burn / trail ticks.
## Ledger (risks.md B25, owner 2026-11-09 "นับทุกแบบ"): every status keeps the ComboCast of the press that applied
## it (*_cast; null = no press, e.g. tests). Burn / trail: the newer application's ledger, like burn_source. A refused
## freeze keeps the first. tick_cast names the ONE ledger that a DoT kill on this step is credited to.

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
var _burn_t := 0.0
var _trail_cd := 0.0
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
func apply_trail(per_tick: float, hold: float, source: Object = null, cast: ComboCast = null) -> void:
	trail_per_tick = maxf(trail_per_tick if trail_hold > 0.0 else 0.0, per_tick)
	trail_hold = maxf(trail_hold, hold)
	trail_source = source
	trail_cast = cast

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

func taken_mult() -> float:
	return (1.0 + (mark_taken if mark_left > 0.0 else 0.0)) * (1.0 + (zone_taken if zone_hold > 0.0 else 0.0))

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
		if burn_left <= 1e-6:
			burn_left = 0.0
			burn_per_tick = 0.0
			_burn_t = 0.0
	_trail_cd = maxf(0.0, _trail_cd - delta)     # runs out of the fire too: no extra tick on re-entry
	if trail_hold > 0.0:
		if _trail_cd <= 1e-6:
			_trail_cd = step
			trail_dmg = trail_per_tick * taken
		trail_hold = maxf(0.0, trail_hold - delta)
		if trail_hold <= 0.0:
			trail_per_tick = 0.0
	if burn_dmg > 0.0 or trail_dmg > 0.0:
		var by_trail := trail_dmg > burn_dmg
		tick_cast = trail_cast if by_trail else burn_cast
		tick_source = trail_source if by_trail else burn_source
	if trail_hold <= 0.0:
		trail_cast = null
		trail_source = null
	if burn_left <= 0.0: burn_cast = null
	_carry += burn_dmg + trail_dmg
	var whole := int(floor(_carry + 1e-6))
	_carry -= whole
	return whole

func clear() -> void:
	burn_left = 0.0
	burn_per_tick = 0.0
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
	zone_hold = 0.0
	zone_slow = 0.0
	zone_taken = 0.0
	zone_cast = null
	_burn_t = 0.0
	_trail_cd = 0.0
	_carry = 0.0
