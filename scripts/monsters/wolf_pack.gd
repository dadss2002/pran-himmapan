class_name WolfPack
extends Node2D
## A pack of ghost wolves sharing aggro and a single lunge token; respawns its dead after
## wolf.respawn seconds. The pack node sits at the world origin; wolves use world positions.
## M4d addendum 4: a room group's pack may hold several piles (MonsterPiles.place; a single is a pile of 1):
## `piles` gives each its home and spawn points; a monster's home is its pile's centre, it spawns and respawns
## on its own point, and seeing or being hit wakes only its pile (owner: "ปลุกแค่กองที่โดน/เห็น"). Each pile has
## its own lunge token and its own "hero unreachable here" spot. Monsters closer than one body width push apart
## gently at all times (monster_push.speed px/s at most, walls stop it, the hero is never pushed), across packs.

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
var _unreachable := {}  # pile -> where the hero was when no route reached him: that pile does not re-aggro there
var _lungers := {}      # pile -> the one monster of that pile allowed to lunge now
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

## One lunge at a time per pile (two piles of one group may each lunge). The token's holder may have been freed
## since: untyped until is_instance_valid (a typed Wolf var errors on a freed instance).
func request_lunge(w: Wolf) -> bool:
	var cur = _lungers.get(w.pile)
	if not is_instance_valid(cur) or cur.state not in ["lunge_warn", "lunge"]:
		_lungers[w.pile] = w
	return _lungers[w.pile] == w

func end_lunge(w: Wolf) -> void:
	if _lungers.get(w.pile) == w:
		_lungers.erase(w.pile)

## Where the hero stood when no route from w's pile reached him (INF: nowhere): that pile does not re-aggro there.
func unreachable_for(w: Wolf) -> Vector2:
	return _unreachable.get(w.pile, Vector2.INF)

func mark_unreachable(w: Wolf, at: Vector2) -> void:
	_unreachable[w.pile] = at

func _on_wolf_died(w: Wolf) -> void:
	_respawn[w] = Balance.num("wolf.respawn")

## Task 4 (RoomReset): each monster's kept_state() in spawn order, a dead one with its respawn seconds left.
func snapshot() -> Array:
	var out: Array = []
	for w in wolves:
		var st: Dictionary = w.kept_state()
		if not st.alive: st["respawn"] = float(_respawn.get(w, Balance.num("wolf.respawn")))
		out.append(st)
	return out

## Task 4: put back a snapshot() taken of this group when the hero left (same group, same piles, so the same
## monsters in the same order). The respawn time of the dead goes on from where it stopped (it does not run
## while the hero is in another room). A list of another size is ignored (the room spawns fresh).
func restore(kept: Array) -> void:
	if kept.size() != wolves.size(): return
	_respawn.clear()
	_lungers.clear()
	for i in wolves.size():
		var w: Wolf = wolves[i]
		w.restore_kept(kept[i])
		if not w.is_alive(): _respawn[w] = float(kept[i].get("respawn", Balance.num("wolf.respawn")))

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
	if is_inside_tree(): others = _room_monsters()
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

static var _room_frame := -1
static var _room_lists := {}     # parent instance id -> every monster of the packs under it (this physics frame)

## Every monster of the packs sharing this pack's parent; the group is read once per physics frame.
func _room_monsters() -> Array:
	var f := Engine.get_physics_frames()
	if f != _room_frame:
		_room_frame = f
		_room_lists = {}
		for p in get_tree().get_nodes_in_group("monster_packs"):
			var k: int = p.get_parent().get_instance_id() if p.get_parent() else 0
			if not _room_lists.has(k): _room_lists[k] = []
			_room_lists[k].append_array(p.wolves)
	var key: int = get_parent().get_instance_id() if get_parent() else 0
	# a pack added during this frame (its monsters not in the list yet): read the room again
	if not _room_lists.has(key) or (not wolves.is_empty() and not _room_lists[key].has(wolves[0])):
		_room_lists[key] = []
		for p in get_tree().get_nodes_in_group("monster_packs"):
			if p.get_parent() == get_parent(): _room_lists[key].append_array(p.wolves)
	return _room_lists[key]

func _physics_process(delta: float) -> void:
	step_all(delta, hero)
