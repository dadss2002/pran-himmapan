extends RefCounted
## Task 6 fog (docs/superpowers/specs/2026-11-07-m4c-farm-links-fog-minimap.md §3): 16 x 16 cells of 32 px per
## 512 x 512 room, a cell revealed when the hero comes within 96 px of it, revealed cells kept per room
## (32 bytes) for the rest of the game; every new game starts with all fog and the save holds no fog (owner
## 2026-11-08). Boundary rule (FogGrid): distance from the feet to the nearest point of the cell's closed square
## <= 96 reveals it (exactly 96 does). Fog is shown on the minimap only: nothing here draws over the world.

const SAVE := "user://test_fog_save.json"
const SETTINGS := "user://test_fog_settings.json"

var tree: SceneTree

func setup(t: SceneTree) -> void:
	tree = t

func _clean() -> void:
	for f in [SAVE, SETTINGS, SaveGame.marker_path(SAVE)] + _bads():
		if FileAccess.file_exists(f): DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

func _ground() -> Node2D:
	var g: Node2D = load("res://scenes/test_ground.tscn").instantiate()
	g.layout_seed = 7
	g.save_path = SAVE
	g.settings_path = SETTINGS
	tree.root.add_child(g)
	await tree.process_frame
	for p in g.packs: p.calm = 1000.0
	return g

func _free(g: Node2D) -> void:
	if is_instance_valid(g):
		g.queue_free()
		await tree.process_frame

func _frames(n: int) -> void:
	for i in n: await tree.physics_frame

## The room's grid as 16 strings ("#" revealed, "." fog), row 0 at the top.
func _picture(f: FogGrid, id: String) -> Array:
	var out := []
	var c := f.cells(id)
	for cy in c.y:
		var row := ""
		for cx in c.x: row += "#" if f.is_revealed(id, cx, cy) else "."
		out.append(row)
	return out

## Compares f's grid of id with `want` (rows given by index; every other row all fog).
func _check(f: FogGrid, id: String, want: Dictionary, what: String) -> String:
	var got := _picture(f, id)
	for cy in 16:
		var w: String = want.get(cy, "................")
		if got[cy] != w: return "%s: row %d is %s, want %s\n%s" % [what, cy, got[cy], w, "\n".join(got)]
	return ""

