extends SceneTree
## Gameplay demo recorder (not a test): xvfb-run -a godot --path . --rendering-driver opengl3 --script tools/demo_video.gd
## Plays the test ground (M3c rooms, M3d monsters) with scripted input and writes every 2nd physics frame to /tmp/pran_demo/f_#####.png.
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

## Walk along the room's walk grid (8 px cells) to `to`.
func _go(to: Vector2, max_frames := 600) -> void:
	var nav: AStarGrid2D = g._navs[g.room_id]
	var path := nav.get_point_path(Vector2i((hero.global_position / 8.0).floor()), Vector2i((to / 8.0).floor()))
	var k := 1
	var room: String = g.room_id
	for f in max_frames:
		if hero.global_position.distance_to(to) < 10.0 or g.room_id != room: break
		while k < path.size() - 1 and hero.global_position.distance_to(path[k]) < 6.0: k += 1
		var target: Vector2 = path[mini(k, path.size() - 1)] if path.size() > 1 else to
		hero.external_input = (target - hero.global_position).normalized()
		await _frames(1)
	hero.external_input = Vector2.ZERO

## Walk onto a warp and wait until the next room is in.
func _through(warp_id: String) -> void:
	var from: String = g.room_id
	await _go(g.rooms.warp_at(from, warp_id), 900)
	for i in 120:
		if g.room_id != from: break
		hero.external_input = (g.rooms.warp_at(from, warp_id) - hero.global_position).normalized()
		await _frames(1)
	hero.external_input = Vector2.ZERO
	await _frames(30)

func _pack(kind: String) -> WolfPack:
	for p in g.packs:
		if p.kind == kind: return p
	return null

func _alive(p: WolfPack) -> int:
	var c := 0
	for w in p.wolves:
		if w.state != "dead": c += 1
	return c

func _fight_for(p: WolfPack, frames: int) -> void:
	Input.action_press("attack")
	await _frames(frames)
	Input.action_release("attack")

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
	# start room: hit a deer, it runs away
	var deer := _pack("deer")
	await _go(deer.home + Vector2(-60, 30))
	await _fight_for(deer, 150)
	await _frames(40)
	# west to the boars: they leave you alone until you shoot one
	await _through("west")
	var boars := _pack("boar")
	await _go(boars.home + Vector2(90, 40))
	await _frames(60)
	await _fight(boars, 1200)
	await _frames(30)
	await _collect_drops(300)
	g.hud.open_bag()
	await _idle(90)
	g.hud.bag_panel.close()
	await _idle(10)
	# south to the pond: poison mushrooms and a hidden viper
	await _through("south")
	var shrooms := _pack("shroom")
	await _go(shrooms.home + Vector2(-90, 0))
	await _fight(shrooms, 900)
	await _frames(60)
	print("DEMO frames=%d" % n)
	quit(0)
