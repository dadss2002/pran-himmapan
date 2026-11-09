extends RefCounted
## Save hardening (docs/superpowers/specs/2026-11-09-save-hardening.md, owner-approved 2026-11-09):
## HMAC signature (Q1 a wrong one = broken save), old unsigned version-3 saves accepted once and re-signed (Q2 a),
## any value out of range fails the whole save (Q3 a), gold <= save.gold_cap (Q4), unknown bag / waypoint ids
## fail, files over save.max_bytes are refused before parsing, the old "fog" key is still dropped.
## A save the game itself writes must always load: round trips at many states, also random loot-filled bags.

const TMP := "user://test_save_h.json"
const BAD := "user://test_save_h.bad.json"

func _clean() -> void:
	for p in [TMP, TMP + ".tmp", SaveGame.marker_path(TMP)] + _bads():
		if FileAccess.file_exists(p): DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

func _raw() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(TMP))

func _write_text(t: String) -> void:
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string(t)
	f.close()

## Writes `d` as an old (pre-signing) version-3 file on a device that never wrote a signed save.
func _write_old_v3(d: Dictionary) -> void:
	var old := d.duplicate(true)
	old.erase("sig")
	old["version"] = 3
	_clean()
	_write_text(JSON.stringify(old))

## true when the load threw the file away: a new game, the file kept as .bad.json.
func _broken(s: Dictionary) -> bool:
	return int(s.level) == 1 and int(s.exp) == 0 and FileAccess.file_exists(BAD) and not FileAccess.file_exists(TMP)

## Saves `st` with the game's own save(), loads it back. {s: loaded state, bad: thrown away}.
func _cycle(st: Dictionary) -> Dictionary:
	_clean()
	var ok := SaveGame.save(st, TMP)
	var s := SaveGame.load_or_new(TMP)
	var out := {"s": s, "bad": FileAccess.file_exists(BAD), "saved": ok}
	_clean()
	return out

func _cap_gem(type: String, level: int, exp: int) -> Dictionary:
	var opts := []
	for k in ["dmg_pct", "cd_cut", "mp_cut", "crit"]:
		opts.append({"k": k, "v": float(Balance.data()["gem_options"][k].max)})
	var g := {"type": type, "level": level, "exp": exp, "rarity": "legend", "opts": opts}
	if type == "element": g["element"] = "ice"
	return g

func _top_item(base: String, plus := 0) -> Dictionary:
	var opts := []
	var ref := int(Balance.num("option_ref_level"))
	for k in ["crit", "hp", "mp_regen", "gold_pct"]:
		opts.append({"k": k, "v": Gear.option_range(k, ref).y})
	var it := {"base": base, "rarity": "legend", "level": ref if bool(Gear.base(base).get("from_source", false)) else Gear.req_level(base), "opts": opts}
	if Enhance.can(it): it["plus"] = plus
	return it

func _stones() -> Array:
	return Array(RoomSet.open().waypoint_ids())

func _fitting_all(skill: String) -> Array:
	var out := []
	for t in Gem.types():
		if Gem.fits(String(t), skill): out.append(String(t))
	return out

## A state with everything at its top: max level, gold cap, a full bag (+max legend gear, legend gems at the cap,
## full stacks), every socket filled, every stone unlocked.
func _rich() -> Dictionary:
	var st := SaveGame.new_state()
	st.level = Progression.cap()
	st.exp = 0
	var inv := Inventory.new()
	inv.gold = int(Balance.num("save.gold_cap"))
	inv.add("potion_hp", 99); inv.add("potion_mp", 99); inv.add("ore_himmapan", 99); inv.add("gem_split", 99)
	inv.add("gem_element", 1)
	for base in Balance.data()["gear"]: inv.add_item(_top_item(String(base), Enhance.max_plus()))
	for t in Gem.types():
		if inv.has_free_slot(): inv.add_gem(_cap_gem(String(t), Gem.cap(), 0))
	while inv.has_free_slot(): inv.add_gem(_cap_gem("multiply", Gem.cap() - 1, Gem.exp_to_next(Gem.cap() - 1) - 1))
	st.inventory = inv.to_dict()
	var eq := {}
	for s in Gear.SLOTS: eq[s] = null
	eq.bow = _top_item("bow_buffalo_horn", Enhance.max_plus())
	eq.armor = _top_item("armor_wolf_leather", Enhance.max_plus())
	eq.ring = _top_item("ring")
	eq.necklace = _top_item("necklace")
	st.equipped = eq
	# M5b Task 1: every slot filled with a different fitting type (the game never puts two of one type in a skill)
	# on every skill that exists (gems on a skill with no numbers / not unlocked are refused, owner 2026-11-09).
	var sk := {}
	for id in Balance.data()["skill_labels"]:
		if not Skills.exists(String(id)): continue
		sk[id] = []
		var fit := _fitting_all(String(id))
		for i in Balance.data()["gem_slots"].size(): sk[id].append(_cap_gem(fit[i], 1 + i * 6, i))
	st.skills = sk
	st.waypoints = _stones()
	st["room"] = "c2r1"
	st["seed"] = 2147483647
	return st

