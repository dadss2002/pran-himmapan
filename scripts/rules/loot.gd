class_name Loot
## Drop rolls (docs/spec-numbers.md §5, docs/gems.md §6). Equipment: loot.<kind>.gear chance,
## base picked evenly from gear_pool.<kind>, rarity and options from Gear.roll_item.

static func roll(kind: String, level: int, rng: RandomNumberGenerator) -> Array:
	var t := "loot." + kind
	var out: Array = []
	# M3g: more monsters, each worth less (horde.gold_mult, horde.drop_mult)
	var drop := Balance.horde("drop_mult")
	var gold := rng.randi_range(int(Balance.num(t + ".gold_min")), int(Balance.num(t + ".gold_max"))) + level
	out.append({"id": "gold", "count": maxi(1, int(round(gold * Balance.horde("gold_mult"))))})
	if rng.randf() < Balance.num(t + ".ore") * drop:
		out.append({"id": "ore_himmapan", "count": 1})
	if rng.randf() < Balance.num(t + ".gem") * drop:
		var gems: Array = Balance.data()["gems"]
		var type: String = gems[rng.randi_range(0, gems.size() - 1)]
		out.append({"id": "gem_" + type, "count": 1, "gem": Gem.roll(type, rng)})
	if Balance.has(t + ".gear") and rng.randf() < Balance.num(t + ".gear") * drop:
		var pool: Array = Balance.data()["gear_pool"][kind]
		var base: String = pool[rng.randi_range(0, pool.size() - 1)]
		out.append({"id": base, "count": 1, "item": Gear.roll_item(base, level, rng)})
	return out