func _read_save() -> Dictionary:
	var f := FileAccess.open(SAVE, FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	return d

func _write_save(d: Dictionary) -> void:
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()

## A Task 6 save as it was really written: version 3, unsigned, on a device that has not yet written a signed
## save (save hardening 2026-11-09: a hand-edited signed save is broken, so the old file is modelled exactly).
func _write_old_save(d: Dictionary) -> void:
	var old := d.duplicate(true)
	old.erase("sig")
	old["version"] = 3
	_write_save(old)
	var m := SaveGame.marker_path(SAVE)
	if FileAccess.file_exists(m): DirAccess.remove_absolute(ProjectSettings.globalize_path(m))

## 96 px round the middle of cell (5, 5) at (176, 176): 7 x 7 cells less the 4 corners (their nearest point is
## 80 + 80 px away = 113 px), 45 cells; nothing else.
func test_reveal_centre():
	var f := FogGrid.new()
	if f.cells("c1r1") != Vector2i(16, 16) or f.byte_count("c1r1") != 32: return "grid %s / %d bytes" % [f.cells("c1r1"), f.byte_count("c1r1")]
	var n := f.reveal("c1r1", Vector2(176, 176))
	if n != 45: return "revealed %d cells (want 45)" % n
	var r := _check(f, "c1r1", {
		2: "...#####........",
		3: "..#######.......",
		4: "..#######.......",
		5: "..#######.......",
		6: "..#######.......",
		7: "..#######.......",
		8: "...#####........"}, "centre")
	if r != "": return r
	if f.reveal("c1r1", Vector2(176, 176)) != 0 or f.reveal("c1r1", Vector2(177, 176)) != 0: return "already revealed cells counted again"
	if f.revealed_count("c1r1") != 45: return "count %d" % f.revealed_count("c1r1")
	if f.known_ids() != ["c1r1"]: return "other rooms touched: %s" % [f.known_ids()]
	return ""

## The west edge (feet at x 0, row 5's middle): only cells inside the room, no wrap onto the row above's east
## end; cell (3, 5) at exactly 96 px is revealed. A corner near (8, 8) and the far corner (512, 512).
func test_reveal_edge_and_corners():
	var f := FogGrid.new()
	if f.reveal("a", Vector2(0, 176)) != 20: return "edge revealed %d (want 20)" % f.revealed_count("a")
	var r := _check(f, "a", {
		2: "##..............",
		3: "###.............",
		4: "###.............",
		5: "####............",
		6: "###.............",
		7: "###.............",
		8: "##.............."}, "west edge")
	if r != "": return r
	f.reveal("b", Vector2(8, 8))
	r = _check(f, "b", {
		0: "####............",
		1: "####............",
		2: "###.............",
		3: "##.............."}, "corner (8, 8)")
	if r != "": return r
	f.reveal("c", Vector2(512, 512))     # (12, 15) and (15, 12) at exactly 96 px
	r = _check(f, "c", {
		12: "...............#",
		13: ".............###",
		14: ".............###",
		15: "............####"}, "far corner")
	if r != "": return r
	f.reveal("d", Vector2(-50, -50))     # outside the room: (0, 0) is 70.7 px away, (1, 0) and (0, 1) 96.04
	r = _check(f, "d", {0: "#..............."}, "outside the north-west corner")
	if r != "": return r
	if f.reveal("e", Vector2(-200, 100)) != 0 or f.known("e"): return "feet 200 px outside revealed something"
	if f.reveal("e", Vector2(5000, 5000)) != 0: return "feet far outside revealed something"
	return ""

## Rounding at the boundary: feet on the corner of 4 cells at (256, 256): rows 7 and 8 reveal columns 4-11
## (columns 4 and 11 at exactly 96 px); 0.01 px to the east, column 4 is 96.01 px away and stays fog.
func test_reveal_boundary_rounding():
	var f := FogGrid.new()
	f.reveal("a", Vector2(256, 256))
	for cy in [7, 8]:
		for cx in 16:
			if f.is_revealed("a", cx, cy) != (cx >= 4 and cx <= 11): return "(256, 256): cell (%d, %d) %s" % [cx, cy, f.is_revealed("a", cx, cy)]
	var g := FogGrid.new()
	g.reveal("a", Vector2(256.01, 256))
	if g.is_revealed("a", 4, 8) or g.is_revealed("a", 4, 7): return "column 4 revealed at 96.01 px"
	if not g.is_revealed("a", 11, 8) or g.is_revealed("a", 12, 8): return "columns 11 / 12 wrong at 256.01"
	var h := FogGrid.new()
	h.reveal("a", Vector2(256, 160))     # straight up: row 1's bottom (y 64) is exactly 96 px away, row 0's 128
	if not h.is_revealed("a", 7, 1) or not h.is_revealed("a", 8, 1) or h.is_revealed("a", 6, 1) or h.is_revealed("a", 7, 0):
		return "vertical boundary:\n%s" % "\n".join(_picture(h, "a"))
	return ""

## A room never entered (or a name the grid has never heard of) is all fog: is_revealed false everywhere, 32 zero
## bytes, not known, nothing in the save; cells off the grid are fog too.
func test_unknown_room_all_fog():
	var rooms := RoomSet.open()
	var f := FogGrid.from_rooms(rooms)
	f.reveal("c1r1", Vector2(256, 256))
	for id in ["c0r0", "nowhere"]:
		for cy in 16:
			for cx in 16:
				if f.is_revealed(id, cx, cy): return "%s (%d, %d) revealed" % [id, cx, cy]
		var b := f.to_bytes(id)
		if b.size() != 32 or b.count(0) != 32: return "%s bytes %s" % [id, b]
		if f.known(id) or f.revealed_count(id) != 0: return "%s known" % id
	if f.to_save().keys() != ["c1r1"]: return "save holds %s" % [f.to_save().keys()]
	for p in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(16, 0), Vector2i(0, 16)]:
		if f.is_revealed("c1r1", p.x, p.y): return "off-grid cell %s revealed" % p
	return ""

