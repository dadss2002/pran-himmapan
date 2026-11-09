class_name RoomLevels
extends RefCounted
## M4d addendum (docs/superpowers/specs/2026-11-08-m4d-random-layout.md, "monster levels follow the layout",
## approved 2026-11-08): a room's monster level comes from how far it is from the start in this session's
## layout. Pure rules, no scene.
##
## d = rooms walked from c1r1 (c1r1 d = 0); D = the largest d of any forest room (e0 left out).
## L = 1 when d = 0, else round(1 + (d - 1) * SPAN / max(D - 1, 1)) + 1, clamped to MIN_LV..MAX_LV:
## the rooms next to the start are Lv2, the farthest forest room Lv10.
## Each room keeps its kinds and counts; every group uses L, except a group that was 1 level above the
## room's first group in the room data keeps that +1 (cap MAX_LV). e0 keeps its own level-by-hero sets.
## e0's set (addendum 2, approved 2026-11-08): target = max(hero level, level of the room the hero came
## from); the set whose average monster level is closest to the target, ties to the higher set (arena_set).
## e0's level (addendum 3, approved 2026-11-08): every monster of the chosen set = level of the room the hero
## came from + 1, max ARENA_MAX_LV (an arena-only level); the set keeps its kinds, counts and homes.

const MIN_LV := 2       # ⚙ approved: the rooms next to the start
const MAX_LV := 10      # ⚙ approved: the farthest forest room, and the cap for +1 groups
const SPAN := 8.0       # ⚙ approved: levels spread over d = 1..D
const ARENA_MAX_LV := 11  # ⚙ approved (addendum 3): e0 = previous room + 1, at most Lv11

## L for a room d rooms from the start when the farthest forest room is `far` rooms away.
static func level_at(d: int, far: int) -> int:
	if d <= 0: return 1
	return clampi(roundi(1.0 + (d - 1) * SPAN / maxi(far - 1, 1)) + 1, MIN_LV, MAX_LV)

## {room id: L} for every forest room reachable from the start in `layout` (RoomLayout dict); e0 left out.
static func for_layout(layout: Dictionary) -> Dictionary:
	var dist := RoomLayout.distances(layout.get("pos", {}), layout.get("links", []))
	var far := 0
	for id in dist:
		if id != RoomLayout.BOSS: far = maxi(far, int(dist[id]))
	var out := {}
	for id in dist:
		if id != RoomLayout.BOSS: out[id] = level_at(int(dist[id]), far)
	return out

## Copies of a room's monster groups at room level L: the same kinds, counts and homes; a group that was
## 1 level above the first group keeps +1 (cap MAX_LV), every other group gets L.
static func groups(monsters: Array, room_level: int) -> Array:
	var out: Array = []
	if monsters.is_empty(): return out
	var first := int(monsters[0].level)
	for m in monsters:
		var g: Dictionary = m.duplicate(true)
		var plus := 1 if int(m.level) == first + 1 else 0
		g["level"] = mini(room_level + plus, MAX_LV)
		out.append(g)
	return out

## The average level of one monster set (each monster counts once: groups weighted by their count).
static func set_level(monsters: Array) -> float:
	var n := 0
	var sum := 0
	for m in monsters:
		n += int(m.count)
		sum += int(m.level) * int(m.count)
	return float(sum) / n if n > 0 else 0.0

## Index into `sets` (e0's monster_sets) for a hero of hero_level who came from a room of from_level
## (0 = none): target = max(both); the set whose average level is closest; ties go to the higher set.
static func arena_set(sets: Array, hero_level: int, from_level: int) -> int:
	var target := float(maxi(hero_level, from_level))
	var best := -1
	var best_gap := INF
	var best_lv := -INF
	for i in sets.size():
		var lv := set_level(sets[i])
		var gap := absf(lv - target)
		if gap < best_gap - 0.0001 or (absf(gap - best_gap) <= 0.0001 and lv > best_lv):
			best = i
			best_gap = gap
			best_lv = lv
	return best

## e0 monster level for a hero who came from a room of from_level (addendum 3): from_level + 1, at most
## ARENA_MAX_LV; 0 when the previous room's level is unknown (from_level <= 0).
static func arena_level(from_level: int) -> int:
	if from_level <= 0: return 0
	return mini(from_level + 1, ARENA_MAX_LV)

## Copies of one e0 monster set with every group at arena_level(from_level): the same kinds, counts and
## homes. An unknown previous room (from_level <= 0) keeps the set's own levels.
static func arena_groups(monster_set: Array, from_level: int) -> Array:
	var lv := arena_level(from_level)
	var out: Array = []
	for m in monster_set:
		var g: Dictionary = m.duplicate(true)
		if lv > 0: g["level"] = lv
		out.append(g)
	return out
