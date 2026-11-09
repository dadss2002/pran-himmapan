class_name GemCombo
## Gem combos (M5b, docs/superpowers/specs/2026-11-08-gem-combos.md). Pure rules, no scene access.
## Two gems that form a recipe on one skill = a combo (tier 2); three = an advanced combo (tier 3) that
## replaces its 2-gem base(s). Recipes and every number: balance.json gem_combos.recipes, in recipe-book order.
## Owner 2026-11-09: one combo per skill (higher tier first, then book order); combo values do not grow with
## gem level (resolve ignores gem levels); 3-gem rows read literally.
## Callers pass the OPEN sockets only (Hero.open_gems): a gem in a closed slot never forms a combo.

const ELEMENT_KEYS := ["fire", "ice", "lightning"]

static func _rows() -> Array:
	return Balance.data().get("gem_combos", {}).get("recipes", [])

## Recipe rows in data (= recipe-book) order.
static func recipes() -> Array:
	return _rows()

static func ids() -> Array:
	var out: Array = []
	for row in _rows(): out.append(String(row.id))
	return out

## The recipe row, {} when the id is unknown.
static func recipe(id: String) -> Dictionary:
	for row in _rows():
		if String(row.id) == id: return row
	return {}

## A number of a recipe ("trail_frac", "kill_mp_cap", ...), `default` when the row does not have it.
static func p(id: String, key: String, default := 0.0) -> float:
	var row := recipe(id)
	if not row.has(key): return default
	return float(row[key])

## A socketed gem's recipe key: its type, or its element (fire / ice / lightning) for an element gem.
## "" for an element gem with no element yet, or anything that is not a gem.
static func gem_key(gem) -> String:
	if typeof(gem) != TYPE_DICTIONARY: return ""
	var t := String(gem.get("type", ""))
	if t == "element": return String(gem.get("element", ""))
	return t

## The gem type behind a recipe key ("fire" → "element").
static func key_type(key: String) -> String:
	return "element" if key in ELEMENT_KEYS else key

## Thai name of a recipe key for the recipe book: "ธาตุไฟ", "แยกศร".
static func key_name(key: String) -> String:
	if key in ELEMENT_KEYS:
		return "ธาตุ" + String(Balance.data()["elements"].get(key, {}).get("name", key))
	return Gem.display_name(key).trim_prefix("เจม")

## The one combo `gems` form on `skill_id`: {} or {"id", "tier", "name", "slots"} (socket indices of the
## recipe's gems, ascending). Gems that are not Dictionaries or do not fit the skill are ignored; gems outside
## the recipe keep their own effect. Highest tier wins; ties go to data order.
static func resolve(skill_id: String, gems: Array) -> Dictionary:
	var at := {}      # key → first socket index holding it
	for i in gems.size():
		var g = gems[i]
		if typeof(g) != TYPE_DICTIONARY: continue
		var key := gem_key(g)
		if key == "" or at.has(key): continue
		if not Gem.fits(key_type(key), skill_id): continue
		at[key] = i
	if at.size() < 2: return {}
	var best := {}
	for row in _rows():
		var tier := int(row.tier)
		if not best.is_empty() and tier <= int(best.tier): continue
		var all := true
		for k in row.gems:
			if not at.has(String(k)): all = false
		if all: best = row
	if best.is_empty(): return {}
	var slots: Array = []
	for k in best.gems: slots.append(at[String(k)])
	slots.sort()
	return {"id": String(best.id), "tier": int(best.tier), "name": String(best.name), "slots": slots}

static func _pct(v: float) -> String:
	return Gear._trim(v * 100.0) + "%"

static func _n(v: float) -> String:
	return Gear._trim(v)

