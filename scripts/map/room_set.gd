class_name RoomSet
extends RefCounted
## The forest rooms (data/rooms.json, written by tools/painted_rooms.py): one painted chunk each,
## joined by warps. Pure rules: room data, a PaintedLayout per room, where a warp lands you.
## M4d: each room lists its painted "exits" (a point per side); which exits are joined comes from a
## RoomLayout given to use_layout() (a new random one every session). room(id).warps holds only the
## joined exits ({id, at, to, to_warp}); a dead-end exit has no warp. Until use_layout() is called the
## fixed M4b layout (RoomLayout.fallback) is active. Old data with fixed "warps" and no "exits" still loads.

const PATH := "res://data/rooms.json"
const ARRIVAL := 40.0         # how far into the room from the paired warp you appear
const WARP_RADIUS := 14.0
const REARM := 22.0

var start := ""
var size := Vector2.ZERO      # fallback for rooms without their own "size" (M4b: each room has one)
var cell := 8
var active: Dictionary = {}   # the RoomLayout in use ({pos, links, fallback}); empty for old fixed-warp data
var _rooms: Dictionary = {}
var _layouts: Dictionary = {}
var _levels = null            # RoomLevels.for_layout(active), worked out once per layout (room_levels())
var _pile_rooms: Dictionary = {}   # id -> MonsterPiles.prepare() data (never depends on the session layout)

static func open(path := PATH) -> RoomSet:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return null
	return from_dict(JSON.parse_string(f.get_as_text()))

## A room set from rooms.json's dict; rooms without their own "size" (pre-M4b data) use the global one.
static func from_dict(d: Dictionary) -> RoomSet:
	var r := RoomSet.new()
	r.start = String(d.start)
	r.size = Vector2(d.size[0], d.size[1])
	r.cell = int(d.cell)
	r._rooms = d.rooms
	if not r.exit_table().is_empty(): r.use_layout(RoomLayout.fallback(r.exit_table()))
	return r

## Rooms with painted exits, for RoomLayout.generate(): {id: {"exits": [side, ...], "arena": bool}}.
func exit_table() -> Dictionary:
	var out := {}
	for id in _rooms:
		if not _rooms[id].has("exits"): continue
		var sides: Array = []
		for e in _rooms[id].exits: sides.append(String(e.id))
		out[String(id)] = {"exits": sides, "arena": bool(_rooms[id].get("arena", false))}
	return out

## Join the rooms as `l` says (RoomLayout dict): each link becomes a warp pair; other exits stay dead ends.
func use_layout(l: Dictionary) -> void:
	active = l
	_levels = null
	var ws := {}
	for id in _rooms:
		if _rooms[id].has("exits"): ws[id] = []
	for k in l.get("links", []):
		for half in [[k[0], k[1], k[2], k[3]], [k[2], k[3], k[0], k[1]]]:
			var e := exit(String(half[0]), String(half[1]))
			if e.is_empty() or not ws.has(half[0]): continue
			ws[half[0]].append({"id": String(half[1]), "at": e.at, "to": String(half[2]), "to_warp": String(half[3])})
	for id in ws:
		var list: Array = ws[id]
		list.sort_custom(func(a, b): return String(a.id) < String(b.id))
		_rooms[id]["warps"] = list

## {room id: monster level} for the active layout (RoomLevels.for_layout), cached until use_layout().
func room_levels() -> Dictionary:
	if _levels == null: _levels = RoomLevels.for_layout(active)
	return _levels

## The room's grid place in the active layout (Vector2i(-1, -1) when it is not on the map).
func grid_pos(id: String) -> Vector2i:
	return active.get("pos", {}).get(id, Vector2i(-1, -1))

## Every painted exit of the room ({id: side, at}); old fixed-warp data: its warps.
func exits(id: String) -> Array:
	return _rooms[id].get("exits", _rooms[id].get("warps", []))

func exit(id: String, side: String) -> Dictionary:
	for e in exits(id):
		if String(e.id) == side: return e
	return {}

func ids() -> PackedStringArray:
	var out := PackedStringArray(_rooms.keys())
	out.sort()
	return out

func has(id: String) -> bool:
	return _rooms.has(id)

func room(id: String) -> Dictionary:
	return _rooms[id]

