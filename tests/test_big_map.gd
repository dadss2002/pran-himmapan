extends RefCounted
## Big map Task 3 (docs/superpowers/plans/2026-11-21-big-map-game.md): the test ground's big-map path (BigMap):
## the hero at the start, the ground TileMapLayer cell for cell, props (floor ones flat, the rest y-sorted with the
## hero, foot on their point), colliders exactly on the walk grid's blocked cells, water that stops the hero, and
## the wood bridge he can walk across. Facts are read from world.json / BigWorld, not typed in.
## One test ground is built for the whole file (building the 4096 px map takes a moment) and freed by the last test.

const TMP_SAVE := "user://test_big_map_save.json"
const FEET := Rect2(-10, -14, 20, 16)     # the hero's capsule (scenes/hero.tscn: r 8, h 20, turned, at (0,-6))

var tree: SceneTree
var _g: Node2D = null

func setup(t: SceneTree) -> void:
	tree = t

func _ground() -> Node2D:
	if _g != null: return _g
	if FileAccess.file_exists(TMP_SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))
	_g = load("res://scenes/test_ground.tscn").instantiate()
	_g.save_path = TMP_SAVE
	_g.use_big_map = true
	tree.root.add_child(_g)
	await tree.physics_frame
	await tree.physics_frame
	return _g

## Whether the hero's feet box at p touches a blocked walk cell (sampled every 2 px, 0.5 px inside its edges).
static func _feet_blocked(w: WalkGrid, p: Vector2) -> bool:
	var r := FEET.grow(-0.5)
	for iy in int(r.size.y / 2.0) + 2:
		var y := minf(r.position.y + iy * 2.0, r.end.y)
		for ix in int(r.size.x / 2.0) + 2:
			if w.blocked_at(p + Vector2(minf(r.position.x + ix * 2.0, r.end.x), y)): return true
	return false

## Walks the hero (physics on, input off) along dir for up to frames frames or until stop(pos) is true; returns
## the first position whose feet touch a blocked cell (Vector2.INF if none) and where he ended, as [touch, end].
func _walk(g: Node2D, from: Vector2, dir: Vector2, frames: int, stop := Callable()) -> Array:
	var h: Hero = g.hero
	h.set_physics_process(false)
	h.global_position = from
	h.velocity = Vector2.ZERO
	await tree.physics_frame
	var touch := Vector2.INF
	for f in frames:
		h.step(1.0 / 60.0, dir)
		await tree.physics_frame
		if touch == Vector2.INF and _feet_blocked(g.big, h.global_position): touch = h.global_position
		if stop.is_valid() and stop.call(h.global_position): break
	return [touch, h.global_position]

func test_big_map_hero_at_start_no_rooms() -> String:
	var g := await _ground()
	var w: BigWorld = g.big
	if w == null or g.big_map == null: return "big map not built (big %s, big_map %s)" % [w, g.big_map]
	if g.layout != w: return "layout is %s, want the BigWorld" % g.layout
	if g.hero.position != w.start() or g.hero.spawn_point != w.start():
		return "hero at %s (spawn %s), want start %s" % [g.hero.position, g.hero.spawn_point, w.start()]
	if g.rooms != null or not g.warps.is_empty() or not g.packs.is_empty() or g.forest != null:
		return "room parts built on the big map: rooms %s warps %d packs %d forest %s" % [g.rooms, g.warps.size(), g.packs.size(), g.forest]
	if g.big_nav == null or g.big_nav.region != Rect2i(0, 0, w.cols, w.rows): return "route grid missing or wrong: %s" % g.big_nav
	var c: Camera2D = g.cam
	if [c.limit_left, c.limit_top, c.limit_right, c.limit_bottom] != [0, 0, 4096, 4096]:
		return "camera limits %s" % [[c.limit_left, c.limit_top, c.limit_right, c.limit_bottom]]
	if g.big_map.get_parent() != g.world or not g.world.y_sort_enabled or not g.big_map.y_sort_enabled:
		return "BigMap must be a y-sorted child of the y-sorted world"
	if not g.save_now(): return "save failed on the big map"
	return ""

func test_big_map_ground_cells_match_world() -> String:
	var g := await _ground()
	var w: BigWorld = g.big
	var gl: TileMapLayer = g.big_map.ground
	if gl.z_index >= 0: return "ground z %d must be under the world" % gl.z_index
	var used := gl.get_used_cells()
	if used.size() != 16384: return "used cells %d, want 16384" % used.size()
	var cols: int = w.atlas().cols
	var ground := w.ground()
	var flip := w.flip()
	var flips := [0, 0, 0, 0]
	for i in ground.size():
		var at := Vector2i(i % 128, i / 128)
		var want := Vector2i(ground[i] % cols, ground[i] / cols)
		if gl.get_cell_source_id(at) != 0 or gl.get_cell_atlas_coords(at) != want:
			return "cell %s atlas %s, want %s" % [at, gl.get_cell_atlas_coords(at), want]
		var alt := gl.get_cell_alternative_tile(at)
		var h := (alt & TileSetAtlasSource.TRANSFORM_FLIP_H) != 0
		var v := (alt & TileSetAtlasSource.TRANSFORM_FLIP_V) != 0
		if (alt & TileSetAtlasSource.TRANSFORM_TRANSPOSE) != 0 or h != bool(flip[i] & 1) or v != bool(flip[i] & 2):
			return "cell %s alternative %d, want flip %d" % [at, alt, flip[i]]
		flips[flip[i]] += 1
	if flips[1] + flips[2] + flips[3] == 0: return "no flipped cell at all: the flip check proves nothing"
	return ""

