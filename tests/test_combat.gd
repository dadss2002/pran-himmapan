extends RefCounted
## Each test returns "" on success or a failure message.

func test_damage_basic():
	var d := Combat.damage(18, 1.0, 6, false, 1.0)
	return "" if d == 17 else "expected 17, got %d" % d

func test_damage_crit():
	var d := Combat.damage(18, 1.0, 6, true, 1.0)
	return "" if d == 25 else "expected 25, got %d" % d

func test_damage_floor():
	var d := Combat.damage(1, 1.0, 100000, false, 0.9)
	return "" if d == 1 else "expected 1, got %d" % d

func test_facing_from_vector():
	var ne := Combat.facing_from_vector(Vector2(1, -1), 0)
	var s := Combat.facing_from_vector(Vector2(0, 1), 4)
	var w := Combat.facing_from_vector(Vector2(-1, 0), 0)
	if ne != 3: return "up+right should be 3 north-east, got %d" % ne
	if s != 0: return "down should be 0 south, got %d" % s
	if w != 6: return "left should be 6 west, got %d" % w
	return ""

func test_facing_kept_when_idle():
	var f := Combat.facing_from_vector(Vector2.ZERO, 5)
	return "" if f == 5 else "expected 5, got %d" % f
