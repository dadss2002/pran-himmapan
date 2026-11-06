extends Node2D
## M2a test ground. PLACEHOLDER art: checker floor + wooden posts drawn in code, to be replaced
## by the PixelLab forest map. Three ghost-wolf packs from balance.json "packs"; Y-sorted World.

const TILE := 32
const GREENS := [Color("#255631"), Color("#316134")]
const POSTS := [Vector2(760, 470), Vector2(1160, 470), Vector2(960, 760), Vector2(640, 860),
	Vector2(1300, 820), Vector2(300, 520), Vector2(1620, 560), Vector2(480, 1100), Vector2(1450, 1120)]
const HERO_SCENE := preload("res://scenes/hero.tscn")

var world: Node2D
var hero: Hero
var hud: Hud
var packs: Array = []
var _built := false
var lock_ring: FxSprite

func _ready() -> void:
	build()

func build() -> void:
	if _built: return
	_built = true
	world = Node2D.new()
	world.name = "World"
	world.y_sort_enabled = true
	add_child(world)
	for p in POSTS:
		world.add_child(_post(p))
	var spawn: Array = Balance.data()["hero_spawn"]
	hero = HERO_SCENE.instantiate()
	hero.spawn_point = Vector2(spawn[0], spawn[1])
	hero.position = hero.spawn_point
	world.add_child(hero)
	hero.setup_sprites()
	hero.health.damaged.connect(func(a, c): _number(hero.global_position + Vector2(0, -40), a, c, true))
	hero.rolled.connect(func(_d): _fx("roll_dust", hero.global_position))
	var cam := Camera2D.new()
	var size: Array = Balance.data()["map_size"]
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(size[0])
	cam.limit_bottom = int(size[1])
	hero.add_child(cam)
	for spec in Balance.data()["packs"]:
		var pack := WolfPack.new()
		pack.level = int(spec.level)
		pack.count = int(spec.count)
		pack.home = Vector2(spec.at[0], spec.at[1])
		pack.y_sort_enabled = true
		pack.hero = hero
		world.add_child(pack)
		if pack.wolves.is_empty(): pack.spawn()
		for w in pack.wolves:
			var wolf: Wolf = w
			wolf.health.damaged.connect(func(a, c): _on_wolf_hit(wolf, a, c))
		packs.append(pack)
	lock_ring = FxSprite.make("lock_on", true)
	lock_ring.visible = false
	world.add_child(lock_ring)        # y-sorted: sits just above the target's feet line
	world.move_child(lock_ring, 0)
	lock_ring.play("lock_on")
	hud = Hud.new()
	add_child(hud)
	if hud.hp_label == null: hud.build()
	hud.bind(hero)
	var label := Label.new()
	label.text = "PLACEHOLDER floor/posts (not PixelLab art)"
	label.add_theme_font_size_override("font_size", 8)
	label.modulate.a = 0.6
	label.position = Vector2(200, 4)
	hud.add_child(label)
	queue_redraw()

func _on_wolf_hit(w: Wolf, amount: int, crit: bool) -> void:
	_number(w.hurt_point() + Vector2(randf_range(-6, 6), -30), amount, crit, false)
	_fx("hit_spark", w.hurt_point())

func _process(_delta: float) -> void:
	if lock_ring == null or hero == null: return
	var t := hero.current_target() if hero.state != "dead" else null
	lock_ring.visible = t != null
	if t: lock_ring.global_position = t.global_position - Vector2(0, 0.5)

func _number(at: Vector2, amount: int, crit: bool, hurt: bool) -> void:
	if not is_inside_tree(): return
	var d := DamageNumber.make(amount, crit, hurt)
	d.position = at
	add_child(d)

func _fx(fx_name: String, at: Vector2) -> void:
	if not is_inside_tree(): return
	var f := FxSprite.make(fx_name)
	f.position = at
	f.z_index = 40
	add_child(f)
	f.play(fx_name)

func _draw() -> void:
	var size: Array = Balance.data()["map_size"]
	for y in int(size[1]) / TILE:
		for x in int(size[0]) / TILE:
			draw_rect(Rect2(x * TILE, y * TILE, TILE, TILE), GREENS[(x + y) % 2])

func _post(at: Vector2) -> StaticBody2D:
	var b := StaticBody2D.new()
	b.position = at  # origin = base of the post
	var c := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(14, 8)
	c.shape = r
	c.position = Vector2(0, -4)
	b.add_child(c)
	var v := Polygon2D.new()
	v.color = Color("#623425")
	v.polygon = PackedVector2Array([Vector2(-7, 0), Vector2(7, 0), Vector2(7, -40), Vector2(-7, -40)])
	b.add_child(v)
	var cap := Polygon2D.new()
	cap.color = Color("#a4712d")
	cap.polygon = PackedVector2Array([Vector2(-7, -40), Vector2(7, -40), Vector2(7, -44), Vector2(-7, -44)])
	b.add_child(cap)
	return b
