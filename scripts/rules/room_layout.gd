class_name RoomLayout
extends RefCounted
## M4d (spec docs/superpowers/specs/2026-11-08-m4d-random-layout.md): a random Diablo-style room layout,
## made fresh every game session from a seed. Pure rules, no scene.
##
## rooms: {id: Array of exit sides} or {id: {"exits": Array, ...}} (RoomSet.exit_table()).
## A layout: {"pos": {id: Vector2i}, "links": [[id_a, side_a, id_b, side_b], ...], "fallback": bool}.
##
## 1. START (c1r1) sits in the middle of a GRID x GRID grid.
## 2. Grow: pick an open exit at random, then at random (weighted by exits², so rooms with more exits come
##    early) an unused forest room that has the matching exit and agrees with every side it touches
##    (exit meets exit, wall meets wall). Every forest room is used once.
## 3. BOSS (e0) goes last, on the open east-facing exit farthest (in rooms walked) from START.
## 4. An exit left without a neighbour is a dead end: no link, so no warp.
## 5. check(): all rooms placed and reachable from START, every touching pair agrees, >= MIN_LOOPS loops,
##    and BOSS no closer to START than any other room (owner: "ลาน e0 อยู่ไกลสุดเสมอ"; without this, about 40 %
##    of layouts had a forest room beyond e0, a few even put e0 next to c1r1).
##    Up to TRIES attempts (one seeded RNG), then the fixed M4b layout (FALLBACK_LINKS, fallback = true).

const GRID := 7
const START := "c1r1"
const BOSS := "e0"
const TRIES := 200            # approved (spec step 6)
const MIN_LOOPS := 1          # approved (spec step 6)
const SIDES := ["north", "east", "south", "west"]
const DIRS := {"north": Vector2i(0, -1), "south": Vector2i(0, 1), "east": Vector2i(1, 0), "west": Vector2i(-1, 0)}
const OPPOSITE := {"north": "south", "south": "north", "east": "west", "west": "east"}

## The fixed M4b layout (was rooms_src.json "links"), used only when no random layout passes check().
const FALLBACK_LINKS := [["c0r0", "south", "c0r1", "north"], ["c0r1", "south", "c0r2", "north"],
	["c0r2", "south", "c0r3", "north"], ["c0r1", "east", "c1r1", "west"], ["c1r0", "south", "c1r1", "north"],
	["c1r1", "east", "c2r1", "west"], ["c2r0", "south", "c2r1", "north"], ["c2r1", "south", "c2r2", "north"],
	["c0r2", "east", "c1r2", "west"], ["c1r2", "south", "c1r3", "north"], ["c1r3", "east", "c2r3", "west"],
	["c2r0", "east", "e0", "west"]]
## Its grid places (the M4b map: cXrY at column X, row Y around c1r1 in the middle; e0 east of c2r0).
const FALLBACK_POS := {"c0r0": Vector2i(2, 2), "c1r0": Vector2i(3, 2), "c2r0": Vector2i(4, 2), "e0": Vector2i(5, 2),
	"c0r1": Vector2i(2, 3), "c1r1": Vector2i(3, 3), "c2r1": Vector2i(4, 3),
	"c0r2": Vector2i(2, 4), "c1r2": Vector2i(3, 4), "c2r2": Vector2i(4, 4),
	"c0r3": Vector2i(2, 5), "c1r3": Vector2i(3, 5), "c2r3": Vector2i(4, 5)}

static func middle() -> Vector2i:
	return Vector2i(GRID / 2, GRID / 2)

static func exits_of(rooms: Dictionary, id: String) -> Array:
	var v = rooms.get(id, [])
	if v is Dictionary: return v.get("exits", [])
	return v

static func generate(seed: int, rooms: Dictionary, tries := TRIES) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	if rooms.has(START) and rooms.has(BOSS):
		for t in tries:
			var l := _attempt(rng, rooms)
			if not l.is_empty() and check(l, rooms).is_empty(): return l
	return fallback(rooms)