## The Thai effect line (spec §1 ผลพิเศษ / §2 ผล), numbers from data. "" for an unknown id.
## No boss-slow clause on the frost rows: owner 2026-11-08 "บอสแข็งได้เหมือนมอนอื่น".
static func describe(id: String) -> String:
	var r := recipe(id)
	if r.is_empty(): return ""
	var f := func(k: String) -> float: return float(r.get(k, 0.0))
	match id:
		"fire_fan":
			return "ทางไฟตามแนวลูกศร %s วิ ไหม้ %s ของแรงลูกศร/วิ (ไม่ซ้อนกันเอง)" % [_n(f.call("trail_secs")), _pct(f.call("trail_frac"))]
		"thunder_hop":
			return "เด้งเพิ่ม +%d ครั้ง และทุกครั้งที่เด้งปล่อยสายฟ้า %s ใส่ตัวใกล้สุด" % [int(f.call("extra_bounces")), _pct(f.call("bolt_frac"))]
		"hawk_eye":
			return "นำวิถีไม่ลดแรง · คริ +%s · โดนแล้วมาร์ก %s วิ เป้ารับดาเมจทุกอย่าง +%s" % [_pct(f.call("crit_bonus")), _n(f.call("mark_secs")), _pct(f.call("mark_taken"))]
		"bloodthirst":
			return "ดูดเลือดสกิลนี้ ×%s · ฆ่าได้ฟื้น HP %s และ MP +%d (สูงสุด %d MP ต่อการกด 1 ครั้ง)" % [_n(f.call("leech_mult")), _pct(f.call("kill_heal_frac")), int(f.call("kill_mp")), int(f.call("kill_mp_cap"))]
		"frost_shard":
			return "โดนครบ %d ดอกในเป้าเดียว แข็ง %s วิ (เป้าละครั้งทุก %s วิ) · ลูกศรสกิลนี้แรง +%s ใส่เป้าที่ช้าหรือแข็ง" % [int(f.call("freeze_hits")), _n(f.call("freeze_secs")), _n(f.call("freeze_lock_secs")), _pct(f.call("bonus_vs_chilled"))]
		"shockwave":
			return "ทะลุแต่ละตัวเกิดวงกระแทก r%d แรง %s" % [int(f.call("blast_radius")), _pct(f.call("blast_frac"))]
		"hunter_zone":
			return "มอนในวงช้าลง %s และรับดาเมจทุกอย่าง +%s" % [_pct(f.call("zone_slow")), _pct(f.call("zone_taken"))]
		"fire_burst":
			return "วงไฟใหญ่ขึ้นอีก +%s ติดไหม้ทุกตัวในวง" % _pct(f.call("area_radius_bonus"))
		"brahmastra":
			return "ทางไฟ %s วิ ไหม้ %s/วิ · ปลายแต่ละแนวระเบิดไฟ r%d แรง %s" % [_n(f.call("trail_secs")), _pct(f.call("trail_frac")), int(f.call("blast_radius")), _pct(f.call("blast_frac"))]
		"thousand_bolts":
			return "ลูกศรทุกแนวเด้ง · ทุกครั้งที่เด้งสายฟ้าแตก %d สาย สายละ %s" % [int(f.call("bolts")), _pct(f.call("bolt_frac"))]
		"garuda":
			return "นำวิถีไม่ลดแรง · คริ +%s · มาร์ก %s วิ +%s · สกิลนี้โดนเป้าที่ติดมาร์ก = คริแน่นอน" % [_pct(f.call("crit_bonus")), _n(f.call("mark_secs")), _pct(f.call("mark_taken"))]
		"anodard":
			return "โดนครบ %d ดอก แข็ง %s วิ (เป้าละครั้งทุก %s วิ) · โดนเป้าที่แข็ง/ช้า = คริแน่นอน และแตกผลึก r%d แรง %s" % [int(f.call("freeze_hits")), _n(f.call("freeze_secs")), _n(f.call("freeze_lock_secs")), int(f.call("blast_radius")), _pct(f.call("blast_frac"))]
		"rahu":
			return "HP ≥ %s: สกิลนี้แรง +%s · ดูดเลือด ×%s · คริฟื้น HP %s · ฆ่าได้ MP +%d (สูงสุด %d ต่อการกด)" % [_pct(f.call("hp_min")), _pct(f.call("hp_bonus")), _n(f.call("leech_mult")), _pct(f.call("crit_heal_frac")), int(f.call("kill_mp")), int(f.call("kill_mp_cap"))]
		"hellfield":
			return "วงกลายเป็นทุ่งไฟ: ช้าลง %s · รับดาเมจ +%s · ไหม้ทุกตัวในวง" % [_pct(f.call("zone_slow")), _pct(f.call("zone_taken"))]
		"earth_piercer":
			return "ทะลุแต่ละตัวระเบิด r%d แรง %s ติดไหม้" % [int(f.call("blast_radius")), _pct(f.call("blast_frac"))]
		"meteor_rain":
			return "ลูกศรทุกดอกระเบิด r%d ดอกละ %s" % [int(f.call("blast_radius")), _pct(f.call("blast_frac"))]
	return ""
