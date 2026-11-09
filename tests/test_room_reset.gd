extends RefCounted
## Task 4 RoomReset (docs/superpowers/specs/2026-11-07-m4c-farm-links-fog-minimap.md §1; m4d addenda 2-4 and
## follow-up 3): monsters re-roll only on a new game or waypoint travel (test_ground.reroll()). Walking out of a
## room and back keeps it: dead monsters stay dead (M4c addendum: room monsters never respawn in place; only a
## re-roll or a new game brings them back; no second EXP), living ones
## where they stood with their elite mark (HP full again, a busy one walks home). A re-roll takes a new pile seed,
## forgets every kept room, re-chooses e0's set (addendum 2) on its next entry, and every room's piles come from
## the baked bank with the new seed and pass the piles test's _check; e0 levels stay prev + 1, max Lv11.

const SAVE := "user://test_reset_save.json"
const SETTINGS := "user://test_reset_settings.json"

var tree: SceneTree
var _checker = null

func setup(t: SceneTree) -> void:
	tree = t

func _ground(seed := 7) -> Node2D:
	var g: Node2D = load("res://scenes/test_ground.tscn").instantiate()
	g.layout_seed = seed
	g.save_path = SAVE
	g.settings_path = SETTINGS
	g.build()
	return g

func _free(g: Node2D) -> void:
	if is_instance_valid(g): g.free()

func _clean() -> void:
	for f in [SAVE, SETTINGS]:
		if FileAccess.file_exists(f): DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

func _kill(w: Wolf) -> void:
	w.health.take_hit(w.hp, false)

func _all(g: Node2D) -> Array:
	var out := []
	for p in g.packs:
		for w in p.wolves: out.append(w)
	return out

func _spots(g: Node2D) -> Array:
	var out := []
	for w in _all(g): out.append(w.position)
	return out

## A hand-made layout with e0 hung on c1r1's east exit: e0's "previous room" is then c1r1 (Lv1), so the set rule
## can be seen choosing by the hero's level (in a generated layout e0 hangs off a far room, Lv10 or so).
func _e0_next_to_c1r1(g: Node2D) -> void:
	g.rooms.use_layout({"pos": {"c1r1": Vector2i(1, 1), "e0": Vector2i(2, 1)},
		"links": [["c1r1", "east", "e0", "west"]], "fallback": false})

## A room next to `id` in the session layout (its first warp's room).
func _next_to(g: Node2D, id: String) -> String:
	return String(g.rooms.room(id).warps[0].to)

## RoomReset alone: keep / state / alive_count; reroll_all forgets every room, takes the seed, counts the roll.
func test_room_reset_rules():
	var r := RoomReset.new()
	if r.has("a") or not r.state("a").is_empty() or r.alive_count("a") != -1: return "a fresh RoomReset holds a room"
	var packs := [[{"alive": true, "pos": Vector2(1, 2), "elite": false, "busy": false},
		{"alive": false, "pos": Vector2(3, 4), "elite": true, "busy": false, "respawn": 6.0}]]
	var groups := [{"kind": "wolf", "count": 2, "level": 3, "at": [10, 10]}]
	var piles := [{"group": 0, "count": 2, "home": Vector2(10, 10), "points": [Vector2(1, 2), Vector2(3, 4)]}]
	r.keep("a", packs, groups, piles)
	packs[0][0].alive = false                     # the kept copy does not follow later changes
	groups[0].level = 9
	var st := r.state("a")
	if st.is_empty() or not r.has("a"): return "room a not kept"
	if int(st.groups[0].level) != 3 or not bool(st.packs[0][0].alive): return "kept state shares the caller's arrays"
	if r.alive_count("a") != 1: return "alive_count %d (want 1)" % r.alive_count("a")
	if r.kept_ids() != ["a"]: return "kept_ids %s" % [r.kept_ids()]
	r.reroll_all(42)
	if r.pile_seed != 42 or r.roll != 1: return "reroll_all: seed %d roll %d" % [r.pile_seed, r.roll]
	if r.has("a") or not r.kept_ids().is_empty(): return "reroll_all kept a room"
	var s := RoomReset.new_seed()
	if s < 0 or s > 0x7fffffff: return "new_seed %d out of 31 bits" % s
	return ""

