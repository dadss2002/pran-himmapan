extends RefCounted
## Enhance window (approved sketch "ตีบวก"), opened from the bag.

func _hero(level := 5) -> Hero:
	var h: Hero = load("res://scenes/hero.tscn").instantiate()
	h.setup_sprites()
	h.set_progress(level, 0)
	h.inventory.slots.clear()
	return h

func _panel(h: Hero, ref: Dictionary) -> EnhancePanel:
	var p := EnhancePanel.new()
	p.build()
	p.open(h, ref)
	return p

func test_safe_and_risky_warnings():
	var h := _hero()
	h.equipped.bow = {"base": "bow_buffalo_horn", "rarity": "common", "level": 5, "opts": [], "plus": 2}
	h.inventory.add("ore_himmapan", 20)
	h.inventory.gold = 10000
	var p := _panel(h, {"worn": "bow"})
	var d := p.detail()
	var r := ""
	if d.title != "ธนูเขาควาย +2 → +3": r = "title %s" % d.title
	elif d.stat != "ATK +17.9 → +18.9": r = "stat %s" % d.stat
	elif d.chance != "90%" or not d.safe or not d.warn.contains("เสียแค่แร่กับทอง"): r = "safe step: %s %s %s" % [d.chance, d.safe, d.warn]
	h.equipped.bow.plus = 6
	p.refresh()
	d = p.detail()
	if r == "" and (d.safe or not d.warn.contains("ลดเหลือ +5") or d.chance != "50%"): r = "risky step: %s %s" % [d.warn, d.chance]
	p.free(); h.free()
	return r

func test_not_enough_disables():
	var h := _hero()
	h.inventory.add("ore_himmapan", 2)
	h.inventory.gold = 50
	var p := _panel(h, {"worn": "bow"})            # bamboo +0 → +1 needs 1 ore, 100 gold
	var d := p.detail()
	var r := ""
	if d.can or d.gold_ok or not d.ore_ok or d.button != "ทองไม่พอ": r = "detail %s" % [d]
	elif p.press() != "ทองไม่พอ" or h.inventory.gold != 50 or int(h.equipped.bow.get("plus", 0)) != 0: r = "pressed anyway"
	p.free(); h.free()
	return r

func test_worn_item_updates_stats_and_saves():
	var h := _hero()
	h.inventory.add("ore_himmapan", 5)
	h.inventory.gold = 1000
	var saves := [0]
	h.gear_changed.connect(func(): saves[0] += 1)
	var atk_before: float = h.stats().atk
	var p := _panel(h, {"worn": "bow"})
	var res := p.press(0.0)
	var r := ""
	if res != "ตีติด! +1": r = "result %s" % res
	elif int(h.equipped.bow.plus) != 1: r = "plus %s" % h.equipped.bow.get("plus")
	elif absf(h.stats().atk - (atk_before + 8 * 0.06)) > 1e-4: r = "ATK %.3f, want +0.48" % h.stats().atk
	elif saves[0] != 1: r = "gear_changed fired %d times (saves)" % saves[0]
	elif h.inventory.gold != 900 or h.inventory.count_of("ore_himmapan") != 4: r = "costs gold %d ore %d" % [h.inventory.gold, h.inventory.count_of("ore_himmapan")]
	p.free(); h.free()
	return r

func test_bag_offers_enhance_for_bow_not_ring():
	var h := _hero()
	h.inventory.add_item({"base": "ring", "rarity": "rare", "level": 3, "opts": []})
	h.inventory.add_item({"base": "armor_wolf_leather", "rarity": "good", "level": 4, "opts": [], "plus": 3})
	var bag := BagPanel.new()
	bag.build()
	bag.open(h)
	var r := ""
	bag.select(0)
	if bag.selected_detail().enhance: r = "ring should not offer ตีบวก"
	bag.select(1)
	var d := bag.selected_detail()
	if r == "" and not d.enhance: r = "armor should offer ตีบวก"
	elif r == "" and d.name != "ชุดหนังหมาป่า +3": r = "name %s" % d.name
	elif r == "" and d.main != "DEF +11.8 · HP +47": r = "main %s (DEF 10 ×1.18, HP 40 ×1.18)" % d.main
	bag.select_worn("bow")
	if r == "" and not bag.selected_detail().enhance: r = "worn bow should offer ตีบวก"
	bag.free(); h.free()
	return r
