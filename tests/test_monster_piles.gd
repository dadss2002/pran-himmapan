extends RefCounted
## M4d addendum 4 (docs/superpowers/specs/2026-11-08-m4d-random-layout.md): monster groups split into piles of
## 2-4 (MonsterPiles.split), piles spread at random over open ground (MonsterPiles.place): same seed same piles,
## pile centres >= 80 px apart, in-pile spawn points >= 2 x body width apart, arrival rules kept, bosses never
## piled, per-room kinds / counts / levels unchanged, and how many rooms fall back over 20 live seeds.
## Follow-up 3: the baked bank (PileBank, data/piles_bank.json): matches today's data, every entry passes
## _check, the game picks entry room_seed % 64 fast, a stale bank places live.
## Follow-up ("มอนกองบ้างกระจายบ้าง"): per kind in a room piled_count(n) = n / 2 halves up, at least 2 when
## n >= 2, stand in piles; the rest are singles >= 60 px from every single and pile centre. In the game a
## pile (or a single) wakes alone, lunges on its own token and a revived monster comes back on its own spot.
## Follow-up 2: singles >= 60 px from every member spawn point of every pile (not only its centre); a kind of
## exactly 2 is one pile of 2 or two singles, 50/50 per placement seed; a split that fits no group is drawn
## again before the per-group fallback; a lunge token held by a freed monster does not error.

var tree: SceneTree

func setup(t: SceneTree) -> void:
	tree = t

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r

## Every room's monster group list(s): forest rooms one list, e0 its four sets.
func _lists(rooms: RoomSet, id: String) -> Array:
	var out: Array = []
	var sets: Array = rooms.room(id).get("monster_sets", [])
	if sets.is_empty(): out.append(rooms.room(id).get("monsters", []))
	else: out.append_array(sets)
	return out

func test_split_sums_and_sizes():
	for n in range(1, 13):
		for s in 40:
			var parts := MonsterPiles.split(n, _rng(s * 31 + n))
			var sum := 0
			for p in parts: sum += p
			if sum != n: return "split(%d) = %s sums to %d" % [n, parts, sum]
			if n == 1:
				if parts != [1]: return "split(1) = %s (want [1])" % [parts]
				continue
			for p in parts:
				if p < 2 or p > 4: return "split(%d) = %s has a pile of %d (want 2-4)" % [n, parts, p]
	if MonsterPiles.split(0, _rng(1)) != []: return "split(0) not empty"
	return ""

## The spec's examples: 5 -> 2+3; 6 -> 2+4, 3+3 or 2+2+2, and all three show up.
func test_split_examples():
	var seen6 := {}
	for s in 200:
		var five := MonsterPiles.split(5, _rng(s))
		five.sort()
		if five != [2, 3]: return "split(5) = %s (want 2+3)" % [five]
		var six := MonsterPiles.split(6, _rng(s))
		six.sort()
		seen6[str(six)] = true
	for want in ["[2, 4]", "[3, 3]", "[2, 2, 2]"]:
		if not seen6.has(want): return "split(6) never gave %s in 200 seeds (got %s)" % [want, seen6.keys()]
	return ""

## The follow-up's rounding: per kind n / 2 with halves up, never a pile of 1 (2 -> one pile of 2).
func test_piled_count_rounding():
	var want := {0: 0, 1: 0, 2: 2, 3: 2, 4: 2, 5: 3, 6: 3, 7: 4, 8: 4, 9: 5, 10: 5, 11: 6, 12: 6, 16: 8}
	for n in want:
		if MonsterPiles.piled_count(n) != want[n]: return "piled_count(%d) = %d (want %d)" % [n, MonsterPiles.piled_count(n), want[n]]
	return ""

## Pile sizes per group: per kind piled_for of the kind's total (piled_count; a kind of 2: the seed's 50/50
## draw), sizes 2-4, no group given more than it has, a boss group one pile of its count; today's rooms (e0
## sets included) for many seeds.
func test_pile_sizes_per_kind():
	var rooms := RoomSet.open()
	var lists: Array = []
	for id in rooms.ids(): lists.append_array(_lists(rooms, id))
	lists.append([{"kind": "kongkoi", "level": 9, "count": 4, "at": [0, 0]}, {"kind": "kongkoi", "level": 10, "count": 2, "at": [0, 0]},
		{"kind": "viper", "level": 9, "count": 1, "at": [0, 0]}, {"kind": "wolf", "level": 9, "count": 2, "at": [0, 0]},
		{"kind": "kongkoi", "level": 10, "count": 1, "at": [0, 0], "boss": true}])
	for groups in lists:
		for s in 30:
			var sizes := MonsterPiles.pile_sizes(groups, _rng(s), s)
			var piled := {}
			var total := {}
			for gi in groups.size():
				var g: Dictionary = groups[gi]
				var sum := 0
				for x in sizes[gi]:
					sum += x
					if not bool(g.get("boss", false)) and (x < 2 or x > 4): return "%s: a pile of %d" % [g.kind, x]
				if sum > int(g.count): return "%s group of %d given piles %s" % [g.kind, g.count, sizes[gi]]
				if bool(g.get("boss", false)):
					if sizes[gi] != [int(g.count)]: return "boss group split %s" % [sizes[gi]]
					continue
				piled[g.kind] = int(piled.get(g.kind, 0)) + sum
				total[g.kind] = int(total.get(g.kind, 0)) + int(g.count)
			for k in total:
				var want := MonsterPiles.piled_for(total[k], s, k)
				if piled[k] != want: return "%s x%d seed %d: %d piled (want %d)" % [k, total[k], s, piled[k], want]
	return ""

