class_name SaveGame
## Local save (user://save.json). A missing, broken or other-version file never crashes:
## the game starts fresh and a broken file is kept as <name>.bad.json.

const VERSION := 2   # 2 = M2c equipment; version-1 saves are migrated
const PATH := "user://save.json"

static func new_state() -> Dictionary:
	var inv := Inventory.new()
	inv.add("potion_hp", int(Balance.num("potion.start_hp")))
	inv.add("potion_mp", int(Balance.num("potion.start_mp")))
	return {"version": VERSION, "level": 1, "exp": 0, "inventory": inv.to_dict(), "equipped": start_equipped()}

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
	return {"base": String(it.base), "rarity": String(it.rarity), "level": lvl, "opts": opts}

static func _item_ok(it, slot := "") -> bool:
	if typeof(it) != TYPE_DICTIONARY: return false
	if typeof(it.get("base")) != TYPE_STRING or not Gear.is_gear(it.base): return false
	if slot != "" and Gear.slot_of(it.base) != slot: return false
	var rarities := []
	for r in Balance.data()["rarity"]: rarities.append(r.id)
	if not (it.get("rarity") in rarities): return false
	if not (typeof(it.get("level")) in [TYPE_INT, TYPE_FLOAT]): return false
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
		d["version"] = VERSION                 # M2b save: keep progress, wear the starting kit
		d["equipped"] = start_equipped()
	var ok: bool = typeof(d) == TYPE_DICTIONARY and int(d.get("version", -1)) == VERSION \
		and d.has("level") and d.has("exp") and _inventory_ok(d.get("inventory")) \
		and _equipped_ok(d.get("equipped"))
	if not ok:
		var bad := path.get_basename() + ".bad.json"
		DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(bad))
		return new_state()
	var eq := {}
	for sl in Gear.SLOTS:
		eq[sl] = clean_item(d.equipped[sl]) if d.equipped.get(sl) != null else null
	d.equipped = eq
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
	return true