## Owner 2026-11-09 ("ห้ามได้ผังเดิมซ้ำ"): a waypoint re-roll never gives the room its current pile layout again.
## RoomReset.distinct_seed(old, new, id, bank size) keeps `new` unless it equals `old` or picks the same bank entry
## (posmod(room_seed, size)) for room id; then it steps to the next seed until the entry differs. Deterministic.
## No bank (size 0, live placement) or a 1-entry bank: only the seed must differ.
func test_distinct_seed_never_repeats_the_entry():
	var id := "c2r0"
	var old := 12345
	for n in [64, 7, 2]:
		var e_old := posmod(MonsterPiles.room_seed(old, id), n)
		var clash := old + 1
		while posmod(MonsterPiles.room_seed(clash, id), n) != e_old: clash += 1
		var s := RoomReset.distinct_seed(old, clash, id, n)
		if posmod(MonsterPiles.room_seed(s, id), n) == e_old: return "bank %d: seed %d still picks entry %d" % [n, s, e_old]
		if s == old or s < 0 or s > 0x7fffffff: return "bank %d: seed %d (old %d)" % [n, s, old]
		if RoomReset.distinct_seed(old, clash, id, n) != s: return "bank %d: not deterministic" % n
		var free_seed := clash + 1
		while posmod(MonsterPiles.room_seed(free_seed, id), n) == e_old: free_seed += 1
		if RoomReset.distinct_seed(old, free_seed, id, n) != free_seed: return "bank %d: changed a seed that already differs" % n
	for n in [0, 1]:
		if RoomReset.distinct_seed(old, old, id, n) == old: return "bank %d: the same seed again" % n
		if RoomReset.distinct_seed(old, 999, id, n) != 999: return "bank %d: changed a different seed" % n
	if RoomReset.distinct_seed(0x7fffffff, 0x7fffffff, id, 0) != 0: return "the step must wrap within 31 bits"
	return ""

## Task 5 review 2: the rule is about what the player LAST SAW in a room, not the room's entry under the current pile
## seed. A → B → A: c1r1 shown under roll A, a waypoint trip to c2r0 (roll B: c1r1 would be some other entry, never
## seen), then a trip back to c1r1 (roll C) with the worst candidate seed (one giving c1r1 its roll-A entry back):
## RoomReset.reroll_seed moves it off. Many seeds, deterministic; the old guard (against roll B) would have let it repeat.
func test_a_b_a_trip_never_repeats_the_last_shown_layout():
	var old_guard_missed := 0
	for n in [64, 7, 2, 0]:
		for k in 300:
			var r := RoomReset.new()
			var a := (1000 + k * 7919) & 0x7fffffff
			r.reroll_all(a)
			r.mark_shown("c1r1", a, n)
			var e_a: int = r.last_shown("c1r1").entry
			var b := r.reroll_seed(a + 17 + k, "c2r0")
			r.reroll_all(b)
			r.mark_shown("c2r0", b, n)
			if r.last_shown("c1r1").is_empty() or int(r.last_shown("c1r1").seed) != a: return "reroll_all forgot c1r1's last-shown layout"
			var c0 := a                      # no bank of 2+: the seed it was shown with is the clash
			if n > 1:
				c0 = b + 1
				while posmod(MonsterPiles.room_seed(c0, "c1r1"), n) != e_a: c0 += 1
			if RoomReset.distinct_seed(b, c0, "c1r1", n) == c0: old_guard_missed += 1
			var c := r.reroll_seed(c0, "c1r1", false)   # the destination's own rule; every-room guard: test_guard_all_rooms_*
			if n > 1 and posmod(MonsterPiles.room_seed(c, "c1r1"), n) == e_a: return "bank %d seed %d: c1r1 shows entry %d again" % [n, a, e_a]
			if c == a or c == b or c < 0 or c > 0x7fffffff: return "bank %d: roll C seed %d (A %d, B %d)" % [n, c, a, b]
			if r.reroll_seed(c0, "c1r1", false) != c: return "bank %d: not deterministic" % n
	if old_guard_missed == 0: return "setup: no case the old guard (current seed only) would have let repeat"
	return ""

