class_name RoomReset
extends RefCounted
## Task 4 (M4c §1, owner: "สุ่มใหม่เมื่อใช้ Waypoint หรือเข้าเกมใหม่เท่านั้น"): monsters re-roll only on waypoint
## travel or a new game. Walking between rooms keeps every room as the hero left it: dead monsters stay dead
## (M4c addendum: room monsters never respawn in place, so a cleared room stays empty until a re-roll or a new
## game), living ones stand where they were. Pure rules, no scene.
##
## What a kept room holds (keep): the groups it was built from (kinds, counts, levels: e0's set and arena level
## stay as they were), its piles (MonsterPiles / PileBank shape), and per group one list of each monster's
## kept state in spawn order (WolfPack.snapshot: alive, pos, elite, busy, a dead one's respawn seconds left).
##
## A re-roll (reroll_all) takes a new pile seed and forgets every kept room, so each room's piles next time come
## from the baked bank with the new seed (RoomSet.piles with MonsterPiles.room_seed(pile_seed, id)). `roll`
## counts re-rolls: a room built before the latest re-roll belongs to the old roll and is not kept when left.
## The e0 set is re-chosen after a re-roll by its owner (test_ground clears arena_set; spec addendum 2).

var pile_seed := 0
var roll := 0                     # re-rolls so far (0 = never rolled)
var _kept := {}                   # room id -> {groups, piles, packs}

## A new pile seed for a waypoint re-roll (31 bits, like the session layout seed).
static func new_seed() -> int:
	return int(randi() & 0x7fffffff)

## Owner 2026-11-09 ("ห้ามได้ผังเดิมซ้ำ"): a waypoint re-roll never gives room id its current pile layout again.
## Keeps new_seed unless it equals old_seed or, with a bank of bank_size > 1 entries, picks the same entry for room id
## (PileBank.pick: posmod(MonsterPiles.room_seed(seed, id), size)); then steps to the next seed (31 bits, wrapping)
## until it differs. Deterministic, a few string hashes at most (a clash is 1 in the bank's size). No bank (live
## placement) or a 1-entry bank: only the seed must differ.
static func distinct_seed(old_seed: int, new_seed: int, room_id: String, bank_size: int) -> int:
	var s := new_seed & 0x7fffffff
	var old_entry := posmod(MonsterPiles.room_seed(old_seed, room_id), bank_size) if bank_size > 1 else -1
	for i in 4096:                       # a guard only: each step clashes with chance 1 / bank_size
		if s != old_seed and (old_entry < 0 or posmod(MonsterPiles.room_seed(s, room_id), bank_size) != old_entry): return s
		s = (s + 1) & 0x7fffffff
	return s

## Re-roll every room: new pile seed, no kept rooms.
func reroll_all(seed: int) -> void:
	pile_seed = seed
	roll += 1
	_kept.clear()

## Keep room id as the hero leaves it: the groups and piles it was built from and each group's monster states
## (packs: one WolfPack.snapshot() per group, in group order).
func keep(id: String, packs: Array, groups: Array, piles: Array) -> void:
	_kept[id] = {"groups": groups.duplicate(true), "piles": piles.duplicate(true), "packs": packs.duplicate(true)}

## The kept state of room id ({groups, piles, packs}); {} when the room has not been left since the last re-roll.
func state(id: String) -> Dictionary:
	return _kept.get(id, {})

func has(id: String) -> bool:
	return _kept.has(id)

## Rooms kept now (sorted).
func kept_ids() -> Array:
	var out: Array = _kept.keys()
	out.sort()
	return out

## How many of room id's monsters are alive in its kept state (-1 when not kept).
func alive_count(id: String) -> int:
	if not _kept.has(id): return -1
	var n := 0
	for pack in _kept[id].packs:
		for m in pack:
			if bool(m.alive): n += 1
	return n
