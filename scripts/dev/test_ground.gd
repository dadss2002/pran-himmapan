extends Node2D
## M1 test ground. PLACEHOLDER art only: flat checker floor + wooden posts drawn in code,
## to be replaced by the PixelLab forest map. Y-sort on World so the hero walks behind/in front of posts.

const TILE := 32
const SIZE := Vector2i(30, 20)
const GREENS := [Color("#255631"), Color("#316134")]
const POSTS := [Vector2(220, 150), Vector2(380, 150), Vector2(300, 260), Vector2(470, 300), Vector2(150, 330)]

@onready var world: Node2D = $World
@onready var hero: Hero = $World/Hero

func _ready() -> void:
	for p in POSTS:
		world.add_child(_post(p))

func _draw() -> void:
	for y in SIZE.y:
		for x in SIZE.x:
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
