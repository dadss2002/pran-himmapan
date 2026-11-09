class_name FogGrid
extends RefCounted
## M4c §3 fog (Task 6, owner-approved 2026-11-07, docs/superpowers/specs/2026-11-07-m4c-farm-links-fog-minimap.md):
## each room has a fog grid of ⚙ CELL x CELL px cells (16 x 16 for a 512 x 512 room). A cell is revealed when the
## hero comes within ⚙ RADIUS px of it; revealed cells stay revealed for the rest of the game (16 x 16 bits = 32
## bytes per room). Owner 2026-11-08: every new game starts with all fog, so the game save does not hold the fog.
## The fog is drawn on the minimap / full map only (Tasks 7-8), never over the game world. Pure rules, no scene.
##
## Choices (Task 6, not in the spec):
## - "within RADIUS px of a cell" = the distance from the hero's feet to the nearest point of the cell's closed
##   square [cx*CELL, cx*CELL + CELL] x [cy*CELL, cy*CELL + CELL] is <= RADIUS (exactly RADIUS reveals it). The
##   cell the feet stand in is always revealed; feet outside the room reveal the room's cells within reach.
## - A room of another size has ceil(w / CELL) x ceil(h / CELL) cells (all rooms are 512 x 512 today); a room
##   whose size was never given counts as DEFAULT_SIZE.
## - Bits: cell i = cy * cols + cx is bit (i & 7) (least significant first) of byte i >> 3; spare bits of the last
##   byte stay 0. The save holds each room's bytes as base64 ({room id: text}); a room with no revealed cell is
##   left out. Anything wrong in it (not a dict, a non-string id or value, an id not in the room set, bad base64,
##   the wrong length) is ignored room by room: that room stays all fog, the rest of the save loads.
## - Persistence (owner 2026-11-08, spec addendum): the fog lives for one game (one session) and comes back with
##   every new game; the test ground builds a fresh FogGrid per game and never saves it. to_save / load_save
##   stay as a tested data format (unused by the game save).

## Emitted when room_id's revealed cells change (reveal() revealed new cells, from_bytes(), clear()): the
## minimap redraws its fog then (Task 7).
signal changed(room_id: String)

const CELL := 32                          # ⚙ spec §3: one fog cell = 32 x 32 px
const RADIUS := 96.0                      # ⚙ spec §3: reveal distance
const DEFAULT_SIZE := Vector2(512, 512)   # M4b room size

var _sizes := {}     # room id -> Vector2i cells (rooms given by from_rooms / set_room_size)
var _bits := {}      # room id -> PackedByteArray (only rooms with something revealed)
var _ids := {}       # the room set's ids (load_save keeps only these); empty = any id
var _last_room := ""
var _last_pos := Vector2.INF

## A fog grid for a room set's rooms (their sizes), with `saved` (to_save() data, may be null) loaded.
static func from_rooms(rooms: RoomSet, saved = null) -> FogGrid:
	var f := FogGrid.new()
	for id in rooms.ids():
		f.set_room_size(String(id), rooms.room_size(String(id)))
		f._ids[String(id)] = true
	f.load_save(saved)
	return f

## Room id is size_px big (its cells: ceil(size / CELL)). Changing a room's size forgets its revealed cells.
func set_room_size(id: String, size_px: Vector2) -> void:
	var c := Vector2i(maxi(1, ceili(size_px.x / CELL)), maxi(1, ceili(size_px.y / CELL)))
	if _sizes.get(id, c) != c: _bits.erase(id)
	_sizes[id] = c
	_forget_last()

## Room id's grid size in cells (16 x 16 for a 512 x 512 room).
func cells(id: String) -> Vector2i:
	return _sizes.get(id, Vector2i(ceili(DEFAULT_SIZE.x / CELL), ceili(DEFAULT_SIZE.y / CELL)))

## Bytes in room id's saved grid (32 for 16 x 16).
func byte_count(id: String) -> int:
	var c := cells(id)
	return (c.x * c.y + 7) / 8

## Reveals room id's cells within RADIUS of pos (the hero's feet, room px). Returns how many were newly revealed
## (changed is emitted when > 0). Called every physics frame: the same room and position as the last call is
## skipped, and only the cells in the square round pos are looked at (at most 9 x 9).
func reveal(room_id: String, pos: Vector2) -> int:
	if room_id == _last_room and pos == _last_pos: return 0
	_last_room = room_id
	_last_pos = pos
	var c := cells(room_id)
	var x0 := maxi(0, floori((pos.x - RADIUS) / CELL) - 1)
	var x1 := mini(c.x - 1, floori((pos.x + RADIUS) / CELL) + 1)
	var y0 := maxi(0, floori((pos.y - RADIUS) / CELL) - 1)
	var y1 := mini(c.y - 1, floori((pos.y + RADIUS) / CELL) + 1)
	if x0 > x1 or y0 > y1: return 0
	var r2 := RADIUS * RADIUS
	var bits: PackedByteArray = _bits.get(room_id, PackedByteArray())
	var fresh := 0
	for cy in range(y0, y1 + 1):
		var top := float(cy * CELL)
		var dy := maxf(0.0, maxf(top - pos.y, pos.y - top - CELL))
		var dy2 := dy * dy
		if dy2 > r2: continue
		for cx in range(x0, x1 + 1):
			var left := float(cx * CELL)
			var dx := maxf(0.0, maxf(left - pos.x, pos.x - left - CELL))
			if dx * dx + dy2 > r2: continue
			var i := cy * c.x + cx
			var b := 1 << (i & 7)
			if bits.is_empty(): bits.resize(byte_count(room_id))     # zero-filled
			if bits[i >> 3] & b: continue
			bits[i >> 3] |= b
			fresh += 1
	if fresh > 0:
		_bits[room_id] = bits
		changed.emit(room_id)
	return fresh

