class_name Skills
## Active skill numbers (docs/skills.md §1, balance.json "skills"). Skill level = char level −
## unlock level + 1; each level above 1 adds +5% damage and −1% cooldown (cut capped at 30%).

## True when balance.json has numbers for the skill (skills.<id>.unlock). A skill can have gem labels before it has
## numbers (ห่าศร until M5b builds it): such a skill has no slots and is never unlocked.
static func exists(id: String) -> bool:
	return Balance.has("skills.%s.unlock" % id)

static func unlock_level(id: String) -> int:
	return int(Balance.num("skills.%s.unlock" % id))

static func skill_level(id: String, char_level: int) -> int:
	return maxi(0, char_level - unlock_level(id) + 1)

static func damage_mult(id: String, char_level: int) -> float:
	var lv := maxi(1, skill_level(id, char_level))
	return Balance.num("skills.%s.mult" % id) * (1.0 + Balance.num("skills.per_level_damage") * (lv - 1))

## extra_cut = cooldown cut from gear; the total cut is still capped at skills.max_cooldown_cut.
static func cooldown(id: String, char_level: int, extra_cut := 0.0) -> float:
	var lv := maxi(1, skill_level(id, char_level))
	var cut := minf(Balance.num("skills.per_level_cooldown") * (lv - 1) + extra_cut, Balance.num("skills.max_cooldown_cut"))
	return Balance.num("skills.%s.cooldown" % id) * (1.0 - cut)

static func mp_cost(id: String) -> float:
	return Balance.num("skills.%s.mp" % id)