func _piles(rooms: RoomSet, id: String, groups: Array, s: int) -> Array:
	return MonsterPiles.place(rooms.pile_room(id), groups, MonsterPiles.room_seed(s, id))

func test_same_seed_same_piles_other_seed_differs():
	var rooms := RoomSet.open()
	for id in ["c1r2", "x2", "e0"]:
		var groups: Array = _lists(rooms, id)[0]
		var a := _piles(rooms, id, groups, 7)
		var b := _piles(rooms, id, groups, 7)
		if str(a) != str(b): return "%s: seed 7 gave two different placements" % id
		var differ := false
		for s in [8, 9, 10]:
			if str(_piles(rooms, id, groups, s)) != str(a): differ = true
		if not differ: return "%s: seeds 7-10 all gave the same piles" % id
	if MonsterPiles.room_seed(7, "c1r2") == MonsterPiles.room_seed(7, "c2r2"): return "room id not in the seed"
	return ""

## All checks for one room's placement (made with placement seed `seed`); "" when fine.
func _check(rooms: RoomSet, id: String, groups: Array, piles: Array, seed: int) -> String:
	var room := rooms.pile_room(id)
	var near_ok := bool(rooms.room(id).get("near_arrival_ok", false))
	# kinds, counts and levels per group unchanged
	var per := {}
	for p in piles: per[int(p.group)] = int(per.get(int(p.group), 0)) + int(p.count)
	for gi in groups.size():
		if int(per.get(gi, 0)) != int(groups[gi].count): return "%s group %d (%s x%d): piles hold %d" % [id, gi, groups[gi].kind, groups[gi].count, per.get(gi, 0)]
	for p in piles:
		var g: Dictionary = groups[int(p.group)]
		if p.kind != String(g.kind) or int(p.level) != int(g.level): return "%s pile %s Lv%d from group %s Lv%d" % [id, p.kind, p.level, g.kind, g.level]
		if p.points.size() != int(p.count): return "%s pile of %d has %d points" % [id, p.count, p.points.size()]
	if MonsterPiles.fell_back(piles): return ""   # counted by the 200-seed test
	# about half of each kind stands in piles (piled_for), the rest are singles; singles are piles of 1
	var kind_n := {}
	var kind_piled := {}
	for g in groups:
		if bool(g.get("boss", false)): continue
		kind_n[String(g.kind)] = int(kind_n.get(String(g.kind), 0)) + int(g.count)
	for p in piles:
		if p.boss: continue
		if bool(p.single) != (int(p.count) == 1): return "%s %s pile of %d marked single=%s" % [id, p.kind, p.count, p.single]
		if not p.single: kind_piled[String(p.kind)] = int(kind_piled.get(String(p.kind), 0)) + int(p.count)
	for k in kind_n:
		var want := MonsterPiles.piled_for(int(kind_n[k]), seed, k)
		if int(kind_piled.get(k, 0)) != want: return "%s %s x%d: %d in piles (want %d) and %d singles" % [id, k, kind_n[k], kind_piled.get(k, 0), want, int(kind_n[k]) - int(kind_piled.get(k, 0))]
	var arrivals: Array = room.arrivals
	for i in piles.size():
		var p: Dictionary = piles[i]
		if not p.boss and (int(p.count) < 1 or int(p.count) > 4): return "%s pile of %d" % [id, p.count]
		var floor := MonsterPiles.arrival_floor(String(p.kind), near_ok)
		if near_ok and floor != 48.0: return "near_arrival_ok floor %s" % floor
		if not near_ok and MonsterPiles.attacks_first(String(p.kind)) and floor != MonsterPiles.aggro_of(String(p.kind)) + 12.0: return "aggro floor %s" % floor
		if not near_ok and not MonsterPiles.attacks_first(String(p.kind)) and floor != 60.0: return "passive floor %s" % floor
		for q in [p.home] + p.points:
			if not MonsterPiles.is_open(room, q): return "%s %s pile at %s: point %s not on open ground" % [id, p.kind, p.home, q]
			for a in arrivals:
				if (q as Vector2).distance_to(a) < floor: return "%s %s point %s is %.1f px from arrival %s (min %d)" % [id, p.kind, q, (q as Vector2).distance_to(a), a, floor]
		if p.single and p.points != [p.home]: return "%s single %s: points %s, home %s" % [id, p.kind, p.points, p.home]
		var bw := MonsterPiles.body_width(String(p.kind))
		for a in p.points.size():
			for b in range(a + 1, p.points.size()):
				var d: float = p.points[a].distance_to(p.points[b])
				if d < 2.0 * bw - 0.001: return "%s %s pile: points %.1f px apart (min 2 x %.1f)" % [id, p.kind, d, bw]
	return _spacing(id, piles)

