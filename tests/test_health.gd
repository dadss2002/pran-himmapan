extends RefCounted

var _deaths := 0

func _h(max_hp: int) -> Health:
	var h := Health.new()
	h.setup(max_hp)
	return h

func test_take_hit_reduces_and_dies():
	var h := _h(120)
	_deaths = 0
	h.died.connect(func(): _deaths += 1)
	if not h.take_hit(119, false): return "first hit refused"
	if h.hp != 1: return "hp %d != 1" % h.hp
	h.take_hit(5, false)
	var r := ""
	if h.hp != 0 or not h.is_dead(): r = "should be dead at 0 (hp %d)" % h.hp
	elif h.take_hit(5, false): r = "dead health must refuse hits"
	elif _deaths != 1: r = "died emitted %d times" % _deaths
	h.free()
	return r

func test_invulnerable_ignores():
	var h := _h(50)
	h.set_invulnerable(0.5)
	var r := ""
	if h.take_hit(10, false): r = "hit during invulnerability accepted"
	h.tick(0.51)
	if r == "" and not h.take_hit(10, false): r = "hit after invulnerability refused"
	if r == "" and h.hp != 40: r = "hp %d != 40" % h.hp
	h.free()
	return r

func test_reset_full():
	var h := _h(30)
	h.take_hit(30, false)
	h.reset_full()
	var r := "" if h.hp == 30 and not h.is_dead() else "reset_full failed"
	h.free()
	return r
