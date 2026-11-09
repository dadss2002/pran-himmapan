class_name SaveGame
## Local save (user://save.json; on the web user:// lives in the browser's IndexedDB). A missing, broken or
## other-version file never crashes: the game starts fresh and a broken file is kept as <name>.bad.json.
##
## Save hardening (docs/superpowers/specs/2026-11-09-save-hardening.md, owner-approved 2026-11-09):
## - Signed: "sig" = HMAC-SHA256 (key SIG_KEY) of canonical() of the save without "sig". A wrong or missing
##   signature on a version-4 save = a broken save (Q1 a).
## - Old unsigned saves (version 1..3, made before signing) pass the same checks, load and are written back signed
##   at once (Q2 a), but only while this device has never written a signed save (marker file <name>.signed): a
##   hand-made unsigned file is not accepted after that. Deleting the marker re-opens that door (docs/risks.md S5).
## - Any value out of range fails the whole save (Q3 a): nothing is clamped any more, except a JSON float
##   round-trip tolerance (TOL) on option values.
## - Files larger than save.max_bytes are refused before parsing.

const VERSION := 4   # 4 = signed + strict ranges; 3 = M3a gems + ตีบวก; versions 1..3 are migrated
const PATH := "user://save.json"
## Option values may come back from JSON a hair off; anything further out of range fails the save.
const TOL := 0.0011
## SPEED BUMP ONLY (docs/risks.md S5/S6): this key ships inside the game (.pck / .wasm) and the repo is public, so
## anyone who reads the code can sign an edited save. It stops casual editing of the save file, nothing more. A
## save signed with it must never be trusted for trade, co-op or a cash shop (that needs a server).
const SIG_KEY := "PRAN Hunter of Himmapan / save v4 / speed bump only - this key ships inside the game"

## The file that says this device has written a signed save (Q2: old unsigned saves are accepted only before it).
static func marker_path(path := PATH) -> String:
	return path.get_basename() + ".signed"

static var _item_ids := {}
## A bag id the game knows: equipment, gem_<known type>, or a stackable with an entry in data/items.json.
static func known_item(id: String) -> bool:
	if Gear.is_gear(id): return true
	if id.begins_with("gem_"): return id.trim_prefix("gem_") in Gem.types()
	if _item_ids.is_empty():
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
		if typeof(d) == TYPE_DICTIONARY:
			for k in d:
				if not String(k).begins_with("_"): _item_ids[String(k)] = true
	return _item_ids.has(id)

static var _stones: Array = []
## Room ids with a waypoint stone (data/rooms.json): the only ids a save's "waypoints" may hold.
static func stone_ids() -> Array:
	if _stones.is_empty():
		var rs := RoomSet.open()
		if rs != null: _stones = Array(rs.waypoint_ids())
	return _stones

## Deterministic text of a parsed save for signing: keys sorted, numbers as %.6f (so a float that JSON brings back
## a hair off still signs the same), strings JSON-escaped.
static func canonical(v) -> String:
	match typeof(v):
		TYPE_DICTIONARY:
			var keys: Array = []
			for k in v: keys.append(k)
			keys.sort_custom(func(a, b): return String(a) < String(b))
			var parts := PackedStringArray()
			for k in keys: parts.append(JSON.stringify(String(k)) + ":" + canonical(v[k]))
			return "{" + ",".join(parts) + "}"
		TYPE_ARRAY:
			var parts := PackedStringArray()
			for x in v: parts.append(canonical(x))
			return "[" + ",".join(parts) + "]"
		TYPE_INT, TYPE_FLOAT: return "%.6f" % float(v)
		TYPE_STRING, TYPE_STRING_NAME: return JSON.stringify(String(v))
		TYPE_BOOL: return "true" if v else "false"
		TYPE_NIL: return "null"
	return JSON.stringify(v)

## HMAC-SHA256 (hex) of the save without its "sig".
static func signature(d: Dictionary) -> String:
	var body := d.duplicate()
	body.erase("sig")
	var ctx := HMACContext.new()
	if ctx.start(HashingContext.HASH_SHA256, SIG_KEY.to_utf8_buffer()) != OK: return ""
	ctx.update(canonical(body).to_utf8_buffer())
	return ctx.finish().hex_encode()

static func _sig_ok(d: Dictionary) -> bool:
	return typeof(d.get("sig")) == TYPE_STRING and String(d.sig).length() == 64 and String(d.sig) == signature(d)

## A whole number lo..hi (JSON brings every number back as a float).
static func _int_in(v, lo: int, hi: int) -> bool:
	return _num(v) and is_finite(float(v)) and float(v) == floorf(float(v)) and float(v) >= lo and float(v) <= hi

static func _rarity_options(r: String) -> int:
	for row in Balance.data()["rarity"]:
		if row.id == r: return int(row.options)
	return 0

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