## Spacing between piles and singles: pile centres >= 80 px apart; a single >= 60 px from every other single
## and from every pile's centre and every member spawn point (follow-up 2: "วัด 60 px จากทุกตัวในกอง").
func _spacing(id: String, piles: Array) -> String:
	for i in piles.size():
		var p: Dictionary = piles[i]
		for j in range(i + 1, piles.size()):
			var q: Dictionary = piles[j]
			var d2: float = p.home.distance_to(q.home)
			if p.single and q.single:
				if d2 < 60.0: return "%s singles %s and %s only %.1f px apart (min 60)" % [id, p.home, q.home, d2]
			elif p.single or q.single:
				var one: Dictionary = p if p.single else q
				var pile: Dictionary = q if p.single else p
				for m in [pile.home] + pile.points:
					var d3: float = one.home.distance_to(m)
					if d3 < 60.0: return "%s single %s only %.1f px from %s %s %s (min 60 from every member)" % [id, one.home, d3, pile.kind, "pile centre" if m == pile.home else "pile member", m]
			elif d2 < 80.0: return "%s pile centres %s and %s only %.1f px apart" % [id, p.home, q.home, d2]
	return ""

func test_piles_follow_the_rules_every_room():
	var rooms := RoomSet.open()
	for s in [1, 7, 42]:
		for id in rooms.ids():
			for groups in _lists(rooms, id):
				var e := _check(rooms, id, groups, _piles(rooms, id, groups, s), MonsterPiles.room_seed(s, id))
				if e != "": return "seed %d: %s" % [s, e]
	return ""

## Follow-up 2 spacing check on a hand-made room: a single 70 px from a pile's centre but 44 px from one of
## its members is caught (the old centre-only rule passed it); 60 px from every member passes.
func test_spacing_check_measures_every_member():
	var pile := {"kind": "boar", "count": 2, "single": false, "boss": false, "home": Vector2(200, 200),
		"points": [Vector2(174, 200), Vector2(226, 200)]}
	var near := {"kind": "boar", "count": 1, "single": true, "boss": false, "home": Vector2(270, 200), "points": [Vector2(270, 200)]}
	if near.home.distance_to(pile.home) < 60.0: return "test setup: single not 60 px from the centre"
	if _spacing("t", [pile, near]) == "": return "a single 44 px from a pile member passed"
	if _spacing("t", [near, pile]) == "": return "a single 44 px from a pile member passed (single listed first)"
	var far := {"kind": "boar", "count": 1, "single": true, "boss": false, "home": Vector2(286, 200), "points": [Vector2(286, 200)]}
	if _spacing("t", [pile, far]) != "": return "a single 60 px from every member failed: %s" % _spacing("t", [pile, far])
	return ""

## Follow-up 2 in the real rooms: over 60 seeds, every room (e0's four sets each), no single is closer than
## 60 px to any pile's centre or member spawn point (the centre-only rule broke this in many rooms).
func test_singles_clear_every_pile_member():
	var rooms := RoomSet.open()
	var checked := 0
	for s in 60:
		for id in rooms.ids():
			for groups in _lists(rooms, id):
				var piles := _piles(rooms, id, groups, 1000 + s)
				if MonsterPiles.fell_back(piles): continue
				checked += 1
				var e := _spacing(id, piles)
				if e != "": return "seed %d: %s" % [1000 + s, e]
	if checked < 60 * 19 - 5: return "only %d placements checked (most fell back)" % checked
	return ""

## Follow-up 2: a kind with exactly 2 monsters in a room is one pile of 2 or two singles, 50/50 by the placement
## seed: the same seed the same answer, both answers across seeds, about half each; the counts stay right and
## the other kinds keep piled_count. c1r1 with its deer cut to one group of 2.
func test_kind_of_two_pile_or_singles():
	var rooms := RoomSet.open()
	var groups: Array = _lists(rooms, "c1r1")[0].duplicate(true)
	var deer := -1
	for gi in range(groups.size() - 1, -1, -1):
		if String(groups[gi].kind) != "deer": continue
		if deer >= 0: groups.remove_at(deer)
		deer = gi
	groups[deer].count = 2
	var outcome := {"pile": 0, "singles": 0}
	var falls := 0
	for s in 200:
		var seed := MonsterPiles.room_seed(s, "c1r1")
		var want := MonsterPiles.pair_piled(seed, "deer")
		if MonsterPiles.pair_piled(seed, "deer") != want: return "seed %d: two answers" % s
		var piles := _piles(rooms, "c1r1", groups, s)
		if MonsterPiles.fell_back(piles):
			falls += 1
			continue
		var e := _check(rooms, "c1r1", groups, piles, seed)
		if e != "": return "seed %d: %s" % [s, e]
		var sizes := []
		for p in piles:
			if p.kind == "deer": sizes.append(int(p.count))
		sizes.sort()
		if want and sizes != [2]: return "seed %d: pile drawn, deer stand as %s" % [s, sizes]
		if not want and sizes != [1, 1]: return "seed %d: singles drawn, deer stand as %s" % [s, sizes]
		outcome["pile" if want else "singles"] += 1
	if falls > 2: return "%d of 200 seeds fell back" % falls
	if outcome.pile < 60 or outcome.singles < 60: return "not about 50/50 over 200 seeds: %s" % outcome
	print("    kind of 2 (c1r1 deer, 200 seeds): %s, fallbacks %d" % [outcome, falls])
	# a different room id gives a different draw for some seeds
	var differ := false
	for s in 40:
		if MonsterPiles.pair_piled(MonsterPiles.room_seed(s, "c1r1"), "deer") != MonsterPiles.pair_piled(MonsterPiles.room_seed(s, "c2r0"), "deer"): differ = true
	if not differ: return "the room id does not change the draw"
	return ""

