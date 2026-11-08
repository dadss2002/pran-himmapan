class_name WolfPack
extends Node2D
## A pack of ghost wolves sharing aggro and a single lunge token; respawns its dead after
## wolf.respawn seconds. The pack node sits at the world origin; wolves use world positions.
## M4d addendum 4: a room group's pack may hold several piles (MonsterPiles.place): `piles` gives each its
## home and spawn points; a monster's home is its pile's centre, it spawns and respawns on its own point, and
## seeing or being hit wakes only its pile. Monsters closer than one body width push apart gently
## (monster_push.speed px/s at most, walls stop it, the hero is never pushed), across packs too.

const WOLF_SCENE := preload("res://scenes/wolf.tscn")
const MONSTER_SCENE := preload("res://scenes/monster.tscn")

@export var level := 1
@export var count := 4
@export var home := Vector2.ZERO
@export var kind := "wolf"      # "wolf" or a Balance "monsters" id (deer, boar, shroom, macaque, viper, kongkoi)
var blocked := Callable()       # the room's blocked_at, for projectiles
var piles: Array = []           # [{home: Vector2, points: [Vector2]}] (MonsterPiles); empty = one ring at home

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
	var spots := []                     # [pile index, home, point] per monster
	for pi in piles.size():
		for q in piles[pi].points: spots.append([pi, piles[pi].home, q])
	if spots.size() != count: spots.clear()
	for i in count:
		var w: Wolf = WOLF_SCENE.instantiate() if kind == "wolf" else MONSTER_SCENE.instantiate()
		if kind != "wolf": w.set("kind", kind)
		w.level = level
		w.pack = self
		if spots.is_empty():
			w.home = home
			w.position = home + Vector2(Balance.num("wolf.pack_ring"), 0).rotated(TAU * i / count) * Vector2(1, 0.7)
		else:
			w.pile = int(spots[i][0])
			w.home = spots[i][1]
			w.position = spots[i][2]
			w.spawn_at = spots[i][2]
		add_child(w)
		w.setup()
		w.roll_elite()
		w.died.connect(_on_wolf_died)
		wolves.append(w)

## The hero was seen (or one was hit): every monster of `who`'s pile chases; no `who` (or one pile): all.
func alert(h: Hero, who: Wolf = null) -> void:
	hero = h
	for w in wolves:
		if who == null or who.pile < 0 or w.pile == who.pile: w.start_chase(h)

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
	_separate(delta)
	tick(delta)

func _enter_tree() -> void:
	add_to_group("monster_packs")

## Keep live monsters from stacking on one spot (they do not collide with each other; M4d addendum 4):
## each of this pack's monsters closer than one body width (centre to centre) to another live monster of any
## pack in the room moves away from it, at most monster_push.speed px/s, by move_and_collide (walls stop it;
## the hero is not in the monsters' collision mask, so he is never pushed). Each pack moves only its own
## monsters, so a pair from two packs is pushed once from each side. Lunging monsters neither push nor move.
func _separate(delta: float) -> void:
	var others: Array = wolves
	if is_inside_tree():
		others = []
		for p in get_tree().get_nodes_in_group("monster_packs"):
			if p.get_parent() == get_parent(): others.append_array(p.wolves)
	var step := Balance.num("monster_push.speed") * delta
	for a in wolves:
		if not a.is_alive() or a.state in ["lunge_warn", "lunge"]: continue
		var away := Vector2.ZERO
		for b in others:
			if b == a or not is_instance_valid(b) or not b.is_alive() or b.state in ["lunge_warn", "lunge"]: continue
			var d: Vector2 = a.position - b.position
			var dist := d.length()
			var gap: float = (a.body_width() + b.body_width()) * 0.5
			if dist >= gap: continue
			# exactly on top of each other: split by their order so the two go opposite ways
			var dir := d / dist if dist > 0.01 else (Vector2.RIGHT if a.get_instance_id() > b.get_instance_id() else Vector2.LEFT)
			away += dir * (gap - dist) * 0.5
		if away != Vector2.ZERO: a.push(away.limit_length(step))

func _physics_process(delta: float) -> void:
	step_all(delta, hero)