## Item with JSON floats turned back into ints where the game expects them. Loading refuses anything out of range
## first (_item_ok, owner Q3 a), so the clamps here only ever move an option value by the float tolerance TOL.
static func clean_item(it: Dictionary) -> Dictionary:
	var lvl := clampi(roundi(float(it.level)), 1, int(Balance.num("option_ref_level")))
	var opts: Array = []
	for o in it.get("opts", []):
		var top := Gear.option_range(String(o.k), int(Balance.num("option_ref_level")))
		opts.append({"k": String(o.k), "v": clampf(float(o.v), 0.0, top.y)})
	return {"base": String(it.base), "rarity": String(it.rarity), "level": lvl, "opts": opts, "plus": roundi(float(it.get("plus", 0)))}

## Gem with JSON floats turned back into ints.
static func clean_gem(g: Dictionary) -> Dictionary:
	var opts: Array = []
	for o in g.get("opts", []): opts.append({"k": String(o.k), "v": float(o.v)})
	var out := {"type": String(g.type), "level": roundi(float(g.level)), "exp": roundi(float(g.exp)), "rarity": String(g.rarity), "opts": opts}
	if g.has("element"): out["element"] = String(g.element)
	return out

static func _rarities() -> Array:
	var out := []
	for r in Balance.data()["rarity"]: out.append(r.id)
	return out

static func _num(v) -> bool:
	return typeof(v) in [TYPE_INT, TYPE_FLOAT]

## A gem the game can load: known type, level 1..cap, EXP 0..next level - 1, known rarity, no more options than
## its rarity rolls, unique options in range, an element only (and always) on element gems.
static func _gem_ok(g) -> bool:
	if typeof(g) != TYPE_DICTIONARY or typeof(g.get("type")) != TYPE_STRING: return false
	if not (g.type in Gem.types()): return false
	if not _int_in(g.get("level"), 1, Gem.cap()): return false
	if not _int_in(g.get("exp"), 0, maxi(0, Gem.exp_to_next(int(g.level)) - 1)): return false
	if not (g.get("rarity") in _rarities()): return false
	if (g.type == "element") != g.has("element"): return false
	if g.has("element") and not Balance.data()["elements"].has(String(g.element)): return false
	var opts = g.get("opts", [])
	if typeof(opts) != TYPE_ARRAY or opts.size() > _rarity_options(String(g.rarity)): return false
	var seen := {}
	for o in opts:
		if typeof(o) != TYPE_DICTIONARY or not Balance.data()["gem_options"].has(String(o.get("k", ""))): return false
		if not _num(o.get("v")) or seen.has(o.k): return false
		var d: Dictionary = Balance.data()["gem_options"][o.k]
		if float(o.v) < float(d.min) - TOL or float(o.v) > float(d.max) + TOL: return false
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

## Equipment the game can load: known base (in the right slot), known rarity, level 1..option_ref_level (the highest
## drop level), +0..max (+0 only on what cannot be enhanced), no more options than its rarity rolls, unique options each 0..its Lv10 top (± TOL).
static func _item_ok(it, slot := "") -> bool:
	if typeof(it) != TYPE_DICTIONARY: return false
	if typeof(it.get("base")) != TYPE_STRING or not Gear.is_gear(it.base): return false
	if slot != "" and Gear.slot_of(it.base) != slot: return false
	if not (it.get("rarity") in _rarities()): return false
	var ref := int(Balance.num("option_ref_level"))
	if not _int_in(it.get("level"), 1, ref): return false
	if it.has("plus") and not _int_in(it.plus, 0, Enhance.max_plus() if Enhance.can(it) else 0): return false
	var opts = it.get("opts", [])
	if typeof(opts) != TYPE_ARRAY or opts.size() > _rarity_options(String(it.rarity)): return false
	var seen := {}
	for o in opts:
		if typeof(o) != TYPE_DICTIONARY or not Balance.data()["options"].has(String(o.get("k", ""))): return false
		if not _num(o.get("v")) or seen.has(o.k): return false
		if float(o.v) < -TOL or float(o.v) > Gear.option_range(String(o.k), ref).y + TOL: return false
		seen[o.k] = true
	return true

static func _equipped_ok(eq) -> bool:
	if typeof(eq) != TYPE_DICTIONARY: return false
	if eq.get("bow") == null: return false          # arrows need a bow
	for s in Gear.SLOTS:
		if eq.get(s) != null and not _item_ok(eq.get(s), s): return false
	return true

## Writes the save signed, atomically (tmp file + rename). The data first goes through JSON once, so it is signed
## exactly as load_or_new() will read it back; the text is checked to verify before it is written. false when
## nothing was written (the old file stays).
static func save(state: Dictionary, path := PATH) -> bool:
	var data := state.duplicate(true)
	data["version"] = VERSION
	data.erase("sig")
	if not data.has("equipped"): data["equipped"] = start_equipped()
	if not data.has("skills"): data["skills"] = {}
	var plain = JSON.parse_string(JSON.stringify(data))
	if typeof(plain) != TYPE_DICTIONARY: return false
	plain["sig"] = signature(plain)
	var text := JSON.stringify(plain)
	var back = JSON.parse_string(text)
	if text.to_utf8_buffer().size() > int(Balance.num("save.max_bytes")) or typeof(back) != TYPE_DICTIONARY or not _sig_ok(back):
		push_error("SaveGame: the save would not load back; not written")
		return false
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null: return false
	f.store_string(text)
	f.close()
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path)) != OK: return false
	if not FileAccess.file_exists(marker_path(path)):
		var m := FileAccess.open(marker_path(path), FileAccess.WRITE)
		if m != null:
			m.store_string("signed saves only")
			m.close()
	return true