## Whether cell (cx, cy) of room id is revealed. Unknown rooms and cells off the grid are fog (false).
func is_revealed(room_id: String, cx: int, cy: int) -> bool:
	var c := cells(room_id)
	if cx < 0 or cy < 0 or cx >= c.x or cy >= c.y or not _bits.has(room_id): return false
	var i := cy * c.x + cx
	return (_bits[room_id][i >> 3] & (1 << (i & 7))) != 0

## How many of room id's cells are revealed.
func revealed_count(room_id: String) -> int:
	var n := 0
	for byte in _bits.get(room_id, PackedByteArray()):
		while byte:
			n += byte & 1
			byte >>= 1
	return n

## Whether any cell of room id is revealed (the room has been entered; Task 8 draws only these).
func known(room_id: String) -> bool:
	return _bits.has(room_id)

## The rooms with something revealed, sorted.
func known_ids() -> Array[String]:
	var out: Array[String] = []
	for id in _bits: out.append(String(id))
	out.sort()
	return out

## Room id's grid as bytes (byte_count(id) long: 32 for 16 x 16; all 0 = all fog, also for an unknown room).
func to_bytes(room_id: String) -> PackedByteArray:
	if _bits.has(room_id): return _bits[room_id].duplicate()
	var out := PackedByteArray()
	out.resize(byte_count(room_id))
	return out

## Sets room id's grid from to_bytes() data. false (and nothing changes) when the length is not byte_count(id).
## Spare bits past the last cell are dropped; all 0 makes the room all fog again.
func from_bytes(room_id: String, bytes: PackedByteArray) -> bool:
	if bytes.size() != byte_count(room_id): return false
	var b := bytes.duplicate()
	var c := cells(room_id)
	var spare := b.size() * 8 - c.x * c.y
	if spare > 0: b[b.size() - 1] &= (1 << (8 - spare)) - 1
	var any := false
	for v in b:
		if v != 0:
			any = true
			break
	if any: _bits[room_id] = b
	else: _bits.erase(room_id)
	_forget_last()
	changed.emit(room_id)
	return true

## Fogs room id again.
func clear(room_id: String) -> void:
	if _bits.erase(room_id): changed.emit(room_id)
	_forget_last()

## Fogs every room again.
func clear_all() -> void:
	var ids := _bits.keys()
	_bits.clear()
	_forget_last()
	for id in ids: changed.emit(String(id))

## For the save: {room id: base64 of to_bytes(id)} for every room with something revealed.
func to_save() -> Dictionary:
	var out := {}
	for id in known_ids(): out[id] = Marshalls.raw_to_base64(_bits[id])
	return out

## Replaces every room's fog with `saved` (to_save() data); rooms missing or wrong in it are all fog (see the
## choices above). null / a non-dict = all fog (old saves).
func load_save(saved) -> void:
	_bits.clear()
	_forget_last()
	if typeof(saved) != TYPE_DICTIONARY: return
	for id in saved:
		if typeof(id) != TYPE_STRING or (not _ids.is_empty() and not _ids.has(id)): continue
		var text = saved[id]
		if typeof(text) != TYPE_STRING or not _base64_ok(text, byte_count(id)): continue
		from_bytes(id, Marshalls.base64_to_raw(text))

## text is base64 of exactly n bytes (checked before decoding, so bad text never reaches the decoder).
static func _base64_ok(text: String, n: int) -> bool:
	if text.length() != 4 * ((n + 2) / 3): return false
	var pad := (3 - n % 3) % 3
	for i in text.length():
		var ch := text.unicode_at(i)
		var ok := (ch >= 65 and ch <= 90) or (ch >= 97 and ch <= 122) or (ch >= 48 and ch <= 57) or ch == 43 or ch == 47
		if i >= text.length() - pad: ok = ch == 61        # '=' padding only at the end
		if not ok: return false
	return true

## For the minimap (Task 7): a cols x rows image of room id, one pixel per cell: `fog` where the cell is fogged,
## clear (alpha 0) where it is revealed. Draw it stretched over the room picture with nearest filtering.
func fog_image(room_id: String, fog := Color.BLACK) -> Image:
	var c := cells(room_id)
	var img := Image.create_empty(c.x, c.y, false, Image.FORMAT_RGBA8)
	img.fill(fog)
	if not _bits.has(room_id): return img
	for cy in c.y:
		for cx in c.x:
			if is_revealed(room_id, cx, cy): img.set_pixel(cx, cy, Color(0, 0, 0, 0))
	return img

func _forget_last() -> void:
	_last_room = ""
	_last_pos = Vector2.INF
