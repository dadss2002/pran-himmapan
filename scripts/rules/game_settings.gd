class_name GameSettings
## Player settings kept apart from the game save (a new game keeps them): user://settings.json.
## M4d Task 3d: "แสดง FPS" (show the frame-rate line). A missing or broken file gives the defaults.

const PATH := "user://settings.json"
const DEFAULTS := {"show_fps": true}

static func load_or_default(path := PATH) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate()
	if not FileAccess.file_exists(path): return out
	var j := JSON.new()
	if j.parse(FileAccess.get_file_as_string(path)) != OK or typeof(j.data) != TYPE_DICTIONARY: return out
	var d: Dictionary = j.data
	for k in DEFAULTS:
		if d.has(k) and typeof(d[k]) == typeof(DEFAULTS[k]): out[k] = d[k]
	return out

static func save(settings: Dictionary, path := PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: return false
	f.store_string(JSON.stringify(settings))
	f.close()
	return true