## Loaded state equals what was saved (numbers to 1e-6; items as clean_item writes them).
func _same(a, b) -> bool:
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]: return absf(float(a) - float(b)) < 1e-6
	if typeof(a) == TYPE_DICTIONARY and typeof(b) == TYPE_DICTIONARY:
		if a.size() != b.size(): return false
		for k in a:
			if not b.has(k) or not _same(a[k], b[k]): return false
		return true
	if typeof(a) == TYPE_ARRAY and typeof(b) == TYPE_ARRAY:
		if a.size() != b.size(): return false
		for i in a.size():
			if not _same(a[i], b[i]): return false
		return true
	if typeof(a) in [TYPE_STRING, TYPE_STRING_NAME] and typeof(b) in [TYPE_STRING, TYPE_STRING_NAME]: return String(a) == String(b)
	return typeof(a) == typeof(b) and a == b

func _check_same(st: Dictionary, s: Dictionary) -> String:
	if int(s.level) != int(st.level) or int(s.exp) != int(st.exp): return "level/exp %s/%s, saved %s/%s" % [s.level, s.exp, st.level, st.exp]
	if not _same(st.inventory, s.inventory): return "bag differs:\n%s\n%s" % [st.inventory, s.inventory]
	for sl in Gear.SLOTS:
		var want = SaveGame.clean_item(st.equipped[sl]) if st.equipped.get(sl) != null else null
		if not _same(want, s.equipped[sl]): return "%s differs: %s vs %s" % [sl, want, s.equipped[sl]]
	if not _same(st.get("skills", {}), s.skills): return "sockets differ %s vs %s" % [st.get("skills"), s.skills]
	if not _same(st.get("waypoints", []), s.waypoints): return "waypoints %s vs %s" % [st.get("waypoints"), s.waypoints]
	return ""

## The game's own saves always come back: signed (version 4, "sig"), not thrown away, unchanged; saving the
## loaded state again loads again.
func test_signed_round_trip_many_states():
	var states := {}
	states.fresh = SaveGame.new_state()
	var high := SaveGame.new_state()
	high.level = Progression.cap() - 1
	high.exp = Progression.exp_to_next(Progression.cap() - 1) - 1
	states.high = high
	var top := SaveGame.new_state()
	top.level = Progression.cap()
	top.exp = 0
	states.max_level = top
	states.rich = _rich()
	var wp := SaveGame.new_state()
	wp.waypoints = _stones()
	states.waypoints = wp
	for name in states:
		var st: Dictionary = states[name]
		_clean()
		if not SaveGame.save(st, TMP): return "%s: save failed" % name
		var raw := _raw()
		if int(raw.get("version", -1)) != SaveGame.VERSION or typeof(raw.get("sig")) != TYPE_STRING or String(raw.sig).length() != 64:
			_clean()
			return "%s: file not signed v%d: version %s sig %s" % [name, SaveGame.VERSION, raw.get("version"), raw.get("sig")]
		var s := SaveGame.load_or_new(TMP)
		if FileAccess.file_exists(BAD): _clean(); return "%s: the game's own save was thrown away" % name
		var r := _check_same(st, s)
		if r != "": _clean(); return "%s: %s" % [name, r]
		if not SaveGame.save(s, TMP): _clean(); return "%s: saving the loaded state failed" % name
		var s2 := SaveGame.load_or_new(TMP)
		if FileAccess.file_exists(BAD): _clean(); return "%s: second round thrown away" % name
		r = _check_same(st, s2)
		_clean()
		if r != "": return "%s (2nd round): %s" % [name, r]
	return ""

