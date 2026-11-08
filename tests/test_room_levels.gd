extends RefCounted
## M4d addendum (docs/superpowers/specs/2026-11-08-m4d-random-layout.md, "monster levels follow the layout"):
## d = rooms walked from c1r1 in the session's layout, D = the largest d of any forest room (e0 left out);
## L = 1 at d = 0, else round(1 + (d - 1) * 8 / max(D - 1, 1)) + 1 clamped to 2..10. Every group in a room
## uses L, except a group that was 1 level above the room's first group keeps that +1 (cap 10). e0 unchanged.

const TMP_SAVE := "user://test_levels_save.json"
const SEEDS := 200

var tree: SceneTree
var _table := {}

func setup(t: SceneTree) -> void:
	tree = t

func _rooms() -> Dictionary:
	if _table.is_empty(): _table = RoomSet.open().exit_table()
	return _table

## Rooms walked from c1r1 (written here, not RoomLayout's, so the tests check it independently).
func _walk(links: Array) -> Dictionary:
	var dist := {"c1r1": 0}
	var todo := ["c1r1"]
	while not todo.is_empty():
		var id: String = todo.pop_front()
		for k in links:
			for h in [[k[0], k[2]], [k[2], k[0]]]:
				if h[0] == id and not dist.has(h[1]):
					dist[h[1]] = dist[id] + 1
					todo.append(h[1])
	return dist

## The approved formula, written out again for the tests.
func _want(d: int, far: int) -> int:
	if d == 0: return 1
	return clampi(int(round(1.0 + (d - 1) * 8.0 / maxi(far - 1, 1))) + 1, 2, 10)

func _far(dist: Dictionary) -> int:
	var far := 0
	for id in dist:
		if id != "e0": far = maxi(far, int(dist[id]))
	return far

func test_formula_by_hand():
	var cases := [[0, 5, 1], [1, 1, 2], [1, 5, 2], [2, 5, 4], [3, 5, 6], [4, 5, 8], [5, 5, 10],
		[2, 6, 4], [3, 6, 5], [4, 6, 7], [5, 6, 8], [6, 6, 10], [1, 2, 2], [2, 2, 10], [9, 6, 10]]
	for c in cases:
		var got := RoomLevels.level_at(c[0], c[1])
		if got != c[2]: return "d=%d D=%d gives Lv%d (want %d)" % [c[0], c[1], got, c[2]]
	return ""

## A hand-made chain c1r1 - a - b - c, with e0 one step past c: e0 is not a forest room, so D = 3.
func test_small_layout_leaves_e0_out():
	var l := {"pos": {"c1r1": Vector2i(3, 3), "a": Vector2i(4, 3), "b": Vector2i(5, 3), "c": Vector2i(6, 3),
		"e0": Vector2i(6, 4)}, "links": [["c1r1", "east", "a", "west"], ["a", "east", "b", "west"],
		["b", "east", "c", "west"], ["c", "south", "e0", "north"]], "fallback": false}
	var lv := RoomLevels.for_layout(l)
	if lv.has("e0"): return "e0 got a layout level (%d); it keeps its own sets" % lv.e0
	var want := {"c1r1": 1, "a": 2, "b": 6, "c": 10}
	return "" if lv == want else "levels %s (want %s)" % [lv, want]

func test_start_is_level_1_and_neighbours_level_2():
	for s in SEEDS:
		var l := RoomLayout.generate(s, _rooms())
		var lv := RoomLevels.for_layout(l)
		var dist := _walk(l.links)
		if int(lv.get("c1r1", -1)) != 1: return "seed %d: c1r1 Lv%s" % [s, lv.get("c1r1")]
		for id in dist:
			if int(dist[id]) == 1 and id != "e0" and int(lv[id]) != 2: return "seed %d: neighbour %s Lv%d" % [s, id, lv[id]]
	return ""

func test_farthest_forest_room_is_level_10():
	for s in SEEDS:
		var l := RoomLayout.generate(s, _rooms())
		var lv := RoomLevels.for_layout(l)
		var dist := _walk(l.links)
		var far := _far(dist)
		var any := false
		for id in dist:
			if id == "e0" or int(dist[id]) != far: continue
			any = true
			if int(lv[id]) != 10: return "seed %d: farthest room %s (d=%d) Lv%d" % [s, id, far, lv[id]]
		if not any: return "seed %d: no farthest forest room" % s
		if lv.has("e0"): return "seed %d: e0 got a layout level" % s
	return ""

