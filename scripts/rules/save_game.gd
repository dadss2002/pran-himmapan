class_name SaveGame
## Local save (user://save.json). A missing, broken or other-version file never crashes:
## the game starts fresh and a broken file is kept as <name>.bad.json.

const VERSION := 3   # 3 = M3a gems + ตีบวก; versions 1 and 2 are migrated
const PATH := "user://save.json"

static func new_state() -> Dictionary:
	var inv := Inventory.new()
	inv.add("potion_hp", int(Balance.num("potion.start_hp")))
	inv.add("potion_mp", int(Balance.num("potion.start_mp")))
	return {"version": VERSION, "level": 1, "exp": 0, "inventory": inv.to_dict(), "equipped": start_equipped(), "skills": {},
		"waypoints": []}

## Starting kit: ธนูไม้ไผ่ + ชุดพรานฝึกหัด (balance.json "start_gear"), ring/necklace empty.
static func start_equipped() -> Dictionary:
	var eq := {}
	for s in Gear.SLOTS: eq[s] = null
	var start: Dictionary = Balance.data()["start_gear"]
	for s in start: eq[s] = Gear.new_item(String(start[s]))
	return eq

## Item with JSON floats turned back into ints where the game expects them.
## Levels clamp to 1..option_ref_level and option values to their range at Lv10.
static func clean_item(it: Dictionary) -> Dictionary:
	var lvl := clampi(int(it.level), 1, int(Balance.num("option_ref_level")))
	var opts: Array = []
	for o in it.get("opts", []):
		var top := Gear.option_range(String(o.k), int(Balance.num("option_ref_level")))
		opts.append({"k": String(o.k), "v": clampf(float(o.v), 0.0, top.y)})
	return {"base": String(it.base), "rarity": String(it.rarity), "level": lvl, "opts": opts, "plus": int(it.get("plus", 0))}

## Gem with JSON floats turned back into ints.
static func clean_gem(g: Dictionary) -> Dictionary:
	var opts: Array = []
	for o in g.get("opts", []): opts.append({"k": String(o.k), "v": float(o.v)})
	var out := {"type": String(g.type), "level": int(g.level), "exp": int(g.exp), "rarity": String(g.rarity), "opts": opts}
	if g.has("element"): out["element"] = String(g.element)
	return out

static func _rarities() -> Array:
	var out := []
	for r in Balance.data()["rarity"]: out.append(r.id)
	return out

static func _num(v) -> bool:
	return typeof(v) in [TYPE_INT, TYPE_FLOAT]

## A gem the game can load: known type, level 1..cap, EXP >= 0, known rarity, unique options in range,
## an element only (and always) on element gems.
static func _gem_ok(g) -> bool:
	if typeof(g) != TYPE_DICTIONARY or typeof(g.get("type")) != TYPE_STRING: return false
	if not (g.type in Gem.types()): return false
	if not _num(g.get("level")) or int(g.level) < 1 or int(g.level) > Gem.cap(): return false
	if not _num(g.get("exp")) or int(g.exp) < 0: return false
	if not (g.get("rarity") in _rarities()): return false
	if (g.type == "element") != g.has("element"): return false
	if g.has("element") and not Balance.data()["elements"].has(String(g.element)): return false
	var opts = g.get("opts", [])
	if typeof(opts) != TYPE_ARRAY: return false
	var seen := {}
	for o in opts:
		if typeof(o) != TYPE_DICTIONARY or not Balance.data()["gem_options"].has(String(o.get("k", ""))): return false
		if not _num(o.get("v")) or seen.has(o.k): return false
		var d: Dictionary = Balance.data()["gem_options"][o.k]
		if float(o.v) < float(d.min) - 0.0011 or float(o.v) > float(d.max) + 0.0011: return false
		seen[o.k] = true
	return true

## Sockets: known skill → up to 4 slots of null or a fitting gem.
static func _skills_ok(sk) -> bool:
	if typeof(sk) != TYPE_DICTIONARY: return false
	for id in sk:
		if not Balance.data()["skill_labels"].has(String(id)): return false
		if typeof(sk[id]) != TYPE_ARRAY or sk[id].size() > Balance.data()["gem_slots"].size(): return false
		for g in sk[id]:
			if g != null and (not _gem_ok(g) or not Gem.fits(String(g.type), String(id))): return false
	return true

static func _item_ok(it, slot := "") -> bool:
	if typeof(it) != TYPE_DICTIONARY: return false
	if typeof(it.get("base")) != TYPE_STRING or not Gear.is_gear(it.base): return false
	if slot != "" and Gear.slot_of(it.base) != slot: return false
	var rarities := []
	for r in Balance.data()["rarity"]: rarities.append(r.id)
	if not (it.get("rarity") in rarities): return false
	if not (typeof(it.get("level")) in [TYPE_INT, TYPE_FLOAT]): return false
	if it.has("plus") and (not _num(it.plus) or int(it.plus) < 0 or int(it.plus) > Enhance.max_plus()): return false
	var opts = it.get("opts", [])
	if typeof(opts) != TYPE_ARRAY: return false
	var seen := {}
	for o in opts:
		if typeof(o) != TYPE_DICTIONARY or not Balance.data()["options"].has(String(o.get("k", ""))): return false
		if not (typeof(o.get("v")) in [TYPE_INT, TYPE_FLOAT]): return false
		if seen.has(o.k): return false
		seen[o.k] = true
	return true

