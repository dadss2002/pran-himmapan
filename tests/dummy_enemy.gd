extends Node2D
## Minimal enemy for hero/arrow tests: same interface as Wolf (is_alive, hurt_point, receive_hit) and, from M5b
## Task 4, the same status API (apply_status / apply_freeze / apply_mark / apply_trail / apply_zone, is_frozen /
## is_chilled / is_marked) on a real StatusEffects. receive_hit records the multiplier it was given (no taken_mult),
## so older tests keep their numbers; combo tests read `status` and the counters.
## M5b Task 8 (sustain combos, the one kill hook): `die_on_hit` dies at its first hit (a kill by any hit), `deal` = the
## damage receive_hit reports (a burn from it is deal × burn_frac), `last_hit_crit` = the last hit was a crit (a sure
## crit: crit chance ≥ 1.0; no roll), and a DoT kill in tick_status goes through Hero.combo_hit like Wolf.tick_burn.

var alive := true
var hp := 40
var def := 0
var hits: Array = []   # [atk, mult, from]
var crit_chances: Array = []   # the crit chance of each hit, in step with hits (M5b Task 7: sure crits)
var status := StatusEffects.new()
var freezes := 0       # successful apply_freeze calls
var statuses: Array = []   # [kind, value, cast] from apply_status
var die_on_hit := false
var deal := 1
var last_hit_crit := false

func is_alive() -> bool:
	return alive

func hurt_point() -> Vector2:
	return position + Vector2(0, -14)

func receive_hit(atk: float, mult: float, from: Vector2, crit_chance := -1.0, _crit_mult := -1.0) -> int:
	hits.append([atk, mult, from])
	crit_chances.append(crit_chance)
	last_hit_crit = crit_chance >= 1.0
	if die_on_hit: alive = false
	return deal

func apply_status(kind: String, value := 0.0, leech := 0.0, source: Object = null, cast: ComboCast = null) -> void:
	if not alive: return
	statuses.append([kind, value, cast])
	if kind == "burn": status.apply_burn(value, leech, source, cast)
	elif kind == "slow": status.apply_slow()

func apply_freeze(secs: float, lock_secs: float, cast: ComboCast = null) -> bool:
	if not alive or not status.apply_freeze(secs, lock_secs, cast): return false
	freezes += 1
	return true

func apply_mark(taken: float, secs: float, cast: ComboCast = null) -> void:
	if alive: status.apply_mark(taken, secs, cast)

func apply_trail(raw_per_tick: float, hold: float, source: Object = null, cast: ComboCast = null, leech := 0.0) -> void:
	var d := float(def)                 # float DEF, as Wolf.def_factor (review M6)
	if alive: status.apply_trail(raw_per_tick * (1.0 - d / (d + 100.0)), hold, source, cast, leech)

func apply_zone(slow: float, taken: float, hold: float, cast: ComboCast = null) -> void:
	if alive: status.apply_zone(slow, taken, hold, cast)

func is_frozen() -> bool:
	return alive and status.is_frozen()

func is_chilled() -> bool:
	return alive and (status.is_slowed() or status.is_frozen())

func is_marked() -> bool:
	return alive and status.is_marked()

## Advances the statuses; burn / trail damage comes off hp (dies at 0). Returns the damage dealt. Leeches like
## Wolf.tick_burn (Task 4 review): each DoT part with its own fraction to its own source, parts under 1 HP included.
func tick_status(delta: float) -> int:
	var dmg := status.tick(delta)
	if not alive: return dmg
	Wolf.leech_to(status.last_burn_source, status.last_burn_dmg * status.last_burn_leech)
	Wolf.leech_to(status.last_trail_source, status.last_trail_dmg * status.last_trail_leech)
	if dmg > 0:
		hp -= dmg
		if hp <= 0:
			alive = false
			Hero.combo_hit(status.tick_source, status.tick_cast, self, true, dmg)   # as Wolf.tick_burn
	return dmg