## The fixed M4b layout: FALLBACK_LINKS between the rooms that exist (the M4d rooms x1..x3 are left out).
static func fallback(rooms: Dictionary) -> Dictionary:
	var pos := {}
	var links: Array = []
	for k in FALLBACK_LINKS:
		if not rooms.has(k[0]) or not rooms.has(k[2]): continue
		links.append(k.duplicate())
		pos[k[0]] = FALLBACK_POS[k[0]]
		pos[k[2]] = FALLBACK_POS[k[2]]
	pos[START] = FALLBACK_POS[START]
	return {"pos": pos, "links": links, "fallback": true}

static func _attempt(rng: RandomNumberGenerator, rooms: Dictionary) -> Dictionary:
	var pos := {START: middle()}
	var at := {middle(): START}
	var left: Array = []
	for id in rooms:
		if id != START and id != BOSS: left.append(String(id))
	left.sort()
	while not left.is_empty():
		var opens := _shuffled(rng, open_exits(pos, at, rooms))
		var placed := false
		for o in opens:
			var t: Vector2i = o[0] + DIRS[o[1]]
			var cands: Array = []
			var total := 0
			for id in left:
				var ex := exits_of(rooms, id)
				if OPPOSITE[o[1]] in ex and fits(t, ex, at, rooms):
					cands.append(id)
					total += ex.size() * ex.size()
			if cands.is_empty(): continue
			var r := rng.randi_range(1, total)
			var pick: String = cands[-1]
			for id in cands:
				var n := exits_of(rooms, id).size()
				r -= n * n
				if r <= 0:
					pick = id
					break
			pos[pick] = t
			at[t] = pick
			left.erase(pick)
			placed = true
			break
		if not placed: return {}
	var spots := boss_spots(pos, at, rooms)
	if spots.is_empty(): return {}
	var far := 0
	for s in spots: far = maxi(far, int(s[1]))
	var best: Array = []
	for s in spots:
		if int(s[1]) == far: best.append(s[0])
	var cell: Vector2i = best[rng.randi_range(0, best.size() - 1)]
	pos[BOSS] = cell
	at[cell] = BOSS
	return {"pos": pos, "links": links_of(pos, rooms), "fallback": false}

## Where BOSS could go now: [[cell, rooms walked from START], ...] for every open east-facing exit whose
## cell BOSS fits (its west exit meets that exit; walls everywhere else).
static func boss_spots(pos: Dictionary, at: Dictionary, rooms: Dictionary) -> Array:
	var out: Array = []
	var dist := distances(pos, links_of(pos, rooms))
	var boss_ex := exits_of(rooms, BOSS)
	if not ("west" in boss_ex): return out
	for o in open_exits(pos, at, rooms):
		if o[1] != "east": continue
		var t: Vector2i = o[0] + DIRS.east
		if fits(t, boss_ex, at, rooms): out.append([t, int(dist.get(at[o[0]], 0)) + 1])
	return out

## Exits of placed rooms facing an empty cell inside the grid: [[cell, side], ...], in a fixed order.
static func open_exits(pos: Dictionary, at: Dictionary, rooms: Dictionary) -> Array:
	var out: Array = []
	var ids: Array = pos.keys()
	ids.sort()
	for id in ids:
		for s in SIDES:
			if not (s in exits_of(rooms, id)): continue
			var t: Vector2i = pos[id] + DIRS[s]
			if _inside(t) and not at.has(t): out.append([pos[id], s])
	return out

## A room with exits `ex` can go in cell t: inside the grid, empty, and every placed neighbour agrees
## (exit meets exit, wall meets wall).
static func fits(t: Vector2i, ex: Array, at: Dictionary, rooms: Dictionary) -> bool:
	if not _inside(t) or at.has(t): return false
	for s in SIDES:
		var n: Vector2i = t + DIRS[s]
		if not at.has(n): continue
		if (s in ex) != (OPPOSITE[s] in exits_of(rooms, at[n])): return false
	return true

