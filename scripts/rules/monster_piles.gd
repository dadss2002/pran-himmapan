class_name MonsterPiles
extends RefCounted
## M4d addendum 4 (owner-approved 2026-11-08: "สุ่มกองแบบ 2-4 ตัว") and its follow-up ("มอนกองบ้างกระจายบ้าง"):
## about half of each kind's monsters in a room stand in piles of 2-4 (one kind per pile), the rest stand alone
## (singles) spread over the room's open ground. Bosses (a group with "boss": true) are never piled and stay at
## their home. Pure rules, no scene.
##
## How many stand in piles (piled_count): per kind in the room (all its non-boss groups together), n / 2 rounded
## with halves up, and at least 2 when n >= 2 (a pile is never smaller than 2): 1 -> 0 (a single), 2 -> 2 (one
## pile, no single), 3 -> 2 + 1 single, 4 -> 2 + 2, 5 -> 3 + 2, 6 -> 3 + 3, 10 -> 5 + 5, 12 -> 6 + 6. The piled
## part is split into piles of 2-4 (split) and each pile goes to the group of that kind with the most monsters
## left (a pile is one group's: the same pack, level and respawn); the rest of each group are singles.
## Follow-up 2 (owner "สุ่ม: บางครั้งกอง 2 บางครั้งเดี่ยว 2 ตัว"): a kind with exactly 2 monsters in a room is
## one pile of 2 or two singles, 50/50, drawn once per placement seed (pile seed + room id) and kind
## (pair_piled / piled_for); other counts keep piled_count.
##
## Rules for a placement (all checked, else the room falls back to the built homes of rooms.json):
## - every spawn point, and the pile's centre (its home), on the room's main open ground: a hero-sized body fits
##   there and it can be walked to from the room's spawn (the same open ground tools/painted_rooms.py uses);
## - pile centres at least PILE_GAP px apart (bosses' homes included);
## - every single at least SINGLE_GAP px from every other single and from every pile's centre and every
##   member spawn point of every pile (follow-up 2: "วัด 60 px จากทุกตัวในกอง"; bosses' points included), and
##   PILE_GAP px from a boss's home (as the piles: a boss stands apart);
##   each single takes the farthest from everyone already placed of SINGLE_CANDIDATES fitting random spots,
##   so singles spread out instead of bunching;
## - every spawn point and centre keeps the arrival rules: kinds that attack first (wolf, aggressive, ambush)
##   aggro + ARRIVAL_EXTRA px from every arrival (each exit's arrival and the room's own spawn), other kinds
##   PASSIVE_ARRIVAL px (painted_rooms.py's hard_off); in a near_arrival_ok room (x1, x2) NEAR_ARRIVAL_MIN px;
## - inside a pile the spawn points are at least 2 x body width apart centre to centre (pile_radius).
## The seed is the session's pile seed combined with the room id (room_seed): the same session shows the same
## piles each time the room is entered; Task 4's re-roll passes a new pile seed.