## Bags filled from real loot rolls (rolled option floats such as 0.037), random gear worn, random level/EXP/gold:
## every one loads unchanged.
func test_random_loot_saves_always_load():
	var rng := RandomNumberGenerator.new()
	var kinds: Array = Balance.data()["loot"].keys()
	for i in 150:
		rng.seed = 9100 + i
		var st := SaveGame.new_state()
		var inv := Inventory.new()
		inv.from_dict(st.inventory)
		var eq: Dictionary = st.equipped
		var tries := 0
		while inv.has_free_slot() and tries < 400:
			tries += 1
			for it in Loot.roll(String(kinds[rng.randi_range(0, kinds.size() - 1)]), rng.randi_range(1, 10), rng, rng.randf() < 0.3):
				if it.has("item"):
					if rng.randf() < 0.3: eq[Gear.slot_of(String(it.item.base))] = it.item
					else: inv.add_item(it.item)
				elif it.has("gem"):
					for k in 3: Gem.add_exp(it.gem, rng.randi_range(0, 3000))
					inv.add_gem(it.gem)
				else: inv.add(String(it.id), int(it.count) * 50)
		if eq.bow != null and Enhance.can(eq.bow): eq.bow["plus"] = rng.randi_range(0, Enhance.max_plus())
		st.inventory = inv.to_dict()
		st.equipped = eq
		st.level = rng.randi_range(1, Progression.cap())
		st.exp = 0 if st.level >= Progression.cap() else rng.randi_range(0, Progression.exp_to_next(st.level) - 1)
		var c := _cycle(st)
		if c.bad or not c.saved: return "seed %d: own save thrown away (saved %s)" % [9100 + i, c.saved]
		var r := _check_same(st, c.s)
		if r != "": return "seed %d: %s" % [9100 + i, r]
	return ""

## Every leaf of a signed save changed by one small step (number -1, or +0.001 below 1; string +"x"; sig hex
## flipped): broken -> .bad.json, new game (Q1 a). Most of these edits stay in range, so the same edits re-signed
## with the key load for over a third of them: for those the signature, not the range checks, is what stops them.
func test_any_changed_field_breaks_the_save():
	_clean()
	SaveGame.save(_rich(), TMP)
	var raw := _raw()
	var leaves := []
	_leaves(raw, [], leaves)
	if leaves.size() < 100: return "only %d leaves" % leaves.size()
	var resigned_ok := 0
	for path in leaves:
		var d := raw.duplicate(true)
		_mutate(d, path)
		_clean()
		_write_text(JSON.stringify(d))
		var s := SaveGame.load_or_new(TMP)
		if not _broken(s): _clean(); return "changing %s was accepted" % [path]
		if path != ["sig"]:
			d.sig = SaveGame.signature(d)
			_clean()
			_write_text(JSON.stringify(d))
			if not _broken(SaveGame.load_or_new(TMP)): resigned_ok += 1
	_clean()
	return "" if resigned_ok * 3 > leaves.size() else "only %d of %d edits stay in range: the test does not reach the signature" % [resigned_ok, leaves.size()]

func _leaves(v, path: Array, out: Array) -> void:
	if typeof(v) == TYPE_DICTIONARY:
		for k in v: _leaves(v[k], path + [k], out)
	elif typeof(v) == TYPE_ARRAY:
		for i in v.size(): _leaves(v[i], path + [i], out)
	else: out.append(path)

func _mutate(d, path: Array) -> void:
	var cur = d
	for i in path.size() - 1: cur = cur[path[i]]
	var k = path.back()
	var v = cur[k]
	match typeof(v):
		TYPE_INT, TYPE_FLOAT: cur[k] = float(v) - 1.0 if float(v) >= 1.0 else float(v) + 0.001
		TYPE_STRING:
			if k is String and k == "sig": cur[k] = ("1" if String(v)[0] == "0" else "0") + String(v).substr(1)
			else: cur[k] = String(v) + "x"
		TYPE_NIL: cur[k] = 0
		TYPE_BOOL: cur[k] = not v

## One character of the file text changed (every letter / digit, one at a time): never accepted.
func test_any_changed_character_breaks_the_save():
	var st := SaveGame.new_state()
	st.level = 6
	st.exp = 123
	var inv := Inventory.new()
	inv.from_dict(st.inventory)
	inv.gold = 4321
	inv.add_item({"base": "ring", "rarity": "epic", "level": 7, "opts": [{"k": "crit", "v": 0.037}, {"k": "hp", "v": 31}, {"k": "mp_regen", "v": 0.9}]})
	inv.add_gem({"type": "element", "level": 4, "exp": 17, "rarity": "good", "opts": [{"k": "crit", "v": 0.031}], "element": "fire"})
	st.inventory = inv.to_dict()
	st.equipped.bow["plus"] = 3
	st.skills = {"piercing": [{"type": "multiply", "level": 2, "exp": 5, "rarity": "rare", "opts": [{"k": "dmg_pct", "v": 0.05}, {"k": "crit", "v": 0.02}]}]}
	st.waypoints = ["c1r1", "c2r0"]
	_clean()
	SaveGame.save(st, TMP)
	var text := FileAccess.get_file_as_string(TMP)
	var tried := 0
	for i in text.length():
		var c := text.unicode_at(i)
		var to := -1
		if c >= 48 and c <= 57: to = 48 + (c - 48 + 1) % 10
		elif c >= 97 and c <= 122: to = 97 + (c - 97 + 1) % 26
		elif c >= 65 and c <= 90: to = 65 + (c - 65 + 1) % 26
		if to < 0: continue
		tried += 1
		_clean()
		_write_text(text.substr(0, i) + String.chr(to) + text.substr(i + 1))
		var s := SaveGame.load_or_new(TMP)
		if not _broken(s): _clean(); return "changing char %d ('%s' in ...%s...) was accepted" % [i, String.chr(c), text.substr(maxi(0, i - 12), 24)]
	_clean()
	return "" if tried > 300 else "only %d characters tried" % tried