## Reviewer gap: a first split that fits no group is drawn again before the per-group fallback. Four groups
## of 2 (8, 4 to pile): split(4) is [4] about half the time (no group holds 4), [2, 2] fits; three groups of 3
## and one of 2 (11, 6 to pile): [4, 2] or [2, 4] fit none. The half rule holds for every seed, and the
## no-fit first draws really happen (the branch is exercised).
func test_pile_sizes_redraw_before_fallback():
	var cases := [[2, 2, 2, 2], [3, 3, 3, 2]]
	for counts in cases:
		var groups: Array = []
		for c in counts: groups.append({"kind": "deer", "level": 3, "count": c, "at": [0, 0]})
		var n := 0
		for c in counts: n += c
		var redrawn := 0
		for s in 60:
			var first := MonsterPiles.split(MonsterPiles.piled_count(n), _rng(s))
			var fits := true
			var left: Array = counts.duplicate()
			for x in first:
				var best := -1
				for i in left.size():
					if left[i] >= x and (best < 0 or left[i] > left[best]): best = i
				if best < 0:
					fits = false
					break
				left[best] -= x
			if not fits: redrawn += 1
			var sizes := MonsterPiles.pile_sizes(groups, _rng(s), s)
			var piled := 0
			for gi in groups.size():
				var sum := 0
				for x in sizes[gi]:
					if x < 2 or x > 4: return "%s seed %d: a pile of %d" % [counts, s, x]
					sum += x
				if sum > counts[gi]: return "%s seed %d: group of %d given %s" % [counts, s, counts[gi], sizes[gi]]
				piled += sum
			if piled != MonsterPiles.piled_count(n): return "%s seed %d: %d piled (want %d, half rule); first draw %s" % [counts, s, piled, MonsterPiles.piled_count(n), first]
		if redrawn == 0: return "%s: no seed drew a split that fits no group (branch not exercised)" % [counts]
	return ""

## A boss group is never split and stays at its home; the other groups still pile round it (>= 80 px).
func test_boss_not_piled():
	var rooms := RoomSet.open()
	var groups: Array = rooms.room("e0").monster_sets[1].duplicate(true)
	var boss := {"kind": "kongkoi", "level": 10, "count": 1, "at": [400, 300], "boss": true}
	groups.append(boss)
	var r := ""
	for s in 20:
		var piles := _piles(rooms, "e0", groups, s)
		var bosses := piles.filter(func(p): return p.boss)
		if bosses.size() != 1: return "seed %d: %d boss piles" % [s, bosses.size()]
		if bosses[0].home != Vector2(400, 300) or bosses[0].points != [Vector2(400, 300)]: return "seed %d: boss moved to %s" % [s, bosses[0].home]
		if int(bosses[0].count) != 1: return "boss pile of %d" % bosses[0].count
		if MonsterPiles.fell_back(piles): continue
		for p in piles:
			if not p.boss and p.home.distance_to(Vector2(400, 300)) < 80.0: return "seed %d: a %s pile %.1f px from the boss" % [s, p.kind, p.home.distance_to(Vector2(400, 300))]
	return r

## In-pile spacing is measured with each kind's body width (collision box at the 0.85 scale).
func test_body_widths_from_collision():
	for k in ["wolf"] + Array(Monster.KINDS):
		var bw := MonsterPiles.body_width(k)
		var scene: PackedScene = load("res://scenes/wolf.tscn" if k == "wolf" else "res://scenes/monster.tscn")
		var n: Node = scene.instantiate()
		var full: float = (n.get_node("Feet").shape as RectangleShape2D).size.x
		n.free()
		if absf(bw - full * 0.85) > 0.001: return "%s body width %.2f (want 0.85 x %.1f)" % [k, bw, full]
		for c in [2, 3, 4]:
			var pts := MonsterPiles.ring_points(Vector2.ZERO, c, MonsterPiles.pile_radius(k, c), 0.3)
			for a in pts.size():
				for b in range(a + 1, pts.size()):
					if pts[a].distance_to(pts[b]) < 2.0 * bw: return "%s pile of %d: %.1f px apart" % [k, c, pts[a].distance_to(pts[b])]
	return ""

## Live placement (MonsterPiles.place, the path a stale bank falls back to) over 20 seeds x every room (e0's
## four sets each): no placement falls back to the built homes and every one passes _check. Follow-up 3: the
## 200-seed run moved to the baked bank (test_bank_entries_follow_the_rules, 64 placements per room and set,
## all checked); the bake itself places live with seeds 0..63.
func test_live_20_seeds_fallbacks():
	var rooms := RoomSet.open()
	var falls := {}
	var bad := ""
	var t0 := Time.get_ticks_msec()
	for s in 20:
		for id in rooms.ids():
			var lists := _lists(rooms, id)
			for li in lists.size():
				var piles := _piles(rooms, id, lists[li], s)
				if MonsterPiles.fell_back(piles):
					var key: String = id if lists.size() == 1 else "%s set %d" % [id, li]
					falls[key] = int(falls.get(key, 0)) + 1
				elif bad == "":
					bad = _check(rooms, id, lists[li], piles, MonsterPiles.room_seed(s, id))
	print("    piles live: 20 seeds, fallbacks %s (%d ms)" % [falls if not falls.is_empty() else "none", Time.get_ticks_msec() - t0])
	if bad != "": return bad
	return "" if falls.is_empty() else "rooms fell back to built homes: %s" % falls