## RoomReset.GUARD_ALL_ROOMS (owner 2026-11-09 "กันทุกห้อง": the room being left never repeats either): false = only
## the trip's destination is guarded; true = every room shown this session. Both settings, many seeds.
func test_guard_all_rooms_switch():
	if not RoomReset.GUARD_ALL_ROOMS: return "GUARD_ALL_ROOMS is off: the owner's rule is every room (กันทุกห้อง)"
	var n := 64
	var left_repeats := 0
	for k in 200:
		var r := RoomReset.new()
		var a := 5000 + k * 104729
		r.reroll_all(a)
		r.mark_shown("c1r1", a, n)
		var b := r.reroll_seed(a + 1, "c2r0")
		r.reroll_all(b)
		r.mark_shown("c2r0", b, n)           # the hero stands in c2r0 and travels to c1r1
		if r.guarded("c1r1", false) != ["c1r1"] or r.guarded("c1r1", true) != ["c1r1", "c2r0"]: return "guarded %s / %s" % [r.guarded("c1r1", false), r.guarded("c1r1", true)]
		if r.guarded("c1r1") != r.guarded("c1r1", RoomReset.GUARD_ALL_ROOMS): return "guarded() does not follow GUARD_ALL_ROOMS"
		var e_left: int = r.last_shown("c2r0").entry
		var e_dest: int = r.last_shown("c1r1").entry
		var c0 := b + 1                      # gives the room being left (c2r0) its entry back, the destination a new one
		while posmod(MonsterPiles.room_seed(c0, "c2r0"), n) != e_left or posmod(MonsterPiles.room_seed(c0, "c1r1"), n) == e_dest: c0 += 1
		if r.reroll_seed(c0, "c1r1", false) != c0: return "destination only: changed a seed that is new for c1r1"
		left_repeats += 1
		var c := r.reroll_seed(c0, "c1r1", true)
		if posmod(MonsterPiles.room_seed(c, "c2r0"), n) == e_left: return "all rooms: c2r0 shows entry %d again" % e_left
		if posmod(MonsterPiles.room_seed(c, "c1r1"), n) == e_dest: return "all rooms: c1r1 shows entry %d again" % e_dest
	if left_repeats == 0: return "setup: no case"
	return ""

## The same in the game: c1r2 shown, a re-roll trip to c2r0 and back to c1r2 with the worst seed: c1r2 does not show
## the layout it was last seen with (go_to records it; the memory survives both re-rolls).
func test_game_a_b_a_trip_never_repeats():
	var g := _ground()
	var a_id := "c1r2"
	var b_id := "c2r0"
	var r := ""
	if not g.rooms.has(a_id) or not g.rooms.has(b_id): r = "setup: layout lacks %s / %s" % [a_id, b_id]
	if r == "":
		g.go_to(a_id, "", false)
		var m: Dictionary = g.reset.last_shown(a_id)
		if m.is_empty() or int(m.seed) != g.pile_seed: r = "go_to did not record %s's layout (%s)" % [a_id, m]
		else:
			var n := int(m.size)
			var seed_a: int = g.pile_seed
			var homes_a: Array = g._room_piles.map(func(p): return p.home)
			var b: int = g.reroll(seed_a + 5, b_id)
			g.go_to(b_id, "", false)
			var c0 := seed_a
			if n > 1:
				c0 = b + 1
				while posmod(MonsterPiles.room_seed(c0, a_id), n) != int(m.entry): c0 += 1
			var got: int = g.reroll(c0, a_id)
			g.go_to(a_id, "", false)
			var m2: Dictionary = g.reset.last_shown(a_id)
			if int(m2.seed) != got: r = "%s recorded seed %d, the roll is %d" % [a_id, int(m2.seed), got]
			elif n > 1 and int(m2.entry) == int(m.entry): r = "%s shows bank entry %d again" % [a_id, int(m.entry)]
			elif got == seed_a: r = "%s re-rolled back to seed %d" % [a_id, seed_a]
			elif g._room_piles.map(func(p): return p.home) == homes_a: r = "%s has its last-shown piles again (bank %d)" % [a_id, n]
	_free(g)
	_clean()
	return r