## A version-4 save with its "sig" removed (or not a string) is broken.
func test_v4_without_sig_is_broken():
	for bad_sig in [null, 12, ""]:
		_clean()
		SaveGame.save(SaveGame.new_state(), TMP)
		var raw := _raw()
		if bad_sig == null: raw.erase("sig")
		else: raw.sig = bad_sig
		_clean()
		_write_text(JSON.stringify(raw))
		var s := SaveGame.load_or_new(TMP)
		if not _broken(s): _clean(); return "a v4 save with sig %s loaded" % [bad_sig]
	_clean()
	return ""

## Q2 a: an old unsigned version-3 save (made before signing) passes the full checks, loads, and the file on disk
## is at once version 4 and signed (and loads again). Once this device has written a signed save, an unsigned
## version-3 file is no longer accepted ("once").
func test_old_v3_unsigned_save_is_signed_once():
	var st := SaveGame.new_state()
	st.level = 7
	st.exp = 50
	st.inventory.gold = 900
	st.waypoints = ["c0r2"]
	_write_old_v3(st)
	var s := SaveGame.load_or_new(TMP)
	var r := ""
	if FileAccess.file_exists(BAD): r = "a valid old v3 save was thrown away"
	elif int(s.level) != 7 or int(s.exp) != 50 or int(s.inventory.gold) != 900 or s.waypoints != ["c0r2"]: r = "progress lost: %s" % s
	if r == "":
		var raw := _raw()
		if int(raw.version) != SaveGame.VERSION or typeof(raw.get("sig")) != TYPE_STRING: r = "file on disk not re-signed: v%s sig %s" % [raw.version, raw.get("sig")]
		elif int(SaveGame.load_or_new(TMP).level) != 7 or FileAccess.file_exists(BAD): r = "the re-signed file did not load"
	if r == "":
		var old := _raw()                       # same device: a hand-made unsigned v3 file is refused now
		old.erase("sig")
		old.version = 3
		old.inventory.gold = 9000
		_write_text(JSON.stringify(old))
		if not _broken(SaveGame.load_or_new(TMP)): r = "an unsigned v3 file was accepted after this device signed a save"
	_clean()
	return r

## Q2 + Q3: an old unsigned version-3 save with any value out of range is broken (not clamped).
func test_old_v3_unsigned_out_of_range_is_broken():
	var cases := [
		func(d): d.level = Progression.cap() + 1,
		func(d): d.exp = Progression.exp_to_next(int(d.level)),
		func(d): d.inventory.gold = int(Balance.num("save.gold_cap")) + 1,
		func(d): d.equipped.bow["plus"] = Enhance.max_plus() + 1,
		func(d): d.waypoints = ["c9r9"],
	]
	for i in cases.size():
		var st := SaveGame.new_state()
		st.level = 3
		cases[i].call(st)
		_write_old_v3(st)
		var s := SaveGame.load_or_new(TMP)
		var b := _broken(s)
		_clean()
		if not b: return "old v3 case %d loaded: %s" % [i, s]
	return ""

## Old v1 / v2 saves still migrate (and end up signed v4 on disk).
func test_v1_v2_migrate_and_get_signed():
	for v in [1, 2]:
		_clean()
		var d := {"version": v, "level": 4, "exp": 10, "inventory": {"gold": 50, "slots": [{"id": "potion_hp", "count": 3}]}}
		if v == 2: d["equipped"] = SaveGame.start_equipped()
		_write_text(JSON.stringify(d))
		var s := SaveGame.load_or_new(TMP)
		var raw := _raw() if FileAccess.file_exists(TMP) else {}
		var bad := FileAccess.file_exists(BAD)
		_clean()
		if bad or int(s.level) != 4: return "v%d save rejected: %s" % [v, s]
		if int(raw.get("version", -1)) != SaveGame.VERSION or not raw.has("sig"): return "v%d not re-signed: %s" % [v, raw]
	return ""

func _loads(mut: Callable) -> bool:
	var st := SaveGame.new_state()
	st.level = 3
	mut.call(st)
	var c := _cycle(st)
	return not c.bad and int(c.s.level) == int(st.level)

