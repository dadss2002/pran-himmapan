class_name Balance
## Read-only access to res://data/balance.json (all tuning numbers live there).

const PATH := "res://data/balance.json"
static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		assert(f != null, "missing " + PATH)
		_data = JSON.parse_string(f.get_as_text())
	return _data

static func _lookup(path: String):
	var cur = data()
	for part in path.split("."):
		if typeof(cur) != TYPE_DICTIONARY or not cur.has(part):
			return null
		cur = cur[part]
	return cur

static func has(path: String) -> bool:
	return _lookup(path) != null

static func num(path: String) -> float:
	var v = _lookup(path)
	assert(v != null, "balance.json has no key " + path)
	return float(v)

static func hero(level: int) -> Dictionary:
	var l := level - 1
	return {
		"hp": int(num("hero.hp_base") + num("hero.hp_per_level") * l + num("gear.trainee_armor.hp")),
		"atk": int(num("hero.atk_base") + num("hero.atk_per_level") * l + num("gear.bamboo_bow.atk")),
		"def": int(num("hero.def_base") + num("hero.def_per_level") * l + num("gear.trainee_armor.def")),
	}

static func wolf(level: int) -> Dictionary:
	var l := level - 1
	return {
		"hp": int(num("wolf.hp_base") + num("wolf.hp_per_level") * l),
		"atk": int(num("wolf.atk_base") + num("wolf.atk_per_level") * l),
		"def": int(num("wolf.def_base") + num("wolf.def_per_level") * level),
		"exp": int(num("wolf.exp_base") + num("wolf.exp_per_level") * level),
	}

static func dodge(level: int) -> Dictionary:
	var key := "dodge.lv5" if level >= int(num("dodge.upgrade_level")) else "dodge.lv1"
	return {
		"distance": num(key + ".distance"), "duration": num(key + ".duration"),
		"iframe": num(key + ".iframe"), "cooldown": num(key + ".cooldown"),
	}

static func mp(level: int) -> int:
	return int(num("mp.base") + num("mp.per_level") * (level - 1))
