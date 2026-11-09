class_name Sfx
## Sound effects (M4d Task 3g; spec docs/superpowers/specs/2026-11-08-sound.md, files assets/audio/, credits
## assets/audio/CREDITS.md). Static, so any script can call Sfx.play("bow_shot") / Sfx.play_monster("wolf",
## "die"); the players live under one node the test ground makes (attach()). With no such node (unit tests)
## or audio off, nothing is played but every request is still logged for tests (requested / started).
##
## Playback rules (spec "กติกาเล่นเสียง", Claude's proposal, not game numbers):
## - one id plays at most VOICES at once (bookkeeping by each sound's length, so it works on the dummy
##   audio driver too); a monster kind's hurt + die sounds at most MONSTER_BURST per MONSTER_WINDOW s;
## - pitch ±PITCH_JITTER at random, except the Thai instrument sounds and the UI sounds;
## - effects at FX_VOL, UI at UI_VOL, times the player's volume (settings 0-100 %);
## - stop_world() (room change) stops what is still ringing from the old room; UI, level-up and the warp
##   gong carry on.
## Web: browsers only start audio after the first tap/click; Godot resumes its audio context itself on that
## gesture, and play() before it is simply silent (no error, no prompt).

const DIR := "res://assets/audio/"
## event id -> file (assets/audio/<file>.ogg), the spec's event table
const EVENTS := {
	"bow_shot": "bow_shot",        # bow shot and every arrow skill
	"arrow_hit": "arrow_hit",      # an arrow hits a monster (not a crit)
	"crit_hit": "crit_hit",        # a critical hit (instead of arrow_hit)
	"pickup": "pickup",            # an item / gem picked up
	"coin": "ranat_coin",          # gold picked up
	"level_up": "gong_levelup",
	"warp": "gong_warp",           # leaving a room (and, later, waypoint travel)
	"chest_open": "ranat_chest",   # no chests in the game yet: the id is ready
	"ui_button": "ui_button",      # HUD / menu button presses
	"ui_open": "ui_bag_open",      # bag, skills (and later the map) opening
	"toast": "ui_notify",          # a toast shown
}
const UI := ["ui_button", "ui_open", "toast"]
## Thai instrument sounds (ranat / gong) keep their tuning: no pitch change. pickup is ranat too.
const THAI := ["pickup", "coin", "level_up", "warp", "chest_open"]
## Sounds that do not stop when the room changes.
const KEEP_ON_ROOM_CHANGE := ["level_up", "warp", "ui_button", "ui_open", "toast"]
## monster kind -> [hurt variants, die variants]: assets/audio/monsters/<kind>_<event>_<a..>.ogg
const MONSTERS := {
	"wolf": [3, 2], "boar": [3, 2], "deer": [3, 2], "macaque": [5, 3],
	"kongkoi": [3, 2], "shroom": [3, 2], "viper": [3, 2],
}
const VOICES := 4
const MONSTER_BURST := 2
const MONSTER_WINDOW := 0.05
const PITCH_JITTER := 0.05
const FX_VOL := 0.8
const UI_VOL := 0.6
const MAX_PLAYERS := 24
const LOG_MAX := 64

static var enabled := true
static var volume := 1.0                     # 0..1, from the settings' 0-100
static var rng := RandomNumberGenerator.new()   # variants and pitch; tests seed it
static var host: Node = null                 # parent of the players (attach)
## Test hooks: the last LOG_MAX requests ({id}) and started voices ({id, path, pitch, volume_db, ui, at}).
static var requested: Array = []
static var started: Array = []
static var fake_now := -1.0                  # tests set the clock; < 0 = real time
static var _voices := {}                     # id -> end times of the voices still sounding
static var _monster_times := {}              # kind -> start times inside the last MONSTER_WINDOW
static var _streams := {}                    # path -> AudioStream (or null when missing)
static var _seeded := false

## Makes the players' parent under `parent` (the test ground). It keeps running while the tree is paused
## (the bag and skill screens pause the game; their sounds must still play).
static func attach(parent: Node) -> Node:
	var n := Node.new()
	n.name = "Sfx"
	n.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(n)
	host = n
	return n

static func set_enabled(b: bool) -> void:
	enabled = b
	if not b: stop_all()

## v = 0..1 (the settings' volume / 100); players already sounding follow at once.
static func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	for p in _players():
		var a := p as AudioStreamPlayer
		a.volume_db = _db(bool(a.get_meta("ui", false)))

static func path_of(id: String) -> String:
	return DIR + String(EVENTS[id]) + ".ogg" if EVENTS.has(id) else ""

## Every variant file of a monster kind's event ("hurt" / "die").
static func monster_paths(kind: String, event: String) -> Array:
	var out := []
	if not MONSTERS.has(kind) or not event in ["hurt", "die"]: return out
	var n: int = MONSTERS[kind][0 if event == "hurt" else 1]
	for i in n: out.append("%smonsters/%s_%s_%s.ogg" % [DIR, kind, event, char(97 + i)])
	return out

