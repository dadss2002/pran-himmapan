extends RefCounted
## M3d forest monsters: numbers from the approved spec (docs/superpowers/specs/2026-11-07-m3d-forest-monsters-design.md §2)
## and each temper / attack, in a real tree with physics bodies.

var tree: SceneTree
const DT := 1.0 / 60.0
const FRUIT := preload("res://scripts/monsters/fruit.gd")
const CLOUD := preload("res://scripts/monsters/hazard_cloud.gd")

func setup(t: SceneTree) -> void:
	tree = t

func _world() -> Node2D:
	await tree.process_frame            # the root must be running before heroes get their @onready nodes
	var w := Node2D.new()
	tree.root.add_child(w)
	return w

func _hero(world: Node2D, pos: Vector2) -> Hero:
	var h: Hero = load("res://scenes/hero.tscn").instantiate()
	h.position = pos
	world.add_child(h)
	h.set_physics_process(false)
	h.health.setup(100000)
	return h

func _pack(world: Node2D, kind: String, home: Vector2, lv := 1, count := 1) -> WolfPack:
	var p := WolfPack.new()
	p.kind = kind
	p.level = lv
	p.count = count
	p.home = home
	world.add_child(p)
	p.set_physics_process(false)
	return p

func _tick(p: WolfPack, h: Hero, frames: int, watch := Callable()) -> void:
	for i in frames:
		await tree.physics_frame
		h.step(DT, Vector2.ZERO)
		p.step_all(DT, h)
		if watch.is_valid(): watch.call()

## Freed at the end of the frame, so a failure message may still read the monster; the next test's
## _world() waits a frame first.
func _done(world: Node2D) -> void:
	world.queue_free()

func _count(world: Node2D, script: Script) -> int:
	var c := 0
	for ch in world.find_children("*", "", true, false):
		if ch.get_script() == script and not ch.is_queued_for_deletion(): c += 1
	return c

func test_stats_match_spec():
	# spec M3d §2 formulas x M3g horde multipliers (HP/EXP x0.5, ATK x0.8, DEF same)
	var want := {
		["deer", 1]: {"hp": 15, "atk": 0, "def": 2, "exp": 5},
		["boar", 3]: {"hp": 50, "atk": 9, "def": 6, "exp": 12},
		["shroom", 2]: {"hp": 32, "atk": 6, "def": 6, "exp": 9},
		["macaque", 3]: {"hp": 32, "atk": 8, "def": 5, "exp": 12},
		["viper", 5]: {"hp": 42, "atk": 14, "def": 7, "exp": 18},
		["kongkoi", 10]: {"hp": 148, "atk": 25, "def": 18, "exp": 42},
	}
	for key in want:
		var got := Monster.stats_for(key[0], key[1])
		for s in want[key]:
			if got[s] != want[key][s]:
				return "%s Lv%d %s = %s (spec %s)" % [key[0], key[1], s, got[s], want[key][s]]
	return ""

func test_every_kind_has_art_for_five_directions():
	for k in Monster.KINDS:
		var path := "res://assets/monsters/%s/manifest.json" % k
		if not FileAccess.file_exists(path): return "no manifest for " + k
		var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		if m.directions.size() != 8: return "%s has %d directions" % [k, m.directions.size()]
	return ""

func test_boar_ignores_hero_until_hit():
	var world: Node2D = await _world()
	var h := _hero(world, Vector2(360, 300))
	var p := _pack(world, "boar", Vector2(300, 300))
	await tree.physics_frame
	var m: Monster = p.wolves[0]
	m.global_position = Vector2(300, 300)
	var fought := [false]
	await _tick(p, h, 120, func(): if m.state != "idle" and m.state != "return": fought[0] = true)
	if fought[0]:
		await _done(world)
		return "a passive boar went for the hero before being hit (state %s)" % m.state
	m.receive_hit(1, 1.0, h.global_position)
	await _tick(p, h, 120)
	var lost := 100000 - h.health.hp
	await _done(world)
	return "" if lost > 0 else "the boar never hit back after being hit (state %s)" % m.state

func test_deer_runs_away_when_hit_and_never_hurts():
	var world: Node2D = await _world()
	var h := _hero(world, Vector2(340, 300))
	var p := _pack(world, "deer", Vector2(300, 300))
	await tree.physics_frame
	var m: Monster = p.wolves[0]
	m.global_position = Vector2(300, 300)
	m.receive_hit(1, 1.0, h.global_position)
	var st := m.state
	var d0 := m.global_position.distance_to(h.global_position)
	await _tick(p, h, 60)
	var d1 := m.global_position.distance_to(h.global_position)
	var lost := 100000 - h.health.hp
	await _done(world)
	if st != "flee": return "deer state after a hit = %s (want flee)" % st
	if d1 <= d0 + 40: return "deer only got from %d to %d px away in 1 s" % [d0, d1]
	return "" if lost == 0 else "a deer hurt the hero (%d)" % lost