## Follow-up 3: the bank set of room id with these groups, or why it is missing ("" key "err").
func _bank_set(rooms: RoomSet, id: String, groups: Array, label: String) -> Dictionary:
	var bank := PileBank.find(id, rooms.pile_hash(id, groups))
	if bank.is_empty(): return {"err": "piles bank stale or missing for %s (room data, groups or rules changed): run tools/bake_piles.gd" % label}
	return bank

func _label(id: String, lists: Array, li: int) -> String:
	return id if lists.size() == 1 else "%s set %d" % [id, li]

## Follow-up 3: data/piles_bank.json has, for every room and every e0 set, a set whose input hash matches
## today's room data, groups and rules, with PileBank.SIZE (64) placements and their seeds.
func test_bank_matches_current_data():
	PileBank.reload()
	var rooms := RoomSet.open()
	var n := 0
	for id in rooms.ids():
		var lists := _lists(rooms, id)
		for li in lists.size():
			var bank := _bank_set(rooms, id, lists[li], _label(id, lists, li))
			if bank.has("err"): return bank.err
			if PileBank.SIZE != 64: return "bank size %d (want 64)" % PileBank.SIZE
			if bank.p.size() != 64 or bank.seeds.size() != 64: return "%s: %d placements, %d seeds (want 64)" % [_label(id, lists, li), bank.p.size(), bank.seeds.size()]
			n += 1
	if n != rooms.ids().size() + 3: return "%d banked sets (want one per room + e0's 3 more)" % n
	return ""

## Follow-up 3: every banked placement, read back as the game reads it, passes the same _check as live
## placement with the seed it was made with (kinds/counts/levels, half in piles, open ground, arrival floors,
## in-pile spacing, 80 px between piles, 60 px from singles to everyone), none is a fallback, and the 64 of a
## set all differ.
func test_bank_entries_follow_the_rules():
	PileBank.reload()
	var rooms := RoomSet.open()
	var t0 := Time.get_ticks_msec()
	var checked := 0
	for id in rooms.ids():
		var lists := _lists(rooms, id)
		for li in lists.size():
			var groups: Array = lists[li]
			var bank := _bank_set(rooms, id, groups, _label(id, lists, li))
			if bank.has("err"): return bank.err
			var seen := {}
			for i in bank.p.size():
				var piles := PileBank.decode(bank.p[i], groups)
				if MonsterPiles.fell_back(piles): return "%s entry %d is a fallback" % [_label(id, lists, li), i]
				var e := _check(rooms, id, groups, piles, int(bank.seeds[i]))
				if e != "": return "%s bank entry %d (seed %d): %s" % [_label(id, lists, li), i, int(bank.seeds[i]), e]
				seen[str(piles)] = true
				checked += 1
			if seen.size() != bank.p.size(): return "%s: only %d different placements of %d" % [_label(id, lists, li), seen.size(), bank.p.size()]
	print("    piles bank: %d placements checked (%d ms)" % [checked, Time.get_ticks_msec() - t0])
	return ""

## Follow-up 3: with a matching hash RoomSet.piles() returns bank entry room_seed % 64 (levels from the
## groups: forest rooms at the layout's level, e0 at the arena level), the same each call, without preparing
## the room's open ground, in under 5 ms (first entry of a fresh RoomSet, hash included; the bank file is
## already loaded); other pile seeds pick other entries.
func test_bank_pick_is_the_entry_and_fast():
	PileBank.reload()
	PileBank.data()                  # loaded once per run (about 6 ms headless desktop), not per room
	var r := ""
	var cases := [["c1r2", -1], ["e0", 1], ["e0", 3], ["c1r1", -1], ["x2", -1]]
	var times := []
	for c in cases:
		var rooms := RoomSet.open()
		var id: String = c[0]
		var groups: Array = RoomLevels.groups(rooms.room(id).monsters, 6) if int(c[1]) < 0 else RoomLevels.arena_groups(rooms.room(id).monster_sets[int(c[1])], 7)
		var seed := MonsterPiles.room_seed(7, id)
		var t0 := Time.get_ticks_usec()
		var got := rooms.piles(id, groups, seed)
		var us := Time.get_ticks_usec() - t0
		times.append("%s%s %.2f ms" % [id, "" if int(c[1]) < 0 else " set %d" % c[1], us / 1000.0])
		var bank := PileBank.find(id, rooms.pile_hash(id, groups))
		if bank.is_empty(): return "%s: no bank set (run tools/bake_piles.gd)" % id
		var want := PileBank.decode(bank.p[posmod(seed, 64)], groups)
		if str(got) != str(want): r = "%s: piles() is not bank entry %d" % [id, posmod(seed, 64)]
		elif us > 5000: r = "%s: bank pick took %.1f ms (want < 5)" % [id, us / 1000.0]
		elif not rooms._pile_rooms.is_empty(): r = "%s: a bank hit prepared the room's open ground" % id
		elif str(rooms.piles(id, groups, seed)) != str(got): r = "%s: same seed, different piles" % id
		for p in got:
			if r == "" and int(p.level) != int(groups[int(p.group)].level): r = "%s: a pile at Lv%d, its group Lv%d" % [id, p.level, groups[int(p.group)].level]
		if r == "":
			var picks := {}
			for s in 8: picks[str(rooms.piles(id, groups, MonsterPiles.room_seed(s, id)))] = true
			if picks.size() < 5: r = "%s: 8 pile seeds gave only %d placements" % [id, picks.size()]
		if r != "": break
	print("    bank pick: %s" % ", ".join(times))
	return r

