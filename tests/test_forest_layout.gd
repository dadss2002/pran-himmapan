extends RefCounted
## ForestLayout: corner masks, blocking, and the real map file passing its own check.

const TILES := {"water": {}, "stone": {}, "forest_floor": {}}
const PROPS := {"tree": {"size": [96, 128], "feet": [48, 120], "foot": [20, 10], "flat": false},
	"flowers": {"size": [32, 32], "feet": [16, 16], "foot": null, "flat": true}}

func _small(terrain: Array, extra := {}) -> ForestLayout:
	var d := {"cells": [10, 8], "terrain": terrain, "hero_spawn": [16, 16], "pack_homes": []}
	d.merge(extra, true)
	return ForestLayout.from_dict(d, TILES, PROPS)

func test_mask_bits():
	# water on the 2×2 corners (3..4, 3..4) → cell 3,3 is fully water, its neighbours partial
	var l := _small([{"t": "water", "rect": [3, 3, 1, 1]}])
	var want := {Vector2i(3, 3): 15, Vector2i(2, 2): 1, Vector2i(3, 2): 3, Vector2i(4, 2): 2,
		Vector2i(2, 3): 5, Vector2i(4, 3): 10, Vector2i(2, 4): 4, Vector2i(3, 4): 12, Vector2i(4, 4): 8,
		Vector2i(6, 6): 0}
	for k in want:
		var c := l.cell(k.x, k.y)
		if int(c.mask) != want[k]: return "cell %s mask %d, want %d" % [k, c.mask, want[k]]
		if want[k] > 0 and c.terrain != "water": return "cell %s terrain %s" % [k, c.terrain]
	if l.cell(6, 6).terrain != "grass": return "grass cell"
	return ""

func test_three_terrains_rejected():
	var l := _small([{"t": "water", "rect": [2, 2, 2, 2]}, {"t": "stone", "rect": [4, 2, 2, 2]}])
	var errs := l.validate()
	for e in errs:
		if e.contains("touches two terrains"): return ""
	return "no error for stone touching water: %s" % [errs]

func test_blocked_rules():
	var l := _small([{"t": "water", "rect": [1, 1, 3, 3]}],
		{"walk": [[64, 32, 32, 96]], "props": [{"id": "tree", "at": [256, 160]}, {"id": "flowers", "at": [64, 220]}]})
	var r := ""
	if not l.blocked_at(Vector2(1.5, 2.5) * 32): r = "pond not blocked"
	elif l.blocked_at(Vector2(2.5, 2.5) * 32): r = "bridge column blocked"
	elif l.blocked_at(Vector2(0.5, 0.5) * 32): r = "corner with one water corner blocked"
	elif not l.blocked_at(Vector2(256, 155)): r = "tree feet not blocked"
	elif l.blocked_at(Vector2(256, 165)): r = "below the tree feet blocked"
	elif l.blocked_at(Vector2(64, 215)): r = "flowers block"
	elif not l.blocked_at(Vector2(-1, 40)): r = "left of map not blocked"
	elif not l.blocked_at(Vector2(40, 8 * 32)): r = "bottom edge not blocked"
	return r

func test_layout_valid():
	var l := ForestLayout.open()
	if l.cols != 60 or l.rows != 40: return "map %dx%d cells" % [l.cols, l.rows]
	var errs := l.validate()
	return "" if errs.is_empty() else "%d problems, first: %s" % [errs.size(), errs.slice(0, 3)]

func test_map_matches_balance_size():
	var l := ForestLayout.open()
	var s: Array = Balance.data()["map_size"]
	return "" if l.size_px() == Vector2(s[0], s[1]) else "map %s vs balance %s" % [l.size_px(), s]
