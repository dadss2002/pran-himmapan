extends SceneTree
## Real-render screenshots (not headless):
## xvfb-run -a godot --path . --rendering-driver opengl3 --script tests/screenshots.gd
## Writes docs/preview/m1_*.png at 2x.

const OUT := "res://docs/preview/"

func _initialize() -> void:
	_run()

func _snap(name: String) -> void:
	await process_frame
	await process_frame
	var img := root.get_texture().get_image()
	img.resize(img.get_width() * 2, img.get_height() * 2, Image.INTERPOLATE_NEAREST)
	var path := ProjectSettings.globalize_path(OUT + name)
	img.save_png(path)
	print("saved ", path, " ", img.get_size())

func _frames(n: int) -> void:
	for i in n:
		await physics_frame  # physics ticks are real-time; render frames are not under xvfb

func _run() -> void:
	var ground: Node2D = load("res://scenes/test_ground.tscn").instantiate()
	root.add_child(ground)
	var hero: Hero = ground.get_node("World/Hero")
	await _frames(30)
	await _snap("m1_idle_south.png")

	Input.action_press("move_right"); Input.action_press("move_up")
	await _frames(25)
	await _snap("m1_walk_north_east.png")
	Input.action_release("move_right"); Input.action_release("move_up")

	Input.action_press("move_right")
	await _frames(3)
	Input.action_release("move_right")
	await _frames(3)
	hero.try_shoot()
	await _frames(32)  # past the release frame, arrow in flight
	await _snap("m1_shoot_east.png")
	await _frames(40)

	# contact sheet: every facing, idle (bow on back) and mid-shot (bow in hand)
	ground.queue_free()
	await process_frame
	var bg := ColorRect.new()
	bg.color = Color("#255631"); bg.size = Vector2(640, 360)
	root.add_child(bg)
	var hero_scene: PackedScene = load("res://scenes/hero.tscn")
	for row in 2:
		for f in 8:
			var h: Hero = hero_scene.instantiate()
			h.set_physics_process(false)
			h.position = Vector2(48 + f * 76, 150 + row * 150)
			root.add_child(h)
			h.facing = f
			if row == 1:
				h.state = "shoot"
				h._refresh(true)
				h.body.pause()
				h.body.frame = 4
			else:
				h._refresh(true)
				h.body.pause()
	await _snap("m1_bow_layer_8dir.png")
	quit(0)