## The file's JSON, or null when it is too big (checked before reading it all), unreadable or not JSON.
static func _read(path: String):
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > int(Balance.num("save.max_bytes")): return null
	var text := f.get_as_text()
	f.close()
	var j := JSON.new()
	return j.data if j.parse(text) == OK else null

static func load_or_new(path := PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return new_state()
	var d = _read(path)
	var resign := false
	if typeof(d) == TYPE_DICTIONARY:
		if d.has("sig"):
			if _sig_ok(d): d.erase("sig")
			else: d = null                     # Q1 a: a wrong signature is a broken save
		elif _int_in(d.get("version"), 1, 3) and not FileAccess.file_exists(marker_path(path)):
			resign = true                      # Q2 a: made before signing; checked like any save, then signed
		else: d = null                         # a version-4 save must be signed
	if typeof(d) == TYPE_DICTIONARY and _int_in(d.get("version"), 1, 1):
		d["version"] = 2                       # M2b save: keep progress, wear the starting kit
		d["equipped"] = start_equipped()
	if typeof(d) == TYPE_DICTIONARY and _int_in(d.get("version"), 2, 2):
		d["version"] = 3                       # M2c save: gems stay stacked (plain), plus 0, no sockets
		d["skills"] = {}
	if typeof(d) == TYPE_DICTIONARY and _int_in(d.get("version"), 3, 3):
		d["version"] = VERSION                 # unsigned M3a..M4c save: same data, gets signed below
	if not (typeof(d) == TYPE_DICTIONARY and _state_ok(d)):
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
	# Waypoints.load_save). _state_ok has refused anything but stone room ids (Q3 a); repeats are dropped.
	var wps: Array = []
	for id in d.get("waypoints", []):
		if not wps.has(String(id)): wps.append(String(id))
	d["waypoints"] = wps
	# Owner 2026-11-08: the fog comes back with every new game and loading is a new game, so the fog is no longer
	# saved. Saves from Task 6 may still hold a "fog" key (any value): it is dropped, the rest of the save loads.
	d.erase("fog")
	d.version = VERSION
	d.level = roundi(float(d.level))
	d.exp = 0 if d.level >= Progression.cap() else roundi(float(d.exp))
	if resign: save(d, path)
	return d

## Everything load_or_new() keeps must be in range (Q3 a): version, level 1..cap, EXP 0..next level - 1 (at the
## cap it is then set to 0), the bag, worn gear, sockets and waypoints.
static func _state_ok(d: Dictionary) -> bool:
	if not _int_in(d.get("version"), VERSION, VERSION): return false
	if not _int_in(d.get("level"), 1, Progression.cap()): return false
	if not _int_in(d.get("exp"), 0, maxi(0, Progression.exp_to_next(int(d.level)) - 1)): return false
	return _inventory_ok(d.get("inventory")) and _equipped_ok(d.get("equipped")) and _skills_ok(d.get("skills", {})) \
		and _waypoints_ok(d.get("waypoints", []))

## Unlocked stones: a list of room ids that have a waypoint stone. Unknown ids fail the save (Q3 a).
static func _waypoints_ok(w) -> bool:
	if typeof(w) != TYPE_ARRAY: return false
	for id in w:
		if typeof(id) != TYPE_STRING or not (id in stone_ids()): return false
	return true

## A bag the game can load: {gold 0..save.gold_cap, slots: up to bag.slots of {id: a known item, count: 1..bag.stack}}.
static func _inventory_ok(inv) -> bool:
	if typeof(inv) != TYPE_DICTIONARY: return false
	if not _int_in(inv.get("gold", 0), 0, int(Balance.num("save.gold_cap"))): return false
	var slots = inv.get("slots", [])
	if typeof(slots) != TYPE_ARRAY or slots.size() > int(Balance.num("bag.slots")): return false
	for s in slots:
		if typeof(s) != TYPE_DICTIONARY or typeof(s.get("id")) != TYPE_STRING: return false
		if not known_item(s.id): return false
		if not _int_in(s.get("count"), 1, int(Balance.num("bag.stack"))): return false
		if s.has("item") and (int(s.count) != 1 or not _item_ok(s.item) or String(s.item.base) != String(s.id)): return false
		if not s.has("item") and Gear.is_gear(String(s.id)): return false     # gear must carry its item data
		if s.has("gem") and (int(s.count) != 1 or not _gem_ok(s.gem) or "gem_" + String(s.gem.type) != String(s.id)): return false
	return true