func _ring(lvl, v, rarity := "good") -> Callable:
	return _ring_mut.bind(lvl, v, rarity)

func _gem(lvl, exp, n := 1) -> Callable:
	return _gem_mut.bind(lvl, exp, n)

func _ring_mut(d: Dictionary, lvl, v, rarity: String) -> void:
	d.equipped.ring = {"base": "ring", "rarity": rarity, "level": lvl, "opts": [{"k": "crit", "v": v}]}

func _gem_mut(d: Dictionary, lvl, exp, n: int) -> void:
	var opts := []
	for k in ["dmg_pct", "cd_cut", "mp_cut", "crit", "gem_exp"].slice(0, n): opts.append({"k": k, "v": float(Balance.data()["gem_options"][k].min)})
	d.inventory.slots.append({"id": "gem_split", "count": 1, "gem": {"type": "split", "level": lvl, "exp": exp, "rarity": "good", "opts": opts}})

## Q3 a: each range check, pass and fail (all written with the game's own signed save()).
func test_range_checks_pass_and_fail():
	var cap := Progression.cap()
	var ref := int(Balance.num("option_ref_level"))
	var top := Gear.option_range("crit", ref).y
	var gold_cap := int(Balance.num("save.gold_cap"))
	var good := {
		"item level 1": _ring(1, 0.03), "item level max": _ring(ref, 0.03),
		"option at the top": _ring(ref, top), "option within float tolerance": _ring(ref, top + 0.001), "option 0": _ring(ref, 0.0),
		"player level cap": func(d): d.level = cap; d.exp = 0,
		"player level 1": func(d): d.level = 1; d.exp = Progression.exp_to_next(1) - 1,
		"exp 0": func(d): d.exp = 0, "exp next-1": func(d): d.exp = Progression.exp_to_next(3) - 1,
		"gold 0": func(d): d.inventory.gold = 0, "gold cap": func(d): d.inventory.gold = gold_cap,
		"known material": func(d): d.inventory.slots.append({"id": "ore_himmapan", "count": 99}),
		"plain gem stack": func(d): d.inventory.slots.append({"id": "gem_leech", "count": 99}),
		"waypoint stones": func(d): d.waypoints = _stones(),
		"no waypoints key": func(d): d.erase("waypoints"),
		"options = rarity count": _ring(5, 0.03, "good"),
		"gem exp next-1": _gem(3, Gem.exp_to_next(3) - 1),
		"gem at cap": _gem(Gem.cap(), 0),
		"bow at +max": func(d): d.equipped.bow["plus"] = Enhance.max_plus(),
		"ring with plus 0": func(d): d.equipped.ring = {"base": "ring", "rarity": "good", "level": 5, "opts": [{"k": "crit", "v": 0.03}], "plus": 0},
	}
	var refused := {
		"item level 0": _ring(0, 0.03), "item level max+1": _ring(ref + 1, 0.03), "item level 99": _ring(99, 0.03),
		"item level 3.5": _ring(3.5, 0.03),
		"option above top": _ring(ref, top + 0.01), "option 9.0": _ring(ref, 9.0), "option negative": _ring(ref, -0.01),
		"more options than the rarity has": func(d): d.equipped.ring = {"base": "ring", "rarity": "good", "level": 5, "opts": [{"k": "crit", "v": 0.03}, {"k": "hp", "v": 20}]},
		"common with an option": _ring(5, 0.03, "common"),
		"player level 0": func(d): d.level = 0,
		"player level cap+1": func(d): d.level = cap + 1; d.exp = 0,
		"player level 2.5": func(d): d.level = 2.5,
		"exp next": func(d): d.exp = Progression.exp_to_next(3),
		"exp 99999": func(d): d.exp = 99999,
		"exp -1": func(d): d.exp = -1,
		"exp 1.5": func(d): d.exp = 1.5,
		"gold cap+1": func(d): d.inventory.gold = gold_cap + 1,
		"gold -1": func(d): d.inventory.gold = -1,
		"gold 10.5": func(d): d.inventory.gold = 10.5,
		"unknown bag id": func(d): d.inventory.slots.append({"id": "sword_of_cheat", "count": 1}),
		"gold as a bag item": func(d): d.inventory.slots.append({"id": "gold", "count": 99}),
		"count 1.5": func(d): d.inventory.slots.append({"id": "potion_hp", "count": 1.5}),
		"unknown waypoint id": func(d): d.waypoints = ["c1r1", "c9r9"],
		"room without a stone": func(d): d.waypoints = ["c0r0"],
		"non-string waypoint": func(d): d.waypoints = [7],
		"waypoints not a list": func(d): d.waypoints = "c1r1",
		"gem exp next": _gem(3, Gem.exp_to_next(3)),
		"gem level cap+1": _gem(Gem.cap() + 1, 0),
		"gem more options than rarity": _gem(3, 0, 2),
		"plus 2.5": func(d): d.equipped.bow["plus"] = 2.5,
		"plus on a ring": func(d): d.equipped.ring = {"base": "ring", "rarity": "good", "level": 5, "opts": [{"k": "crit", "v": 0.03}], "plus": 3},
	}
	for name in good:
		if not _loads(good[name]): return "should load: %s" % name
	for name in refused:
		if _loads(refused[name]): return "should be refused: %s" % name
	return ""