## The same rule in the game: reroll(seed, room) with a seed that would pick the room's current bank entry lays a
## different layout when the room is built again.
func test_reroll_with_a_clashing_seed_changes_the_room():
	var g := _ground()
	var id := "c1r2"
	g.go_to(id, "", false)
	var r := ""
	var groups: Array = g._room_groups
	var bank := PileBank.find(id, g.rooms.pile_hash(id, groups))
	var n: int = bank["p"].size() if not bank.is_empty() else 0
	var old: int = g.pile_seed
	var homes0: Array = g._room_piles.map(func(p): return p.home)
	var clash := old + 1
	if n > 1:
		while posmod(MonsterPiles.room_seed(clash, id), n) != posmod(MonsterPiles.room_seed(old, id), n): clash += 1
	var got: int = g.reroll(clash, id)
	if n > 1 and posmod(MonsterPiles.room_seed(got, id), n) == posmod(MonsterPiles.room_seed(old, id), n): r = "the re-roll kept bank entry %d" % posmod(MonsterPiles.room_seed(old, id), n)
	elif got == old: r = "the re-roll kept the seed"
	if r == "":
		g.go_to(id, "", false)
		if g._room_piles.map(func(p): return p.home) == homes0: r = "%s has the same piles after the re-roll (bank size %d)" % [id, n]
	if r == "" and g.reroll(old + 1000) != old + 1000: r = "reroll(seed) without a room must keep the seed"
	_free(g)
	_clean()
	return r

