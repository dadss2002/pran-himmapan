class_name WolfPack
extends Node2D
## A pack of ghost wolves sharing aggro and a single lunge token; respawns its dead after
## wolf.respawn seconds. The pack node sits at the world origin; wolves use world positions.

const WOLF_SCENE := preload("res://scenes/wolf.tscn")
const MONSTER_SCENE := preload("res://scenes/monster.tscn")

@export var level := 1
@export var count := 4
@export var home := Vector2.ZERO
@export var kind := "wolf"      # "wolf" or a Balance "monsters" id (deer, boar, shroom, macaque, viper, kongkoi)
var blocked := Callable()       # the room's blocked_at, for projectiles

var wolves: Array = []
var hero: Hero
var nav: AStarGrid2D = null     # the map's walk grid (PaintedLayout.make_nav), shared by the pack
var calm := 0.0                 # seconds the group ignores the hero (the room fade-in after a warp)
var unreachable_at := Vector2.INF   # where the hero was when no route reached him: no re-aggro there
var _lunger: Wolf = null
var _respawn := {}      # Wolf -> seconds left

func _ready() -> void:
	if wolves.is_empty():
		spawn()

func spawn() -> void:
	for i in count:
		var w: Wolf = WOLF_SCENE.instantiate() if kind == "wolf" else MONSTER_SCENE.instantiate()
		if kind != "wolf": w.set("kind", kind)
		w.level = level
		w.pack = self
		w.home = home
		w.position = home + Vector2(Balance.num("wolf.pack_ring"), 0).rotated(TAU * i / count) * Vector2(1, 0.7)
		add_child(w)
		w.setup()
		w.roll_elite()
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
	calm = maxf(0.0, calm - delta)
	for w in _respawn.keys():
		_respawn[w] -= delta
		if _respawn[w] <= 0.0:
			_respawn.erase(w)
			w.revive()


func step_all(delta: float, h: Hero) -> void:
	for w in wolves:
		w.step(delta, h)
	_separate()
	tick(delta)

## Keep live wolves from stacking on one spot (they do not collide with each other).
func _separate() -> void:
	for i in wolves.size():
		for j in range(i + 1, wolves.size()):
			var a: Wolf = wolves[i]
			var b: Wolf = wolves[j]
			if not a.is_alive() or not b.is_alive(): continue
			if a.state in ["lunge_warn", "lunge"] or b.state in ["lunge_warn", "lunge"]: continue
			var d := b.position - a.position
			var dist := d.length()
			if dist < Balance.num("wolf.pack_spacing"):
				var dir := d.normalized() if dist > 0.01 else Vector2.RIGHT
				var push := dir * minf((Balance.num("wolf.pack_spacing") - dist) * 0.5, 1.5)
				a.push(-push)
				b.push(push)

func _physics_process(delta: float) -> void:
	step_all(delta, hero)
