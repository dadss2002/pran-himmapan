extends SceneTree
## M4d: dumps RoomLayout examples and statistics for tools/layout_examples.py.
## Usage: godot --headless --script tools/layout_examples.gd -- OUT.json [SEEDS=200] [EXAMPLES=3,17,42]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "user://layout_examples.json"
	var n := int(args[1]) if args.size() > 1 else 200
	var examples: Array = []
	for s in (String(args[2]) if args.size() > 2 else "3,17,42").split(","): examples.append(int(s))
	var rs := RoomSet.open()
	var t := rs.exit_table()
	var stats := {"seeds": n, "fallback": 0, "loops": {}, "dead_ends": {}, "boss_steps": {}}
	for s in n:
		var l := RoomLayout.generate(s, t)
		if l.fallback:
			stats.fallback += 1
			continue
		var lo := str(RoomLayout.loops(l))
		var de := str(RoomLayout.dead_ends(l, t).size())
		var bs := str(RoomLayout.distances(l.pos, l.links).get("e0", -1))
		stats.loops[lo] = stats.loops.get(lo, 0) + 1
		stats.dead_ends[de] = stats.dead_ends.get(de, 0) + 1
		stats.boss_steps[bs] = stats.boss_steps.get(bs, 0) + 1
	var ex: Array = []
	for s in examples:
		var l := RoomLayout.generate(s, t)
		var pos := {}
		for id in l.pos: pos[id] = [l.pos[id].x, l.pos[id].y]
		ex.append({"seed": s, "pos": pos, "links": l.links, "fallback": l.fallback,
			"dead_ends": RoomLayout.dead_ends(l, t), "loops": RoomLayout.loops(l)})
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"stats": stats, "examples": ex}, " "))
	f.close()
	print(JSON.stringify(stats))
	quit()
