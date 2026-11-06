class_name Enhance
## ตีบวก +1…+10 (spec-numbers §7, M3a design §7). Pure rules on balance.json "enhance".
## Failing while the item is at +safe_max or lower costs only ore and gold; from +6 up it drops one step.

static func _n(key: String) -> float:
	return Balance.num("enhance." + key)

static func max_plus() -> int:
	return int(_n("max"))

## Chance to reach `target` (1..10).
static func chance(target: int) -> float:
	return float(Balance.data()["enhance"]["chance"][clampi(target, 1, max_plus()) - 1])

static func ore(target: int) -> int:
	return int(_n("ore_per_step")) * target

static func gold(target: int) -> int:
	return int(_n("gold_base")) * target * target

## Main-stat bonus at a plus: +6% per step up to +6, then +10% per step.
static func bonus(plus: int) -> float:
	var low := mini(plus, int(_n("bonus_low_until")))
	var high := maxi(0, plus - int(_n("bonus_low_until")))
	return low * _n("bonus_low") + high * _n("bonus_high")

static func can(item: Dictionary) -> bool:
	return Gear.slot_of(String(item.get("base", ""))) in Balance.data()["enhance"]["slots"]

## Tries once. Mutates item.plus and the inventory (ore, gold) only when the attempt happens.
## result: ok | fail | down | no_ore | no_gold | max | cannot
## roll: the 0–1 draw (tests pass one); < 0 draws from rng.
static func attempt(item: Dictionary, inv: Inventory, rng: RandomNumberGenerator, roll := -1.0) -> Dictionary:
	var plus := int(item.get("plus", 0))
	if not can(item): return {"result": "cannot", "plus": plus}
	if plus >= max_plus(): return {"result": "max", "plus": plus}
	var target := plus + 1
	var ore_id := String(Balance.data()["enhance"]["ore_id"])
	if inv.count_of(ore_id) < ore(target): return {"result": "no_ore", "plus": plus}
	if inv.gold < gold(target): return {"result": "no_gold", "plus": plus}
	inv.remove(ore_id, ore(target))
	inv.gold -= gold(target)
	var r := roll if roll >= 0.0 else rng.randf()
	if r < chance(target):
		item["plus"] = target
		return {"result": "ok", "plus": target}
	if plus > int(_n("safe_max")):
		item["plus"] = plus - 1
		return {"result": "down", "plus": plus - 1}
	return {"result": "fail", "plus": plus}
