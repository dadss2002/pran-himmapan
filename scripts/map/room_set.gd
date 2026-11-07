class_name RoomSet
extends RefCounted
## The forest rooms (data/rooms.json, written by tools/painted_rooms.py): one painted chunk each,
## joined by warps. Pure rules: room data, a PaintedLayout per room, where a warp lands you.

const PATH := "res://data/rooms.json"
const ARRIVAL := 40.0         # how far into the room from the paired warp you appear
const WARP_RADIUS := 14.0
const REARM := 22.0

var start := ""
var size := Vector2.ZERO      # fallback for rooms without their own "size" (M4b: each room has one)
var cell := 8
var _rooms: Dictionary = {}
var _layouts: Dictionary = {}

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
	return r

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
		if not _rooms[id].has("spawn") and not room(id).warps.is_empty():
			l.hero_spawn = _arrival_on(l, room(id).warps[0])
		_layouts[id] = l
	return _layouts[id]

func spawn(id: String) -> Vector2:
	return layout(id).hero_spawn

func warp(id: String, warp_id: String) -> Dictionary:
	for w in room(id).warps:
		if String(w.id) == warp_id: return w
	return {}

func warp_at(id: String, warp_id: String) -> Vector2:
	var w := warp(id, warp_id)
	return Vector2(w.at[0], w.at[1])

## Where you stand after coming out of warp_id in room id: ARRIVAL px from it toward the room's
## middle, moved to the nearest spot a hero-sized body fits.
func arrival(id: String, warp_id: String) -> Vector2:
	return _arrival_on(layout(id), warp(id, warp_id))

func _arrival_on(l: PaintedLayout, w: Dictionary) -> Vector2:
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

## Every problem with the rooms; empty means playable.
func validate() -> Array[String]:
	var errs: Array[String] = []
	if not has(start): errs.append("start room %s missing" % start)
	for id in ids():
		var l := layout(id)
		for e in l.validate(): errs.append("%s: %s" % [id, e])
		for w in room(id).warps:
			var at := Vector2(w.at[0], w.at[1])
			if l.blocked_at(at): errs.append("%s warp %s on blocked ground" % [id, w.id])
			if not has(String(w.to)) or warp(String(w.to), String(w.to_warp)).is_empty():
				errs.append("%s warp %s leads nowhere" % [id, w.id])
			elif String(warp(String(w.to), String(w.to_warp)).to) != id:
				errs.append("%s warp %s is not paired back" % [id, w.id])
			if not l.reachable(l.hero_spawn, at): errs.append("%s warp %s cannot be walked to" % [id, w.id])
	return errs
