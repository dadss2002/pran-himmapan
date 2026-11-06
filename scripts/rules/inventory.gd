class_name Inventory
extends RefCounted
## The bag: bag.slots slots, stacks of bag.stack. Gold is a wallet, not a slot.
## Equipment sits one per slot as {id: base, count: 1, item: {base, rarity, level, opts}} and never stacks.

var gold := 0
var slots: Array = []     # [{id, count}] or [{id, count: 1, item}]

func _max_slots() -> int: return int(Balance.num("bag.slots"))
func _stack() -> int: return int(Balance.num("bag.stack"))

## Adds items; returns how many did NOT fit.
func add(id: String, count: int) -> int:
	if id == "gold":
		gold += count
		return 0
	var left := count
	for s in slots:
		if left == 0: break
		if s.id == id and not s.has("item") and s.count < _stack():
			var put := mini(left, _stack() - s.count)
			s.count += put
			left -= put
	while left > 0 and slots.size() < _max_slots():
		var put := mini(left, _stack())
		slots.append({"id": id, "count": put})
		left -= put
	return left

## Puts one equipment item in a free slot. false when the bag is full.
func add_item(item: Dictionary) -> bool:
	if slots.size() >= _max_slots(): return false
	slots.append({"id": String(item.base), "count": 1, "item": item.duplicate(true)})
	return true

func has_free_slot() -> bool:
	return slots.size() < _max_slots()

func remove(id: String, count: int) -> bool:
	if count_of(id) < count: return false
	var left := count
	for i in range(slots.size() - 1, -1, -1):
		if left == 0: break
		var s: Dictionary = slots[i]
		if s.id != id or s.has("item"): continue
		var take := mini(left, s.count)
		s.count -= take
		left -= take
		if s.count == 0: slots.remove_at(i)
	return true

func count_of(id: String) -> int:
	if id == "gold": return gold
	var n := 0
	for s in slots:
		if s.id == id and not s.has("item"): n += s.count
	return n

func is_full_for(id: String) -> bool:
	if id == "gold": return false
	if slots.size() < _max_slots(): return false
	if Gear.is_gear(id): return true          # equipment always needs its own slot
	for s in slots:
		if s.id == id and not s.has("item") and s.count < _stack(): return false
	return true

func to_dict() -> Dictionary:
	return {"gold": gold, "slots": slots.duplicate(true)}

func from_dict(d: Dictionary) -> void:
	gold = int(d.get("gold", 0))
	slots = []
	for s in d.get("slots", []):
		var e := {"id": String(s.id), "count": int(s.count)}
		if s.has("item"): e["item"] = SaveGame.clean_item(s.item)
		slots.append(e)