## Walking out and back: the killed stay dead (unseen, no EXP again; M4c addendum: they stay dead however long
## the hero waits, until a re-roll brings the room back fresh), the living stand where they were (a chasing one walks home), elite marks kept, HP full; the piles
## (homes, spawn points) unchanged.
func test_out_and_back_keeps_dead_and_positions():
	var g := _ground()
	var id := "c1r2"
	var other := _next_to(g, id)
	g.go_to(id, "", false)
	var r := ""
	var ws := _all(g)
	if ws.size() < 5: r = "%s has %d monsters" % [id, ws.size()]
	var pack: WolfPack = g.packs[0]
	var dead: Array = [pack.wolves[0], pack.wolves[1]] if pack.wolves.size() >= 2 else []
	if r == "" and dead.size() < 2: r = "first pack of %s has %d monsters" % [id, pack.wolves.size()]
	if r == "":
		for w in dead: _kill(w)
		pack.tick(3.0)                          # 3 s pass in the room
	var moved: Wolf = ws[ws.size() - 1]
	var hurt: Wolf = ws[ws.size() - 2]
	var elite: Wolf = ws[ws.size() - 3]
	var moved_to: Vector2 = moved.spawn_at + Vector2(10, 6)
	if r == "":
		moved.position = moved_to
		moved.state = "chase"
		hurt.health.take_hit(1, false)
		elite.set_elite(true)
	var homes := []
	for w in ws: homes.append([w.home, w.spawn_at])
	var before := {}
	for w in ws: before[ws.find(w)] = w.position
	var exp_before: int = g.hero.exp
	var lv_before: int = g.hero.level
	g.go_to(other, "", false)
	if r == "" and not g.reset.has(id): r = "%s not kept on leaving" % id
	if r == "" and g.reset.alive_count(id) != ws.size() - 2: r = "kept %d alive (want %d)" % [g.reset.alive_count(id), ws.size() - 2]
	g.go_to(id, "", false)
	var back := _all(g)
	if r == "" and back.size() != ws.size(): r = "%d monsters back (want %d)" % [back.size(), ws.size()]
	if r == "" and (g.hero.exp != exp_before or g.hero.level != lv_before): r = "coming back gave EXP again"
	for i in mini(back.size(), ws.size()):
		if r != "": break
		var w: Wolf = back[i]
		if [w.home, w.spawn_at] != homes[i]: r = "monster %d home/spawn moved" % i
		elif i < 2:
			if w.is_alive() or w.visible or w.hp != 0: r = "killed monster %d is back (state %s, hp %d)" % [i, w.state, w.hp]
		elif not w.is_alive(): r = "living monster %d came back dead" % i
		elif w.hp != w.health.max_hp: r = "monster %d HP %d / %d (want full)" % [i, w.hp, w.health.max_hp]
		elif w.position != before[i]: r = "monster %d at %s (was %s)" % [i, w.position, before[i]]
		elif (w.elite) != (i == ws.size() - 3): r = "monster %d elite %s" % [i, w.elite]
		elif i == ws.size() - 1 and w.state != "return": r = "the chasing monster came back %s (want return)" % w.state
		elif i != ws.size() - 1 and w.state != "idle": r = "monster %d came back %s" % [i, w.state]
	if r == "" and back[ws.size() - 1].position != moved_to: r = "the moved monster is at %s (want %s)" % [back[ws.size() - 1].position, moved_to]
	# M4c addendum (owner 2026-11-08): the dead stay dead in the room, long past the old 9 s respawn
	var p2: WolfPack = g.packs[0]
	if r == "":
		p2.tick(Balance.num("wolf.respawn") * 4.0)
		for i in 2:
			if p2.wolves[i].is_alive(): r = "killed monster %d revived in the room (the dead stay dead until a re-roll)" % i
	# ... until a re-roll (waypoint trip): the room comes back fresh, everyone alive
	if r == "":
		g.reroll(4242)
		g.go_to(id, "", false)
		var fresh := _all(g)
		if fresh.size() != ws.size(): r = "after the re-roll %d monsters (want %d)" % [fresh.size(), ws.size()]
		for w in fresh:
			if r == "" and not w.is_alive(): r = "a monster still dead after the re-roll"
	_free(g)
	_clean()
	return r

## A re-roll: a new pile seed, no kept rooms (the room the hero stands in is not kept when he leaves it after
## the re-roll), the left room spawns fresh on new piles, and over every room most piles differ.
func test_reroll_new_piles_and_clears_state():
	var g := _ground()
	var id := "c1r2"
	var other := _next_to(g, id)
	g.go_to(id, "", false)
	var first := _spots(g)
	_kill(_all(g)[0])
	g.go_to(other, "", false)
	var r := ""
	if not g.reset.has(id): r = "%s not kept" % id
	var old_seed: int = g.pile_seed
	var old_piles := {}
	for rid in g.rooms.ids(): old_piles[rid] = str(g.piles_for(rid, g.groups_for(rid, _next_to(g, rid))))
	var got: int = g.reroll(old_seed + 1000)
	if r == "" and (got != old_seed + 1000 or g.pile_seed != got): r = "reroll used seed %d / %d" % [got, g.pile_seed]
	if r == "" and not g.reset.kept_ids().is_empty(): r = "kept after reroll: %s" % [g.reset.kept_ids()]
	if r == "" and g.arena_set != -1: r = "e0 set %d still chosen after reroll" % g.arena_set
	# the room he stands in at the re-roll is not kept when he leaves it
	_kill(_all(g)[0])
	g.go_to(id, "", false)
	if r == "" and g.reset.has(other): r = "the room left after the reroll was kept"
	var back := _all(g)
	for w in back:
		if r == "" and not w.is_alive(): r = "a monster is dead in %s after the reroll" % id
	if r == "" and _spots(g) == first: r = "%s piles unchanged after the reroll" % id
	var changed := 0
	for rid in g.rooms.ids():
		if str(g.piles_for(rid, g.groups_for(rid, _next_to(g, rid)))) != old_piles[rid]: changed += 1
	var n: int = g.rooms.ids().size()
	print("    reroll: piles changed in %d of %d rooms" % [changed, n])
	if r == "" and changed < n - 1: r = "only %d of %d rooms got new piles" % [changed, n]
	_free(g)
	_clean()
	return r