## Rooms of another size: ceil(size / 32) cells each way, bytes to match, reveal reaches the last cell.
func test_other_room_sizes():
	var f := FogGrid.new()
	f.set_room_size("wide", Vector2(640, 384))
	f.set_room_size("odd", Vector2(500, 300))
	if f.cells("wide") != Vector2i(20, 12) or f.byte_count("wide") != 30: return "wide %s %d" % [f.cells("wide"), f.byte_count("wide")]
	if f.cells("odd") != Vector2i(16, 10) or f.byte_count("odd") != 20: return "odd %s %d" % [f.cells("odd"), f.byte_count("odd")]
	f.reveal("wide", Vector2(630, 380))
	if not f.is_revealed("wide", 19, 11) or f.is_revealed("wide", 20, 11): return "wide's last cell"
	var g := FogGrid.new()
	g.set_room_size("wide", Vector2(640, 384))
	if not g.from_bytes("wide", f.to_bytes("wide")) or g.to_bytes("wide") != f.to_bytes("wide"): return "wide round trip"
	var rooms := RoomSet.open()
	var all := FogGrid.from_rooms(rooms)
	for id in rooms.ids():
		if all.cells(id) != Vector2i(rooms.room_size(id) / 32.0): return "%s cells %s for size %s" % [id, all.cells(id), rooms.room_size(id)]
		if all.byte_count(id) != 32: return "%s: %d bytes (every room is 512 today)" % [id, all.byte_count(id)]
	return ""

## to_bytes / from_bytes: 32 bytes, every cell back as it was; the bit order (cell i = cy * 16 + cx is bit i & 7
## of byte i >> 3); wrong lengths refused with nothing changed; all zero = all fog again.
func test_bytes_round_trip():
	var f := FogGrid.new()
	f.reveal("c1r1", Vector2(176, 176))
	f.reveal("c1r1", Vector2(500, 40))
	var b := f.to_bytes("c1r1")
	if b.size() != 32: return "%d bytes" % b.size()
	var g := FogGrid.new()
	if not g.from_bytes("c1r1", b): return "from_bytes refused its own bytes"
	if _picture(g, "c1r1") != _picture(f, "c1r1"): return "round trip differs"
	if g.to_bytes("c1r1") != b: return "bytes differ after the round trip"
	var one := PackedByteArray()
	one.resize(32)
	one[0] = 1             # cell 0 = (0, 0)
	one[2] = 2             # cell 17 = (1, 1)
	one[31] = 128          # cell 255 = (15, 15)
	var h := FogGrid.new()
	h.from_bytes("x", one)
	if h.revealed_count("x") != 3 or not h.is_revealed("x", 0, 0) or not h.is_revealed("x", 1, 1) or not h.is_revealed("x", 15, 15):
		return "bit order: %s" % ["\n".join(_picture(h, "x"))]
	for n in [0, 31, 33]:
		var bad := PackedByteArray()
		bad.resize(n)
		bad.fill(255)
		if h.from_bytes("x", bad): return "%d bytes accepted" % n
	if h.revealed_count("x") != 3: return "a refused from_bytes changed the room"
	var zero := PackedByteArray()
	zero.resize(32)
	h.from_bytes("x", zero)
	if h.known("x") or h.revealed_count("x") != 0: return "all-zero bytes should fog the room"
	var seen := []
	h.changed.connect(func(id): seen.append(id))
	h.reveal("x", Vector2(10, 10))
	h.reveal("x", Vector2(10, 10))
	h.clear("x")
	if seen != ["x", "x"] or h.known("x"): return "changed signals %s (want reveal + clear)" % [seen]
	h.reveal("x", Vector2(10, 10))
	h.reveal("y", Vector2(10, 10))
	h.clear_all()
	if not h.known_ids().is_empty(): return "clear_all left %s" % [h.known_ids()]
	if h.reveal("x", Vector2(10, 10)) == 0: return "after clear_all the same spot reveals nothing (stale skip)"
	return ""