## Follow-up 3: the input hash follows what a placement depends on: picture size, blocked grid, exits, spawn,
## near_arrival_ok, the groups' kind / count / home / boss; not the groups' levels or the session's warps.
func test_bank_hash_follows_the_inputs():
	var rooms := RoomSet.open()
	var id := "c1r1"
	var groups: Array = rooms.room(id).monsters
	var base := rooms.pile_hash(id, groups)
	if rooms.pile_hash(id, RoomLevels.groups(groups, 9)) != base: return "a level change changed the hash"
	rooms.use_layout(RoomLayout.generate(5, rooms.exit_table()))
	if rooms.pile_hash(id, groups) != base: return "the session layout (warps) changed the hash"
	var edits := {
		"blocked": func(d): _open_lone_cell(d),
		"exits": func(d): d.exits[0].at = [float(d.exits[0].at[0]) + 8.0, d.exits[0].at[1]],
		"size": func(d): d.size = [520, 512],
		"spawn": func(d): d.spawn = [float(d.spawn[0]) + 8.0, d.spawn[1]],
		"near_arrival_ok": func(d): d.near_arrival_ok = true}
	for k in edits:
		var rs := RoomSet.open()
		var d: Dictionary = rs._rooms[id].duplicate(true)
		edits[k].call(d)
		rs._rooms[id] = d
		if rs.pile_hash(id, groups) == base: return "a %s change kept the hash" % k
	var g_edits := {
		"count": func(g): g[0].count = int(g[0].count) + 1,
		"kind": func(g): g[0].kind = "viper" if String(g[0].kind) != "viper" else "boar",
		"home": func(g): g[0].at = [float(g[0].at[0]) + 1.0, g[0].at[1]],
		"boss": func(g): g[0]["boss"] = true}
	for k in g_edits:
		var g2: Array = groups.duplicate(true)
		g_edits[k].call(g2)
		if rooms.pile_hash(id, g2) == base: return "a group %s change kept the hash" % k
	return ""

## A room data edit that leaves its open ground as it was: one rock cell walled in by rock on all 8 sides
## turns walkable (too small for a body, so not open ground). false when the room has no such cell.
func _open_lone_cell(d: Dictionary) -> bool:
	var rows: Array = d.blocked
	for y in range(1, rows.size() - 1):
		for x in range(1, String(rows[y]).length() - 1):
			var lone := true
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if String(rows[y + dy])[x + dx] != "#": lone = false
			if lone:
				var row := String(rows[y])
				rows[y] = row.substr(0, x) + "." + row.substr(x + 1)
				return true
	return false

## Follow-up 3: a stale bank (the room's data changed without a rebake: one walled-in rock cell opened; or
## groups that were never baked) gives live placement, which still follows every rule.
func test_stale_bank_places_live():
	var id := "c1r1"
	var rooms := RoomSet.open()
	var d: Dictionary = rooms._rooms[id].duplicate(true)
	if not _open_lone_cell(d): return "no rock cell to open in %s" % id
	rooms._rooms[id] = d
	var groups: Array = rooms.room(id).monsters
	var seed := MonsterPiles.room_seed(7, id)
	if not PileBank.find(id, rooms.pile_hash(id, groups)).is_empty(): return "an edited room still matches the bank"
	var got := rooms.piles(id, groups, seed)
	var want := MonsterPiles.place(rooms.pile_room(id), groups, seed)
	if str(got) != str(want): return "stale bank: piles() is not the live placement"
	var e := _check(rooms, id, groups, got, seed)
	if e != "": return "stale bank live placement: %s" % e
	var fresh := RoomSet.open()
	var g2: Array = groups.duplicate(true)
	g2[0].at = [float(g2[0].at[0]) + 8.0, g2[0].at[1]]
	if str(fresh.piles(id, g2, seed)) != str(MonsterPiles.place(fresh.pile_room(id), g2, seed)): return "unbaked groups: piles() is not the live placement"
	return ""