static func _equipped_ok(eq) -> bool:
	if typeof(eq) != TYPE_DICTIONARY: return false
	if eq.get("bow") == null: return false          # arrows need a bow
	for s in Gear.SLOTS:
		if eq.get(s) != null and not _item_ok(eq.get(s), s): return false
	return true

static func save(state: Dictionary, path := PATH) -> bool:
	var data := state.duplicate(true)
	data["version"] = VERSION
	if not data.has("equipped"): data["equipped"] = start_equipped()
	if not data.has("skills"): data["skills"] = {}
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null: return false
	f.store_string(JSON.stringify(data))
	f.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path)) == OK

static func load_or_new(path := PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return new_state()
	var text := FileAccess.get_file_as_string(path)
	var j := JSON.new()
	var d = j.data if j.parse(text) == OK else null
	if typeof(d) == TYPE_DICTIONARY and int(d.get("version", -1)) == 1:
		d["version"] = 2                       # M2b save: keep progress, wear the starting kit
		d["equipped"] = start_equipped()
	if typeof(d) == TYPE_DICTIONARY and int(d.get("version", -1)) == 2:
		d["version"] = VERSION                 # M2c save: gems stay stacked (plain), plus 0, no sockets
		d["skills"] = {}
	var ok: bool = typeof(d) == TYPE_DICTIONARY and int(d.get("version", -1)) == VERSION \
		and d.has("level") and d.has("exp") and _inventory_ok(d.get("inventory")) \
		and _equipped_ok(d.get("equipped")) and _skills_ok(d.get("skills", {}))
	if not ok:
		var bad := path.get_basename() + ".bad.json"
		DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(bad))
		return new_state()
	var eq := {}
	for sl in Gear.SLOTS:
		eq[sl] = clean_item(d.equipped[sl]) if d.equipped.get(sl) != null else null
	d.equipped = eq
	var sk := {}
	for id in d.get("skills", {}):
		sk[String(id)] = []
		for g in d.skills[id]: sk[String(id)].append(clean_gem(g) if g != null else null)
	d.skills = sk
	# Task 5: unlocked waypoint stones (room ids). Older saves have none (the start stone is always unlocked:
	# Waypoints.load_save); anything but strings is dropped instead of failing the whole save.
	var wps: Array = []
	var saved_wps = d.get("waypoints", [])
	if typeof(saved_wps) == TYPE_ARRAY:
		for id in saved_wps:
			if typeof(id) == TYPE_STRING and not wps.has(id): wps.append(id)
	d["waypoints"] = wps
	# Owner 2026-11-08: the fog comes back with every new game and loading is a new game, so the fog is no longer
	# saved. Saves from Task 6 may still hold a "fog" key (any value): it is dropped, the rest of the save loads.
	d.erase("fog")
	d.version = VERSION
	d.level = clampi(int(d.level), 1, Progression.cap())
	d.exp = 0 if d.level >= Progression.cap() else clampi(int(d.exp), 0, Progression.exp_to_next(d.level) - 1)
	return d

## A bag the game can load: {gold >= 0, slots: up to bag.slots of {id: String, count: 1..bag.stack}}.
static func _inventory_ok(inv) -> bool:
	if typeof(inv) != TYPE_DICTIONARY: return false
	if not (typeof(inv.get("gold", 0)) in [TYPE_INT, TYPE_FLOAT]) or float(inv.get("gold", 0)) < 0: return false
	var slots = inv.get("slots", [])
	if typeof(slots) != TYPE_ARRAY or slots.size() > int(Balance.num("bag.slots")): return false
	for s in slots:
		if typeof(s) != TYPE_DICTIONARY or typeof(s.get("id")) != TYPE_STRING: return false
		if not (typeof(s.get("count")) in [TYPE_INT, TYPE_FLOAT]): return false
		if int(s.count) < 1 or int(s.count) > int(Balance.num("bag.stack")): return false
		if s.has("item") and (int(s.count) != 1 or not _item_ok(s.item) or String(s.item.base) != String(s.id)): return false
		if not s.has("item") and Gear.is_gear(String(s.id)): return false     # gear must carry its item data
		if s.has("gem") and (int(s.count) != 1 or not _gem_ok(s.gem) or "gem_" + String(s.gem.type) != String(s.id)): return false
		if String(s.id).begins_with("gem_") and not (String(s.id).trim_prefix("gem_") in Gem.types()): return false
	return true