## Every id the game itself can put in the bag is a known id.
func test_every_id_the_game_makes_is_known():
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for s in SaveGame.new_state().inventory.slots:
		if not SaveGame.known_item(String(s.id)): return "start kit id %s unknown" % s.id
	for kind in Balance.data()["loot"]:
		for i in 3000:
			for it in Loot.roll(String(kind), 1 + i % 10, rng, i % 2 == 0):
				if it.id != "gold" and not SaveGame.known_item(String(it.id)): return "loot id %s unknown" % it.id
	for t in Gem.types():
		if not SaveGame.known_item("gem_" + String(t)): return "gem_%s unknown" % t
	for g in Balance.data()["gear"]:
		if not SaveGame.known_item(String(g)): return "gear %s unknown" % g
	if not SaveGame.known_item(String(Balance.data()["enhance"]["ore_id"])): return "ore unknown"
	if SaveGame.known_item("gold") or SaveGame.known_item("_doc") or SaveGame.known_item("gem_zzz"): return "junk ids known"
	return ""

## Q4: the wallet never goes above the cap, so a player can never write a save the loader refuses.
func test_gold_income_clamps_at_cap():
	var cap := int(Balance.num("save.gold_cap"))
	if cap != 9999999: return "save.gold_cap %d, owner chose 9,999,999" % cap
	var inv := Inventory.new()
	inv.gold = cap - 5
	if inv.add("gold", 100) != 0: return "gold must always be picked up"
	if inv.gold != cap: return "gold %d, want the cap %d" % [inv.gold, cap]
	inv.add("gold", 1)
	if inv.gold != cap: return "gold went past the cap: %d" % inv.gold
	inv.gold -= 10
	inv.add("gold", 4)
	if inv.gold != cap - 6: return "gold below the cap should still add: %d" % inv.gold
	return ""

## A file over save.max_bytes is refused before parsing (counts as broken); the biggest save the game can make
## is far below it.
func test_huge_file_refused():
	var max_bytes := int(Balance.num("save.max_bytes"))
	if max_bytes != 256 * 1024: return "save.max_bytes %d, spec says 256 KB" % max_bytes
	var st := SaveGame.new_state()
	st.level = 4
	st["pad"] = "x".repeat(max_bytes)
	_write_old_v3(st)
	var s := SaveGame.load_or_new(TMP)
	if not _broken(s): _clean(); return "a %d-byte file was loaded" % (max_bytes + 100)
	_clean()
	SaveGame.save(_rich(), TMP)
	var size := FileAccess.get_file_as_string(TMP).to_utf8_buffer().size()
	_clean()
	return "" if size * 8 < max_bytes else "the biggest real save is %d bytes" % size

## A version-4 save written on 2026-11-09 (Godot 4.5.1) must load forever: changing SIG_KEY, canonical() or the
## engine's number parsing would otherwise throw away every player's save. If this fails, do not "fix" the
## fixture: keep the old way readable (or migrate) first.
const FIXTURE_V4 := '{"equipped":{"armor":{"base":"armor_trainee","level":1.0,"opts":[],"rarity":"common"},"bow":{"base":"bow_bamboo","level":1.0,"opts":[],"plus":6.0,"rarity":"common"},"necklace":null,"ring":null},"exp":321.0,"inventory":{"gold":12345.0,"slots":[{"count":5.0,"id":"potion_hp"},{"count":3.0,"id":"potion_mp"},{"count":1.0,"id":"ring","item":{"base":"ring","level":7.0,"opts":[{"k":"crit","v":0.037},{"k":"hp","v":31.0},{"k":"mp_regen","v":0.9}],"rarity":"epic"}},{"count":1.0,"gem":{"element":"fire","exp":17.0,"level":4.0,"opts":[{"k":"crit","v":0.031}],"rarity":"good","type":"element"},"id":"gem_element"}]},"level":7.0,"room":"c2r0","seed":123456789.0,"sig":"98b23451d8cb9f4332f108cf3539ec29404389797945dd02d2e207a892e424ca","skills":{"piercing":[{"exp":5.0,"level":2.0,"opts":[{"k":"dmg_pct","v":0.057},{"k":"crit","v":0.02}],"rarity":"rare","type":"multiply"},null]},"version":4.0,"waypoints":["c1r1","c2r0"]}'

