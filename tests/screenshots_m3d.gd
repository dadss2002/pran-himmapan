extends SceneTree
## M3c rooms + M3d monsters screenshots:
## xvfb-run -a godot --path . --rendering-driver opengl3 --script tests/screenshots_m3d.gd
## One shot per room (hero next to its first monster group, monsters frozen in place), a line-up of
## every kind, and the warnings (shroom ring, kongkoi stomp, poison mist, warp ring).

const OUT := "res://docs/preview/"
const SAVE := "user://shots_m3d_save.json"
var g: Node2D
var hero: Hero

func _initialize() -> void:
	_run()
	_watchdog()

func _watchdog() -> void:
	await create_timer(150.0).timeout
	print("watchdog: giving up")
	quit(1)

func _snap(name: String) -> void:
	for i in 3: await process_frame
	var img := root.get_texture().get_image()
	img.resize(img.get_width() * 2, img.get_height() * 2, Image.INTERPOLATE_NEAREST)
	img.save_png(ProjectSettings.globalize_path(OUT + name))
	print("saved ", name)

func _frames(n: int) -> void:
	for i in n: await physics_frame

func _freeze() -> void:
	for p in g.packs:
		p.set_physics_process(false)
		p.set_process(false)

func _room(id: String) -> void:
	g.go_to(id, "", false)
	await _frames(2)
	_freeze()
	var ms: Array = g.rooms.room(id).get("monsters", [])
	var at: Vector2 = Vector2(ms[0].at[0], ms[0].at[1]) + Vector2(-80, 50) if ms.size() > 0 else g.rooms.spawn(id)
	hero.global_position = at
	hero.velocity = Vector2.ZERO
	await _frames(4)

func _run() -> void:
	seed(3)
	if FileAccess.file_exists(SAVE): DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
	g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = SAVE
	root.add_child(g)
	await process_frame
	hero = g.hero
	hero.set_physics_process(false)
	await _frames(10)
	for id in g.rooms.ids():
		await _room(id)
		await _snap("m3d_room_%s.png" % id)
	# M3h elites: one elite per group in c1r2, one of them hurt so the HP bar shows
	await _room("c1r2")
	var first := true
	for p in g.packs:
		var e: Wolf = p.wolves[0]
		e.set_elite(true)
		if first:
			e.health.take_hit(int(e.health.max_hp * 0.4), false)
			first = false
	await _frames(4)
	await _snap("m3h_elite.png")
	# line-up: one of each kind beside the hero in the start room
	await _room("c1r1")
	var x := 250.0
	for k in ["wolf"] + Monster.KINDS:
		var p := WolfPack.new()
		p.kind = k
		p.level = 3
		p.count = 1
		p.home = Vector2(x, 300)
		g.add_child(p)
		g.packs.append(p)
		x += 44.0
	await _frames(2)
	_freeze()
	for p in g.packs:
		if p.kind != "deer" or p.wolves.size() == 1:
			for w in p.wolves:
				if p.home.y == 300: w.global_position = p.home
	hero.global_position = Vector2(390, 250)
	await _frames(4)
	await _snap("m3d_lineup.png")
	# attacks: a shroom ring warning and a kongkoi stomp warning, poison mist where a shroom died
	var shroom: Monster
	var kong: Monster
	for p in g.packs:
		if p.kind == "shroom" and p.home.y == 300: shroom = p.wolves[0]
		if p.kind == "kongkoi" and p.home.y == 300: kong = p.wolves[0]
	shroom._hero = hero
	kong._hero = hero
	shroom.state = "ring_warn"
	shroom._show_telegraph(true, shroom.global_position)
	kong.state = "ring_warn"
	kong._show_telegraph(true, kong.global_position)
	await _frames(20)
	await _snap("m3d_ring_warnings.png")
	shroom.health.take_hit(100000, false)
	await _frames(20)
	await _snap("m3d_poison_mist.png")
	# a warp ring at the start room's north exit
	g.go_to("c1r1", "", false)
	await _frames(2)
	_freeze()
	var w0: Dictionary = g.rooms.room("c1r1").warps[0]
	hero.global_position = Vector2(w0.at[0], w0.at[1]) + Vector2(0, 60)
	await _frames(8)
	await _snap("m3d_warp_ring.png")
	quit(0)
