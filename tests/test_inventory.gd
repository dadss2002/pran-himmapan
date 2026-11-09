extends RefCounted
## Bag stacking + save/load robustness.

const TMP := "user://test_save.json"
const TMP_BAD := "user://test_save.bad.json"

func _cleanup() -> void:
	for p in [TMP, TMP_BAD, SaveGame.marker_path(TMP)]:     # no marker: hand-written old files count as pre-signing
		if FileAccess.file_exists(p): DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

func test_stacking_and_overflow():
	var inv := Inventory.new()
	if inv.add("ore_himmapan", 99) != 0: return "99 ore should fit"
	if inv.add("ore_himmapan", 5) != 0: return "5 more ore should open a second slot"
	if inv.slots.size() != 2 or inv.count_of("ore_himmapan") != 104: return "ore stacks %s" % [inv.slots]
	for i in 22: inv.add("gem_split", 99)
	if inv.slots.size() != 24: return "should have 24 slots, has %d" % inv.slots.size()
	var left := inv.add("gem_leech", 3)
	if left != 3: return "full bag should return leftover 3, got %d" % left
	if not inv.is_full_for("gem_leech"): return "is_full_for should be true"
	if inv.add("ore_himmapan", 1) != 0: return "ore still fits into its partial stack"
	return ""

func test_remove():
	var inv := Inventory.new()
	inv.add("potion_hp", 5)
	if inv.remove("potion_hp", 6): return "removing more than owned must fail"
	if not inv.remove("potion_hp", 5) or inv.count_of("potion_hp") != 0 or inv.slots.size() != 0: return "remove to zero should free the slot"
	return ""

func test_gold_not_a_slot():
	var inv := Inventory.new()
	for i in 24: inv.add("gem_split", 99)
	if inv.add("gold", 7) != 0: return "gold must always fit"
	return "" if inv.gold == 7 and inv.slots.size() == 24 else "gold %d slots %d" % [inv.gold, inv.slots.size()]

func test_save_roundtrip():
	_cleanup()
	var inv := Inventory.new()
	inv.add("gold", 120); inv.add("ore_himmapan", 3); inv.add("potion_hp", 5)
	var ok := SaveGame.save({"level": 4, "exp": 425, "inventory": inv.to_dict()}, TMP)
	var s := SaveGame.load_or_new(TMP)
	var inv2 := Inventory.new()
	inv2.from_dict(s.inventory)
	_cleanup()
	if not ok: return "save failed"
	if s.level != 4 or s.exp != 425: return "loaded %s" % s
	return "" if inv2.gold == 120 and inv2.count_of("ore_himmapan") == 3 and inv2.count_of("potion_hp") == 5 else "inventory %s" % [inv2.to_dict()]

func test_load_corrupt_save_starts_fresh():
	_cleanup()
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string("{not json at all")
	f.close()
	var s := SaveGame.load_or_new(TMP)
	var kept := FileAccess.file_exists(TMP_BAD)
	_cleanup()
	if s.level != 1 or s.exp != 0: return "corrupt save should give a new game, got %s" % s
	return "" if kept else "the broken file should be kept as save.bad.json"

func test_save_v2_roundtrip_with_items():
	_cleanup()
	var inv := Inventory.new()
	inv.add_item({"base": "ring", "rarity": "epic", "level": 3, "opts": [{"k": "crit", "v": 0.012}, {"k": "hp", "v": 9}, {"k": "mp_regen", "v": 0.4}]})
	var eq := {"bow": Gear.new_item("bow_bamboo"), "armor": null, "ring": null, "necklace": Gear.new_item("necklace")}
	SaveGame.save({"level": 3, "exp": 5, "inventory": inv.to_dict(), "equipped": eq}, TMP)
	var s := SaveGame.load_or_new(TMP)
	_cleanup()
	if s.version != SaveGame.VERSION: return "version %s" % s.version
	if s.equipped.necklace.base != "necklace" or s.equipped.armor != null: return "equipped %s" % s.equipped
	var it: Dictionary = s.inventory.slots[0].item
	return "" if it.rarity == "epic" and it.opts.size() == 3 and is_equal_approx(float(it.opts[0].v), 0.012) else "item %s" % it

func test_v1_save_migrates_to_start_kit():
	_cleanup()
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "level": 4, "exp": 10, "inventory": {"gold": 50, "slots": [{"id": "potion_hp", "count": 3}]}}))
	f.close()
	var s := SaveGame.load_or_new(TMP)
	var bad := FileAccess.file_exists(TMP_BAD)
	_cleanup()
	if bad: return "a version-1 save was treated as broken"
	if s.level != 4 or s.inventory.gold != 50: return "progress lost %s" % s
	return "" if s.equipped.bow.base == "bow_bamboo" and s.equipped.armor.base == "armor_trainee" else "equipped %s" % s.equipped