func test_big_map_props_placed_and_layered() -> String:
	var g := await _ground()
	var w: BigWorld = g.big
	var bm: BigMap = g.big_map
	var props := w.props()
	if bm.skipped != 0: return "%d props skipped" % bm.skipped
	if bm.prop_sprites.size() + bm.floor_sprites.size() != props.size():
		return "%d + %d sprites for %d props" % [bm.prop_sprites.size(), bm.floor_sprites.size(), props.size()]
	if bm.floor_layer.y_sort_enabled or bm.floor_layer.z_index >= 0 or bm.floor_layer.z_index <= bm.ground.z_index:
		return "floor layer y-sort %s z %d (ground z %d)" % [bm.floor_layer.y_sort_enabled, bm.floor_layer.z_index, bm.ground.z_index]
	var fi := 0
	var pi := 0
	var floors := 0
	for p in props:
		var s: Sprite2D
		if bool(p.get("floor", false)):
			s = bm.floor_sprites[fi]
			fi += 1
			floors += 1
			if s.get_parent() != bm.floor_layer: return "floor prop %s not on the floor layer" % p.name
		else:
			s = bm.prop_sprites[pi]
			pi += 1
			if s.get_parent() != bm: return "prop %s not a y-sorted child of BigMap" % p.name
		if s.texture == null or s.texture.resource_path != "%s/%s.png" % [w.props_dir, p.name] or s.position != Vector2(p.x, p.y) or s.offset != -Vector2(p.foot[0], p.foot[1]) or s.centered:
			return "prop %s at %s offset %s, want foot %s on %s" % [p.name, s.position, s.offset, p.foot, Vector2(p.x, p.y)]
	if floors == 0: return "no floor prop in world.json: the layer check proves nothing"
	# a bridge is drawn under the hero even when he stands north of its foot point (y-sort would put it on top)
	for s in bm.floor_sprites:
		if s.is_y_sort_enabled(): return "floor sprite %s y-sorted" % s.name
	return ""

