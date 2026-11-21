class_name WalkGrid
extends RefCounted
## A blocked-cell walk grid shared by PaintedLayout (one room) and BigWorld (the big map): what blocks, whether a
## hero-sized body fits, whether places reach each other on foot, and the route-finding grid. Pure rules.
## Cells are kept as packed bits (bit i = y*cols+x is (_bits[i >> 3] >> (i & 7)) & 1, 1 = blocked), the same
## encoding as world.json "walk". Anything outside the grid counts as blocked.

## Free cells a body needs around its feet cell (x: ±1, y: -2..0): the hero's 20×16 feet box sits at
## y-14..y+2, so it can touch three rows.
const CLEAR_X := 1
const CLEAR_UP := 2

var size := Vector2.ZERO
var cell := 8
var cols := 0
var rows := 0
var hero_spawn := Vector2.ZERO
var _bits := PackedByteArray()     # packed blocked bits, (cols*rows + 7) / 8 bytes
var _roomy := PackedByteArray()    # cols*rows, 1 = roomy; built on first use (_roomy_grid)

## Sets an all-open grid of c x r cells.
func _reset_cells(c: int, r: int) -> void:
	cols = c
	rows = r
	_bits = PackedByteArray()
	_bits.resize((c * r + 7) / 8)
	_roomy = PackedByteArray()

## Marks cell index i (y*cols+x) blocked (while building the grid).
func _mark(i: int) -> void:
	_bits[i >> 3] |= 1 << (i & 7)
	if not _roomy.is_empty(): _roomy = PackedByteArray()

## Takes packed bits as they are; false (grid unchanged) when the length does not fit c x r.
func _take_bits(c: int, r: int, bits: PackedByteArray) -> bool:
	if c <= 0 or r <= 0 or bits.size() != (c * r + 7) / 8: return false
	cols = c
	rows = r
	_bits = bits
	_roomy = PackedByteArray()
	return true

func size_px() -> Vector2:
	return size

func cell_blocked(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= cols or y >= rows: return true
	var i := y * cols + x
	return ((_bits[i >> 3] >> (i & 7)) & 1) == 1

## Outside the map (or not a finite point) counts as blocked.
func blocked_at(p: Vector2) -> bool:
	if not p.is_finite(): return true
	if p.x < 0 or p.y < 0 or p.x >= size.x or p.y >= size.y: return true
	return cell_blocked(int(p.x) / cell, int(p.y) / cell)

## Room for a hero-sized body with its feet in cell x, y (cells x-CLEAR_X..x+CLEAR_X, y-CLEAR_UP..y all open).
func roomy(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= cols or y >= rows: return false
	return _roomy_grid()[y * cols + x] == 1

## The roomy flag of every cell, worked out once: a row pass (x-1..x+1 open) then a column pass (y-2..y).
func _roomy_grid() -> PackedByteArray:
	if _roomy.size() == cols * rows: return _roomy
	var h := PackedByteArray()
	h.resize(cols * rows)
	for y in rows:
		var row := y * cols
		for x in cols:
			var ok := 1
			for dx in range(-CLEAR_X, CLEAR_X + 1):
				if cell_blocked(x + dx, y):
					ok = 0
					break
			h[row + x] = ok
	var r := PackedByteArray()
	r.resize(cols * rows)
	for y in range(CLEAR_UP, rows):
		for x in cols:
			var ok := 1
			for dy in range(-CLEAR_UP, 1):
				if h[(y + dy) * cols + x] == 0:
					ok = 0
					break
			r[y * cols + x] = ok
	_roomy = r
	return _roomy

## Whether a hero-sized body can walk from a to b (4-way flood over roomy cells).
func reachable(a: Vector2, b: Vector2) -> bool:
	var start := Vector2i(int(a.x) / cell, int(a.y) / cell)
	var goal := Vector2i(int(b.x) / cell, int(b.y) / cell)
	if not roomy(start.x, start.y) or not roomy(goal.x, goal.y): return false
	var rg := _roomy_grid()
	var seen := PackedByteArray()
	seen.resize(cols * rows)
	var queue: Array[Vector2i] = [start]
	seen[start.y * cols + start.x] = 1
	var i := 0
	while i < queue.size():
		var c := queue[i]
		i += 1
		if c == goal: return true
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + o
			if n.x < 0 or n.y < 0 or n.x >= cols or n.y >= rows: continue
			var k := n.y * cols + n.x
			if seen[k] == 1 or rg[k] == 0: continue
			seen[k] = 1
			queue.append(n)
	return false

## A walk grid for route finding: a cell is solid unless a hero-sized body fits with its feet there.
## Building it walks every cell: make it once per grid and share it (wolf packs keep one `nav`).
func make_nav() -> AStarGrid2D:
	var g := AStarGrid2D.new()
	g.region = Rect2i(0, 0, cols, rows)
	g.cell_size = Vector2(cell, cell)
	g.offset = Vector2(cell, cell) / 2.0
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.update()
	var rg := _roomy_grid()
	for y in rows:
		var row := y * cols
		var x := 0
		while x < cols:       # solid runs along the row in one call each
			if rg[row + x] == 1:
				x += 1
				continue
			var x0 := x
			while x < cols and rg[row + x] == 0: x += 1
			g.fill_solid_region(Rect2i(x0, y, x - x0, 1), true)
	return g