func test_frozen_v4_save_still_loads():
	_clean()
	_write_text(FIXTURE_V4)
	var s := SaveGame.load_or_new(TMP)
	var bad := FileAccess.file_exists(BAD)
	_clean()
	if bad: return "the 2026-11-09 signed save no longer loads (key / canonical form / engine changed?)"
	if int(s.level) != 7 or int(s.exp) != 321 or int(s.inventory.gold) != 12345 or s.waypoints != ["c1r1", "c2r0"]: return "loaded %s" % s
	if absf(float(s.inventory.slots[2].item.opts[0].v) - 0.037) > 1e-6 or int(s.equipped.bow.plus) != 6: return "items %s" % [s.inventory.slots]
	return ""

## Old Task 6 saves (version 3, unsigned) may hold "fog": it is dropped (owner 2026-11-08), the rest loads, and
## the re-signed file has no fog.
func test_old_fog_key_still_dropped():
	for junk in ["junk", 12, null, {"c1r1": "zz"}]:
		var st := SaveGame.new_state()
		st.level = 5
		st["fog"] = junk
		_write_old_v3(st)
		var s := SaveGame.load_or_new(TMP)
		var r := ""
		if FileAccess.file_exists(BAD): r = "fog %s threw the save away" % [junk]
		elif s.has("fog") or int(s.level) != 5: r = "fog %s: %s" % [junk, s]
		elif _raw().has("fog"): r = "fog %s written back" % [junk]
		_clean()
		if r != "": return r
	return ""

## Every refused-save copy (<name>.bad.json, <name>.bad.N.json).
func _bads() -> Array:
	var out := []
	for n in SaveGame.BAD_KEEP: out.append(SaveGame.bad_path(TMP, n))
	return out

func _bad_level() -> int:
	var d = JSON.parse_string(FileAccess.get_file_as_string(BAD))
	return int(d.level) if typeof(d) == TYPE_DICTIONARY else -1

## Review 3b8d147 #1: a second refused file never overwrites the first refused copy (a stale old build served from
## cache can move a good v4 save to .bad.json; the next refusal must keep it). Up to BAD_KEEP copies are kept.
func test_refused_saves_never_overwrite_each_other():
	_clean()
	var good := SaveGame.new_state()
	good.level = 9
	SaveGame.save(good, TMP)
	var text := FileAccess.get_file_as_string(TMP)
	var at := text.find("\"sig\":\"") + 7
	_write_text(text.substr(0, at) + ("0" if text[at] != "0" else "1") + text.substr(at + 1))   # tampered: refused
	SaveGame.load_or_new(TMP)
	_write_text("{not json")                                            # refused again
	SaveGame.load_or_new(TMP)
	var r := ""
	if not FileAccess.file_exists(BAD) or not FileAccess.file_exists(SaveGame.bad_path(TMP, 1)):
		r = "two refusals should keep two copies (.bad.json and .bad.1.json)"
	elif _bad_level() != 9:
		r = "the first refused copy was overwritten"
	if r == "":
		for k in SaveGame.BAD_KEEP + 2:
			_write_text("{junk %d" % k)
			SaveGame.load_or_new(TMP)
		if _bad_level() != 9: r = "the first copy was lost after many refusals"
		elif FileAccess.file_exists(TMP): r = "the refused file is still in place"
	_clean()
	return r

## Review 3b8d147 #2: save() checks the ranges too; a state with one value out of range is not written and the last
## good file stays (instead of a save the next load refuses whole).
func test_save_refuses_out_of_range_and_keeps_last_good():
	_clean()
	var good := SaveGame.new_state()
	good.level = 5
	var r := ""
	if not SaveGame.save(good, TMP): r = "a good save was not written"
	var bad := good.duplicate(true)
	bad.inventory.gold = int(Balance.num("save.gold_cap")) + 1
	if r == "" and SaveGame.save(bad, TMP): r = "a save with gold over the cap was written"
	if r == "":
		var s := SaveGame.load_or_new(TMP)
		if int(s.level) != 5 or FileAccess.file_exists(BAD): r = "the last good save did not stay (level %d)" % int(s.level)
	_clean()
	return r

# ---------- M5b Task 1: sockets (owner 2026-11-08 slots, 2026-11-09 gems stay where they are) ----------

## Writes `st` signed with the key but without save()'s range check: the file a key holder could hand-make (S9).
func _write_signed(st: Dictionary) -> void:
	var d = JSON.parse_string(JSON.stringify(st))
	d["version"] = SaveGame.VERSION
	d["sig"] = SaveGame.signature(d)
	_clean()
	_write_text(JSON.stringify(d))