func layout(id: String) -> PaintedLayout:
	if not _layouts.has(id):
		var d: Dictionary = _rooms[id].duplicate()
		if not d.has("size"): d["size"] = [size.x, size.y]
		d["cell"] = cell
		if not d.has("spawn"): d["spawn"] = [0, 0]
		var l := PaintedLayout.from_dict(d)
		if not _rooms[id].has("spawn") and not exits(id).is_empty():
			l.hero_spawn = _arrival_on(l, exits(id)[0])   # never depends on the session's layout
		_layouts[id] = l
	return _layouts[id]

func spawn(id: String) -> Vector2:
	return layout(id).hero_spawn

func warp(id: String, warp_id: String) -> Dictionary:
	for w in room(id).get("warps", []):
		if String(w.id) == warp_id: return w
	return {}

func warp_at(id: String, warp_id: String) -> Vector2:
	var w := warp(id, warp_id)
	return Vector2(w.at[0], w.at[1])

## Where you stand after coming out of warp_id (an exit side) in room id: ARRIVAL px from it toward the
## room's middle, moved to the nearest spot a hero-sized body fits.
func arrival(id: String, warp_id: String) -> Vector2:
	return _arrival_on(layout(id), exit(id, warp_id))

func _arrival_on(l: PaintedLayout, w: Dictionary) -> Vector2:
	return arrival_on(l, w)

## Where you stand coming out of exit w of room layout l (see arrival()).
static func arrival_on(l: PaintedLayout, w: Dictionary) -> Vector2:
	var at := Vector2(w.at[0], w.at[1])
	var want := at + (l.size_px() / 2.0 - at).normalized() * ARRIVAL
	var best := at
	var best_d := INF
	for y in l.rows:
		for x in l.cols:
			if not l.roomy(x, y): continue
			var p := Vector2(x + 0.5, y + 0.5) * l.cell
			var dd := p.distance_squared_to(want)
			if dd < best_d and p.distance_to(at) > REARM + 2.0:
				best_d = dd
				best = p
	return best

## M4d addendum 4: room data for MonsterPiles.place(): its layout, every painted exit's arrival plus the
## room's own spawn (as tools/painted_rooms.py), and the main open ground; worked out once per room.
func pile_room(id: String) -> Dictionary:
	if not _pile_rooms.has(id):
		var l := layout(id)
		var arrivals: Array = []
		for e in exits(id): arrivals.append(arrival(id, String(e.id)))
		if _rooms[id].has("spawn"): arrivals.append(l.hero_spawn)
		_pile_rooms[id] = MonsterPiles.prepare(_rooms[id], l, arrivals)
		_pile_rooms[id]["id"] = id
	return _pile_rooms[id]

## Every problem with the rooms; empty means playable.
func validate() -> Array[String]:
	var errs: Array[String] = []
	if not has(start): errs.append("start room %s missing" % start)
	var seen := {start: true}            # every room on the active layout can be walked to from the start
	var todo := [start]
	while has(start) and not todo.is_empty():
		for w in room(todo.pop_back()).get("warps", []):
			if has(String(w.to)) and not seen.has(String(w.to)):
				seen[String(w.to)] = true
				todo.append(String(w.to))
	for id in active.get("pos", {}):
		if not seen.has(id): errs.append("%s cannot be reached from %s" % [id, start])
	for id in ids():
		var l := layout(id)
		for e in l.validate(): errs.append("%s: %s" % [id, e])
		for e in exits(id):              # any exit may be joined in some session
			var p := Vector2(e.at[0], e.at[1])
			if l.blocked_at(p): errs.append("%s exit %s on blocked ground" % [id, e.id])
			elif not l.reachable(l.hero_spawn, p): errs.append("%s exit %s cannot be walked to" % [id, e.id])
		for w in room(id).get("warps", []):
			if exit(id, String(w.id)).is_empty(): errs.append("%s warp %s has no painted exit" % [id, w.id])
			var at := Vector2(w.at[0], w.at[1])
			if l.blocked_at(at): errs.append("%s warp %s on blocked ground" % [id, w.id])
			if not has(String(w.to)) or warp(String(w.to), String(w.to_warp)).is_empty():
				errs.append("%s warp %s leads nowhere" % [id, w.id])
			elif String(warp(String(w.to), String(w.to_warp)).to) != id:
				errs.append("%s warp %s is not paired back" % [id, w.id])
			if not l.reachable(l.hero_spawn, at): errs.append("%s warp %s cannot be walked to" % [id, w.id])
	return errs
