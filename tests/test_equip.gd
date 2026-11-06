extends RefCounted
## Equip / unequip and gear stats (M2c).

func _hero(level := 1) -> Hero:
	var h: Hero = load("res://scenes/hero.tscn").instantiate()
	h.setup_sprites()
	if level > 1: h.set_progress(level, 0)
	return h

func _item(base: String, rarity := "common", opts: Array = [], level := -1) -> Dictionary:
	return {"base": base, "rarity": rarity, "level": Gear.req_level(base) if level < 0 else level, "opts": opts}

func test_start_kit_worn():
	var h := _hero()
	var r := ""
	if h.equipped.bow == null or h.equipped.bow.base != "bow_bamboo": r = "bow %s" % [h.equipped.bow]
	elif h.equipped.armor == null or h.equipped.armor.base != "armor_trainee": r = "armor %s" % [h.equipped.armor]
	elif h.equipped.ring != null or h.equipped.necklace != null: r = "ring/necklace should start empty"
	h.free()
	return r

func test_items_never_stack():
	var inv := Inventory.new()
	inv.add_item(_item("ring"))
	inv.add_item(_item("ring"))
	inv.add("ring", 1)            # a plain add must not merge into an item slot either
	var item_slots := 0
	for s in inv.slots:
		if s.has("item"): item_slots += 1
	return "" if item_slots == 2 and inv.slots.size() == 3 else "slots %s" % [inv.slots]

func test_equip_swaps_with_bag():
	var h := _hero(5)
	h.inventory.slots.clear()
	h.inventory.add("potion_hp", 2)
	h.inventory.add_item(_item("bow_buffalo_horn", "rare", [{"k": "crit", "v": 0.02}]))
	var changed := [0]
	h.gear_changed.connect(func(): changed[0] += 1)
	var why := h.equip(1)
	var r := ""
	if why != "": r = "refused: %s" % why
	elif h.equipped.bow.base != "bow_buffalo_horn": r = "bow not worn"
	elif h.inventory.slots[1].get("item", {}).get("base", "") != "bow_bamboo": r = "old bow not in the same slot: %s" % [h.inventory.slots]
	elif changed[0] != 1: r = "gear_changed fired %d times" % changed[0]
	h.free()
	return r

func test_equip_refused_above_level():
	var h := _hero(2)
	h.inventory.slots.clear()
	h.inventory.add_item(_item("bow_buffalo_horn"))
	var why := h.equip(0)
	var r := ""
	if why != "ต้องเลเวล 5": r = "reason '%s'" % why
	elif h.equipped.bow.base != "bow_bamboo" or h.inventory.slots[0].item.base != "bow_buffalo_horn": r = "something moved"
	elif h.equip(5) == "": r = "equip of an empty slot index accepted"
	h.free()
	return r

func test_unequip_and_full_bag():
	var h := _hero()
	h.inventory.slots.clear()
	var r := ""
	if h.unequip("bow") != "ต้องถือธนูไว้" or h.equipped.bow == null: r = "the bow must stay (swap it instead)"
	elif h.unequip("armor") != "" or h.equipped.armor != null or h.inventory.slots.size() != 1: r = "unequip into an empty bag failed"
	h.equipped.armor = _item("armor_trainee")
	for i in 23: h.inventory.add("junk_%d" % i, 1)
	if r == "" and h.unequip("armor") != "กระเป๋าเต็ม": r = "unequip with a full bag should be refused"
	elif r == "" and h.equipped.armor == null: r = "armor came off anyway"
	h.free()
	return r

func _wear(h: Hero, slot: String, it) -> void:
	var eq: Dictionary = h.equipped.duplicate(true)
	eq[slot] = it
	h.set_equipped(eq)

func test_each_option_changes_its_stat():
	var r := ""
	var cases := [
		["atk_pct", 0.10, "atk", func(a, b): return is_equal_approx(b.atk, a.atk * 1.10)],
		["crit", 0.04, "crit", func(a, b): return is_equal_approx(b.crit, a.crit + 0.04)],
		["crit_dmg", 0.20, "crit_mult", func(a, b): return is_equal_approx(b.crit_mult, a.crit_mult + 0.20)],
		["atk_speed", 0.10, "shot_cd", func(a, b): return is_equal_approx(b.shot_cd, a.shot_cd / 1.10)],
		["hp", 30, "hp", func(a, b): return b.hp == a.hp + 30],
		["def", 5, "def", func(a, b): return b.def == a.def + 5],
		["move_speed", 0.05, "walk", func(a, b): return is_equal_approx(b.walk, a.walk * 1.05)],
		["skill_cd", 0.05, "skill_cd_cut", func(a, b): return is_equal_approx(b.skill_cd_cut, 0.05)],
		["exp_pct", 0.05, "exp_mult", func(a, b): return is_equal_approx(b.exp_mult, 1.05)],
		["gold_pct", 0.10, "gold_mult", func(a, b): return is_equal_approx(b.gold_mult, 1.10)],
		["mp", 20, "mp", func(a, b): return b.mp == a.mp + 20],
		["mp_regen", 1.0, "mp_regen", func(a, b): return is_equal_approx(b.mp_regen, a.mp_regen + 1.0)],
	]
	for c in cases:
		var h := _hero()
		var before := h.stats()
		_wear(h, "ring", _item("ring", "good", [{"k": c[0], "v": c[1]}]))
		var after := h.stats()
		if not c[3].call(before, after): r = "%s: %s %s → %s" % [c[0], c[2], before[c[2]], after[c[2]]]
		h.free()
		if r != "": break
	return r

