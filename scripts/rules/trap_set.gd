class_name TrapSet
extends RefCounted
## M5b Task 8c: the traps (กับดักหนาม) one hero has out. Pure rule, no scene access (risks.md §3): it holds any
## objects with `armed` (waiting to be stepped on) and `done` (finished) and never frees one itself.
## docs/skills.md "วางค้างได้ 2 อัน" (owner D4, max 2): at most `max_armed` ARMED traps; one more pushes out the oldest
## armed one. A sprung trap (it shows the root until the root ends) stays held, so it can be ended with the room, but
## no longer counts. Never saved. Client-side only (risks.md S1): online play needs the server to own this list.

var _items: Array = []         # oldest first: armed traps and sprung ones that are not over yet

## Holds `trap`. Returns the trap that had to go to keep at most max_armed armed (the oldest armed one; the caller
## ends it), or null.
func add(trap: Object, max_armed: int) -> Object:
	_drop_freed()
	_items.append(trap)
	var a := armed()
	if max_armed < 1 or a.size() <= max_armed: return null
	var old: Object = a[0]
	_items.erase(old)
	return old

## The traps still waiting to be stepped on, oldest first.
func armed() -> Array:
	_drop_freed()
	return _items.filter(func(t): return t.armed)

## Every trap held (armed and sprung), oldest first.
func all() -> Array:
	_drop_freed()
	return _items.duplicate()

func size() -> int:
	_drop_freed()
	return _items.size()

## Lets go of the traps that are over; returns them (the caller frees one that is not in a tree).
func prune() -> Array:
	_drop_freed()
	var gone: Array = []
	for i in range(_items.size() - 1, -1, -1):
		if _items[i].done:
			gone.push_front(_items[i])
			_items.remove_at(i)
	return gone

## Lets go of every trap; returns the ones it held (the caller ends them: warp, room change, the hero's death).
func clear() -> Array:
	_drop_freed()
	var held := _items
	_items = []
	return held

func _drop_freed() -> void:
	for i in range(_items.size() - 1, -1, -1):
		if not is_instance_valid(_items[i]): _items.remove_at(i)