const MIN_PILE := 2              # ⚙ addendum 4
const MAX_PILE := 4              # ⚙ addendum 4
const PILE_GAP := 80.0           # ⚙ addendum 4: pile centres at least this far apart
const SINGLE_GAP := 60.0         # ⚙ addendum 4 follow-ups: a single this far from every single, pile centre and pile member
const NEAR_ARRIVAL_MIN := 48.0   # addenda 2-3 (x1, x2)
const ARRIVAL_EXTRA := 12.0      # aggro + 12 (painted_rooms.py hard_off for kinds that attack first)
const PASSIVE_ARRIVAL := 60.0    # painted_rooms.py hard_off for kinds that do not attack first
const TRIES := 80                # placements tried before falling back to the built homes
const SAMPLES := 400             # random open cells tried per pile in one placement
const RADIUS_SLACK := 0.5        # px added to the smallest ring radius (float safety)
const PACK_CANDIDATES := 12      # packed tries: the closest-to-the-others of this many fitting spots
const SINGLE_CANDIDATES := 16    # a single takes the farthest-from-the-others of this many fitting spots
const PAIR_PILE_CHANCE := 0.5    # ⚙ follow-up 2: a kind of exactly 2 stands as one pile of 2 (else two singles)
const SETTLE_TRIES := 4          # settle runs (each from a new random start) before falling back
const SETTLE_MOVES := 20000      # nudges per settle run
const SETTLE_STEP := 10.0        # px: a nudge's spread
const SETTLE_TURN := 0.4         # rad: a pile's turn spread per nudge
const SETTLE_JUMP := 0.1         # share of nudges that jump to a random spot of its ground instead
const SETTLE_HEAT := 3.0         # px of added overlap a nudge may still be kept with at the start (cools to 0)
const SPLIT_TRIES := 8           # random splits of a kind's piled part tried before the smallest-piles split

## Pile sizes for a group of `count`: each 2-4, summing to count; 1 stays [1] (0 gives []).
## Each next size is drawn evenly from the sizes that leave 0 or at least 2 behind.
static func split(count: int, rng: RandomNumberGenerator) -> Array[int]:
	var out: Array[int] = []
	if count <= 0: return out
	if count < MIN_PILE:
		out.append(count)
		return out
	var left := count
	while left > 0:
		var ok: Array[int] = []
		for s in range(MIN_PILE, MAX_PILE + 1):
			if s == left or left - s >= MIN_PILE: ok.append(s)
		var s: int = ok[rng.randi_range(0, ok.size() - 1)]
		out.append(s)
		left -= s
	return out

## How many of a kind's n monsters (in one room) stand in piles: n / 2, halves rounded up, at least 2 when
## n >= 2 (a pile is never smaller than 2); the other n - piled_count(n) are singles.
static func piled_count(n: int) -> int:
	if n < MIN_PILE: return 0
	return maxi(MIN_PILE, ceili(n / 2.0))

## Follow-up 2: whether a kind with exactly 2 monsters in a room stands as one pile of 2 (true) or as two
## singles, PAIR_PILE_CHANCE, from the placement seed (room_seed: pile seed + room id) and the kind; the same
## seed always gives the same answer, at every placement try.
static func pair_piled(seed: int, kind: String) -> bool:
	var r := RandomNumberGenerator.new()
	r.seed = ("%d:%s:pair" % [seed, kind]).hash()
	return r.randf() < PAIR_PILE_CHANCE

## How many of a kind's n monsters stand in piles in a placement with this seed: piled_count(n), except a kind
## of exactly 2, which is 2 (one pile) or 0 (two singles) by pair_piled.
static func piled_for(n: int, seed: int, kind: String) -> int:
	if n == MIN_PILE: return MIN_PILE if pair_piled(seed, kind) else 0
	return piled_count(n)

## The placement seed for one room: the session's pile seed combined with the room id.
static func room_seed(pile_seed: int, room_id: String) -> int:
	return ("%d:%s" % [pile_seed, room_id]).hash()

static var _widths := {}

## A kind's body width (px): its collision box's width at the monster scale (Wolf.size_scale()).
static func body_width(kind: String) -> float:
	if _widths.has(kind): return _widths[kind]
	var scene: PackedScene = load("res://scenes/wolf.tscn" if kind == "wolf" else "res://scenes/monster.tscn")
	var n: Node = scene.instantiate()
	var feet: CollisionShape2D = n.get_node("Feet")
	var w: float = (feet.shape as RectangleShape2D).size.x * Wolf.size_scale()
	n.free()
	_widths[kind] = w
	return w

## Ring radius for a pile of n so neighbouring spawn points are at least 2 x body width apart (0 for n = 1).
static func pile_radius(kind: String, n: int) -> float:
	if n <= 1: return 0.0
	return 2.0 * body_width(kind) / (2.0 * sin(PI / n)) + RADIUS_SLACK