func test_viper_hides_until_close_then_strikes():
	var world: Node2D = await _world()
	var h := _hero(world, Vector2(500, 300))
	var p := _pack(world, "viper", Vector2(300, 300), 4)
	await tree.physics_frame
	var m: Monster = p.wolves[0]
	m.global_position = Vector2(300, 300)
	await _tick(p, h, 10)
	var hidden_far := m.is_hidden()
	h.global_position = Vector2(355, 300)
	await _tick(p, h, 90)
	var lost := 100000 - h.health.hp
	var hidden_near := m.is_hidden()
	await _done(world)
	if not hidden_far: return "viper visible with the hero 200 px away"
	if hidden_near: return "viper still hidden with the hero 55 px away"
	return "" if lost > 0 else "viper never struck a hero 55 px away (state %s)" % m.state

func test_macaque_keeps_away_and_throws_fruit():
	var world: Node2D = await _world()
	var h := _hero(world, Vector2(420, 300))
	var p := _pack(world, "macaque", Vector2(300, 300), 3)
	await tree.physics_frame
	var m: Monster = p.wolves[0]
	m.global_position = Vector2(300, 300)
	var thrown := [0]
	var closest := [9999.0]
	await _tick(p, h, 240, func():
		thrown[0] = maxi(thrown[0], _count(world, FRUIT))
		closest[0] = minf(closest[0], m.global_position.distance_to(h.global_position)))
	var lost := 100000 - h.health.hp
	var st := m.state
	await _done(world)
	if thrown[0] == 0: return "macaque threw no fruit in 4 s (state %s)" % st
	if closest[0] < 50: return "macaque came within %d px (keeps 90-130)" % closest[0]
	return "" if lost > 0 else "no fruit hit a standing hero"

func test_shroom_ring_poisons_and_death_leaves_mist():
	var world: Node2D = await _world()
	var h := _hero(world, Vector2(325, 300))
	var p := _pack(world, "shroom", Vector2(300, 300), 2)
	await tree.physics_frame
	var m: Monster = p.wolves[0]
	m.global_position = Vector2(300, 300)
	m.receive_hit(1, 1.0, h.global_position)
	var warned := [false]
	await _tick(p, h, 60, func(): if m.state == "ring_warn": warned[0] = true)
	var poisoned := h.poison_left > 0.0
	m.health.take_hit(100000, false)
	await tree.physics_frame
	var clouds := _count(world, CLOUD)
	await _done(world)
	if not warned[0]: return "shroom never warned its ring (state %s)" % m.state
	if not poisoned: return "the ring did not poison the hero"
	return "" if clouds == 1 else "%d mist clouds after the shroom died (want 1)" % clouds

func test_kongkoi_stomps_unprovoked():
	var world: Node2D = await _world()
	var h := _hero(world, Vector2(400, 300))
	var p := _pack(world, "kongkoi", Vector2(300, 300), 4)
	await tree.physics_frame
	var m: Monster = p.wolves[0]
	m.global_position = Vector2(300, 300)
	var warned := [false]
	await _tick(p, h, 180, func(): if m.state == "ring_warn": warned[0] = true)
	var lost := 100000 - h.health.hp
	var poisoned := h.poison_left > 0.0
	await _done(world)
	if not warned[0]: return "kongkoi never stomped (state %s)" % m.state
	if poisoned: return "kongkoi's stomp poisoned (it should not)"
	return "" if lost > 0 else "the stomp did no damage"

func test_passive_calms_down_back_home():
	var world: Node2D = await _world()
	var h := _hero(world, Vector2(340, 300))
	var p := _pack(world, "boar", Vector2(300, 300))
	await tree.physics_frame
	var m: Monster = p.wolves[0]
	m.global_position = Vector2(300, 300)
	await _tick(p, h, 1)                          # it has seen the hero
	m.receive_hit(1, 1.0, h.global_position)
	h.global_position = Vector2(1200, 300)        # far past the leash
	await _tick(p, h, 600)
	var ok := not m.provoked and m.state in ["idle", "return"]
	var why := "boar still provoked=%s state=%s after the hero left" % [m.provoked, m.state]
	await _done(world)
	return "" if ok else why

func test_deer_drops_double_gold():
	var m := Monster.new()
	m.kind = "deer"
	var g := m.gold_mult()
	m.kind = "kongkoi"
	var t := m.loot_table()
	m.free()
	if g != 2.0: return "deer gold x%s (want x2)" % g
	return "" if t == "kongkoi" else "kongkoi loot table %s" % t