## to_save / load_save: base64 of the 32 bytes per known room; garbage ignored room by room (non-dict, non-string
## ids or values, ids not in the room set, bad base64, wrong length), the good rooms still load; null = all fog.
func test_save_data_and_invalid_data_ignored():
	var rooms := RoomSet.open()
	var f := FogGrid.from_rooms(rooms)
	f.reveal("c1r1", Vector2(256, 256))
	f.reveal("c2r0", Vector2(30, 480))
	var s := f.to_save()
	if s.keys() != ["c1r1", "c2r0"]: return "save keys %s" % [s.keys()]
	if String(s.c1r1).length() != 44 or Marshalls.base64_to_raw(s.c1r1).size() != 32: return "save text %s" % s.c1r1
	var back := FogGrid.from_rooms(rooms, JSON.parse_string(JSON.stringify(s)))
	for id in ["c1r1", "c2r0", "c0r0"]:
		if back.to_bytes(id) != f.to_bytes(id): return "%s differs after save/load" % id
	if not FogGrid.from_rooms(rooms, null).known_ids().is_empty(): return "null save not all fog"
	if not FogGrid.from_rooms(rooms, "junk").known_ids().is_empty(): return "string save not all fog"
	if not FogGrid.from_rooms(rooms, [s.c1r1]).known_ids().is_empty(): return "array save not all fog"
	var short := PackedByteArray()
	short.resize(31)
	short.fill(255)
	var bad := {
		"c1r1": s.c1r1,                                  # the one good room
		"c0r0": 12345,                                   # not text
		"c0r1": "not base64 at all!!!!!!!!!!!!!!!!!!!!!!!!!!",
		"c0r2": Marshalls.raw_to_base64(short),          # 31 bytes
		"c1r0": String(s.c1r1).substr(0, 40),            # cut short
		"c1r2": String(s.c1r1).replace("A", "=").replace("Q", "="),   # '=' in the middle
		"zz9": s.c2r0,                                   # no such room
		7: s.c2r0,                                       # not a room id
		"c2r1": null}
	var g := FogGrid.from_rooms(rooms, bad)
	if g.known_ids() != ["c1r1"]: return "invalid entries loaded: %s" % [g.known_ids()]
	if g.to_bytes("c1r1") != f.to_bytes("c1r1"): return "the good room did not load"
	var loose := FogGrid.new()                           # no room set: any id, the default size
	loose.load_save({"zz9": s.c2r0})
	if loose.known_ids() != ["zz9"]: return "a grid without a room set should take any id"
	return ""