## In the real test ground: each group is one pack holding its piles (spawn points and homes from
## MonsterPiles), same piles on walking out and back, new pile seed gives new piles.
func test_ground_spawns_piles_and_keeps_them():
	var g: Node2D = load("res://scenes/test_ground.tscn").instantiate()
	g.layout_seed = 7
	g.save_path = "user://test_piles_save.json"
	g.settings_path = "user://test_piles_settings.json"
	g.build()
	var r := ""
	var id := "c1r2"
	g.go_to(id, "", false)
	var first := _spots(g)
	var src: Array = g.rooms.room(id).monsters
	if g.packs.size() != src.size(): r = "%d packs for %d groups" % [g.packs.size(), src.size()]
	var groups := RoomLevels.groups(src, int(g.rooms.room_levels()[id]))
	var want: Array = g.rooms.piles(id, groups, MonsterPiles.room_seed(g.pile_seed, id))
	# follow-up 3: the game's piles are the baked bank's entry room_seed % 64
	var bank := PileBank.find(id, g.rooms.pile_hash(id, groups))
	if r == "" and bank.is_empty(): r = "no bank set for %s (run tools/bake_piles.gd)" % id
	elif r == "" and str(want) != str(PileBank.decode(bank.p[posmod(MonsterPiles.room_seed(g.pile_seed, id), 64)], groups)): r = "the game's piles are not the bank entry"
	var want_pts := []
	for p in want:
		for q in p.points: want_pts.append(q)
	if r == "" and first != want_pts: r = "spawned at %s, piles say %s" % [first, want_pts]
	for p in g.packs:
		for w in p.wolves:
			if r == "" and w.pile < 0: r = "a %s has no pile" % p.kind
	g.go_to("c1r1", "", false)
	g.go_to(id, "", false)
	if r == "" and _spots(g) != first: r = "walking out and back moved the piles"
	g.reroll_piles(g.pile_seed + 1)
	g.go_to(id, "", false)
	if r == "" and _spots(g) == first: r = "a new pile seed gave the same piles"
	g.free()
	for f in ["user://test_piles_save.json", "user://test_piles_settings.json"]:
		if FileAccess.file_exists(f): DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	return r

func _spots(g: Node2D) -> Array:
	var out := []
	for p in g.packs:
		for w in p.wolves: out.append(w.position)
	return out

func _ground() -> Node2D:
	var g: Node2D = load("res://scenes/test_ground.tscn").instantiate()
	g.layout_seed = 7
	g.save_path = "user://test_piles_save.json"
	g.settings_path = "user://test_piles_settings.json"
	g.build()
	return g

func _free_ground(g: Node2D) -> void:
	g.free()
	for f in ["user://test_piles_save.json", "user://test_piles_settings.json"]:
		if FileAccess.file_exists(f): DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

## c1r2 (seed 7): its wolf packs. The hero waits on the room's spawn, out of every wolf's sight (wolves keep
## aggro + 12 px from it), and one idle step lets every monster know him.
func _c1r2(g: Node2D) -> Array:
	g.go_to("c1r2", "", false)
	g.hero.position = g.rooms.spawn("c1r2")
	for p in g.packs:
		p.calm = 0.0
		p.step_all(0.016, g.hero)
	return g.packs.filter(func(p): return p.kind == "wolf")

func _members(p: WolfPack, pile: int) -> Array:
	return p.wolves.filter(func(w): return w.pile == pile)

func _awake(g: Node2D) -> Array:
	var out := []
	for p in g.packs:
		for w in p.wolves:
			if w.state != "idle": out.append(w)
	return out

func _calm_all(g: Node2D) -> void:
	for p in g.packs:
		for w in p.wolves:
			w.state = "idle"
			w._t = 0.0

func _same(a: Array, b: Array) -> bool:
	if a.size() != b.size(): return false
	for x in a:
		if not b.has(x): return false
	return true

## Owner: "ปลุกแค่กองที่โดน/เห็น". Seeing the hero wakes only the seer's pile; a hit on a member of another pile
## of the same group wakes only that pile; a hit on a single (or a single seeing him) wakes it alone. Other
## piles and packs stay idle.
func test_seen_or_hit_wakes_only_that_pile():
	var g := _ground()
	var r := ""
	var wolves := _c1r2(g)
	var multi: Array = []           # [pack, pile] with 2+ members
	var single: Array = []
	for p in wolves:
		var sizes := {}
		for w in p.wolves: sizes[w.pile] = int(sizes.get(w.pile, 0)) + 1
		for pi in sizes:
			if sizes[pi] >= 2: multi.append([p, pi])
			else: single.append([p, pi])
	if multi.size() < 2 or single.is_empty(): r = "c1r2 seed 7: %d wolf piles and %d singles (want 2+ and 1+)" % [multi.size(), single.size()]
	if r == "" and not _awake(g).is_empty(): r = "monsters awake before anything happened: %d" % _awake(g).size()
	if r == "":
		var p: WolfPack = multi[0][0]
		var w0: Wolf = _members(p, multi[0][1])[0]
		w0._start_aggro()                  # what step() does when it sees the hero
		if not _same(_awake(g), _members(p, multi[0][1])): r = "seen: %d awake, want only its pile of %d" % [_awake(g).size(), _members(p, multi[0][1]).size()]
	if r == "":
		_calm_all(g)
		var other: Array = multi[1]
		for m in multi.slice(1):
			if m[0] == multi[0][0]: other = m     # prefer another pile of the same pack
		var w1: Wolf = _members(other[0], other[1])[0]
		w1.receive_hit(20.0, 1.0, w1.position + Vector2(30, 0))
		if not _same(_awake(g), _members(other[0], other[1])): r = "hit: %d awake, want only its pile of %d" % [_awake(g).size(), _members(other[0], other[1]).size()]
	if r == "":
		_calm_all(g)
		var s: Wolf = _members(single[0][0], single[0][1])[0]
		s.receive_hit(20.0, 1.0, s.position + Vector2(30, 0))
		if not _same(_awake(g), [s]): r = "hit single: %d awake" % _awake(g).size()
		_calm_all(g)
		s._start_aggro()
		if r == "" and not _same(_awake(g), [s]): r = "single saw the hero: %d awake" % _awake(g).size()
	_free_ground(g)
	return r