## Every forest room on the map has a level from the formula; levels never drop as d grows.
func test_levels_follow_distance():
	for s in SEEDS:
		var l := RoomLayout.generate(s, _rooms())
		var lv := RoomLevels.for_layout(l)
		var dist := _walk(l.links)
		var far := _far(dist)
		for id in l.pos:
			if id == "e0": continue
			if not lv.has(id): return "seed %d: %s has no level" % [s, id]
			if int(lv[id]) != _want(int(dist[id]), far): return "seed %d: %s d=%d Lv%d (want %d)" % [s, id, dist[id], lv[id], _want(int(dist[id]), far)]
		for a in lv:
			for b in lv:
				if int(dist[a]) < int(dist[b]) and int(lv[a]) > int(lv[b]):
					return "seed %d: %s (d=%d) Lv%d above %s (d=%d) Lv%d" % [s, a, dist[a], lv[a], b, dist[b], lv[b]]
	return ""

func test_group_offset_kept_and_capped():
	var src := [{"kind": "wolf", "level": 3, "count": 5, "at": [10, 20]}, {"kind": "macaque", "level": 4, "count": 3, "at": [30, 40]}]
	var got := RoomLevels.groups(src, 5)
	if int(got[0].level) != 5 or int(got[1].level) != 6: return "L5: levels %d, %d (want 5, 6)" % [got[0].level, got[1].level]
	if got[1].kind != "macaque" or int(got[1].count) != 3 or got[1].at != [30, 40]: return "group data changed: %s" % [got[1]]
	if int(src[0].level) != 3 or int(src[1].level) != 4: return "the room data was changed"
	got = RoomLevels.groups(src, 10)
	if int(got[0].level) != 10 or int(got[1].level) != 10: return "L10: levels %d, %d (want 10, 10 - cap)" % [got[0].level, got[1].level]
	var c2r3 := [{"kind": "kongkoi", "level": 9, "count": 4}, {"kind": "kongkoi", "level": 9, "count": 4},
		{"kind": "kongkoi", "level": 10, "count": 2}, {"kind": "viper", "level": 9, "count": 4}]
	var lv: Array = []
	for g in RoomLevels.groups(c2r3, 4): lv.append(int(g.level))
	if lv != [4, 4, 5, 4]: return "c2r3-like at L4: %s (want [4, 4, 5, 4])" % [lv]
	var same := [{"kind": "deer", "level": 1, "count": 8}, {"kind": "boar", "level": 1, "count": 8}]
	lv = []
	for g in RoomLevels.groups(same, 1): lv.append(int(g.level))
	return "" if lv == [1, 1] else "c1r1-like at L1: %s" % [lv]

## The real rooms: the +1 groups are c1r0 deer, c0r2 viper, c2r2 macaque and c2r3's Lv10 kongkoi.
func test_real_rooms_offsets():
	var rooms := RoomSet.open()
	var plus := {}
	for id in rooms.ids():
		if id == "e0": continue
		var ms: Array = rooms.room(id).get("monsters", [])
		var got := RoomLevels.groups(ms, 5)
		for i in got.size():
			if int(got[i].level) == 6: plus[id + " " + String(got[i].kind)] = true
			elif int(got[i].level) != 5: return "%s %s Lv%d at L5" % [id, got[i].kind, got[i].level]
	var want := ["c0r2 viper", "c1r0 deer", "c2r2 macaque", "c2r3 kongkoi"]
	var keys := plus.keys()
	keys.sort()
	return "" if keys == want else "+1 groups %s (want %s)" % [keys, want]

func _ground(seed: int) -> Node2D:
	if FileAccess.file_exists(TMP_SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))
	var g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = TMP_SAVE
	g.layout_seed = seed
	g.build()
	return g

