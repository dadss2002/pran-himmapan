class_name WolfPack
extends Node2D
## A pack of ghost wolves sharing aggro and a single lunge token; respawns its dead after
## wolf.respawn seconds. The pack node sits at the world origin; wolves use world positions.

const WOLF_SCENE := preload("res://scenes/wolf.tscn")

@export var level := 1
@export var count := 4
@export var home := Vector2.ZERO

var wolves: Array = []
var hero: Hero
var _lunger: Wolf = null
var _respawn := {}      # Wolf -> seconds left

func _ready() -> void:
	if wolves.is_empty():
		spawn()

func spawn() -> void:
	for i in count:
		var w: Wolf = WOLF_SCENE.instantiate()
		w.level = level
		w.pack = self
		w.home = home
		w.position = home + Vector2(26, 0).rotated(TAU * i / count) * Vector2(1, 0.7)
		add_child(w)
		w.setup()
		w.died.connect(_on_wolf_died)
		wolves.append(w)

func alert(h: Hero) -> void:
	hero = h
	for w in wolves:
		w.start_chase(h)

func request_lunge(w: Wolf) -> bool:
	if _lunger == null or not is_instance_valid(_lunger) or _lunger.state not in ["lunge_warn", "lunge"]:
		_lunger = w
	return _lunger == w

func end_lunge(w: Wolf) -> void:
	if _lunger == w:
		_lunger = null

func _on_wolf_died(w: Wolf) -> void:
	_respawn[w] = Balance.num("wolf.respawn")

func tick(delta: float) -> void:
	for w in _respawn.keys():
		_respawn[w] -= delta
		if _respawn[w] <= 0.0:
			_respawn.erase(w)
			w.revive()

func step_all(delta: float, h: Hero) -> void:
	for w in wolves:
		w.step(delta, h)
	tick(delta)

func _physics_process(delta: float) -> void:
	step_all(delta, hero)
