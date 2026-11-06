extends RefCounted
## In-tree wolf tests: real physics bodies, collisions and a full pack (review findings 1-3).

var tree: SceneTree
const DT := 1.0 / 60.0

func setup(t: SceneTree) -> void:
	tree = t

func _world() -> Node2D:
	var w := Node2D.new()
	tree.root.add_child(w)
	return w

func _hero(world: Node2D, pos: Vector2) -> Hero:
	var h: Hero = load("res://scenes/hero.tscn").instantiate()
	h.position = pos
	world.add_child(h)
	h.set_physics_process(false)
	return h

func _pack(world: Node2D, count: int, home: Vector2) -> WolfPack:
	var p := WolfPack.new()
	p.level = 1
	p.count = count
	p.home = home
	world.add_child(p)
	p.set_physics_process(false)
	return p

func _tick(p: WolfPack, h: Hero, frames: int) -> void:
	for i in frames:
		await tree.physics_frame
		h.step(DT, Vector2.ZERO)
		p.step_all(DT, h)

func test_every_wolf_in_a_pack_gets_to_bite():
	var world := _world()
	var h := _hero(world, Vector2(300, 300))
	var p := _pack(world, 4, Vector2(220, 300))
	h.health.setup(100000)            # keep the hero alive for the whole test
	var bit := {}
	for i in 300:
		await tree.physics_frame
		h.step(DT, Vector2.ZERO)
		p.step_all(DT, h)
		for w in p.wolves:
			if w.state == "bite": bit[w] = true
	var n := bit.size()
	world.queue_free()
	await tree.process_frame
	return "" if n == 4 else "only %d of 4 wolves ever bit a standing hero in 5 s" % n

func test_side_lunge_hits_in_tree():
	Combat.rng.seed = 5
	var world := _world()
	var h := _hero(world, Vector2(400, 300))
	var p := _pack(world, 1, Vector2(300, 300))
	var w: Wolf = p.wolves[0]
	await tree.physics_frame
	w.global_position = Vector2(300, 300)     # 100 px to the side: lunge range
	await _tick(p, h, 60)
	var lost := 120 - h.health.hp
	world.queue_free()
	await tree.process_frame
	return "" if lost >= 8 and lost <= 9 else "side lunge did %d (want 8-9 from a x1.5 lunge)" % lost
