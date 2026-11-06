class_name SaveGame
## Local save (user://save.json). A missing, broken or other-version file never crashes:
## the game starts fresh and a broken file is kept as <name>.bad.json.

const VERSION := 1
const PATH := "user://save.json"

static func new_state() -> Dictionary:
	var inv := Inventory.new()
	inv.add("potion_hp", int(Balance.num("potion.start_hp")))
	inv.add("potion_mp", int(Balance.num("potion.start_mp")))
	return {"version": VERSION, "level": 1, "exp": 0, "inventory": inv.to_dict()}

static func save(state: Dictionary, path := PATH) -> bool:
	var data := state.duplicate(true)
	data["version"] = VERSION
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
	var ok: bool = typeof(d) == TYPE_DICTIONARY and int(d.get("version", -1)) == VERSION \
		and d.has("level") and d.has("exp") and typeof(d.get("inventory")) == TYPE_DICTIONARY
	if not ok:
		var bad := path.get_basename() + ".bad.json"
		DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(bad))
		return new_state()
	d.level = clampi(int(d.level), 1, Progression.cap())
	d.exp = maxi(0, int(d.exp))
	return d