## Bad prop entries in world.json are skipped with a warning, never a script error or a path outside props_dir.
func test_big_map_prop_entry_checks() -> String:
	var ok := {"name": "chedi_01", "x": 10, "y": 20, "foot": [64, 123], "box": [0, 0, 4, 4], "floor": false}
	if not BigMap.prop_ok(ok): return "good entry refused"
	var bad := [null, 3, {}, {"name": "../../icon", "x": 0, "y": 0, "foot": [0, 0]}, {"name": "a/b", "x": 0, "y": 0, "foot": [0, 0]},
		{"name": "chedi_01", "x": "1", "y": 0, "foot": [0, 0]}, {"name": "chedi_01", "x": 0, "y": NAN, "foot": [0, 0]},
		{"name": "chedi_01", "x": 0, "y": 0, "foot": [0]}, {"name": "chedi_01", "x": 0, "y": 0, "foot": [0, 0], "box": [0, 0, -4, 4]},
		{"name": "chedi_01", "x": 0, "y": 0, "foot": [0, 0], "box": [0, 0, 4]}, {"name": "chedi_01", "x": 0, "y": 0, "foot": [0, 0], "floor": 1},
		{"name": "", "x": 0, "y": 0, "foot": [0, 0]}]
	for b in bad:
		if BigMap.prop_ok(b): return "bad entry accepted: %s" % [b]
	# a world whose props hold a bad entry and a missing sprite still builds; both are skipped
	var f := FileAccess.open("res://data/bigmap/world.json", FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	d.props = [d.props[0], {"name": "../x", "x": 1, "y": 1, "foot": [0, 0]}, {"name": "no_such_prop", "x": 1, "y": 1, "foot": [0, 0], "box": null}]
	var w := BigWorld.from_dict(d)
	if w == null: return "world with bad props did not open"
	var bm := BigMap.new()
	bm.build(w)
	var r := ""
	if bm.prop_sprites.size() + bm.floor_sprites.size() != 1 or bm.skipped != 2:
		r = "%d sprites, %d skipped; want 1 and 2" % [bm.prop_sprites.size() + bm.floor_sprites.size(), bm.skipped]
	bm.free()
	return r

## Colliders = the walk grid: every blocked cell is covered, no open cell is, and every prop box lies on blocked
## cells (so prop boxes need no colliders of their own). Physics is checked on a window round the wood bridge.
func test_big_map_colliders_match_walk_grid() -> String:
	var g := await _ground()
	var w: BigWorld = g.big
	var bm: BigMap = g.big_map
	var cover := PackedByteArray()
	cover.resize(w.cols * w.rows)
	var inside := 0
	for r in bm.collider_rects():
		if r.position.x < 0 or r.position.y < 0 or r.end.x > w.size.x or r.end.y > w.size.y:
			if r.intersects(Rect2(Vector2.ZERO, w.size)): return "wall %s overlaps the map" % r
			continue
		inside += 1
		for cy in range(int(r.position.y) / w.cell, int(r.end.y) / w.cell):
			for cx in range(int(r.position.x) / w.cell, int(r.end.x) / w.cell):
				if cover[cy * w.cols + cx] == 1: return "cell (%d,%d) covered twice" % [cx, cy]
				cover[cy * w.cols + cx] = 1
	if bm.box_count != inside + 4: return "box_count %d, want %d merged + 4 walls" % [bm.box_count, inside]
	for cy in w.rows:
		for cx in w.cols:
			if (cover[cy * w.cols + cx] == 1) != w.cell_blocked(cx, cy):
				return "cell (%d,%d) collider %s, blocked %s" % [cx, cy, cover[cy * w.cols + cx] == 1, w.cell_blocked(cx, cy)]
	for p in w.props():
		var b = p.get("box")
		if b == null: continue
		for cy in range(int(b[1]) / w.cell, (int(b[1]) + int(b[3]) - 1) / w.cell + 1):
			for cx in range(int(b[0]) / w.cell, (int(b[0]) + int(b[2]) - 1) / w.cell + 1):
				if not w.cell_blocked(cx, cy): return "prop %s box %s: cell (%d,%d) open (no collider)" % [p.name, b, cx, cy]
	var space: PhysicsDirectSpaceState2D = g.world.get_world_2d().direct_space_state
	var q := PhysicsPointQueryParameters2D.new()
	q.collision_mask = 1
	for cy in range(200, 250):
		for cx in range(195, 255):
			q.position = Vector2(cx * 8 + 3.5, cy * 8 + 3.5)
			var solid := false
			for hit in space.intersect_point(q, 4):
				if hit.collider == bm.blockers: solid = true
			if solid != w.cell_blocked(cx, cy): return "physics at %s solid %s, blocked %s" % [q.position, solid, not solid]
	return ""

## The river at tile (59,40): walking at it from the nearest open shore east, and north off the wood bridge's
## deck, the hero's feet never touch a blocked (water) cell.
func test_big_map_water_stops_hero() -> String:
	var g := await _ground()
	var w: BigWorld = g.big
	var water := Vector2(59 * 32 + 16, 40 * 32 + 16)
	if not w.blocked_at(water): return "tile (59,40) is open; the test needs water there"
	var cx := int(water.x) / w.cell
	var cy := int(water.y) / w.cell
	while cx < w.cols and not w.roomy(cx, cy): cx += 1
	if cx >= w.cols: return "no open shore east of (59,40)"
	var shore := Vector2(cx * w.cell + 4, cy * w.cell + 4) + Vector2(16, 0)    # a little inland
	var res: Array = await _walk(g, shore, Vector2.LEFT, 120)
	if res[0] != Vector2.INF: return "hero's feet entered a blocked cell at %s walking at the water" % res[0]
	if res[1].x > shore.x - 12: return "hero did not walk to the shore (from %s to %s)" % [shore, res[1]]
	var deck := _deck(w, "bridge_wood")
	if deck == Rect2(): return "no wood bridge deck in world.json"
	var mid := deck.get_center()
	res = await _walk(g, mid, Vector2.UP, 90)
	if res[0] != Vector2.INF: return "hero walked off the deck into the water at %s" % res[0]
	if w.blocked_at(res[1]): return "hero ended in water at %s" % res[1]
	return ""

## The wood bridge is crossed east to west on foot (physics), staying on the deck.
func test_big_map_cross_wood_bridge() -> String:
	var g := await _ground()
	var w: BigWorld = g.big
	var deck := _deck(w, "bridge_wood")
	var y := deck.get_center().y + 4.0
	var from := Vector2(deck.end.x + 24, y)
	var to_x := deck.position.x - 16
	if _feet_blocked(w, from) or _feet_blocked(w, Vector2(to_x, y)): return "bridge ends %s / %s not open for the hero" % [from, Vector2(to_x, y)]
	var res: Array = await _walk(g, from, Vector2.LEFT, 600, func(p): return p.x <= to_x)
	if res[1].x > to_x: return "hero stuck at %s crossing the bridge (want x <= %.0f)" % [res[1], to_x]
	if res[0] != Vector2.INF: return "hero's feet touched a blocked cell at %s on the bridge" % res[0]
	return ""

static func _deck(w: BigWorld, prefix: String) -> Rect2:
	for p in w.props():
		if String(p.name).begins_with(prefix) and p.get("deck") != null:
			return Rect2(p.deck[0], p.deck[1], p.deck[2], p.deck[3])
	return Rect2()

## Last in the file: frees the shared test ground.
func test_big_map_zz_free() -> String:
	if _g != null:
		_g.queue_free()
		await tree.process_frame
		_g = null
	if FileAccess.file_exists(TMP_SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SAVE))
	return ""