func _groups(g: Node2D, id: String) -> Array:
	return RoomLevels.groups(g.rooms.room(id).monsters, int(g.rooms.room_levels()[id]))

## A killed monster comes back after wolf.respawn on its own spawn point (the point MonsterPiles gave it), on
## the room's open ground, wherever it died.
func test_revived_monster_back_on_its_spawn_point():
	var g := _ground()
	var r := ""
	_c1r2(g)
	var room: Dictionary = g.rooms.pile_room("c1r2")
	var planned := []
	for p in g.piles_for("c1r2", _groups(g, "c1r2")):
		planned.append_array(p.points)
	var n := 0
	for p in g.packs:
		for w in p.wolves:
			if w.spawn_at == Vector2.INF:
				r = "a %s has no spawn point" % p.kind
				continue
			if not planned.has(w.spawn_at): r = "a %s spawn point %s is not one of the piles' points" % [p.kind, w.spawn_at]
			w.position = w.spawn_at + Vector2(37, -23)     # chased off before dying
			w.health.take_hit(999999, false)
			if w.is_alive(): r = "a %s did not die" % p.kind
			n += 1
	for p in g.packs: p.tick(Balance.num("wolf.respawn") + 0.1)
	for p in g.packs:
		for w in p.wolves:
			if r != "": break
			if not w.is_alive(): r = "a %s did not come back" % p.kind
			elif w.position != w.spawn_at: r = "a %s came back at %s, its spawn point is %s" % [p.kind, w.position, w.spawn_at]
			elif not MonsterPiles.is_open(room, w.position): r = "a %s came back off the open ground at %s" % [p.kind, w.position]
	if r == "" and n != planned.size(): r = "%d monsters for %d planned points" % [n, planned.size()]
	_free_ground(g)
	return r

## The lunge token and the "hero unreachable here" spot belong to a pile: two piles of one group may each
## lunge at the same time while a second monster of the same pile waits; one pile walled off from the hero
## does not stop another pile of the group from seeing him.
## Reviewer bug: the pile's lunge token held by a monster that was freed since; the next monster of the pile
## may lunge (no error on the freed instance).
func test_lunge_after_previous_lunger_freed():
	var g := _ground()
	var r := ""
	var p: WolfPack = null
	var a: Wolf = null
	var b: Wolf = null
	for q in _c1r2(g):
		for w in q.wolves:
			if a == null and _members(q, w.pile).size() >= 2:
				p = q
				a = w
				b = _members(q, w.pile)[1]
	if a == null: r = "no pile of 2+ in c1r2"
	if r == "":
		if not p.request_lunge(a): r = "first lunge refused"
		a.state = "lunge_warn"
		if r == "" and p.request_lunge(b): r = "a second monster of the pile lunged while the first lunges"
	if r == "":
		p.wolves.erase(a)
		a.free()
		var ok = p.request_lunge(b)
		if ok == null or not ok: r = "lunge refused after the previous lunger was freed (got %s)" % [ok]
		elif p.request_lunge(b) != true: r = "the new lunger lost its token"
	_free_ground(g)
	return r

func test_two_piles_of_one_group_each_lunge():
	var g := _ground()
	var r := ""
	var p: WolfPack = null
	for q in _c1r2(g):
		var piles := {}
		for w in q.wolves: piles[w.pile] = true
		if piles.size() >= 2 and p == null: p = q
	var a: Wolf = null
	var a2: Wolf = null
	var b: Wolf = null
	if p == null: r = "no wolf pack with two piles"
	else:
		for w in p.wolves:
			if a == null and _members(p, w.pile).size() >= 2:
				a = w
				a2 = _members(p, w.pile)[1]
		for w in p.wolves:
			if a != null and b == null and w.pile != a.pile: b = w
		if a == null or b == null: r = "no pile of 2+ beside another pile in one pack"
	if r == "":
		if not p.request_lunge(a): r = "pile %d: first lunge refused" % a.pile
		a.state = "lunge_warn"
		if r == "" and not p.request_lunge(b): r = "pile %d could not lunge while pile %d lunges" % [b.pile, a.pile]
		b.state = "lunge_warn"
		if r == "" and p.request_lunge(a2): r = "a second monster of pile %d lunged at the same time" % a.pile
		p.end_lunge(a)
		a.state = "chase"
		if r == "" and not p.request_lunge(a2): r = "pile %d: no lunge after the first one ended" % a.pile
	if r == "":
		a.state = "idle"
		b.state = "idle"
		p.mark_unreachable(a, g.hero.position)
		if a._wants_aggro(1.0): r = "walled-off pile %d still aggros there" % a.pile
		elif not b._wants_aggro(1.0): r = "pile %d did not aggro: another pile's unreachable spot stopped it" % b.pile
	_free_ground(g)
	return r
