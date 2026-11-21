class_name BigWorld
extends WalkGrid
## The one 4096 x 4096 big map as data (data/bigmap/world.json, baked by tools/bigmap/bake_world.py; its `_doc`
## key describes every field). Pure rules, no scene access: the 8 px walk grid (WalkGrid: blocked_at, roomy,
## reachable, make_nav, same rules as PaintedLayout), monster packs by home, zone level, the boss arena disc,
## the ground tiles for the map scene, and read-only start / stones / chests / arena / props / zones.
## The walk bits stay packed as in the file. A missing or malformed file gives null, never a script error.

## Frozen ids (saves use them). The game keeps these sets in code and never widens them from world.json (a
## modded data file must not add waypoints or chests): other ids in the file are skipped with a warning, and
## tests check world.json carries exactly these ids.
const STONE_IDS := ["w1", "w2", "w3"]
const CHEST_IDS := ["c4", "c11", "c12"]

var tile := 32                     # ground tile size in px
var props_dir := ""                # res:// folder of the prop sprites
var _atlas: Dictionary = {}        # {file, cols, count}
var _ground := PackedInt32Array()  # (size/tile)^2 atlas indices, row-major
var _flip := PackedByteArray()     # same cells: 0 none, 1 h, 2 v, 3 h+v
var _stones: Array = []            # [{id, at: Vector2}]
var _chests: Array = []            # [{id, at: Vector2, kind, level}]
var _packs: Array = []             # [{id, kind, level, count, at: Vector2, home: Vector2, elite}]
var _pack_by_id: Dictionary = {}   # id -> index into _packs
var _arena: Dictionary = {}        # {centre: Vector2, radius, rect: Rect2, gate: Vector2, pack: {kind, level, count, at: Vector2, elite}}
var _props: Array = []             # as in world.json
var _zones: Array = []             # as in world.json

## The baked big map, or null when the file is missing or malformed.
static func open(path := "res://data/bigmap/world.json") -> BigWorld:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return null
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY: return null
	return from_dict(d)

# ---- checks on untrusted data ---------------------------------------------------------------------------------

static func _num_ok(v) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v))

static func _vec_ok(a) -> bool:
	return typeof(a) == TYPE_ARRAY and a.size() == 2 and _num_ok(a[0]) and _num_ok(a[1])

static func _str_ok(v) -> bool:
	return typeof(v) == TYPE_STRING and v != ""

static func _v(a) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))

## text is plain base64 (A-Z a-z 0-9 + /, '=' padding) of exactly n bytes; checked before decoding.
static func _walk_bits(text, n: int) -> PackedByteArray:
	if typeof(text) != TYPE_STRING or text.length() != 4 * ((n + 2) / 3): return PackedByteArray()
	var re := RegEx.create_from_string("^[A-Za-z0-9+/]*={0,2}$")
	if re.search(text) == null: return PackedByteArray()
	var bits := Marshalls.base64_to_raw(text)
	return bits if bits.size() == n else PackedByteArray()

## A pack / boss pack entry: kind, level, count, at (and id for layout packs).
static func _group_ok(p, need_id: bool) -> bool:
	if typeof(p) != TYPE_DICTIONARY: return false
	if need_id and not _str_ok(p.get("id")): return false
	if not _str_ok(p.get("kind")) or not _num_ok(p.get("level")) or not _num_ok(p.get("count")): return false
	if not _vec_ok(p.get("at")): return false
	return p.get("home") == null or _vec_ok(p.get("home"))

# ---- building ------------------------------------------------------------------------------------------------

## Builds from the parsed world.json; null when anything the game needs is missing or has the wrong type.
static func from_dict(d: Dictionary) -> BigWorld:
	var w := BigWorld.new()
	if not _vec_ok(d.get("size")) or not _num_ok(d.get("cell")) or not _num_ok(d.get("tile")): return null
	var sz := _v(d.size)
	var c := int(d.cell)
	var t := int(d.tile)
	if c <= 0 or t <= 0 or sz.x <= 0 or sz.y <= 0: return null
	if int(sz.x) % c != 0 or int(sz.y) % c != 0 or int(sz.x) % t != 0 or int(sz.y) % t != 0: return null
	w.size = sz
	w.cell = c
	w.tile = t
	var cc := int(sz.x) / c
	var rr := int(sz.y) / c
	if not w._take_bits(cc, rr, _walk_bits(d.get("walk"), (cc * rr + 7) / 8)): return null
	if not _vec_ok(d.get("start")): return null
	w.hero_spawn = _v(d.start)
	if not w._read_ground(d): return null
	if not w._read_points(d): return null
	if not w._read_arena(d.get("arena")): return null
	if typeof(d.get("props")) != TYPE_ARRAY or typeof(d.get("zones")) != TYPE_ARRAY: return null
	w._props = d.props.duplicate(true)
	w._zones = d.zones.duplicate(true)
	return w

func _read_ground(d: Dictionary) -> bool:
	var a = d.get("atlas")
	if typeof(a) != TYPE_DICTIONARY or not _str_ok(a.get("file")) or not _num_ok(a.get("cols")) or not _num_ok(a.get("count")):
		return false
	if int(a.cols) <= 0 or int(a.count) <= 0 or not _str_ok(d.get("props_dir")): return false
	_atlas = {"file": String(a.file), "cols": int(a.cols), "count": int(a.count)}
	props_dir = String(d.props_dir)
	var n := (int(size.x) / tile) * (int(size.y) / tile)
	var g = d.get("ground")
	var fl = d.get("flip")
	if typeof(g) != TYPE_ARRAY or typeof(fl) != TYPE_ARRAY or g.size() != n or fl.size() != n: return false
	_ground.resize(n)
	_flip.resize(n)
	var count: int = _atlas.count
	for i in n:
		var gi = g[i]
		var fi = fl[i]
		if not _num_ok(gi) or not _num_ok(fi): return false
		if gi < 0 or gi >= count or gi != floorf(gi) or fi < 0 or fi > 3 or fi != floorf(fi): return false
		_ground[i] = int(gi)
		_flip[i] = int(fi)
	return true