func _sock_state(level: int, skills: Dictionary) -> Dictionary:
	var st := SaveGame.new_state()
	st.level = level
	st.skills = skills
	return st

func _sg(type: String, element := "") -> Dictionary:
	var g := {"type": type, "level": 2, "exp": 5, "rarity": "good", "opts": [{"k": "crit", "v": 0.02}]}
	if element != "": g["element"] = element
	return g

## true when a signed file holding `st` loads as written (not thrown away).
func _signed_loads(st: Dictionary) -> bool:
	_write_signed(st)
	var s := SaveGame.load_or_new(TMP)
	var ok := not _broken(s) and int(s.level) == int(st.level)
	_clean()
	return ok

## The game never puts two gems of one type in a skill (hero.gd socket: "เจมชนิดนี้ใส่ในสกิลนี้แล้ว", since M3a
## b4e683d, before M3a reached main), and every element gem has type "element" (one element per skill, combos spec).
## A save that holds such a pair is hand-made: refused whole (Q3 a).
func test_duplicate_gem_type_in_skill_refuses_save():
	var cap := Progression.cap()
	if _signed_loads(_sock_state(cap, {"piercing": [_sg("element", "fire"), _sg("element", "ice")]})): return "two element gems on one skill loaded"
	if _signed_loads(_sock_state(cap, {"piercing": [_sg("split"), _sg("split")]})): return "two split gems on one skill loaded"
	if _signed_loads(_sock_state(cap, {"piercing": [_sg("split"), null, _sg("split")]})): return "split, null, split loaded"
	if not _signed_loads(_sock_state(cap, {"piercing": [_sg("element", "fire"), _sg("split"), _sg("multiply")], "spread": [_sg("split"), _sg("element", "ice")]})):
		return "one gem of each type per skill must load (the same type on two skills is fine)"
	return ""

## Gems only on skills that exist (have numbers in balance.json "skills") and are unlocked at the save's level: the
## game refuses to socket anything else (socket: "ยังไม่ปลด"), and the character level never goes down. Empty or
## null sockets are fine anywhere a skill has labels (a Lv1 save holds "spread": []).
func test_gems_on_missing_or_locked_skill_refuse_save():
	var refused := {
		"arrow_rain has no numbers yet": _sock_state(Progression.cap(), {"arrow_rain": [_sg("expand")]}),
		"spread locked at Lv2": _sock_state(2, {"spread": [_sg("split")]}),
		"spread locked at Lv1, gem in slot 2": _sock_state(1, {"spread": [null, _sg("multiply")]}),
		"unknown skill id": _sock_state(3, {"sword": []}),
	}
	var good := {
		"Lv1 default sockets": _sock_state(1, {"piercing": [], "spread": []}),
		"null sockets on a locked skill": _sock_state(1, {"spread": [null, null], "arrow_rain": [null]}),
		"spread at its unlock level": _sock_state(3, {"spread": [_sg("split"), _sg("multiply")]}),
		# hand-made (slot 3 is closed at skill Lv1) but kept: owner 2026-11-09 "never lost"; the hero returns it to the bag
		"gem in a closed slot": _sock_state(1, {"piercing": [_sg("split"), _sg("multiply"), _sg("execute")]}),
	}
	for name in refused:
		if _signed_loads(refused[name]): return "should be refused: %s" % name
	for name in good:
		if not _signed_loads(good[name]): return "should load: %s" % name
		if not _cycle(good[name]).saved: _clean(); return "save() refused: %s" % name
		_clean()
	return ""

## The "unlocked" check reads balance.json, so the area skills built later in M5b (ห่าศร, กับดักหนาม, ศรเพลิง)
## work once their numbers are in: nothing is a hard-coded skill list.
func test_unlock_check_follows_skill_data():
	var skills: Dictionary = Balance.data()["skills"]
	var added := not skills.has("arrow_rain")
	if added: skills["arrow_rain"] = {"unlock": 5, "mult": 1.0, "cooldown": 8, "mp": 18}
	Balance.clear_cache()
	var r := ""
	var u := Skills.unlock_level("arrow_rain") if Skills.exists("arrow_rain") else -1
	if u < 2: r = "Skills.exists / unlock_level ignore the skill data (unlock %d)" % u
	elif not _signed_loads(_sock_state(u, {"arrow_rain": [_sg("expand"), _sg("multiply")]})): r = "arrow_rain gems at its unlock level should load"
	elif _signed_loads(_sock_state(u - 1, {"arrow_rain": [_sg("expand")]})): r = "arrow_rain gems before its unlock level should be refused"
	if added:
		skills.erase("arrow_rain")
		Balance.clear_cache()
		if r == "" and Skills.exists("arrow_rain"): r = "test data not restored"
	return r