## Addendum 2: e0's set is kept while the hero walks in and out (even if he levels up), and chosen again by
## the rule (target max(hero level, previous room), closest set, ties higher) on the first entry after a
## re-roll. Here the hero comes from c1r1 (Lv1): at Lv1 set 0 (w1); at Lv10, after the re-roll, set 3 (w3).
func test_reroll_rechooses_e0_set():
	var g := _ground()
	_e0_next_to_c1r1(g)
	var sets: Array = g.rooms.room("e0").monster_sets
	var from_lv := int(g.rooms.room_levels()["c1r1"])
	g.hero.set_progress(1, 0)
	g.go_to("e0", "west", false)
	var r := ""
	var a := RoomLevels.arena_set(sets, 1, from_lv)
	if g.arena_set != a: r = "first entry: set %d (want %d)" % [g.arena_set, a]
	g.hero.set_progress(10, 0)
	g.go_to("c1r1", "", false)
	g.go_to("e0", "west", false)
	if r == "" and g.arena_set != a: r = "set changed to %d without a reroll" % g.arena_set
	if r == "" and String(g.packs[0].kind) != String(sets[a][0].kind): r = "kept e0 holds %s" % g.packs[0].kind
	g.go_to("c1r1", "", false)
	g.reroll(4242)
	g.go_to("e0", "west", false)
	var b := RoomLevels.arena_set(sets, 10, from_lv)
	if r == "" and a == b: r = "test setup: Lv1 and Lv10 heroes pick the same set %d" % a
	if r == "" and g.arena_set != b: r = "after reroll: set %d (want %d)" % [g.arena_set, b]
	if r == "" and g.packs.size() != sets[b].size(): r = "after reroll: %d packs (want %d)" % [g.packs.size(), sets[b].size()]
	for i in mini(g.packs.size(), sets[b].size()):
		if r == "" and String(g.packs[i].kind) != String(sets[b][i].kind): r = "after reroll pack %d is %s" % [i, g.packs[i].kind]
	_free(g)
	_clean()
	return r

func _check_piles(g: Node2D, id: String, groups: Array) -> String:
	if _checker == null: _checker = load("res://tests/test_monster_piles.gd").new()
	var piles: Array = g.piles_for(id, groups)
	if MonsterPiles.fell_back(piles): return "%s fell back to built homes" % id
	var room_seed := MonsterPiles.room_seed(g.pile_seed, id)
	var bank := PileBank.find(id, g.rooms.pile_hash(id, groups))
	if bank.is_empty(): return "%s: no bank set (run tools/bake_piles.gd)" % id
	var i := posmod(room_seed, bank.p.size())
	if str(piles) != str(PileBank.decode(bank.p[i], groups)): return "%s piles are not bank entry %d" % [id, i]
	return _checker._check(g.rooms, id, groups, piles, int(bank.seeds[i]))

## After re-rolls every room's piles (e0: each of its four sets) are the baked bank's entry for the new seed
## and pass the piles test's _check (open ground, arrival floors: Review Focus 3, spacing, counts, levels).
func test_rerolled_piles_pass_check():
	var g := _ground()
	var r := ""
	for s in [3, 77, 1001]:
		g.reroll(s)
		for id in g.rooms.ids():
			var lists: Array = []
			var sets: Array = g.rooms.room(id).get("monster_sets", [])
			if sets.is_empty(): lists.append(g.groups_for(id, _next_to(g, id)))
			else:
				for set in sets: lists.append(RoomLevels.arena_groups(set, 10))
			for groups in lists:
				var e := _check_piles(g, id, groups)
				if e != "":
					r = "seed %d: %s" % [s, e]
					break
			if r != "": break
		if r != "": break
	_free(g)
	_clean()
	return r

