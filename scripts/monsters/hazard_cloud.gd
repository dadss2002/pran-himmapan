extends Node2D
## Poison mist left where a poison mushroom died: for `time` seconds, a hero inside `radius` is
## poisoned (once per cloud).

var radius := 32.0
var time := 2.0
var per_tick := 1
var poison_time := 3.0
var hero: Hero
var _hit := false

func setup(at: Vector2, radius_: float, time_: float, per_tick_: int, poison_time_: float, hero_: Hero) -> void:
	position = at
	radius = radius_
	time = time_
	per_tick = per_tick_
	poison_time = poison_time_
	hero = hero_
	z_index = -5
	# The poisonous area as a faint purple ellipse, with the spore mist rising out of it.
	var disc := Polygon2D.new()
	disc.color = Color(0.6, 0.3, 0.75, 0.3)
	var pts := PackedVector2Array()
	for i in 24: pts.append(Vector2(radius, 0).rotated(TAU * i / 24) * Vector2(1, 0.6))
	disc.polygon = pts
	add_child(disc)
	if FxSprite._manifest().has("poison_mist"):
		var fx := FxSprite.make("poison_mist", true)
		fx.z_index = 10
		add_child(fx)
		fx.play("poison_mist")

func _physics_process(delta: float) -> void:
	step(delta)

func step(delta: float) -> void:
	time -= delta
	if not _hit and hero and is_instance_valid(hero) and hero.global_position.distance_to(position) <= radius:
		_hit = true
		hero.apply_poison(per_tick, poison_time)
	if time <= 0.0: queue_free()