static func ring_points(centre: Vector2, n: int, radius: float, angle: float) -> Array:
	var out := []
	if n <= 1:
		out.append(centre)
		return out
	for i in n:
		out.append(centre + Vector2(radius, 0).rotated(angle + TAU * i / n))
	return out

## Whether a kind attacks the hero on sight (wolf, aggressive, ambush) and its aggro range.
static func attacks_first(kind: String) -> bool:
	if kind == "wolf": return true
	var t := String(Balance._lookup("monsters.%s.temper" % kind))
	return t == "aggressive" or t == "ambush"

static func aggro_of(kind: String) -> float:
	var p := "monsters.%s.aggro" % kind
	return Balance.num(p) if kind != "wolf" and Balance.has(p) else Balance.num("wolf.aggro")

## How far every spawn point of `kind` keeps from every arrival in a room (near_ok: x1, x2).
static func arrival_floor(kind: String, near_ok: bool) -> float:
	if near_ok: return NEAR_ARRIVAL_MIN
	return aggro_of(kind) + ARRIVAL_EXTRA if attacks_first(kind) else PASSIVE_ARRIVAL

## Room data for place(): the PaintedLayout, the arrivals (every exit's arrival + the room's spawn), the
## main open ground (flood from the room's spawn over cells a hero-sized body fits in). RoomSet.pile_room
## builds it (arrivals from RoomSet.arrival_on) and keeps it.
static func prepare(d: Dictionary, l: PaintedLayout, arrivals: Array) -> Dictionary:
	var open := PackedByteArray()
	open.resize(l.cols * l.rows)
	var cells := PackedVector2Array()
	var start := Vector2i(int(l.hero_spawn.x) / l.cell, int(l.hero_spawn.y) / l.cell)
	if l.roomy(start.x, start.y):
		var todo: Array[Vector2i] = [start]
		open[start.y * l.cols + start.x] = 1
		while not todo.is_empty():
			var c: Vector2i = todo.pop_back()
			cells.append((Vector2(c) + Vector2(0.5, 0.5)) * l.cell)
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + o
				if n.x < 0 or n.y < 0 or n.x >= l.cols or n.y >= l.rows: continue
				if open[n.y * l.cols + n.x] == 1 or not l.roomy(n.x, n.y): continue
				open[n.y * l.cols + n.x] = 1
				todo.append(n)
	cells.sort()        # flood order depends on the stack; sorted, a seed always picks the same cell
	return {"layout": l, "arrivals": arrivals, "open": open, "cells": cells,
		"near_arrival_ok": bool(d.get("near_arrival_ok", false))}

## Whether p is on the room's main open ground.
static func is_open(room: Dictionary, p: Vector2) -> bool:
	var l: PaintedLayout = room.layout
	if p.x < 0 or p.y < 0: return false
	var cx := int(p.x) / l.cell
	var cy := int(p.y) / l.cell
	if cx >= l.cols or cy >= l.rows: return false
	return room.open[cy * l.cols + cx] == 1

