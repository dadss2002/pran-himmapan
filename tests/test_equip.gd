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
	if h.unequip("bow") != "" or h.equipped.bow != null or h.inventory.slots.size() != 1: r = "unequip into an empty bag failed"
	for i in 23: h.inventory.add("junk_%d" % i, 1)
	if r == "" and h.unequip("armor") != "กระเป๋าเต็ม": r = "unequip with a full bag should be refused"
	elif r == "" and h.equipped.armor == null: r = "armor came off anyway"
	h.free()
	return r
