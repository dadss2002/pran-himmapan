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
##
## Owner 2026-11-09 ("re-roll ห้ามได้ผังเดิมซ้ำ"), Task 5 review 2: a room never shows again the pile layout the player
## LAST SAW there. RoomReset remembers per room the layout it was last built with (mark_shown: the pile seed, the
## bank's size and the entry picked; test_ground.go_to records it whenever a room is built, kept or fresh). The memory
## outlives reroll_all (a room seen two re-rolls ago still counts) and lasts the session; it is not saved, because a
## load is a new game (new random layout and pile seed, kept rooms and fog not saved either). reroll_seed() moves a
## waypoint re-roll's seed off the last-shown layout of the guarded rooms: the trip's destination, or with
## GUARD_ALL_ROOMS every room shown this session (the room being left too).

var pile_seed := 0
var roll := 0                     # re-rolls so far (0 = never rolled)
var _kept := {}                   # room id -> {groups, piles, packs}
var _shown := {}                  # room id -> {seed, size, entry}: the layout it was last built with (kept across reroll_all)

## Which rooms a waypoint re-roll keeps off their last-shown layout (reroll_seed): false = only the trip's
## destination (the room the hero sees next; owner 2026-11-09); true = every room shown this session, the room being
## left too (the owner is being asked; flip this one line to switch).
const GUARD_ALL_ROOMS := false

## A new pile seed for a waypoint re-roll (31 bits, like the session layout seed).
static func new_seed() -> int:
	return int(randi() & 0x7fffffff)

## Owner 2026-11-09 ("ห้ามได้ผังเดิมซ้ำ"): one room's form of the rule against a known seed (the game uses the per-room
## memory, reroll_seed; review 2: the current pile seed is not always what the player last saw in a room).
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

## Room id was just built (shown) with pile seed `seed` from a bank of bank_size entries (0 = no bank, placed live):
## remember its layout as the one the player last saw there.
func mark_shown(id: String, seed: int, bank_size: int) -> void:
	var s := seed & 0x7fffffff
	_shown[id] = {"seed": s, "size": bank_size,
		"entry": posmod(MonsterPiles.room_seed(s, id), bank_size) if bank_size > 1 else -1}

## The layout room id was last shown with ({seed, size, entry}; entry -1 without a bank of 2+), {} when never shown.
func last_shown(id: String) -> Dictionary:
	return _shown.get(id, {}).duplicate()

## True when pile seed s would give room id the layout it was last shown with: the same seed, or with a bank of 2+
## the same entry (PileBank.pick: posmod(MonsterPiles.room_seed(seed, id), size)). A room never shown: false.
func repeats(id: String, s: int) -> bool:
	var m: Dictionary = _shown.get(id, {})
	if m.is_empty(): return false
	if s == int(m.seed): return true
	return int(m.size) > 1 and posmod(MonsterPiles.room_seed(s, id), int(m.size)) == int(m.entry)

## The rooms a re-roll to dest must keep off their last-shown layout (sorted): dest alone, or with all_rooms every
## room shown this session plus dest.
func guarded(dest: String, all_rooms := GUARD_ALL_ROOMS) -> Array:
	var out: Array = _shown.keys() if all_rooms else []
	if dest != "" and not out.has(dest): out.append(dest)
	out.sort()
	return out

## The pile seed for a waypoint re-roll to dest: new_seed unless it equals the current pile seed or would give a
## guarded room (guarded()) its last-shown layout; then the next seed (31 bits, wrapping) until none does.
## Deterministic; reads only the memory (no groups, no RNG). Each step clashes with chance about guarded rooms /
## bank size, so a few steps at most; after 4096 the last seed is returned (a guard only).
func reroll_seed(new_seed: int, dest: String, all_rooms := GUARD_ALL_ROOMS) -> int:
	var ids := guarded(dest, all_rooms)
	var s := new_seed & 0x7fffffff
	for i in 4096:
		var ok := s != pile_seed
		for id in ids:
			if ok and repeats(id, s): ok = false
		if ok: return s
		s = (s + 1) & 0x7fffffff
	return s

## Re-roll every room: new pile seed, no kept rooms (the last-shown memory stays).
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
