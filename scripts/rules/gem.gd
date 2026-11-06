class_name Gem
## Support gems (docs/gems.md, M3a design §5–§6). A gem is
## {type, level, exp, rarity, opts: [{k, v}], element?}. The main effect grows with gem level
## ("+per_level" for each level above 1); random options are fixed when the gem drops.

static func data(type: String) -> Dictionary:
	return Balance.data()["gem_effects"].get(type, {})

static func types() -> Array:
	return Balance.data()["gem_effects"].keys()

## A new Lv1 gem with a rarity (gear rarity table) and that many unique skill-only options.
static func roll(type: String, rng: RandomNumberGenerator, rarity := "") -> Dictionary:
	var r := rarity if rarity != "" else Gear.roll_rarity(rng)
	var keys: Array = Balance.data()["gem_options"].keys()
	var opts: Array = []
	var n := 0
	for row in Balance.data()["rarity"]:
		if row.id == r: n = int(row.options)
	for i in mini(n, keys.size()):
		var k: String = keys.pop_at(rng.randi_range(0, keys.size() - 1))
		var o: Dictionary = Balance.data()["gem_options"][k]
		opts.append({"k": k, "v": snappedf(rng.randf_range(float(o.min), float(o.max)), 0.001)})
	var g := {"type": type, "level": 1, "exp": 0, "rarity": r, "opts": opts}
	if type == "element":
		var els: Array = Balance.data()["elements"].keys()
		g["element"] = els[rng.randi_range(0, els.size() - 1)]
	return g

## Main effect at the gem's level: value + per_level × (level − 1).
static func effect(gem: Dictionary) -> float:
	var d := data(String(gem.type))
	return float(d.get("value", 0)) + float(d.get("per_level", 0)) * (int(gem.level) - 1)

static func mp_mult(type: String) -> float:
	return float(data(type).get("mp", 1.0))

## The rolled option value (fixed at drop), 0 when the gem does not have it.
static func option(gem: Dictionary, key: String) -> float:
	var v := 0.0
	for o in gem.get("opts", []):
		if o.k == key: v += float(o.v)
	return v

static func exp_to_next(level: int) -> int:
	return int(round(Balance.num("gem_exp.base") * pow(level, Balance.num("gem_exp.power"))))

static func cap() -> int:
	return int(Balance.num("gem_exp.cap"))

## Adds EXP; returns levels gained. At the cap EXP stays 0.
static func add_exp(gem: Dictionary, amount: int) -> int:
	var ups := 0
	if int(gem.level) >= cap():
		gem.exp = 0
		return 0
	gem.exp = int(gem.exp) + amount
	while int(gem.level) < cap() and int(gem.exp) >= exp_to_next(int(gem.level)):
		gem.exp = int(gem.exp) - exp_to_next(int(gem.level))
		gem.level = int(gem.level) + 1
		ups += 1
	if int(gem.level) >= cap(): gem.exp = 0
	return ups

## True when the gem's labels match the skill's (or the gem fits any skill).
static func fits(type: String, skill_id: String) -> bool:
	var labels: Array = data(type).get("labels", [])
	if "any" in labels: return Balance.data()["skill_labels"].has(skill_id)
	for l in Balance.data()["skill_labels"].get(skill_id, []):
		if l in labels: return true
	return false

## Gem slots for a skill level (0 = locked skill).
static func slots_for(skill_level: int) -> int:
	var n := 0
	for t in Balance.data()["gem_slots"]:
		if skill_level >= int(t): n += 1
	return n

## Lv1 common gem with no EXP, options or element: these may stack in the bag.
static func is_plain(gem: Dictionary) -> bool:
	return int(gem.get("level", 1)) == 1 and int(gem.get("exp", 0)) == 0 and String(gem.get("rarity", "common")) == "common" \
		and gem.get("opts", []).is_empty() and not gem.has("element")

static var _items := {}
static func display_name(type: String) -> String:
	if _items.is_empty(): _items = JSON.parse_string(FileAccess.open("res://data/items.json", FileAccess.READ).get_as_text())
	return String(_items.get("gem_" + type, {}).get("name", type))

static func _pct(v: float) -> String:
	return Gear._trim(v * 100.0) + "%"

## What the gem does at its level, in Thai (numbers from balance.json).
static func describe_effect(gem: Dictionary) -> String:
	var t := String(gem.type)
	var d := data(t)
	var e := effect(gem)
	var high := int(gem.level) >= 10
	match t:
		"split": return "ยิงเพิ่ม +%d ดอก ทุกดอกแรง %s" % [int(d.extra_arrows), _pct(e)]
		"ricochet": return "โดนแล้วเด้งไปอีก %d เป้า แรง %s" % [int(d.bounces_at_10) if high else int(d.bounces), _pct(e)]
		"pierce": return "ทะลุเป้าเพิ่ม %d ตัว" % (int(d.extra_at_10) if high else int(d.extra))
		"homing": return "ลูกศรวิ่งตามเป้า แรง %s" % _pct(e)
		"multiply": return "ดาเมจ ×%s" % ("%.2f" % e)
		"expand": return "วงกว้างขึ้น +%s" % _pct(e)
		"extend": return "อยู่นานขึ้น +%s" % _pct(e)
		"execute": return "คริสกิลนี้ +%s" % _pct(e)
		"leech": return "ฟื้นเลือด %s ของดาเมจ" % _pct(e)
		"element":
			var el := String(gem.get("element", ""))
			var ed: Dictionary = Balance.data()["elements"].get(el, {})
			var extra := ""
			match el:
				"fire": extra = "ไหม้ %s/วิ นาน %s วิ" % [_pct(float(ed.burn_frac)), Gear._trim(float(ed.duration))]
				"ice": extra = "ช้าลง %s นาน %s วิ" % [_pct(float(ed.slow)), Gear._trim(float(ed.duration))]
				"lightning": extra = "กระโดดไปอีก 1 ตัว แรง %s" % _pct(float(ed.mult))
			return "ธาตุ%s: ดาเมจ ×%s · %s" % [String(ed.get("name", "")), "%.2f" % e, extra]
	return ""

static func label_text(type: String) -> String:
	var names := {"arrow": "ลูกศร", "any": "ทุกสกิล", "area": "พื้นที่", "dot": "ต่อเนื่อง", "trap": "กับดัก"}
	var out: Array = []
	for l in data(type).get("labels", []): out.append(names.get(l, l))
	return "·".join(out)

## "คูลดาวน์สกิลนี้ −6%"
static func describe_option(o: Dictionary) -> String:
	var d: Dictionary = Balance.data()["gem_options"][o.k]
	return "%s %s%s%%" % [d.name, "−" if bool(d.get("minus", false)) else "+", Gear._trim(float(o.v) * 100.0)]
