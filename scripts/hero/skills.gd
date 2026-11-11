class_name Skills
## Active skill numbers (docs/skills.md §1, balance.json "skills"). Skill level = char level −
## unlock level + 1; each level above 1 adds +5% damage and −1% cooldown (cut capped at 30%).

## M5b Task 8a: the three area skills (ห่าศร / กับดักหนาม / ศรเพลิง: docs/skills.md approved 2026-11-06, combos spec
## D1–D8) are data rows like the arrow skills; the skill list everywhere (hero sockets, skill screen, save checks)
## comes from active_ids(), never from a list in code.

## Thai names (docs/skills.md). A skill with no entry shows its id.
const NAMES := {"piercing": "ศรทะลวง", "spread": "ศรกระจาย", "arrow_rain": "ห่าศร", "thorn_trap": "กับดักหนาม", "fire_arrow": "ศรเพลิง"}
## Skills whose own hit carries an element with no gem (D7: ศรเพลิง burns by itself; an element gem takes its place).
const OWN_ELEMENT := {"fire_arrow": "fire"}
const ICON_DIR := "res://assets/skills/"
const ICON_FALLBACK := "res://assets/skills/slot_empty.png"

## True when balance.json has numbers for the skill (skills.<id>.unlock). A skill can have gem labels before it has
## numbers: such a skill has no slots and is never unlocked.
static func exists(id: String) -> bool:
	return Balance.has("skills.%s.unlock" % id)

## Every active skill that has numbers, ordered by unlock level; ties keep the data order
## (piercing, spread, arrow_rain, thorn_trap, fire_arrow). Read from the data on each call (5 rows).
static func active_ids() -> Array:
	var out: Array = []
	var skills: Dictionary = Balance.data()["skills"]
	for id in skills:
		var row = skills[id]
		if typeof(row) != TYPE_DICTIONARY or not row.has("unlock"): continue
		var at := out.size()
		while at > 0 and int(skills[out[at - 1]].unlock) > int(row.unlock): at -= 1      # stable insertion
		out.insert(at, String(id))
	return out

## How the skill is cast: "arrows" (ศรทะลวง, ศรกระจาย, ศรเพลิง), "rain" (ห่าศร) or "trap" (กับดักหนาม).
static func kind(id: String) -> String:
	var row = Balance.data()["skills"].get(id)
	if typeof(row) != TYPE_DICTIONARY: return "arrows"
	return String(row.get("kind", "arrows"))

static func own_element(id: String) -> String:
	return String(OWN_ELEMENT.get(id, ""))

static func display_name(id: String) -> String:
	return String(NAMES.get(id, id))

## The skill's 48 px icon; the empty-slot picture when the skill has none in the project (placeholder-tolerant).
static func icon(id: String) -> String:
	var path := ICON_DIR + id + ".png"
	return path if ResourceLoader.exists(path) else ICON_FALLBACK

## "ลูกศร·ธาตุ·พื้นที่": the skill's gem labels in Thai (same words as Gem.label_text).
static func label_text(id: String) -> String:
	var out: Array = []
	for l in Balance.data()["skill_labels"].get(id, []): out.append(Gem.LABEL_NAMES.get(l, l))
	return "·".join(out)

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