## SaveGame (owner 2026-11-08: fog comes back with every new game, loading = a new game, so the fog is not
## saved): a new state has no "fog" key; a Task 6 save holding "fog" (a real grid or junk) still loads with the
## rest intact (not moved to .bad.json) and the "fog" key dropped; saving it again writes no "fog".
func test_save_game_has_no_fog_key():
	_clean()
	var rooms := RoomSet.open()
	var f := FogGrid.from_rooms(rooms)
	f.reveal("c0r2", Vector2(100, 100))
	var st := SaveGame.new_state()
	if st.has("fog"): return "new state has fog %s" % [st.get("fog")]
	st.level = 5
	st.waypoints = ["c1r1", "c0r2"]
	SaveGame.save(st, SAVE)
	var raw := _read_save()
	if raw.has("fog"): return "a new state saved a fog key"
	var r := ""
	for old in [f.to_save(), "junk", 12, null]:      # what Task 6 saves held (and broken copies of it)
		raw.fog = old
		_write_old_save(raw)
		var d := SaveGame.load_or_new(SAVE)
		if FileAccess.file_exists(SAVE.get_basename() + ".bad.json"): r = "old fog %s threw the save away" % [old]
		elif d.has("fog"): r = "old fog %s kept in the loaded state" % [old]
		elif int(d.level) != 5 or d.waypoints != ["c1r1", "c0r2"]: r = "old fog %s: level %s waypoints %s" % [old, d.level, d.waypoints]
		if r != "": break
		SaveGame.save(d, SAVE)
		if _read_save().has("fog"): r = "old fog %s written back" % [old]
		raw = _read_save()
		if r != "": break
	_clean()
	return r

## In game: the start room is revealed round the arrival at once; walking reveals the cells round the hero on
## the next physics frame; entering another room reveals its arrival at once; coming back (and a waypoint
## re-roll, which is not a new game) keeps every room's fog for the rest of the game; the save never holds fog;
## a new game (a new ground from the same save, also an old Task 6 save with fog in it) starts with all fog
## except its own arrival (owner 2026-11-08, "หมอกกลับมาใหม่ทุกเกมใหม่"; this replaces the Task 6 "kept on a new
## game" check); the world is not covered (no fog node in the world).
func test_in_game_reveal_kept_in_game_reset_on_new_game():
	_clean()
	var g: Node2D = await _ground()
	var r := ""
	var id: String = g.room_id
	var spawn: Vector2 = g.hero.position
	if not g.fog.is_revealed(id, int(spawn.x) / 32, int(spawn.y) / 32): r = "arrival cell fogged"
	# an open spot far from the arrival (no cell within 96 px of it revealed yet)
	var far := Vector2.INF
	var l: PaintedLayout = g.layout
	if r == "":
		for cy in l.rows:
			for cx in l.cols:
				var p := Vector2(cx * l.cell + l.cell / 2.0, cy * l.cell + l.cell / 2.0)
				var by_exit := false                   # an exit ring would warp him away
				for w in g.warps: by_exit = by_exit or p.distance_to(w.position) < 80.0
				if l.roomy(cx, cy) and not by_exit and p.distance_to(spawn) > 200.0 and not g.fog.is_revealed(id, int(p.x) / 32, int(p.y) / 32):
					far = p
					break
			if far != Vector2.INF: break
		if far == Vector2.INF: r = "no open spot far from the arrival"
	if r == "":
		g.hero.global_position = far
		g.hero.velocity = Vector2.ZERO
		await _frames(2)
		if g.warping: r = "setup: the spot %s warps" % far
	if r == "":
		var at: Vector2 = g.hero.global_position
		var want := FogGrid.new()
		want.reveal(id, at)
		for cy in 16:
			for cx in 16:
				if want.is_revealed(id, cx, cy) and not g.fog.is_revealed(id, cx, cy): r = "cell (%d, %d) near the hero at %s still fogged" % [cx, cy, at]
	var keep := PackedByteArray()
	if r == "":
		g.save_now()
		keep = g.fog.to_bytes(id)
		if _read_save().has("fog"): r = "the save holds fog"
	var other := ""
	var keep_other := PackedByteArray()
	if r == "":
		other = String(g.rooms.room(id).warps[0].to)
		g.go_to(other, "", false)
		var a: Vector2 = g.hero.position
		keep_other = g.fog.to_bytes(other)
		if not g.fog.is_revealed(other, int(a.x) / 32, int(a.y) / 32): r = "arrival in %s not revealed at once" % other
		elif _read_save().has("fog"): r = "go_to saved fog"
	if r == "":
		g.reroll()                                     # what a waypoint trip does: not a new game
		g.go_to(id, "", false)
		var now: PackedByteArray = g.fog.to_bytes(id)
		for i in 32:
			if (now[i] & keep[i]) != keep[i]: r = "start room's fog lost within the game (byte %d)" % i
		var now_other: PackedByteArray = g.fog.to_bytes(other)
		if r == "" and now_other != keep_other: r = "%s's fog changed after leaving it" % other
	if r == "":
		for n in g.world.get_children():
			if n.get_script() and String(n.get_script().resource_path).contains("fog"): r = "a fog node in the world"
	if r == "":
		g.save_now()
	await _free(g)
	for with_old_fog in [false, true]:
		if r != "": break
		if with_old_fog:                               # a Task 6 save that still holds the old game's fog
			var old := FogGrid.from_rooms(RoomSet.open())
			for rid in [id, other]:
				for y in range(16, 512, 32):
					for x in range(16, 512, 32): old.reveal(rid, Vector2(x, y))
			var raw := _read_save()
			raw.fog = old.to_save()
			_write_old_save(raw)
		var g2: Node2D = await _ground()                # a new game from the same save
		var start: String = g2.room_id
		if g2.fog.known_ids() != [start]: r = "new game (old fog %s): rooms known %s (want only the start room)" % [with_old_fog, g2.fog.known_ids()]
		else:
			var only := FogGrid.new()
			only.reveal(start, g2.hero.position)
			if g2.fog.to_bytes(start) != only.to_bytes(start): r = "new game (old fog %s): more than the arrival revealed" % with_old_fog
		await _free(g2)
	_clean()
	return r