## Stones, chests (ids outside the frozen sets or repeated are skipped with a warning) and layout packs.
func _read_points(d: Dictionary) -> bool:
	var ss = d.get("stones")
	var cs = d.get("chests")
	var ps = d.get("packs")
	if typeof(ss) != TYPE_ARRAY or typeof(cs) != TYPE_ARRAY or typeof(ps) != TYPE_ARRAY: return false
	var seen := {}
	for s in ss:
		if typeof(s) != TYPE_DICTIONARY or not _str_ok(s.get("id")) or not _vec_ok(s.get("at")): return false
		if not STONE_IDS.has(s.id) or seen.has(s.id):
			push_warning("BigWorld: stone id %s skipped (not in STONE_IDS or repeated)" % s.id)
			continue
		seen[s.id] = true
		_stones.append({"id": String(s.id), "at": _v(s.at)})
	seen = {}
	for ch in cs:
		if typeof(ch) != TYPE_DICTIONARY or not _str_ok(ch.get("id")) or not _vec_ok(ch.get("at")): return false
		if not _str_ok(ch.get("kind")) or not _num_ok(ch.get("level")): return false
		if not CHEST_IDS.has(ch.id) or seen.has(ch.id):
			push_warning("BigWorld: chest id %s skipped (not in CHEST_IDS or repeated)" % ch.id)
			continue
		seen[ch.id] = true
		_chests.append({"id": String(ch.id), "at": _v(ch.at), "kind": String(ch.kind), "level": int(ch.level)})
	for p in ps:
		if not _group_ok(p, true) or _pack_by_id.has(p.id): return false
		_pack_by_id[String(p.id)] = _packs.size()
		_packs.append({"id": String(p.id), "kind": String(p.kind), "level": int(p.level), "count": int(p.count),
			"at": _v(p.at), "home": _v(p.get("home", p.at)), "elite": bool(p.get("elite", false))})
	return true

func _read_arena(a) -> bool:
	if typeof(a) != TYPE_DICTIONARY or not _vec_ok(a.get("centre")) or not _num_ok(a.get("radius")): return false
	if float(a.radius) <= 0 or not _vec_ok(a.get("gate")) or not _group_ok(a.get("pack"), false): return false
	var r = a.get("rect")
	if typeof(r) != TYPE_ARRAY or r.size() != 4: return false
	for v in r:
		if not _num_ok(v): return false
	var bp: Dictionary = a.pack
	_arena = {"centre": _v(a.centre), "radius": float(a.radius),
		"rect": Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3])), "gate": _v(a.gate),
		"pack": {"kind": String(bp.kind), "level": int(bp.level), "count": int(bp.count), "at": _v(bp.at),
			"elite": bool(bp.get("elite", false))}}
	return true

# ---- packs, zones, arena -------------------------------------------------------------------------------------

## Ids of the packs whose home is within r px of p (distance <= r), in world.json order.
func packs_near(p: Vector2, r: float) -> Array[String]:
	var out: Array[String] = []
	for q in _packs:
		if q.home.distance_to(p) <= r: out.append(q.id)
	return out

## A copy of pack id ({id, kind, level, count, at, home, elite}), or {} if there is no such pack.
func pack(id: String) -> Dictionary:
	if not _pack_by_id.has(id): return {}
	return _packs[_pack_by_id[id]].duplicate(true)

## Spawn centre of pack id (no copy; for hot paths), or Vector2.INF if there is no such pack.
func pack_home(id: String) -> Vector2:
	if not _pack_by_id.has(id): return Vector2.INF
	return _packs[_pack_by_id[id]].home

## Level of the pack whose home is nearest p (first in world.json order on a tie); 0 with no packs.
## The boss arena's pack is not a layout pack and never counts.
func zone_level(p: Vector2) -> int:
	var best := 0
	var bd := INF
	for q in _packs:
		var dd: float = q.home.distance_squared_to(p)
		if dd < bd:
			bd = dd
			best = q.level
	return best

## Whether p is inside the arena's fight disc (centre / radius, edge included); the rect is only its bounds.
func in_arena(p: Vector2) -> bool:
	if not p.is_finite(): return false
	return p.distance_to(_arena.centre) <= _arena.radius

func arena_centre() -> Vector2:
	return _arena.centre

func arena_radius() -> float:
	return _arena.radius

## Where stone id stands (no copy), or Vector2.INF if there is no such stone.
func stone_at(id: String) -> Vector2:
	for s in _stones:
		if s.id == id: return s.at
	return Vector2.INF

# ---- read-only data: every call returns a fresh copy, so callers should keep what they need ------------------

func start() -> Vector2:
	return hero_spawn

func atlas() -> Dictionary:
	return _atlas.duplicate()

## Atlas index of every ground tile, row-major ((size/tile)^2 entries).
func ground() -> PackedInt32Array:
	return _ground.duplicate()

## Flip of every ground tile (0 none, 1 h, 2 v, 3 h+v).
func flip() -> PackedByteArray:
	return _flip.duplicate()

func stones() -> Array:
	return _stones.duplicate(true)

func chests() -> Array:
	return _chests.duplicate(true)

func packs() -> Array:
	return _packs.duplicate(true)

func arena() -> Dictionary:
	return _arena.duplicate(true)

func props() -> Array:
	return _props.duplicate(true)

func zones() -> Array:
	return _zones.duplicate(true)
