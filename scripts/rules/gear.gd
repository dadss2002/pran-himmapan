class_name Gear
## Equipment rules (docs/spec-numbers.md §5–§6, M2 design §5.6). Pure functions on balance.json.
## An item is {base, rarity, level, opts: [{k, v}]}; percent options are fractions (0.052 = 5.2%).

const SLOTS := ["bow", "armor", "ring", "necklace"]
const WHOLE := ["hp", "def", "mp"]          # flat options shown as whole numbers

static func base(id: String) -> Dictionary:
	return Balance.data()["gear"].get(id, {})

static func is_gear(id: String) -> bool:
	return Balance.data()["gear"].has(id)

static func slot_of(id: String) -> String:
	return String(base(id).get("slot", ""))

static func req_level(id: String) -> int:
	return int(base(id).get("level", 1))

static func display_name(id: String) -> String:
	return String(base(id).get("name", id))

static func icon_name(id: String) -> String:
	return String(base(id).get("icon", id))

static func _rarity(id: String) -> Dictionary:
	for r in Balance.data()["rarity"]:
		if r.id == id: return r
	return Balance.data()["rarity"][0]

static func rarity_color(id: String) -> Color:
	return Color(String(_rarity(id).color))

static func rarity_name(id: String) -> String:
	return String(_rarity(id).name)

## Rarity index (0 = common) so "rare and up" checks are simple.
static func rarity_rank(id: String) -> int:
	var list: Array = Balance.data()["rarity"]
	for i in list.size():
		if list[i].id == id: return i
	return 0

static func roll_rarity(rng: RandomNumberGenerator) -> String:
	var x := rng.randf()
	var acc := 0.0
	for r in Balance.data()["rarity"]:
		acc += float(r.chance)
		if x < acc: return String(r.id)
	return String(Balance.data()["rarity"][0].id)   # rounding leftovers count as common

## The option's range for an item of this level: Lv10 range × level/10, at least option_floor of it.
static func option_range(k: String, item_level: int) -> Vector2:
	var o: Dictionary = Balance.data()["options"][k]
	var f := maxf(float(item_level) / Balance.num("option_ref_level"), Balance.num("option_floor"))
	return Vector2(float(o.min) * f, float(o.max) * f)

static func _step(k: String) -> float:
	if k in WHOLE: return 1.0
	if bool(Balance.data()["options"][k].get("pct", false)): return 0.001
	return 0.1

static func _roll_value(k: String, item_level: int, rng: RandomNumberGenerator) -> float:
	var rg := option_range(k, item_level)
	var st := _step(k)
	var lo := ceilf(rg.x / st - 1e-6) * st
	var hi := floorf(rg.y / st + 1e-6) * st
	if lo > hi: return snappedf(rg.x, st)
	return clampf(snappedf(rng.randf_range(rg.x, rg.y), st), lo, hi)

## Rolls an item. Bows and armor have their required level; ring/necklace take the source level.
static func roll_item(id: String, source_level: int, rng: RandomNumberGenerator, rarity := "") -> Dictionary:
	var r := rarity if rarity != "" else roll_rarity(rng)
	var lvl := clampi(source_level, 1, int(Balance.num("option_ref_level"))) if bool(base(id).get("from_source", false)) else req_level(id)
	var keys: Array = Balance.data()["options"].keys()
	var opts: Array = []
	for i in int(_rarity(r).options):
		var k: String = keys.pop_at(rng.randi_range(0, keys.size() - 1))
		opts.append({"k": k, "v": _roll_value(k, lvl, rng)})
	return {"base": id, "rarity": r, "level": lvl, "opts": opts}

static func new_item(id: String) -> Dictionary:
	return {"base": id, "rarity": "common", "level": req_level(id), "opts": []}

## Sum of main stats and options of everything worn. Missing slots count as nothing.
static func totals(equipped: Dictionary) -> Dictionary:
	var t := {}
	for k in Balance.data()["options"]: t[k] = 0.0   # includes the flat "hp", "def", "mp"
	t["atk"] = 0
	for s in SLOTS:
		var it = equipped.get(s)
		if typeof(it) != TYPE_DICTIONARY: continue
		var b := base(String(it.base))
		t.atk += int(b.get("atk", 0))
		t.def += float(b.get("def", 0))
		t.hp += float(b.get("hp", 0))
		for o in it.get("opts", []):
			t[o.k] += float(o.v)
	for k in WHOLE: t[k] = int(round(t[k]))
	return t

## "ATK +5.2%", "คูลดาวน์สกิล −4.1%", "HP +34", "ฟื้น MP +0.8/วิ"
static func describe_option(o: Dictionary) -> String:
	var d: Dictionary = Balance.data()["options"][o.k]
	var sign := "−" if bool(d.get("minus", false)) else "+"
	var v := float(o.v)
	var num := ""
	if bool(d.get("pct", false)): num = "%s%%" % _trim(v * 100.0)
	elif o.k in WHOLE: num = str(int(round(v)))
	else: num = _trim(v)
	return "%s %s%s%s" % [d.name, sign, num, String(d.get("suffix", ""))]

static func _trim(v: float) -> String:
	var s := "%.1f" % v
	return s.trim_suffix(".0")