## Spec M3g §2: which monsters live in which room (kind: count, lowest level); 2 kinds, 15-25 each.
func test_rooms_hold_the_spec_monsters():
	var want := {
		"c1r1": {"deer": 8, "boar": 8}, "c1r0": {"wolf": 10, "deer": 6}, "c0r1": {"boar": 10, "deer": 6},
		"w1": {"boar": 10, "wolf": 8}, "c0r0": {"boar": 10, "macaque": 6}, "c2r1": {"boar": 10, "macaque": 8},
		"c2r2": {"wolf": 10, "macaque": 6}, "c2r0": {"deer": 8, "macaque": 8}, "c0r2": {"shroom": 10, "viper": 6},
		"e0": {"wolf": 12, "macaque": 8}, "c1r2": {"wolf": 12, "shroom": 8}, "e2": {"shroom": 12, "wolf": 10},
		"c0r3": {"viper": 10, "kongkoi": 6}, "c1r3": {"viper": 10, "shroom": 10},
		"c2r3": {"kongkoi": 10, "viper": 8}, "w3": {"kongkoi": 12, "macaque": 8},
	}
	var lv := {"c1r1": 1, "c1r0": 1, "c0r1": 2, "w1": 2, "c0r0": 3, "c2r1": 3, "c2r2": 3, "c2r0": 4,
		"c0r2": 4, "e0": 4, "c1r2": 5, "e2": 6, "c0r3": 7, "c1r3": 8, "c2r3": 9, "w3": 8}
	var rooms := RoomSet.open()
	for id in want:
		var got := {}
		var low := 99
		var high := 0
		var total := 0
		for m in rooms.room(id).get("monsters", []):
			got[m.kind] = got.get(m.kind, 0) + int(m.count)
			total += int(m.count)
			low = mini(low, int(m.level))
			high = maxi(high, int(m.level))
			if int(m.count) > 6: return "%s has a group of %d (max 6)" % [id, m.count]
		if got != want[id]: return "%s has %s (spec %s)" % [id, got, want[id]]
		if total < 15 or total > 25: return "%s has %d monsters (15-25)" % [id, total]
		if low != lv[id]: return "%s lowest level %d (spec %d)" % [id, low, lv[id]]
		if (id == "c2r3" or id == "w3") and high != 10: return "%s has no Lv10 kongkoi" % id
	return ""

## M3g §1: respawn 9 s; gold and drop chances x0.5 per kill.
func test_horde_respawn_and_loot():
	if Balance.num("wolf.respawn") != 9.0: return "respawn %s s (spec 9)" % Balance.num("wolf.respawn")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var ore := 0
	var n := 4000
	var gold_max := 0
	for i in n:
		for it in Loot.roll("wolf", 1, rng):
			if it.id == "ore_himmapan": ore += 1
			if it.id == "gold": gold_max = maxi(gold_max, it.count)
	var rate := float(ore) / n
	var want := Balance.num("loot.wolf.ore") * 0.5
	if absf(rate - want) > 0.03: return "ore rate %.3f (want ~%.3f)" % [rate, want]
	var gmax := int(round((Balance.num("loot.wolf.gold_max") + 1) * 0.5))
	return "" if gold_max <= gmax else "gold up to %d (max %d)" % [gold_max, gmax]

## The hero's start point is kept clear like a warp arrival (start room is all passive anyway).
func test_start_room_all_passive():
	var rooms := RoomSet.open()
	for m in rooms.room(rooms.start).get("monsters", []):
		var t := "passive" if m.kind == "boar" else String(Balance._lookup("monsters.%s.temper" % m.kind)) if m.kind != "wolf" else "aggressive"
		if t == "aggressive" or t == "ambush": return "start room has a %s (attacks first)" % m.kind
	return ""

## Review fix: a passive monster that was hit fights alone; its calm group-mates stay calm.
func test_hit_passive_does_not_wake_its_group():
	var world: Node2D = await _world()
	var h := _hero(world, Vector2(330, 300))
	var p := _pack(world, "boar", Vector2(300, 300), 1, 3)
	await _tick(p, h, 1)
	var m: Monster = p.wolves[0]
	m.provoked = true                      # hit while walking home, now idle at home
	await _tick(p, h, 30)
	var others := []
	for w in p.wolves:
		if w != m: others.append(w.state)
	var st := m.state
	_done(world)
	if st == "idle": return "the provoked boar never went for the hero"
	return "" if not ("chase" in others or "bite" in others or "lunge_warn" in others) else "group-mates joined: %s" % [others]