func test_bad_item_in_save_starts_fresh():
	_cleanup()
	var eq := {"bow": {"base": "armor_trainee", "rarity": "common", "level": 1, "opts": []}, "armor": null, "ring": null, "necklace": null}
	SaveGame.save({"level": 3, "exp": 0, "inventory": Inventory.new().to_dict(), "equipped": eq}, TMP)
	var s := SaveGame.load_or_new(TMP)
	var kept := FileAccess.file_exists(TMP_BAD)
	_cleanup()
	return "" if s.level == 1 and kept else "armor in the bow slot should be rejected, got %s" % s

func test_load_other_version_starts_fresh():
	_cleanup()
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 99, "level": 9, "exp": 1}))
	f.close()
	var s := SaveGame.load_or_new(TMP)
	_cleanup()
	return "" if s.level == 1 and s.version == SaveGame.VERSION else "version 99 should start fresh, got %s" % s

func test_new_game_has_start_kit():
	_cleanup()
	var s := SaveGame.load_or_new(TMP)
	var inv := Inventory.new()
	inv.from_dict(s.inventory)
	return "" if inv.count_of("potion_hp") == 5 and inv.count_of("potion_mp") == 3 else "start kit %s" % [inv.to_dict()]

## Save hardening Q3 a (owner 2026-11-09): EXP at or past the next level fails the whole save (it used to be
## clamped to next - 1).
func test_load_refuses_exp_past_next_level():
	_cleanup()
	SaveGame.save({"level": 2, "exp": 99999, "inventory": Inventory.new().to_dict()}, TMP)
	var s := SaveGame.load_or_new(TMP)
	var kept := FileAccess.file_exists(TMP_BAD)
	_cleanup()
	return "" if s.level == 1 and s.exp == 0 and kept else "EXP 99999 at Lv2 should be refused, loaded %s" % s

func test_load_bad_slots_starts_fresh():
	_cleanup()
	SaveGame.save({"level": 3, "exp": 0, "inventory": {"gold": 5, "slots": [{"id": 7}, "junk"]}}, TMP)
	var s := SaveGame.load_or_new(TMP)
	var kept := FileAccess.file_exists(TMP_BAD)
	_cleanup()
	if s.level != 1: return "bad bag should start fresh, got %s" % s
	return "" if kept else "the broken file should be kept as .bad.json"

func _save_with(eq: Dictionary, slots: Array) -> Dictionary:
	_cleanup()
	SaveGame.save({"level": 3, "exp": 0, "inventory": {"gold": 0, "slots": slots}, "equipped": eq}, TMP)
	var s := SaveGame.load_or_new(TMP)
	_cleanup()
	return s

func test_save_needs_a_bow_and_item_entries():
	var eq := SaveGame.start_equipped()
	eq.bow = null
	var r := ""
	if _save_with(eq, []).level != 1: r = "a save with no bow should start fresh"
	elif _save_with(SaveGame.start_equipped(), [{"id": "ring", "count": 5}]).level != 1: r = "gear id without item data should be rejected"
	return r

## Save hardening Q3 a (owner 2026-11-09): an item level above the highest drop level or an option above its Lv10
## top fails the whole save (they used to be clamped to 10 / 0.05).
func test_save_refuses_item_level_and_options_out_of_range():
	var eq := SaveGame.start_equipped()
	eq.ring = {"base": "ring", "rarity": "good", "level": 99, "opts": [{"k": "crit", "v": 0.03}]}
	var r := ""
	if _save_with(eq, []).level != 1: r = "ring level 99 should be refused"
	eq.ring = {"base": "ring", "rarity": "good", "level": 10, "opts": [{"k": "crit", "v": 9.0}]}
	if r == "" and _save_with(eq, []).level != 1: r = "crit 9.0 should be refused"
	eq.ring = {"base": "ring", "rarity": "good", "level": 10, "opts": [{"k": "crit", "v": 0.05}]}
	if r == "" and _save_with(eq, []).level != 3: r = "a Lv10 ring with crit at its top 0.05 should load"
	eq.ring = {"base": "ring", "rarity": "rare", "level": 3, "opts": [{"k": "hp", "v": 5}, {"k": "hp", "v": 5}]}
	if r == "" and _save_with(eq, []).level != 1: r = "duplicate option keys should be rejected"
	return r

func _g(type: String, rarity := "rare", opts: Array = [{"k": "crit", "v": 0.03}], level := 3) -> Dictionary:
	var g := {"type": type, "level": level, "exp": 40, "rarity": rarity, "opts": opts}
	if type == "element": g["element"] = "fire"
	return g

func test_rolled_gems_take_own_slot():
	var inv := Inventory.new()
	inv.slots.clear()
	inv.add_gem(_g("split"))
	inv.add_gem(_g("split"))
	inv.add("gem_split", 1)
	var with_data := 0
	for s in inv.slots:
		if s.has("gem"): with_data += 1
	var r := "" if with_data == 2 and inv.slots.size() == 3 else "slots %s" % [inv.slots]
	for i in 22: inv.add("junk_%d" % i, 1)
	if r == "" and inv.add_gem(_g("multiply")): r = "rolled gem added to a full bag"
	return r

