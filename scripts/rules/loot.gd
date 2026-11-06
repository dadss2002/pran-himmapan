class_name Loot
## Drop rolls (docs/spec-numbers.md §5, docs/gems.md §6). Equipment drops arrive in M2c.

static func roll(kind: String, level: int, rng: RandomNumberGenerator) -> Array:
	var t := "loot." + kind
	var out: Array = []
	var gold := rng.randi_range(int(Balance.num(t + ".gold_min")), int(Balance.num(t + ".gold_max"))) + level
	out.append({"id": "gold", "count": gold})
	if rng.randf() < Balance.num(t + ".ore"):
		out.append({"id": "ore_himmapan", "count": 1})
	if rng.randf() < Balance.num(t + ".gem"):
		var gems: Array = Balance.data()["gems"]
		out.append({"id": "gem_" + gems[rng.randi_range(0, gems.size() - 1)], "count": 1})
	return out