## fog_image (for the minimap, Task 7): 16 x 16, fog colour where fogged, alpha 0 where revealed.
func test_fog_image():
	var f := FogGrid.new()
	f.reveal("a", Vector2(8, 8))
	var img := f.fog_image("a", Color(0, 0, 0, 0.8))
	if img.get_size() != Vector2i(16, 16): return "size %s" % img.get_size()
	for cy in 16:
		for cx in 16:
			var a := img.get_pixel(cx, cy).a
			if f.is_revealed("a", cx, cy) != (a == 0.0): return "(%d, %d) alpha %s" % [cx, cy, a]
			if not f.is_revealed("a", cx, cy) and absf(a - 0.8) > 0.01: return "fog alpha %s" % a
	if f.fog_image("unknown").get_pixel(0, 0) != Color.BLACK: return "unknown room image not all fog"
	return ""

## Every physics frame is cheap: reveal() on a moving hero averages under 0.2 ms (also while revealing fresh
## cells), and a frame where he stands still costs next to nothing.
func test_reveal_per_frame_cost():
	var f := FogGrid.new()
	var n := 3000
	var t0 := Time.get_ticks_usec()
	for i in n:
		var p := Vector2(fmod(i * 1.7, 520.0) - 4.0, fmod(i * 0.9 + 40.0, 520.0) - 4.0)
		f.reveal("r%d" % (i % 4), p)
	var each := float(Time.get_ticks_usec() - t0) / n / 1000.0
	if each >= 0.2: return "reveal took %.4f ms per call (limit 0.2)" % each
	t0 = Time.get_ticks_usec()
	for i in n: f.reveal("r0", Vector2(100, 100))
	var still := float(Time.get_ticks_usec() - t0) / n / 1000.0
	if still >= 0.02: return "standing still costs %.4f ms" % still
	print("    fog reveal: %.4f ms per moving call, %.5f ms standing still" % [each, still])
	return ""

## Every refused-save copy (<name>.bad.json, <name>.bad.N.json).
func _bads() -> Array:
	var out := []
	for n in SaveGame.BAD_KEEP: out.append(SaveGame.bad_path(SAVE, n))
	return out