func test_plain_gems_stack_and_split():
	var inv := Inventory.new()
	inv.slots.clear()
	var plain := {"type": "split", "level": 1, "exp": 0, "rarity": "common", "opts": []}
	inv.add_gem(plain)
	inv.add_gem(plain.duplicate(true))
	var r := ""
	if inv.slots.size() != 1 or inv.slots[0].count != 2: r = "plain gems should stack: %s" % [inv.slots]
	var g := inv.take_gem(0)
	if r == "" and (g.type != "split" or g.level != 1 or inv.slots[0].count != 1): r = "split one off: %s / %s" % [g, inv.slots]
	inv.add("gem_element", 1)
	var e := inv.take_gem(inv.slots.size() - 1)
	if r == "" and not (String(e.get("element", "")) in ["fire", "ice", "lightning"]): r = "plain element gem got no element when split off: %s" % e
	return r

func test_gem_drop_has_data():
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var seen := 0
	for i in 20000:
		for it in Loot.roll("wolf", 3, rng):
			if String(it.id).begins_with("gem_"):
				seen += 1
				if not it.has("gem") or "gem_" + String(it.gem.type) != it.id: return "gem drop without data: %s" % it
				var want := {"common": 0, "good": 1, "rare": 2, "epic": 3, "legend": 4}
				if it.gem.opts.size() != want[it.gem.rarity]: return "%s gem has %d options" % [it.gem.rarity, it.gem.opts.size()]
	return "" if seen > 100 else "only %d gems in 20000 kills" % seen

func test_save_v3_roundtrip():
	_cleanup()
	var inv := Inventory.new()
	inv.add_gem(_g("element"))
	var eq := SaveGame.start_equipped()
	eq.bow["plus"] = 4
	var skills := {"piercing": [_g("multiply"), null], "spread": [null]}
	SaveGame.save({"level": 5, "exp": 0, "inventory": inv.to_dict(), "equipped": eq, "skills": skills}, TMP)
	var s := SaveGame.load_or_new(TMP)
	_cleanup()
	var r := ""
	if s.version != SaveGame.VERSION: r = "version %s" % s.version
	elif s.equipped.bow.plus != 4: r = "plus lost: %s" % s.equipped.bow
	elif s.skills.piercing[0].type != "multiply" or s.skills.piercing[0].level != 3 or s.skills.piercing[1] != null: r = "sockets %s" % [s.skills]
	else:
		var g: Dictionary = s.inventory.slots.back().gem
		if g.element != "fire" or g.exp != 40 or absf(float(g.opts[0].v) - 0.03) > 1e-6: r = "gem %s" % g
	return r

func test_v2_save_migrates():
	_cleanup()
	var slots := [{"id": "gem_split", "count": 3}, {"id": "gem_element", "count": 1}]
	for i in 22: slots.append({"id": "potion_hp", "count": 99})
	var eq := SaveGame.start_equipped()
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 2, "level": 6, "exp": 3, "inventory": {"gold": 10, "slots": slots}, "equipped": eq}))
	f.close()
	var s := SaveGame.load_or_new(TMP)
	var bad := FileAccess.file_exists(TMP_BAD)
	_cleanup()
	if bad or s.level != 6: return "v2 save rejected: %s" % s
	if s.inventory.slots.size() != 24 or s.inventory.slots[0].count != 3: return "bag changed: %d slots" % s.inventory.slots.size()
	if s.equipped.bow.get("plus", -1) != 0: return "plus should default to 0"
	return "" if typeof(s.get("skills")) == TYPE_DICTIONARY else "skills missing"

func test_bad_gem_rejected():
	var cases := [
		{"inv": [{"id": "gem_zzz", "count": 1, "gem": _g("split")}]},
		{"inv": [{"id": "gem_split", "count": 1, "gem": _g("split", "rare", [], 21)}]},
		{"inv": [{"id": "gem_split", "count": 1, "gem": _g("split", "rare", [{"k": "crit", "v": 0.03}, {"k": "crit", "v": 0.02}])}]},
		{"skills": {"piercing": [_g("expand")]}},
		{"plus": 11},
	]
	for c in cases:
		_cleanup()
		var eq := SaveGame.start_equipped()
		if c.has("plus"): eq.bow["plus"] = c.plus
		SaveGame.save({"level": 3, "exp": 0, "inventory": {"gold": 0, "slots": c.get("inv", [])}, "equipped": eq, "skills": c.get("skills", {})}, TMP)
		var s := SaveGame.load_or_new(TMP)
		var kept := FileAccess.file_exists(TMP_BAD)
		_cleanup()
		if s.level != 1 or not kept: return "should start fresh: %s" % [c]
	return ""