## Addendum 3 after a re-roll: e0 monsters at the previous room's level + 1, max Lv11 (from the Lv10 room behind
## its exit Lv11), the set still by addendum 2's rule. Review fix: put into e0 straight from a Lv6 room that is not
## next to it, the room behind e0's exit counts (Lv11 again, not Lv7).
func test_e0_levels_after_reroll():
	var g := _ground()
	var levels: Dictionary = g.rooms.room_levels()
	var sets: Array = g.rooms.room("e0").monster_sets
	var r := ""
	g.hero.set_progress(1, 0)
	for c in [[10, 11], [6, 7]]:
		var from := ""
		for id in levels:
			if int(levels[id]) == c[0] and id != "e0": from = id
		if from == "":
			r = "seed 7 has no Lv%d room" % c[0]
			break
		g.reroll(500 + c[0])
		g.go_to(from, "", false)
		g.go_to("e0", "west", false)
		var behind := String(g.rooms.room("e0").warps[0].to)
		var prev_lv: int = c[0] if behind == from else int(levels[behind])
		if r == "" and c[0] == 10 and behind != from: r = "test setup: seed 7's Lv10 room %s is not behind e0 (%s)" % [from, behind]
		if r == "" and c[0] == 6 and behind == from: r = "test setup: the Lv6 room is next to e0"
		var want_set := RoomLevels.arena_set(sets, 1, prev_lv)
		var want_lv := RoomLevels.arena_level(prev_lv)
		if r == "" and g.arena_set != want_set: r = "from Lv%d: set %d (want %d)" % [c[0], g.arena_set, want_set]
		for p in g.packs:
			for w in p.wolves:
				if r == "" and w.level != want_lv: r = "from Lv%d %s: a %s is Lv%d (want %d)" % [c[0], from, p.kind, w.level, want_lv]
		if r != "": break
	_free(g)
	_clean()
	return r

## A new game (a new session: test_ground.build) re-rolls: no kept rooms, e0's set not chosen, the pile seed
## is the session's layout seed, every monster alive again; a load does not bring back the old session's
## rooms (the save keeps the layout seed for reference only; each session makes a new layout and starts in
## c1r1). Two random sessions get different pile seeds.
func test_new_game_rerolls():
	var r := ""
	var g := _ground()
	var id := "c1r2"
	g.go_to(id, "", false)
	for w in _all(g): _kill(w)
	g.go_to(_next_to(g, id), "", false)
	g.go_to("e0", "west", false)
	if g.reset.alive_count(id) != 0: r = "test setup: %s kept %d alive" % [id, g.reset.alive_count(id)]
	if r == "" and g.arena_set < 0: r = "test setup: no e0 set chosen"
	g.save_now()
	_free(g)
	var n := _ground()                       # loads the save written above
	if r == "" and not n.reset.kept_ids().is_empty(): r = "new game kept rooms %s" % [n.reset.kept_ids()]
	if r == "" and n.arena_set != -1: r = "new game kept e0 set %d" % n.arena_set
	if r == "" and n.reset.roll != 1: r = "new game roll %d (want 1)" % n.reset.roll
	if r == "" and n.pile_seed != n.session_seed: r = "new game pile seed %d, session seed %d" % [n.pile_seed, n.session_seed]
	if r == "" and n.room_id != n.rooms.start: r = "new game starts in %s" % n.room_id
	n.go_to(id, "", false)
	for w in _all(n):
		if r == "" and not w.is_alive(): r = "a monster of %s is still dead in the new game" % id
	_free(n)
	var a := _ground(-1)
	var b := _ground(-1)
	if r == "" and a.pile_seed == b.pile_seed: r = "two random sessions share pile seed %d" % a.pile_seed
	if r == "" and (a.pile_seed != a.session_seed or b.pile_seed != b.session_seed): r = "random session pile seed is not its layout seed"
	var saved = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
	if r == "" and (not saved is Dictionary or int(saved.get("seed", -1)) != b.session_seed): r = "save does not hold the session's seed for reference: %s" % [saved.get("seed") if saved is Dictionary else saved]
	_free(a)
	_free(b)
	_clean()
	return r

