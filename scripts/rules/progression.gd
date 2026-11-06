class_name Progression
## EXP curve and level-ups (docs/spec-numbers.md §3). Pure functions.

static func exp_to_next(level: int) -> int:
	return int(round(Balance.num("exp.base") * pow(level, Balance.num("exp.power")) * pow(Balance.num("exp.growth"), level)))

static func cap() -> int:
	return int(Balance.num("exp.cap_level"))

## EXP for a kill; monsters 6+ levels below the hero give ×0.3.
static func kill_exp(monster_exp: int, monster_level: int, hero_level: int) -> int:
	if hero_level - monster_level >= int(Balance.num("exp.low_level_gap")):
		return int(round(monster_exp * Balance.num("exp.low_level_mult")))
	return monster_exp

## Adds EXP, levelling up as many times as it covers; at the cap EXP stays 0.
static func add_exp(level: int, exp: int, gain: int) -> Dictionary:
	var lv := level
	var e := exp + gain
	var gained := 0
	while lv < cap() and e >= exp_to_next(lv):
		e -= exp_to_next(lv)
		lv += 1
		gained += 1
	if lv >= cap():
		e = 0
	return {"level": lv, "exp": e, "levels_gained": gained}

## EXP left after dying: minus 5% of the current level bar, never below 0, never de-levels.
static func after_death(level: int, exp: int) -> int:
	if level >= cap(): return 0
	return maxi(0, exp - int(round(Balance.num("exp.death_loss") * exp_to_next(level))))
