class_name GameSettings
## Player settings kept apart from the game save (a new game keeps them): user://settings.json.
## M4d Task 3d: "แสดง FPS" (show the frame-rate line). Task 3g: "sound" on/off and "volume" 0-100 (spec
## docs/superpowers/specs/2026-11-08-sound.md). A missing or broken file gives the defaults.

const PATH := "user://settings.json"
const DEFAULTS := {"show_fps": true, "sound": true, "volume": 100}

static func load_or_default(path := PATH) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate()
	if not FileAccess.file_exists(path): return out
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(path)) != OK or typeof(j.data) != TYPE_DICTIONARY: return out
	var d: Dictionary = j.data
	for k in DEFAULTS:
		if not d.has(k): continue
		if typeof(d[k]) == typeof(DEFAULTS[k]): out[k] = d[k]
		elif typeof(DEFAULTS[k]) == TYPE_INT and typeof(d[k]) == TYPE_FLOAT: out[k] = int(round(d[k]))   # JSON numbers read back as floats
	out["volume"] = clampi(int(out["volume"]), 0, 100)
	return out

static func save(settings: Dictionary, path := PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: return false
	f.store_string(JSON.stringify(settings))
	f.close()
	return true
