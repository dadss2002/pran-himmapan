class_name Waypoints
extends RefCounted
## M4c §2 waypoints (Task 5, owner-approved 2026-11-07): a carved stone in four rooms (c1r1, c0r2, c2r0, c2r1;
## data/rooms.json "waypoint"). Touching a stone the first time unlocks it ("ปลดล็อกจุดวาป"); standing on any
## unlocked stone opens the travel list (only unlocked stones); tapping one travels there: Task 4's re-roll
## (test_ground.reroll()) then go_to that room, landing next to its stone. Unlocked stones are saved
## (SaveGame "waypoints"). Pure rules, no scene: travel() hands the trip to `traveller` (the test ground).
##
## Choices (Task 5, not in the spec): the start stone (c1r1, where every session begins) is always unlocked, also
## for old saves without "waypoints"; travelling to the stone of the room you stand in is allowed and re-rolls
## like any trip (the way to reset a room); the list shows it marked "ที่นี่".

const START := "c1r1"
## px from the middle of the stone's footprint within which the hero's feet "touch" / "stand on" it. The footprint
## is 32 x 16 px (RoomSet.WAYPOINT_*), the hero's feet box 20 x 16 (y-14..y+2), so his feet get within 10 px
## (from the north), 22 (south) or 26 (east / west) of that middle when he walks up to it; the travel landing
## (RoomSet.waypoint_landing) is about 28 px from it.
const RADIUS := 32.0

var ids: Array[String] = []        # every room with a stone, in list order: START first, then by room id
var _unlocked := {}
## Called with the destination room id by travel() (test_ground.travel_to_waypoint).
var traveller: Callable

## The stones of a room set (RoomSet.waypoint_ids), with `saved` (SaveGame "waypoints", may be null) unlocked.
static func from_rooms(rooms: RoomSet, saved = null) -> Waypoints:
	return make(rooms.waypoint_ids(), saved)

static func make(all_ids: Array, saved = null) -> Waypoints:
	var w := Waypoints.new()
	var rest: Array[String] = []
	for id in all_ids:
		if String(id) == START: w.ids.append(START)
		else: rest.append(String(id))
	rest.sort()
	w.ids.append_array(rest)
	w.load_save(saved)
	return w

func has(id: String) -> bool:
	return ids.has(id)

## Unlocks room id's stone; true only the first time (a toast and a save follow).
func unlock(id: String) -> bool:
	if not has(id) or _unlocked.has(id): return false
	_unlocked[id] = true
	return true

func is_unlocked(id: String) -> bool:
	return _unlocked.has(id)

## The unlocked stones, in list order.
func list() -> Array[String]:
	var out: Array[String] = []
	for id in ids:
		if _unlocked.has(id): out.append(id)
	return out

## For the save: the unlocked room ids (list order).
func to_save() -> Array:
	return Array(list())

## Unlocks the saved ids that are stones (anything else is ignored); START is always unlocked.
func load_save(saved) -> void:
	_unlocked.clear()
	if has(START): _unlocked[START] = true
	if typeof(saved) != TYPE_ARRAY: return
	for id in saved:
		if typeof(id) == TYPE_STRING and has(id): _unlocked[id] = true

## Travel to room id's stone (it must be unlocked): the traveller does the re-roll, fade and landing. false when
## refused.
func travel(id: String) -> bool:
	if not is_unlocked(id) or not traveller.is_valid(): return false
	traveller.call(id)
	return true

## Whether feet at `feet` touch / stand on the stone whose base point (bottom middle) is `stone`.
static func touching(stone: Vector2, feet: Vector2) -> bool:
	return feet.distance_to(centre(stone)) <= RADIUS

## The middle of the stone's footprint.
static func centre(stone: Vector2) -> Vector2:
	return stone - Vector2(0, RoomSet.WAYPOINT_H / 2.0)