func test_gear_reaches_the_game():
	var h := _hero()
	_wear(h, "ring", _item("ring", "good", [{"k": "mp", "v": 20}]))
	_wear(h, "necklace", _item("necklace", "good", [{"k": "skill_cd", "v": 0.05}]))
	var r := ""
	if h.max_mp() != 70: r = "max_mp %d, want 70" % h.max_mp()
	elif not is_equal_approx(Skills.cooldown("piercing", 1, h.stats().skill_cd_cut), 4.0 * 0.95): r = "skill cooldown %.3f" % Skills.cooldown("piercing", 1, h.stats().skill_cd_cut)
	elif not is_equal_approx(Skills.cooldown("piercing", 30, 0.2), 4.0 * 0.7): r = "total cut must stay capped at 30%%"
	h.try_shoot()
	if r == "" and not is_equal_approx(h.cooldown, h.stats().shot_cd): r = "shot cooldown %.3f" % h.cooldown
	h.free()
	return r

func test_hp_clamps_when_gear_removed():
	var h := _hero()
	_wear(h, "ring", _item("ring", "good", [{"k": "hp", "v": 30}]))
	var r := ""
	if h.health.max_hp != 150 or h.health.hp != 120: r = "wearing +30 HP: %d/%d (gear must not heal)" % [h.health.hp, h.health.max_hp]
	h.health.hp = 150
	_wear(h, "ring", null)
	if r == "" and (h.health.max_hp != 120 or h.health.hp != 120): r = "after removing: %d/%d" % [h.health.hp, h.health.max_hp]
	h.free()
	return r

func test_bow_layer_shows_equipped_bow():
	var h := _hero(5)
	var r := ""
	if not String(h.bow.texture.resource_path).ends_with("bow_bamboo.png"): r = "start bow %s" % h.bow.texture.resource_path
	_wear(h, "bow", _item("bow_buffalo_horn"))
	if r == "" and not String(h.bow.texture.resource_path).ends_with("bow_buffalo_horn.png"): r = "bow layer %s" % h.bow.texture.resource_path
	h.free()
	return r

func test_exp_bonus_on_kill():
	var h := _hero()
	_wear(h, "ring", _item("ring", "good", [{"k": "exp_pct", "v": 0.10}]))
	h.on_kill(20, 1)
	var r := "" if h.exp == 22 else "exp %d, want 22 (20 × 1.10)" % h.exp
	h.free()
	return r

func test_arrow_carries_crit_stats():
	var h := _hero()
	_wear(h, "ring", _item("ring", "good", [{"k": "crit", "v": 0.05}]))
	var arrows := []
	h.shot.connect(func(a): arrows.append(a))
	h.try_shoot()
	for i in 60: h.step(1.0 / 60.0, Vector2.ZERO)
	var r := ""
	if arrows.size() != 1: r = "%d arrows" % arrows.size()
	elif not is_equal_approx(arrows[0].crit_chance, h.stats().crit): r = "arrow crit %.3f, want %.3f" % [arrows[0].crit_chance, h.stats().crit]
	for a in arrows: a.free()
	h.free()
	return r

func test_small_percent_bonuses_still_count():
	var h := _hero()
	_wear(h, "ring", _item("ring", "good", [{"k": "atk_pct", "v": 0.009}]))
	var r := ""
	if absf(h.stats().atk - 18.0 * 1.009) > 0.001: r = "ATK %.3f, want 18.162 (+0.9%% must not round away)" % h.stats().atk
	_wear(h, "ring", _item("ring", "good", [{"k": "exp_pct", "v": 0.024}]))
	h.set_progress(9, 0)                       # no level-up in between (Lv9 bar is long)
	_wear(h, "ring", _item("ring", "good", [{"k": "exp_pct", "v": 0.024}]))
	for i in 10: h.on_kill(13, 9)
	if r == "" and h.exp != 133: r = "EXP after 10 kills %d, want 133 (130 × 1.024, remainder carried)" % h.exp
	_wear(h, "ring", _item("ring", "good", [{"k": "gold_pct", "v": 0.045}]))
	var gold := 0
	for i in 20: gold += h.bonus_gold(10)
	if r == "" and gold != 209: r = "gold from 20 × 10 %d, want 209 (200 × 1.045, remainder carried)" % gold
	h.free()
	return r