## A real session spawns every pack with its room's layout level (+1 kept); e0 spawns its chosen set
## (M4d addendum 2) at the previous room's level + 1, max 11 (addendum 3): here from the farthest room, Lv11.
func test_session_spawns_layout_levels():
	for s in [1, 3, 58]:
		var g := _ground(s)
		var l: Dictionary = g.rooms.active
		var dist := _walk(l.links)
		var far := _far(dist)
		var near := ""
		var farthest := ""
		for id in dist:
			if id == "e0": continue
			if int(dist[id]) == 1 and near == "": near = id
			if int(dist[id]) == far: farthest = id
		var r := ""
		for id in ["c1r1", near, farthest, "e0"]:
			g.go_to(id, "", false)
			var src: Array = g.rooms.room(id).get("monsters", [])
			# addendum 2: a new Lv1 hero coming from the farthest forest room (Lv10) -> target 10 -> w3 set
			if id == "e0": src = g.rooms.room(id).monster_sets[3]
			if g.packs.size() != src.size(): r = "seed %d %s: %d packs (want %d)" % [s, id, g.packs.size(), src.size()]
			for i in mini(g.packs.size(), src.size()):
				var want := 11                   # addendum 3: from the farthest forest room (Lv10) + 1
				if id != "e0":
					var room_lv := _want(int(dist[id]), far)
					want = mini(room_lv + (1 if int(src[i].level) == int(src[0].level) + 1 else 0), 10)
				var p: WolfPack = g.packs[i]
				if p.level != want: r = "seed %d %s pack %d (%s) Lv%d (want %d)" % [s, id, i, p.kind, p.level, want]
				for w in p.wolves:
					if w.level != want: r = "seed %d %s: a %s is Lv%d (want %d)" % [s, id, p.kind, w.level, want]
			if r != "": break
		if r == "" and int(g.packs[0].level) == 0: r = "no packs"
		g.free()
		if r != "": return r
	return ""

## M4d addendum 2: e0's set. Average levels of the four sets (each monster counted once): w1 (boar 2 x10,
## wolf 3 x8) 2.44; e0 (wolf 5 x12, macaque 4 x8) 4.6; e2 (shroom 6 x12, wolf 7 x10) 6.45; w3 (kongkoi 9 x10,
## kongkoi 10 x2, macaque 8 x8) 8.7. Target = max(hero level, level of the room the hero came from).
func test_arena_set_by_hero_and_previous_room():
	var sets: Array = RoomSet.open().room("e0").get("monster_sets", [])
	if sets.size() != 4: return "e0 has %d sets" % sets.size()
	# [hero level, previous room level, want set index (0 w1, 1 e0, 2 e2, 3 w3)]
	var cases := [[3, 10, 3], [12, 0, 3], [12, 2, 3], [1, 2, 0], [1, 0, 0], [1, 1, 0], [5, 2, 1], [2, 5, 1],
		[7, 4, 2], [4, 7, 2], [8, 0, 3], [3, 3, 0], [4, 0, 1]]
	for c in cases:
		var got := RoomLevels.arena_set(sets, c[0], c[1])
		if got != c[2]: return "hero Lv%d from a Lv%d room: set %d (want %d)" % [c[0], c[1], got, c[2]]
	return ""

## Ties go to the higher set (owner: "สูงกว่าเลเวลฮีโร่กับห้องก่อนหน้า"), whatever order the sets are in.
func test_arena_set_tie_goes_higher():
	var low := [{"kind": "boar", "level": 2, "count": 4}]
	var high := [{"kind": "wolf", "level": 4, "count": 4}]
	if RoomLevels.arena_set([low, high], 3, 0) != 1: return "tie at 3 between Lv2 and Lv4 sets chose the lower"
	if RoomLevels.arena_set([high, low], 3, 0) != 0: return "tie (sets listed high first) chose the lower"
	if RoomLevels.arena_set([low, high], 1, 3) != 1: return "tie from the previous room's level chose the lower"
	var mixed := [{"kind": "boar", "level": 2, "count": 3}, {"kind": "wolf", "level": 6, "count": 1}]   # avg 3.0
	if absf(RoomLevels.set_level(mixed) - 3.0) > 0.001: return "set level %.2f (want 3.0, weighted by count)" % RoomLevels.set_level(mixed)
	return ""

