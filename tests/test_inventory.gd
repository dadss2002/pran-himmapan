extends RefCounted
## Bag stacking + save/load robustness.

const TMP := "user://test_save.json"
const TMP_BAD := "user://test_save.bad.json"

func _cleanup() -> void:
	for p in [TMP, TMP_BAD]:
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

func test_load_caps_exp_below_next_level():
	_cleanup()
	SaveGame.save({"level": 2, "exp": 99999, "inventory": Inventory.new().to_dict()}, TMP)
	var s := SaveGame.load_or_new(TMP)
	_cleanup()
	return "" if s.level == 2 and s.exp == Progression.exp_to_next(2) - 1 else "loaded %s" % s

func test_load_bad_slots_starts_fresh():
	_cleanup()
	SaveGame.save({"level": 3, "exp": 0, "inventory": {"gold": 5, "slots": [{"id": 7}, "junk"]}}, TMP)
	var s := SaveGame.load_or_new(TMP)
	var kept := FileAccess.file_exists(TMP_BAD)
	_cleanup()
	if s.level != 1: return "bad bag should start fresh, got %s" % s
	return "" if kept else "the broken file should be kept as .bad.json"