## Owner 2026-11-09 "กันทุกห้อง": with every room guarded the rule must still be met in the real game. String.hash is
## djb2 and room_seed hashes "<seed>:<id>", so a room's entry in a bank of 64 is (33^L × f(seed) + g(id)) mod 64, L the
## length of ":<id>". Every real suffix is odd (":c0r0" 5, ":e0" / ":x1" 3) and 33² ≡ 1 (mod 64), so 33^L ≡ 33 for all:
## every room's entry moves by the same step with the seed. Each guarded room rules out one value of f(seed) mod its
## bank size, so a seed that repeats no room exists while (rooms with a bank) < the smallest bank (and a bank-less
## room rules out one seed only). Review I3: the real rooms (data/rooms.json via RoomSet) and their real bank sizes
## (PileBank, the smallest set of each room: e0 has one per monster set), every room shown, many re-rolls in a row.
func test_guard_all_rooms_never_repeats_any_room():
	var ids: Array = Array(RoomSet.open().ids())
	ids.sort()
	if ids.size() < 2: return "setup: %d rooms in rooms.json" % ids.size()
	var size := {}
	var banked := 0
	var smallest := 1 << 30
	for id in ids:
		var n := 0
		for set in PileBank.data().get("rooms", {}).get(id, []):
			var k: int = set["p"].size()
			if k > 0: n = k if n == 0 else mini(n, k)
		size[id] = n
		if n > 1:
			banked += 1
			smallest = mini(smallest, n)
	if banked == 0: return "setup: no room has a piles bank"
	if banked >= smallest: return "%d rooms with a bank, smallest bank %d: re-roll guard can run out of seeds (B28)" % [banked, smallest]
	var r := RoomReset.new()
	var s := 4242
	r.reroll_all(s)
	for id in ids: r.mark_shown(id, s, size[id])
	for k in 400:
		var dest: String = ids[k % ids.size()]
		var before := {}
		for id in ids: before[id] = r.last_shown(id)
		var c := r.reroll_seed((s * 31 + k * 7919) & 0x7fffffff, dest, true)
		if c == s: return "re-roll %d: the same pile seed %d" % [k, s]
		for id in ids:
			var n: int = size[id]
			if c == int(before[id].seed): return "re-roll %d: %s gets its last seed %d again" % [k, id, c]
			if n > 1 and posmod(MonsterPiles.room_seed(c, id), n) == int(before[id].entry): return "re-roll %d: %s shows entry %d of %d again" % [k, id, before[id].entry, n]
		r.reroll_all(c)
		s = c
		for id in ids: r.mark_shown(id, c, size[id])
	return ""

## Review M1: when the guarded rooms rule out every seed (a bank of 2, two rooms last shown under seeds that pick
## different entries for f(seed)), reroll_seed gives up after 4096 steps (with a warning) instead of looping on.
func test_reroll_seed_gives_up_when_no_seed_is_free():
	var r := RoomReset.new()
	var s1 := 100
	var s2 := 101
	while posmod(MonsterPiles.room_seed(s2, "c1r1"), 2) == posmod(MonsterPiles.room_seed(s1, "c1r1"), 2): s2 += 1
	r.mark_shown("c1r1", s1, 2)
	r.mark_shown("c2r0", s2, 2)
	r.reroll_all(s2)
	var c := r.reroll_seed(500, "c1r1", true)
	if c != (500 + 4096) & 0x7fffffff: return "gave seed %d, want the guard's last try %d" % [c, 500 + 4096]
	if not (r.repeats("c1r1", c) or r.repeats("c2r0", c)): return "setup: seed %d repeats no room, so a free seed existed" % c
	return ""