## Every pair of neighbouring rooms whose exits face each other, once: [west/north room, side, other, side].
static func links_of(pos: Dictionary, rooms: Dictionary) -> Array:
	var at := {}
	for id in pos: at[pos[id]] = id
	var ids: Array = pos.keys()
	ids.sort()
	var out: Array = []
	for id in ids:
		for s in ["east", "south"]:
			var n: Vector2i = pos[id] + DIRS[s]
			if at.has(n) and s in exits_of(rooms, id) and OPPOSITE[s] in exits_of(rooms, at[n]):
				out.append([id, s, at[n], OPPOSITE[s]])
	return out

## Rooms walked from START over the links: {id: steps}; unreachable rooms are missing.
static func distances(pos: Dictionary, links: Array) -> Dictionary:
	var nb := {}
	for k in links:
		nb[k[0]] = nb.get(k[0], []) + [k[2]]
		nb[k[2]] = nb.get(k[2], []) + [k[0]]
	var dist := {}
	if not pos.has(START): return dist
	dist[START] = 0
	var todo := [START]
	while not todo.is_empty():
		var id: String = todo.pop_front()
		for n in nb.get(id, []):
			if not dist.has(n):
				dist[n] = dist[id] + 1
				todo.append(n)
	return dist

## Loops = links beyond a tree (links - rooms + 1).
static func loops(layout: Dictionary) -> int:
	return layout.links.size() - layout.pos.size() + 1

## Exits of placed rooms with no link (dead ends): [[id, side], ...].
static func dead_ends(layout: Dictionary, rooms: Dictionary) -> Array:
	var linked := {}
	for k in layout.links:
		linked[k[0] + ":" + k[1]] = true
		linked[k[2] + ":" + k[3]] = true
	var out: Array = []
	var ids: Array = layout.pos.keys()
	ids.sort()
	for id in ids:
		for s in exits_of(rooms, id):
			if not linked.has(id + ":" + s): out.append([id, s])
	return out

## Every problem with a random layout; empty means it may be played.
static func check(layout: Dictionary, rooms: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	var pos: Dictionary = layout.pos
	if pos.get(START) != middle(): errs.append("%s not in the middle" % START)
	var at := {}
	for id in pos:
		if not rooms.has(id): errs.append("unknown room %s" % id)
		elif not _inside(pos[id]): errs.append("%s outside the grid" % id)
		elif at.has(pos[id]): errs.append("%s and %s share a cell" % [id, at[pos[id]]])
		else: at[pos[id]] = id
	for id in rooms:
		if not pos.has(id): errs.append("%s not placed" % id)
	if not errs.is_empty(): return errs
	for id in pos:
		for s in SIDES:
			var n: Vector2i = pos[id] + DIRS[s]
			if at.has(n) and (s in exits_of(rooms, id)) != (OPPOSITE[s] in exits_of(rooms, at[n])):
				errs.append("%s %s and %s do not agree" % [id, s, at[n]])
	var want := links_of(pos, rooms)
	if layout.links != want: errs.append("links differ from the placed rooms")
	var dist := distances(pos, layout.links)
	for id in pos:
		if not dist.has(id): errs.append("%s cannot be reached from %s" % [id, START])
	var boss_links: Array = []
	for k in layout.links:
		if k[0] == BOSS or k[2] == BOSS: boss_links.append(k)
	if boss_links.size() != 1 or boss_links[0][2] != BOSS or boss_links[0][3] != "west":
		errs.append("%s must hang on exactly one east-facing exit, links %s" % [BOSS, boss_links])
	if loops(layout) < MIN_LOOPS: errs.append("%d loops (want %d)" % [loops(layout), MIN_LOOPS])
	for id in dist:
		if dist.has(BOSS) and int(dist[id]) > int(dist[BOSS]):
			errs.append("%s is farther than %s (%d > %d rooms)" % [id, BOSS, dist[id], dist[BOSS]])
			break
	return errs

static func _inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < GRID and c.y < GRID

static func _shuffled(rng: RandomNumberGenerator, a: Array) -> Array:
	var out := a.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out