## M4d addendum 3: e0 monster level = level of the room the hero came from + 1, at most Lv11; unknown
## previous room (0) keeps the set's own levels; kinds, counts and homes never change.
func test_arena_level_previous_room_plus_one():
	for c in [[10, 11], [6, 7], [1, 2], [9, 10], [11, 11], [15, 11], [0, 0], [-1, 0]]:
		if RoomLevels.arena_level(c[0]) != c[1]: return "from a Lv%d room: Lv%d (want %d)" % [c[0], RoomLevels.arena_level(c[0]), c[1]]
	var sets: Array = RoomSet.open().room("e0").get("monster_sets", [])
	for from_lv in range(0, 16):
		for st in sets:
			var before: Array = st.duplicate(true)
			var got := RoomLevels.arena_groups(st, from_lv)
			if st != before: return "arena_groups changed the room data in place"
			if got.size() != st.size(): return "set size changed"
			for i in got.size():
				var want := int(st[i].level) if from_lv <= 0 else mini(from_lv + 1, 11)
				if int(got[i].level) != want: return "from Lv%d: %s Lv%d (want %d)" % [from_lv, got[i].kind, got[i].level, want]
				if int(got[i].level) > 11: return "above Lv11"
				if got[i].kind != st[i].kind or int(got[i].count) != int(st[i].count) or got[i].at != st[i].at:
					return "from Lv%d: group %d changed kind/count/home" % [from_lv, i]
	return ""

## Addendum 3 in a real session: e0 from a Lv10 room spawns Lv11, from a Lv6 room Lv7; the set is still
## chosen by addendum 2's rule (kinds unchanged).
func test_session_arena_level_from_previous_room():
	var r := ""
	for c in [[10, 11], [6, 7]]:
		var g := _ground(7)
		var levels: Dictionary = g.rooms.room_levels()
		var from := ""
		for id in levels:
			if int(levels[id]) == c[0]: from = id
		if from == "":
			g.free()
			return "seed 7 has no Lv%d room" % c[0]
		g.hero.set_progress(1, 0)
		g.go_to(from, "", false)
		g.go_to("e0", "west", false)
		var sets: Array = g.rooms.room("e0").monster_sets
		var want_set := RoomLevels.arena_set(sets, 1, c[0])
		if g.arena_set != want_set: r = "from Lv%d: set %d (want %d)" % [c[0], g.arena_set, want_set]
		elif g.packs.size() != sets[want_set].size(): r = "from Lv%d: %d packs" % [c[0], g.packs.size()]
		else:
			for i in g.packs.size():
				var p: WolfPack = g.packs[i]
				if p.kind != String(sets[want_set][i].kind): r = "from Lv%d: pack %d is %s" % [c[0], i, p.kind]
				for w in p.wolves:
					if w.level != c[1]: r = "from Lv%d %s: a %s is Lv%d (want %d)" % [c[0], from, p.kind, w.level, c[1]]
		g.free()
		if r != "": return r
	return ""

## Addendum 3 check: the monster, EXP and loot numbers accept Lv11 (linear formulas, no level tables).
## Ring/necklace drops take the source level clamped to option_ref_level (10): a Lv11 monster drops a Lv10
## one (no Lv11 item numbers exist; owner decision pending).
func test_level_11_numbers():
	var b: Dictionary = Balance.data()
	for k in b["monsters"]:
		var s10 := Monster.stats_for(String(k), 10)
		var s11 := Monster.stats_for(String(k), 11)
		for f in ["hp", "atk", "def", "exp"]:
			if int(s11[f]) < int(s10[f]): return "%s Lv11 %s %d below Lv10 %d" % [k, f, s11[f], s10[f]]
		if int(s11.hp) <= int(s10.hp) or int(s11.exp) <= 0: return "%s Lv11 stats %s" % [k, s11]
	var w11 := Balance.wolf(11)
	if int(w11.hp) <= int(Balance.wolf(10).hp): return "wolf Lv11 %s" % w11
	if Progression.kill_exp(int(w11.exp), 11, 10) != int(w11.exp): return "Lv10 hero gets reduced EXP from Lv11"
	var rng := RandomNumberGenerator.new()
	for kind in b["loot"]:
		for i in 300:
			rng.seed = i
			for it in Loot.roll(String(kind), 11, rng, i % 2 == 0):
				if it.has("item") and int(it.item.level) > 10: return "Lv11 %s drop item Lv%d" % [kind, it.item.level]
	return ""
