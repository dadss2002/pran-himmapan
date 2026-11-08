extends SceneTree
## M4d follow-up 3: bakes data/piles_bank.json (PileBank), SIZE monster placements per forest room, x1-x3 and
## each e0 monster set, made by the game's own placement (MonsterPiles.place) with seeds 0, 1, 2, ... Every
## entry is read back exactly as the game reads it (JSON text, PileBank.decode) and must pass the placement
## test's _check (tests/test_monster_piles.gd: kinds/counts, half in piles, open ground, arrival floors,
## in-pile spacing, pile/single gaps); homes are rounded to 0.5 px unless that breaks the entry (STEPS). A
## seed that falls back to the built homes (or fails even unrounded) is skipped and the next seed is used
## (listed in "seeds").
## Run after any change to data/rooms.json (tools/painted_rooms.py), monster kinds' aggro/temper/collision or
## the MonsterPiles rules; tests/test_monster_piles.gd fails on a stale bank.
## Usage: godot --headless --script tools/bake_piles.gd [-- OUT.json]

## [home rounding px, angle rounding rad] tried in turn (0 = unrounded).
const STEPS := [[0.5, 0.001], [0.1, 0.001], [0.01, 0.0001], [0.001, 0.00001], [0.0, 0.0]]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else ProjectSettings.globalize_path(PileBank.PATH)
	var rooms := RoomSet.open()
	var checker = load("res://tests/test_monster_piles.gd").new()
	var t_all := Time.get_ticks_msec()
	var lines: Array[String] = []
	var room_ids := rooms.ids()
	for ri in room_ids.size():
		var id: String = room_ids[ri]
		var sets: Array = rooms.room(id).get("monster_sets", [])
		var lists: Array = sets if not sets.is_empty() else [rooms.room(id).get("monsters", [])]
		var set_lines: Array[String] = []
		for li in lists.size():
			var groups: Array = lists[li]
			var t0 := Time.get_ticks_msec()
			var entries: Array[String] = []
			var seeds: Array[String] = []
			var skipped: Array = []
			var finer := {}               # entries per rounding step
			var s := 0
			while entries.size() < PileBank.SIZE:
				if s >= PileBank.SIZE * 4:
					printerr("%s set %d: only %d good placements in %d seeds; skipped %s" % [id, li, entries.size(), s, skipped])
					quit(1)
					return
				var piles := MonsterPiles.place(rooms.pile_room(id), groups, s)
				if MonsterPiles.fell_back(piles):
					skipped.append([s, "fell back"])
				else:
					# rounded to 0.5 px first; an entry the rounding breaks (settled right on a gap or a cell
					# border) is stored finer, at last unrounded
					var err := ""
					for step in STEPS:
						var txt := _entry_text(PileBank.encode(piles, step[0], step[1]))
						var back := PileBank.decode(JSON.parse_string(txt), groups)
						err = checker._check(rooms, id, groups, back, s)
						if err == "":
							entries.append(txt)
							seeds.append(str(s))
							finer[step[0]] = int(finer.get(step[0], 0)) + 1
							break
					if err != "": skipped.append([s, err])
				s += 1
			var label := id if lists.size() == 1 else "%s set %d" % [id, li]
			print("  %-10s %d placements from seeds 0..%d, skipped %s, per rounding step %s (%d ms)" % [label,
				entries.size(), s - 1, skipped if not skipped.is_empty() else "none", finer, Time.get_ticks_msec() - t0])
			set_lines.append('  {"set":%d,"hash":"%s","seeds":[%s],"p":[\n   %s]}' % [li, rooms.pile_hash(id, groups),
				",".join(seeds), ",\n   ".join(entries)])
		lines.append('"%s":[\n%s]' % [id, ",\n".join(set_lines)])
	var note := "Baked by tools/bake_piles.gd (M4d follow-up 3); do not edit. Rebake after changing data/rooms.json, monster aggro/temper/collision or MonsterPiles rules."
	var text := '{"version":%d,"size":%d,"note":%s,"rooms":{\n%s}}\n' % [PileBank.VERSION, PileBank.SIZE, JSON.stringify(note), ",\n".join(lines)]
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		printerr("cannot write %s" % out_path)
		quit(1)
		return
	f.store_string(text)
	f.close()
	print("wrote %s: %d bytes, %d ms" % [out_path, text.length(), Time.get_ticks_msec() - t_all])
	quit(0)

## One entry as compact JSON: ints as ints, other numbers with up to 10 decimals, no trailing ".0".
func _entry_text(e: Array) -> String:
	var parts: Array[String] = []
	for v in e:
		var t := str(v) if typeof(v) == TYPE_INT else String.num(float(v), 10)
		if t.ends_with(".0"): t = t.left(-2)
		parts.append(t)
	return "[" + ",".join(parts) + "]"