## Review fix: the ring warning's fill polygons triangulate (no error spam, the fill shows).
func test_ring_warning_fill_triangulates():
	var r: Node2D = load("res://scripts/monsters/ring_warning.gd").new()
	var tri := Geometry2D.triangulate_polygon(r._ellipse(40.0))
	var line: PackedVector2Array = r._ellipse(40.0, true)
	r.free()
	if tri.is_empty(): return "ring fill does not triangulate"
	return "" if line[0] == line[line.size() - 1] else "outline not closed"

## Review fix: a hidden viper is not locked on to; once revealed it is.
func test_hidden_viper_is_not_a_target():
	var world: Node2D = await _world()
	var h := _hero(world, Vector2(450, 300))
	var p := _pack(world, "viper", Vector2(300, 300), 4)
	await tree.physics_frame
	var m: Monster = p.wolves[0]
	m.global_position = Vector2(300, 300)
	await _tick(p, h, 5)
	var far: Node2D = h.current_target()
	h.global_position = Vector2(350, 300)
	await _tick(p, h, 5)
	var near: Node2D = h.current_target()
	_done(world)
	if far != null: return "a hidden viper 150 px away is the hero's target"
	return "" if near == m else "a revealed viper 50 px away is not targeted"

## Review fix: a deer that stops fleeing inside its leash walks home without healing.
func test_deer_flee_does_not_heal_inside_leash():
	var world: Node2D = await _world()
	var h := _hero(world, Vector2(330, 300))
	var p := _pack(world, "deer", Vector2(300, 300), 3)
	await _tick(p, h, 1)
	var m: Monster = p.wolves[0]
	m.global_position = Vector2(300, 300)
	m.receive_hit(20, 1.0, h.global_position)
	var hurt := m.health.hp
	await _tick(p, h, 240, func(): if m.global_position.distance_to(m.home) > 300.0: m.global_position = m.home + (m.global_position - m.home).limit_length(300.0))
	var hp := m.health.hp
	var st := m.state
	_done(world)
	if hurt >= m.health.max_hp: return "the test hit did no damage"
	return "" if hp == hurt else "deer healed %d -> %d after fleeing inside the leash (state %s)" % [hurt, hp, st]

## Review fix (spec §2): the macaque hops back once, about hop_back px, when the hero is under 50 px.
func test_macaque_hops_back_once():
	var world: Node2D = await _world()
	var h := _hero(world, Vector2(330, 300))
	var p := _pack(world, "macaque", Vector2(300, 300), 3)
	await _tick(p, h, 1)
	var m: Monster = p.wolves[0]
	m.global_position = Vector2(300, 300)
	m.start_chase(h)
	h.global_position = Vector2(330, 300)
	var start := m.global_position
	var hopped := [false]
	await _tick(p, h, 16, func(): if m.state == "hop": hopped[0] = true)
	var moved := m.global_position.distance_to(start)
	_done(world)
	if not hopped[0]: return "no hop with the hero 30 px away"
	return "" if moved >= 45.0 and moved <= 75.0 else "hop moved %d px (want ~60)" % moved

## Review fix: right after a warp (screen fading in) a group does not notice the hero.
func test_group_calm_during_fade():
	var world: Node2D = await _world()
	var h := _hero(world, Vector2(380, 300))
	var p := _pack(world, "wolf", Vector2(300, 300), 1, 1)
	await tree.physics_frame
	p.wolves[0].global_position = Vector2(300, 300)
	p.calm = 0.3
	await _tick(p, h, 10)
	var during: String = p.wolves[0].state
	await _tick(p, h, 20)
	var after: String = p.wolves[0].state
	_done(world)
	if during != "idle": return "wolf %s during the fade" % during
	return "" if after != "idle" else "wolf never noticed the hero after the fade"

## Review fix: no group that attacks first has its home within its aggro range of a warp arrival.
func test_no_aggressive_home_by_an_arrival():
	var rooms := RoomSet.open()
	var bad := []
	for id in rooms.ids():
		for m in rooms.room(id).get("monsters", []):
			var k := String(m.kind)
			var t := "aggressive" if k == "wolf" else String(Balance._lookup("monsters.%s.temper" % k))
			if t != "aggressive" and t != "ambush": continue
			var path := "monsters.%s.aggro" % k
			var aggro := Balance.num(path) if Balance.has(path) else Balance.num("wolf.aggro")
			var home := Vector2(m.at[0], m.at[1])
			for w in rooms.room(id).warps:
				var d := rooms.arrival(id, w.id).distance_to(home)
				if d <= aggro: bad.append("%s %s by %s arrival: %d px (aggro %d)" % [id, k, w.id, d, aggro])
	return "" if bad.is_empty() else ", ".join(bad)
