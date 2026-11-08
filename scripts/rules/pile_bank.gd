class_name PileBank
extends RefCounted
## M4d follow-up 3 (owner 2026-11-08: "เตรียมผังมอนไว้ล่วงหน้า 64 แบบต่อห้อง สุ่มเลือก 1 แบบทุกรีเซ็ต"): a bank of
## SIZE monster placements per room and per e0 monster set, baked offline by tools/bake_piles.gd with the same
## MonsterPiles rules (live placement costs 0.3-1 s in c1r2 and e0 sets 1/3, all in the black fade, and the web
## export has no threads). data/piles_bank.json; loaded once per run. Pure rules, no scene.
##
## A room's bank holds one set per monster group list (forest rooms one, e0 four), each with an input hash: the
## room's picture size, blocked grid, exits, spawn and near_arrival_ok, the grid cell, the groups' kind / count /
## home / boss (levels left out: they follow the session layout and are applied after), each kind's arrival
## floor and body width, and the rule numbers (MonsterPiles gaps, RoomSet arrival numbers, PaintedLayout body
## clearance). RoomSet.piles() picks entry posmod(room_seed, SIZE) of the set whose hash matches; when none
## matches (room data changed without a rebake) it places live (MonsterPiles.place) and says so once per room.
##
## An entry is a flat list, one run per pile in MonsterPiles.place() order: group index, count, home x, home y
## (0.5 px), and for a count of 2+ the ring angle of its first member (0.001 rad): the members are rebuilt with
## MonsterPiles.ring_points (so in-pile spacing is exact). A single (or a boss of 1) stands on its home. The
## settle step leaves some placements right on a rule's edge (a gap of 60.0 px, a cell border); when rounding
## breaks such an entry the bake stores it finer (0.1, 0.01, 0.001 px, then unrounded).
## "seeds" holds the placement seed each entry was made with (0..63 unless the bake had to skip one).

const PATH := "res://data/piles_bank.json"
const SIZE := 64                  # ⚙ follow-up 3: placements per room and e0 set
## Bump VERSION whenever MonsterPiles or RoomSet placement logic changes (anything a placement depends on that
## the input hash below does not already cover: the order of tries, how a spot is drawn or scored, how arrivals
## or open ground are worked out), then rebake (BAKE): the old bank no longer loads and every room places live
## until it is rebaked, so a logic change can never leave the game picking placements made by the old rules.
const VERSION := 1
const BAKE := "godot --headless --script tools/bake_piles.gd"

static var _data = null           # parsed bank; {} when the file is missing or unreadable
static var _said := {}            # room ids already reported as stale (once per run)

static func data() -> Dictionary:
	if _data == null:
		_data = {}
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary and int(d.get("version", 0)) == VERSION: _data = d
	return _data

## Forget the loaded bank (tests; the bake tool after writing).
static func reload() -> void:
	_data = null
	_said.clear()

## The level-free, session-free room inputs a placement depends on, as text: from rooms.json's room dict the
## blocked grid, spawn and near_arrival_ok; the picture size and exits as RoomSet resolves them (`size` =
## RoomSet.room_size(id), the size RoomSet.layout(id) gets, the global one for a room without its own;
## `exits` = RoomSet.exits(id), an old room's fixed warps when it has no exits), so the hash follows what the
## placement actually used.
## Task 5: a room with a waypoint stone also has "waypoint" (its landing is an arrival); rooms without one hash
## as before.
static func room_text(raw: Dictionary, cell: int, size: Vector2, exits: Array) -> String:
	var d := {"size": [size.x, size.y], "blocked": raw.get("blocked"), "exits": exits,
		"spawn": raw.get("spawn"), "near_arrival_ok": bool(raw.get("near_arrival_ok", false)), "cell": cell}
	if raw.get("waypoint") != null: d["waypoint"] = raw.get("waypoint")
	return JSON.stringify(d, "", true)

## The input hash of one room (room_text) with one group list.
static func input_hash(room_txt: String, near_ok: bool, groups: Array) -> String:
	var gs: Array = []
	var kinds := {}
	for g in groups:
		var k := String(g.get("kind", "wolf"))
		gs.append([k, int(g.count), float(g.at[0]), float(g.at[1]), bool(g.get("boss", false))])
		kinds[k] = [MonsterPiles.arrival_floor(k, near_ok), MonsterPiles.body_width(k)]
	var rules := [MonsterPiles.MIN_PILE, MonsterPiles.MAX_PILE, MonsterPiles.PILE_GAP, MonsterPiles.SINGLE_GAP,
		MonsterPiles.NEAR_ARRIVAL_MIN, MonsterPiles.ARRIVAL_EXTRA, MonsterPiles.PASSIVE_ARRIVAL,
		MonsterPiles.RADIUS_SLACK, MonsterPiles.PAIR_PILE_CHANCE, RoomSet.ARRIVAL, RoomSet.REARM,
		PaintedLayout.CLEAR_X, PaintedLayout.CLEAR_UP, VERSION]
	return (room_txt + JSON.stringify({"groups": gs, "kinds": kinds, "rules": rules}, "", true)).md5_text()

## The bank set of room id with this hash ({hash, seeds, p}); {} when none (stale or not baked).
static func find(id: String, h: String) -> Dictionary:
	for s in data().get("rooms", {}).get(id, []):
		if String(s["hash"]) == h: return s
	return {}

## The banked placement for room id's groups with placement seed `seed` (MonsterPiles.room_seed), or null when
## the bank has no set with this hash (then the caller places live; reported once per room).
static func pick(id: String, h: String, groups: Array, seed: int) -> Variant:
	var s := find(id, h)
	if s.is_empty() or s["p"].is_empty():
		if not _said.has(id):
			_said[id] = true
			push_warning("piles bank: no placements for %s with today's room data (run %s); placing live" % [id, BAKE])
		return null
	var entries: Array = s["p"]
	return decode(entries[posmod(seed, entries.size())], groups)

## One entry back into MonsterPiles.place()'s result shape (levels from groups).
static func decode(e: Array, groups: Array) -> Array:
	var out: Array = []
	var i := 0
	while i < e.size():
		var gi := int(e[i])
		var n := int(e[i + 1])
		var home := Vector2(float(e[i + 2]), float(e[i + 3]))
		i += 4
		var g: Dictionary = groups[gi]
		var kind := String(g.get("kind", "wolf"))
		var boss := bool(g.get("boss", false))
		var pts: Array = [home]
		if n > 1:
			pts = MonsterPiles.ring_points(home, n, MonsterPiles.pile_radius(kind, n), float(e[i]))
			i += 1
		out.append({"kind": kind, "level": int(g.level), "count": n, "group": gi, "boss": boss,
			"single": not boss and n == 1, "home": home, "points": pts, "fallback": false})
	return out

## One placement (MonsterPiles.place result) as a bank entry (see the header), homes rounded to pos_step px
## and angles to ang_step rad (0: not rounded).
static func encode(piles: Array, pos_step := 0.5, ang_step := 0.001) -> Array:
	var out: Array = []
	for p in piles:
		var home: Vector2 = p.home
		var a := ((p.points[0] as Vector2) - home).angle()
		out.append_array([int(p.group), int(p.count), _snap(home.x, pos_step), _snap(home.y, pos_step)])
		if int(p.count) > 1: out.append(_snap(a, ang_step))
	return out

static func _snap(v: float, step: float) -> float:
	return snappedf(v, step) if step > 0.0 else v
