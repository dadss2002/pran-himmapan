extends SceneTree
## Gameplay demo recorder (not a test): xvfb-run -a godot --path . --rendering-driver opengl3 --script tools/demo_video.gd
## Plays the test ground with scripted input and writes every 2nd physics frame to /tmp/pran_demo/f_#####.png.
## Build the video afterwards with ffmpeg (see docs or the PR). Uses a throwaway save.

const DIR := "/tmp/pran_demo/"
var g: Node2D
var hero: Hero
var n := 0
var tick := 0

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_run()

func _shot() -> void:
	var img := root.get_texture().get_image()
	img.save_png(DIR + "f_%05d.png" % n)
	n += 1

func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		tick += 1
		if tick % 2 == 0: _shot()

func _idle(count: int) -> void:          # while the tree is paused (bag / skills open)
	for i in count:
		await process_frame
		tick += 1
		if tick % 2 == 0: _shot()

func _walk(dir: Vector2, count: int) -> void:
	hero.external_input = dir.normalized()
	await _frames(count)
	hero.external_input = Vector2.ZERO

func _route(points: Array, max_each := 240) -> void:
	for t in points:
		for i in max_each:
			var to: Vector2 = t - hero.global_position
			if to.length() < 10: break
			hero.external_input = to.normalized()
			await _frames(1)
	hero.external_input = Vector2.ZERO

func _pack(level: int) -> WolfPack:
	for p in g.packs:
		if p.level == level: return p
	return null

func _alive(p: WolfPack) -> int:
	var c := 0
	for w in p.wolves:
		if w.state != "dead": c += 1
	return c

func _fight(p: WolfPack, max_frames: int) -> void:
	Input.action_press("attack")
	var i := 0
	while i < max_frames and _alive(p) > 0:
		if i == 40: hero.try_skill("piercing")
		if i == 160: hero.try_skill("spread")
		if i == 260: hero.try_dodge(Vector2(0, 1))
		if i % 300 == 299: hero.try_potion("hp")
		await _frames(1)
		i += 1
	Input.action_release("attack")

func _collect_drops(max_frames: int) -> void:
	for f in max_frames:
		var best: Node2D = null
		for d in g.drops:
			if is_instance_valid(d) and not d.expired:
				if best == null or hero.global_position.distance_to(d.global_position) < hero.global_position.distance_to(best.global_position):
					best = d
		if best == null: break
		var to: Vector2 = best.global_position - hero.global_position
		hero.external_input = to.normalized() if to.length() > 6 else Vector2.ZERO
		await _frames(1)
	hero.external_input = Vector2.ZERO

func _run() -> void:
	seed(7)
	var save := "user://demo_video_save.json"
	if FileAccess.file_exists(save): DirAccess.remove_absolute(ProjectSettings.globalize_path(save))
	g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = save
	root.add_child(g)
	await process_frame
	hero = g.hero
	hero.set_progress(12, 0)               # skills unlocked so both skill buttons show
	await _frames(40)
	var p1 := _pack(1)
	# from the plaza up the north trail to the ruins (Lv1 pack)
	await _route([hero.global_position + Vector2(-70, -10), Vector2(965, 470), Vector2(1030, 380), p1.home + Vector2(60, 90)])
	await _fight(p1, 900)
	await _frames(30)
	await _collect_drops(300)
	await _frames(20)
	g.hud.open_bag()
	await _idle(90)
	g.hud.bag_panel.close()
	await _idle(10)
	# back down past the plaza and west along the trail to the stone road
	await _route([Vector2(1030, 380), Vector2(965, 470), Vector2(880, 575), Vector2(640, 576), Vector2(470, 600), Vector2(410, 760)], 300)
	await _frames(40)
	print("DEMO frames=%d" % n)
	quit(0)
