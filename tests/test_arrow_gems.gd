extends RefCounted
## Arrow gem behaviours: extra pierce, ricochet, homing, leech, element (M3a design §5.2–5.3).

const DT := 1.0 / 60.0
var _spawned: Array = []

func _dummy(pos: Vector2) -> Node2D:
	var d: Node2D = load("res://tests/dummy_enemy.gd").new()
	d.position = pos
	return d

func _arrow(dir: Vector2, enemies: Array, b: Dictionary, pierce_all := false, mult := 1.0) -> Arrow:
	var a: Arrow = load("res://scenes/arrow.tscn").instantiate()
	a.launch(dir, 20.0, enemies, mult, pierce_all)
	var full := {"pierce_extra": 0, "bounces": 0, "bounce_mult": 0.0, "homing": false, "leech": 0.0, "element": "", "element_mult": 1.0}
	full.merge(b, true)
	a.configure(full, null)
	_spawned = []
	a.spawned.connect(func(x): _spawned.append(x))
	return a

func _fly(a: Arrow, s: float) -> void:
	for i in int(round(s / DT)):
		a.advance(DT)
		for x in _spawned.duplicate(): if is_instance_valid(x): x.advance(DT)

func _free(list: Array) -> void:
	for x in list: if is_instance_valid(x): x.free()

func test_pierce_extra_hits_three_then_stops():
	var ds := [_dummy(Vector2(40, 14)), _dummy(Vector2(80, 14)), _dummy(Vector2(120, 14)), _dummy(Vector2(160, 14))]
	var a := _arrow(Vector2.RIGHT, ds, {"pierce_extra": 2})
	_fly(a, 1.0)
	var hits := []
	for d in ds: hits.append(d.hits.size())
	var r := "" if hits == [1, 1, 1, 0] else "hits %s, want first + 2 more" % [hits]
	_free(ds + [a])
	return r

func test_ricochet_once_80():
	var ds := [_dummy(Vector2(60, 14)), _dummy(Vector2(60, 110))]
	var a := _arrow(Vector2.RIGHT, ds, {"bounces": 1, "bounce_mult": 0.8}, false, 1.5)
	_fly(a, 1.0)
	var r := ""
	if ds[0].hits.size() != 1 or ds[1].hits.size() != 1: r = "hits %d / %d, want 1 / 1" % [ds[0].hits.size(), ds[1].hits.size()]
	elif absf(ds[1].hits[0][1] - 1.5 * 0.8) > 1e-6: r = "bounce mult %.3f, want 1.2" % ds[1].hits[0][1]
	_free(ds + _spawned + [a])
	return r

func test_ricochet_no_target_no_error():
	var ds := [_dummy(Vector2(60, 14)), _dummy(Vector2(60, 300))]     # second one out of 120 px
	var a := _arrow(Vector2.RIGHT, ds, {"bounces": 1, "bounce_mult": 0.8})
	_fly(a, 1.0)
	var r := "" if _spawned.is_empty() and ds[1].hits.is_empty() else "bounced to a target 286 px away"
	_free(ds + _spawned + [a])
	return r

func test_homing_turns_and_retargets():
	var t1 := _dummy(Vector2(120, 80))
	var t2 := _dummy(Vector2(200, -60))
	var a := _arrow(Vector2.RIGHT, [t1, t2], {"homing": true})
	for i in 12: a.advance(DT)
	var r := "" if a.dir.y > 0.05 else "arrow did not turn toward the target below (dir %s)" % a.dir
	t1.free()                                   # target gone mid-flight
	for i in 60: a.advance(DT)
	if r == "" and t2.hits.size() != 1 and not a.spent: r = "did not retarget or finish after the target was freed"
	_free([t2, a])
	return r

func test_leech_heals_3pct_with_carry():
	var h: Hero = load("res://scenes/hero.tscn").instantiate()
	h.setup_sprites()
	h.health.hp = 50
	for i in 10: h.leech_heal(10 * 0.03)        # 0.3 HP each → 3 HP total
	var r := "" if h.health.hp == 53 else "hp %d, want 53 (fractions carried)" % h.health.hp
	h.free()
	return r

func test_chain_120px_80pct():
	var ds := [_dummy(Vector2(60, 14)), _dummy(Vector2(60, 100)), _dummy(Vector2(400, 14))]
	var a := _arrow(Vector2.RIGHT, ds, {"element": "lightning", "element_mult": 1.1}, false, 2.0)
	_fly(a, 0.3)
	var r := ""
	if ds[1].hits.size() != 1 or absf(ds[1].hits[0][1] - 2.0 * 0.8) > 1e-6: r = "chain hits %s, want one at 80%%" % [ds[1].hits]
	elif not ds[2].hits.is_empty(): r = "chained beyond 120 px"
	_free(ds + [a])
	return r