## The piles for a room's groups (each group: {kind, level, count, at, ...}; e.g. RoomLevels.groups()).
## Returns [{kind, level, count, home: Vector2, points: Array[Vector2], group: index into groups, boss: bool,
## single: bool, fallback: bool}], in group order (each group's piles, then its singles). A single is a pile of
## count 1 (single: true): it wakes alone and respawns on its own spot. `room` comes from prepare()
## (RoomSet.pile_room). When no placement passes after TRIES tries, every group keeps its built home
## (rooms.json "at", spawn ring PaintedLayout.ring) as one pile and fallback is true. Each try draws new pile
## sizes; the later half of the tries packs the piles closer together (still PILE_GAP apart) so rooms with
## little room still fit. When no try fits, up to SETTLE_TRIES settle runs (_settle) come before the fallback
## (follow-up 2: c1r2 and e0's crowded sets need them since singles keep 60 px from every pile member).
static func place(room: Dictionary, groups: Array, seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var near_ok := bool(room.get("near_arrival_ok", false))
	var cells: PackedVector2Array = room.get("cells", PackedVector2Array())
	for t in TRIES:
		if cells.is_empty(): break
		# a new random split every try: a room with little open ground far from its arrivals (c1r2's wolves)
		# fits fewer, bigger piles; sizes always stay 2-4
		var piles := _split_groups(groups, rng, near_ok, seed)
		# the second half of the tries packs each pile next to the ones already placed (still >= PILE_GAP),
		# so tight rooms fit; the first half spreads them purely at random
		var packed := t >= TRIES / 2
		if _place_all(room, piles, rng, cells, packed): return _clean(piles)
	# no try fitted: settle (a new split each run) before the fallback
	for t in SETTLE_TRIES:
		if cells.is_empty(): break
		var piles := _split_groups(groups, rng, near_ok, seed)
		if _settle(room, piles, rng, cells): return _clean(piles)
	# fallback: the built homes, one pile per group, the old spawn ring
	var out: Array = []
	for gi in groups.size():
		var g: Dictionary = groups[gi]
		var home := Vector2(g.at[0], g.at[1])
		var boss := bool(g.get("boss", false))
		out.append({"kind": String(g.get("kind", "wolf")), "level": int(g.level), "count": int(g.count), "group": gi,
			"boss": boss, "single": not boss and int(g.count) == 1, "home": home, "fallback": true,
			"points": [home] if boss and int(g.count) == 1 else PaintedLayout.ring(home, int(g.count))})
	return out

## Pile sizes per group: for each kind (its non-boss groups together) piled_for(n, seed, kind) monsters split
## into piles of 2-4, each pile given to the group of that kind with the most monsters still unpiled (ties: the
## earlier group). Returns {group index: Array[int] pile sizes}; a boss group is one pile of its count. If a
## pile fits no group (cannot happen with today's rooms; e.g. four groups of 2 drawn [4]), the split is drawn
## again, up to SPLIT_TRIES draws, then the smallest piles (2s and one 3 when odd) are tried; only when none of
## these fits (no assignment exists, e.g. three groups of 2 with 3 to pile) is each group of the kind split on
## its own instead. `seed` is the placement seed (pair_piled).
static func pile_sizes(groups: Array, rng: RandomNumberGenerator, seed: int) -> Dictionary:
	var out := {}
	var by_kind := {}
	for gi in groups.size():
		var g: Dictionary = groups[gi]
		out[gi] = [] as Array[int]
		if bool(g.get("boss", false)):
			out[gi].append(int(g.count))
			continue
		var k := String(g.get("kind", "wolf"))
		if not by_kind.has(k): by_kind[k] = []
		by_kind[k].append(gi)
	for k in by_kind:
		var gis: Array = by_kind[k]
		var n := 0
		for gi in gis: n += int(groups[gi].count)
		var want := piled_for(n, seed, k)
		var got = _assign(groups, gis, split(want, rng))
		for t in range(1, SPLIT_TRIES):
			if got != null: break
			got = _assign(groups, gis, split(want, rng))
		if got == null: got = _assign(groups, gis, _smallest_split(want))
		if got == null:
			for gi in gis:
				out[gi] = split(piled_count(int(groups[gi].count)), rng)
			continue
		for gi in gis: out[gi].append_array(got[gi])
	return out

## Each pile size to the group (of gis) with the most monsters left (ties: the earlier group); null when a
## pile fits no group.
static func _assign(groups: Array, gis: Array, sizes: Array[int]) -> Variant:
	var left := {}
	var got := {}
	for gi in gis:
		left[gi] = int(groups[gi].count)
		got[gi] = [] as Array[int]
	for s in sizes:
		var best := -1
		for gi in gis:
			if int(left[gi]) >= s and (best < 0 or int(left[gi]) > int(left[best])): best = gi
		if best < 0: return null
		got[best].append(s)
		left[best] = int(left[best]) - s
	return got

## The split into the smallest piles: a 3 first when n is odd, then 2s (n < 2: as split()).
static func _smallest_split(n: int) -> Array[int]:
	var out: Array[int] = []
	if n <= 0: return out
	if n < MIN_PILE:
		out.append(n)
		return out
	if n % 2 == 1: out.append(3)
	for i in (n - (3 if n % 2 == 1 else 0)) / 2: out.append(2)
	return out

## Piles and singles for every group (random sizes; a boss group stays whole), in group order: each group's
## piles, then its singles (piles of 1).
static func _split_groups(groups: Array, rng: RandomNumberGenerator, near_ok: bool, seed: int) -> Array:
	var piles: Array = []
	var sizes := pile_sizes(groups, rng, seed)
	for gi in groups.size():
		var g: Dictionary = groups[gi]
		var kind := String(g.get("kind", "wolf"))
		var boss := bool(g.get("boss", false))
		var all: Array[int] = []
		all.append_array(sizes[gi])
		var used := 0
		for s in sizes[gi]: used += s
		for i in int(g.count) - used: all.append(1)
		for s in all:
			piles.append({"kind": kind, "level": int(g.level), "count": s, "group": gi, "boss": boss,
				"single": not boss and s == 1, "home": Vector2(g.at[0], g.at[1]), "points": [], "fallback": false,
				"floor": arrival_floor(kind, near_ok), "radius": pile_radius(kind, s)})
	return piles

## One placement try: bosses at home first, then the hardest piles (farthest from the arrivals, then the
## biggest), then the singles (hardest first), each the farthest from everyone already placed of
## SINGLE_CANDIDATES fitting spots. A single keeps SINGLE_GAP from every pile centre and every pile member's
## spawn point, and a pile's centre and members keep SINGLE_GAP from every single (a single of a kind kept
## far from the arrivals may be placed before a pile). false when a pile or single finds no spot in SAMPLES
## random open cells.
static func _place_all(room: Dictionary, piles: Array, rng: RandomNumberGenerator, cells: PackedVector2Array, packed: bool) -> bool:
	var order: Array = range(piles.size())
	order.sort_custom(func(a, b):
		var pa: Dictionary = piles[a]
		var pb: Dictionary = piles[b]
		if pa.boss != pb.boss: return pa.boss
		if pa.floor != pb.floor: return pa.floor > pb.floor
		if pa.single != pb.single: return pb.single
		if pa.count != pb.count: return pa.count > pb.count
		return a < b)
	var centres: Array = []          # pile centres (bosses included) so far
	var singles: Array = []          # singles so far
	var bosses: Array = []           # boss homes: every pile and single keeps PILE_GAP from them
	var members: Array = []          # every spawn point of the piles so far (bosses included)
	for i in order:
		var p: Dictionary = piles[i]
		if p.boss:
			p.points = ring_points(p.home, int(p.count), float(p.radius), 0.0)
			centres.append(p.home)
			bosses.append(p.home)
			members.append_array(p.points)
			continue
		var best := []                   # [centre, points, score]
		var found := 0
		var pool := _pool(room, cells, float(p.floor))
		if pool.is_empty(): return false
		for s in SAMPLES:
			var c: Vector2 = pool[rng.randi_range(0, pool.size() - 1)]
			var near := INF              # to the nearest pile centre
			for q in centres: near = minf(near, c.distance_to(q))
			var near1 := INF             # to the nearest single
			for q in singles: near1 = minf(near1, c.distance_to(q))
			var near_boss := INF
			for q in bosses: near_boss = minf(near_boss, c.distance_to(q))
			if near_boss < PILE_GAP: continue
			var near_m := INF            # to the nearest pile member's spawn point
			if p.single:
				for q in members: near_m = minf(near_m, c.distance_to(q))
				if near < SINGLE_GAP or near1 < SINGLE_GAP or near_m < SINGLE_GAP: continue
			elif near < PILE_GAP or near1 < SINGLE_GAP: continue
			var pts := ring_points(c, int(p.count), float(p.radius), rng.randf() * TAU)
			if not p.single and _near_any(pts, singles, SINGLE_GAP): continue
			if not _fits(room, c, pts, float(p.floor)): continue
			found += 1
			var score := minf(minf(near, near1), near_m)   # to the nearest pile centre, member or single so far
			if packed:
				# packed tries: the closest spot to the others (still apart by the gaps), the first one on the
				# far edge of its ground (farthest from the middle of the pool), so a tight room fits them all
				if score == INF: score = 1e6 - c.distance_to(_pool_middle(room, float(p.floor)))
				if best.is_empty() or score < best[2]: best = [c, pts, score]
				if found >= PACK_CANDIDATES: break
			elif p.single:
				# spread tries: a single takes the spot farthest from every pile centre and single placed so far
				if best.is_empty() or score > best[2]: best = [c, pts, score]
				if found >= SINGLE_CANDIDATES: break
			else:
				best = [c, pts, score]       # spread tries: a pile takes the first fitting random spot
				break
		if best.is_empty(): return false
		p.home = best[0]
		p.points = best[1]
		if p.single: singles.append(best[0])
		else:
			centres.append(best[0])
			members.append_array(best[1])
	return true

## Settle (follow-up 2: c1r2's wolves need 6 singles 60 px from every pile member in the small ground far from
## its arrivals, which the one-by-one tries rarely fit): every pile and single starts on a random fitting spot
## of its own ground, then one at a time is nudged (moved SETTLE_STEP px at random, a pile also turned)
## SETTLE_MOVES times. A nudge that leaves the open ground or the arrival floor is refused; one that does not
## add to the room's total gap shortfall (_short) is kept, one that adds a little sometimes early on (cooling
## to never). true once nothing is short: every rule of a placement holds. Bosses stay at home.
static func _settle(room: Dictionary, piles: Array, rng: RandomNumberGenerator, cells: PackedVector2Array) -> bool:
	var movers: Array = []
	for i in piles.size():
		var p: Dictionary = piles[i]
		if p.boss:
			p.points = ring_points(p.home, int(p.count), float(p.radius), 0.0)
			continue
		var pool := _pool(room, cells, float(p.floor))
		if pool.is_empty(): return false
		var ok := false
		for k in SAMPLES:
			var c: Vector2 = pool[rng.randi_range(0, pool.size() - 1)]
			var a := rng.randf() * TAU
			var pts := ring_points(c, int(p.count), float(p.radius), a)
			if not _fits(room, c, pts, float(p.floor)): continue
			p.home = c
			p.points = pts
			p.angle = a
			ok = true
			break
		if not ok: return false
		movers.append(i)
	if movers.is_empty(): return true
	var total := 0.0
	for i in piles.size(): total += _short(piles, i)
	total *= 0.5                        # every pair counted from both sides
	for m in SETTLE_MOVES:
		if total <= 0.0: break
		var i: int = movers[rng.randi_range(0, movers.size() - 1)]
		var p: Dictionary = piles[i]
		var c: Vector2 = p.home + Vector2(rng.randfn(0.0, SETTLE_STEP), rng.randfn(0.0, SETTLE_STEP))
		var a: float = p.angle + (0.0 if p.single else rng.randfn(0.0, SETTLE_TURN))
		if rng.randf() < SETTLE_JUMP:
			var pool := _pool(room, cells, float(p.floor))
			c = pool[rng.randi_range(0, pool.size() - 1)]
			a = rng.randf() * TAU
		var pts := ring_points(c, int(p.count), float(p.radius), a)
		if not _fits(room, c, pts, float(p.floor)): continue
		var before := _short(piles, i)
		var keep: Array = [p.home, p.points, p.angle]
		p.home = c
		p.points = pts
		p.angle = a
		var after := _short(piles, i)
		var heat := SETTLE_HEAT * (1.0 - float(m) / SETTLE_MOVES)
		if after <= before or (heat > 0.0 and rng.randf() < exp((before - after) / heat)):
			total += after - before
		else:
			p.home = keep[0]
			p.points = keep[1]
			p.angle = keep[2]
	# exact recount: nothing short means every gap holds (ground and arrivals were checked on every move)
	for i in piles.size():
		if _short(piles, i) > 0.0: return false
	return true

## How far pile i falls short of its gaps to every other pile and single, summed (0: all gaps held): pile
## centres PILE_GAP apart; a single SINGLE_GAP from every single and every pile's centre and member; every
## pile and single PILE_GAP from a boss's home.
static func _short(piles: Array, i: int) -> float:
	var p: Dictionary = piles[i]
	var out := 0.0
	for j in piles.size():
		if j == i: continue
		var q: Dictionary = piles[j]
		if p.single and q.single:
			out += maxf(0.0, SINGLE_GAP - p.home.distance_to(q.home))
			continue
		if p.boss or q.boss: out += maxf(0.0, PILE_GAP - p.home.distance_to(q.home))
		if not p.single and not q.single:
			if not (p.boss or q.boss): out += maxf(0.0, PILE_GAP - p.home.distance_to(q.home))
			continue
		var one: Dictionary = p if p.single else q
		var pile: Dictionary = q if p.single else p
		out += maxf(0.0, SINGLE_GAP - one.home.distance_to(pile.home))
		for m in pile.points:
			out += maxf(0.0, SINGLE_GAP - one.home.distance_to(m))
	return out

## Whether any of pts is closer than gap to any of others.
static func _near_any(pts: Array, others: Array, gap: float) -> bool:
	for a in pts:
		for b in others:
			if (a as Vector2).distance_to(b) < gap: return true
	return false

## The open cells whose centre keeps `floor` px from every arrival (worked out once per room and floor):
## spots are drawn from these, so a kind kept far from the arrivals does not waste its samples.
static func _pool(room: Dictionary, cells: PackedVector2Array, floor: float) -> PackedVector2Array:
	var key := "pool_%d" % int(floor * 10.0)
	if room.has(key): return room[key]
	var arrivals: Array = room.get("arrivals", [])
	var out := PackedVector2Array()
	for c in cells:
		var ok := true
		for a in arrivals:
			if c.distance_to(a) < floor:
				ok = false
				break
		if ok: out.append(c)
	room[key] = out
	var mid := Vector2.ZERO
	for c in out: mid += c
	room["mid_%d" % int(floor * 10.0)] = mid / maxf(1.0, out.size())
	return out

static func _pool_middle(room: Dictionary, floor: float) -> Vector2:
	return room.get("mid_%d" % int(floor * 10.0), Vector2.ZERO)

static func _fits(room: Dictionary, centre: Vector2, pts: Array, floor: float) -> bool:
	var arrivals: Array = room.get("arrivals", [])
	for p in [centre] + pts:
		if not is_open(room, p): return false
		for a in arrivals:
			if (p as Vector2).distance_to(a) < floor: return false
	return true

static func _clean(piles: Array) -> Array:
	var out: Array = []
	for p in piles:
		var q: Dictionary = p.duplicate()
		q.erase("floor")
		q.erase("radius")
		q.erase("angle")
		out.append(q)
	return out         # already in group order (piles are made group by group)

## true when the room fell back to the built homes.
static func fell_back(piles: Array) -> bool:
	return not piles.is_empty() and bool(piles[0].get("fallback", false))
