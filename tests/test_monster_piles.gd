extends RefCounted
## M4d addendum 4 (docs/superpowers/specs/2026-11-08-m4d-random-layout.md): monster groups split into piles of
## 2-4 (MonsterPiles.split), piles spread at random over open ground (MonsterPiles.place): same seed same piles,
## pile centres >= 80 px apart, in-pile spawn points >= 2 x body width apart, arrival rules kept, bosses never
## piled, per-room kinds / counts / levels unchanged, and how many rooms fall back over 200 seeds.

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

## All checks for one room's placement; "" when fine.
func _check(rooms: RoomSet, id: String, groups: Array, piles: Array) -> String:
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
	var arrivals: Array = room.arrivals
	for i in piles.size():
		var p: Dictionary = piles[i]
		if not p.boss and (int(p.count) < 1 or int(p.count) > 4 or (int(p.count) == 1 and int(groups[int(p.group)].count) != 1)):
			return "%s pile of %d" % [id, p.count]
		var floor := MonsterPiles.arrival_floor(String(p.kind), near_ok)
		if near_ok and floor != 48.0: return "near_arrival_ok floor %s" % floor
		if not near_ok and MonsterPiles.attacks_first(String(p.kind)) and floor != MonsterPiles.aggro_of(String(p.kind)) + 12.0: return "aggro floor %s" % floor
		for q in [p.home] + p.points:
			if not MonsterPiles.is_open(room, q): return "%s %s pile at %s: point %s not on open ground" % [id, p.kind, p.home, q]
			for a in arrivals:
				if (q as Vector2).distance_to(a) < floor: return "%s %s point %s is %.1f px from arrival %s (min %d)" % [id, p.kind, q, (q as Vector2).distance_to(a), a, floor]
		var bw := MonsterPiles.body_width(String(p.kind))
		for a in p.points.size():
			for b in range(a + 1, p.points.size()):
				var d: float = p.points[a].distance_to(p.points[b])
				if d < 2.0 * bw - 0.001: return "%s %s pile: points %.1f px apart (min 2 x %.1f)" % [id, p.kind, d, bw]
		for j in range(i + 1, piles.size()):
			var d2: float = p.home.distance_to(piles[j].home)
			if d2 < 80.0: return "%s pile centres %s and %s only %.1f px apart" % [id, p.home, piles[j].home, d2]
	return ""

func test_piles_follow_the_rules_every_room():
	var rooms := RoomSet.open()
	for s in [1, 7, 42]:
		for id in rooms.ids():
			for groups in _lists(rooms, id):
				var e := _check(rooms, id, groups, _piles(rooms, id, groups, s))
				if e != "": return "seed %d: %s" % [s, e]
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

## 200 seeds over every room (e0's four sets each): how many placements fall back to the built homes.
func test_200_seeds_fallbacks():
	var rooms := RoomSet.open()
	var falls := {}
	var bad := ""
	var t0 := Time.get_ticks_msec()
	for s in 200:
		for id in rooms.ids():
			var lists := _lists(rooms, id)
			for li in lists.size():
				var piles := _piles(rooms, id, lists[li], s)
				if MonsterPiles.fell_back(piles):
					var key: String = id if lists.size() == 1 else "%s set %d" % [id, li]
					falls[key] = int(falls.get(key, 0)) + 1
				elif bad == "" and s % 20 == 0:
					bad = _check(rooms, id, lists[li], piles)
	print("    piles: 200 seeds, fallbacks %s (%d ms)" % [falls if not falls.is_empty() else "none", Time.get_ticks_msec() - t0])
	if bad != "": return bad
	return "" if falls.is_empty() else "rooms fell back to built homes: %s" % falls

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
	var want := MonsterPiles.place(g.rooms.pile_room(id), RoomLevels.groups(src, int(g.rooms.room_levels()[id])), MonsterPiles.room_seed(g.pile_seed, id))
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