## Plays event id (EVENTS). `at` is where it happens in the world (kept for later positional sound; all
## sounds are plain, non-positional players today). False when not started (audio off, voice limit, ...).
static func play(id: String, at := Vector2.INF) -> bool:
	_log(requested, {"id": id})
	if not EVENTS.has(id):
		push_warning("Sfx: unknown sound id '%s'" % id)
		return false
	return _start(id, path_of(id), id in UI, not (id in UI or id in THAI), at)

## A monster's cry: event "hurt" or "die", a random variant of that kind each call.
static func play_monster(kind: String, event: String) -> bool:
	var id := "%s_%s" % [kind, event]
	_log(requested, {"id": id})
	var paths := monster_paths(kind, event)
	if paths.is_empty() or not _audible(): return false
	var now := _now()
	var times: Array = _monster_times.get(kind, []).filter(func(t): return now - float(t) < MONSTER_WINDOW)
	_monster_times[kind] = times
	if times.size() >= MONSTER_BURST: return false
	_seed_once()
	var path: String = paths[rng.randi_range(0, paths.size() - 1)]
	if _start(id, path, false, true):
		times.append(now)
		return true
	return false

## Room change: what still rings from the old room stops (UI, level-up and warp go on).
static func stop_world() -> void:
	for id in _voices.keys():
		if not (id in KEEP_ON_ROOM_CHANGE): _voices.erase(id)
	_monster_times.clear()
	for p in _players():
		if not (String(p.get_meta("id", "")) in KEEP_ON_ROOM_CHANGE): (p as AudioStreamPlayer).stop()

static func stop_all() -> void:
	_voices.clear()
	_monster_times.clear()
	for p in _players(): (p as AudioStreamPlayer).stop()

## How many voices of id are sounding now (bookkeeping).
static func voices_of(id: String) -> int:
	var now := _now()
	return (_voices.get(id, []) as Array).filter(func(t): return float(t) > now).size()

## Tests: back to defaults, logs empty, no players' parent.
static func reset() -> void:
	enabled = true
	volume = 1.0
	host = null
	requested.clear()
	started.clear()
	fake_now = -1.0
	_voices.clear()
	_monster_times.clear()

# ---------- inside ----------

static func _audible() -> bool:
	return enabled and volume > 0.0

static func _db(ui: bool) -> float:
	return linear_to_db(volume * (UI_VOL if ui else FX_VOL))

static func _start(id: String, path: String, ui: bool, jitter: bool, at := Vector2.INF) -> bool:
	if not _audible(): return false
	var now := _now()
	var ends: Array = (_voices.get(id, []) as Array).filter(func(t): return float(t) > now)
	_voices[id] = ends
	if ends.size() >= VOICES: return false
	var stream := _stream(path)
	if stream == null: return false
	_seed_once()
	var pitch := 1.0 + rng.randf_range(-PITCH_JITTER, PITCH_JITTER) if jitter else 1.0
	ends.append(now + maxf(0.05, stream.get_length()) / pitch)
	var vdb := _db(ui)
	_log(started, {"id": id, "path": path, "pitch": pitch, "volume_db": vdb, "ui": ui, "at": at})
	var p := _free_player()
	if p:
		p.stream = stream
		p.pitch_scale = pitch
		p.volume_db = vdb
		p.set_meta("ui", ui)
		p.set_meta("id", id)
		p.set_meta("end", ends[-1])
		p.play()
	return true

static func _stream(path: String) -> AudioStream:
	if not _streams.has(path):
		_streams[path] = load(path) if ResourceLoader.exists(path) else null
		if _streams[path] == null: push_warning("Sfx: missing sound %s" % path)
	return _streams[path]

static func _players() -> Array:
	if host == null or not is_instance_valid(host): return []
	return host.get_children().filter(func(c): return c is AudioStreamPlayer)

## A player that is not sounding, a new one while under MAX_PLAYERS, else the one started longest ago.
## A stolen player's sound stops, so its voice leaves its id's count (_voices) too.
static func _free_player() -> AudioStreamPlayer:
	if host == null or not is_instance_valid(host) or not host.is_inside_tree(): return null
	var all := _players()
	for p in all:
		if not (p as AudioStreamPlayer).playing: return _to_back(p)
	if all.size() < MAX_PLAYERS:
		var n := AudioStreamPlayer.new()
		host.add_child(n)
		return n
	var old: AudioStreamPlayer = all[0]
	var old_id := String(old.get_meta("id", ""))
	if _voices.has(old_id) and old.has_meta("end"): (_voices[old_id] as Array).erase(old.get_meta("end"))
	old.stop()
	return _to_back(old)

static func _to_back(p: AudioStreamPlayer) -> AudioStreamPlayer:
	host.move_child(p, -1)        # the oldest stays first
	return p

static func _now() -> float:
	return fake_now if fake_now >= 0.0 else Time.get_ticks_msec() / 1000.0

static func _seed_once() -> void:
	if _seeded: return
	_seeded = true
	rng.randomize()

## Tests: the same variants and pitches again from the same seed.
static func seed_rng(s: int) -> void:
	rng.seed = s            # setting the seed restarts the sequence
	_seeded = true

static func _log(a: Array, e: Dictionary) -> void:
	a.append(e)
	if a.size() > LOG_MAX: a.pop_front()
