class_name LootDrop
extends Node2D
## An item lying on the ground. Pops out of the corpse, bobs, and flies to the hero once it is
## within pickup.magnet px (pickup.speed px/s). Gone after pickup.lifetime s. If the bag has no
## room it stays put and raises bag_full_notice (gold always fits: it is a wallet).

signal collected(item_id: String, count: int)

const CONTACT := 8.0
const POP_TIME := 0.25

var item_id := ""
var count := 1
var expired := false
var bag_full_notice := false
var _age := 0.0
var _pop_from := Vector2.ZERO
var _pop_to := Vector2.ZERO
var _popping := false
var _icon: Sprite2D

static func icon_path(id: String) -> String:
	if id == "gold": return "res://assets/items/coin_gold.png"
	if id.begins_with("gem_"):
		var group: String = Balance.data()["gem_icon_group"].get(id.trim_prefix("gem_"), "blue")
		return "res://assets/items/gem_%s.png" % group
	return "res://assets/items/%s.png" % id

static func make(id: String, n: int) -> LootDrop:
	var d := LootDrop.new()
	d.item_id = id
	d.count = n
	d._icon = Sprite2D.new()
	d._icon.texture = load(icon_path(id))
	d._icon.scale = Vector2.ONE * (14.0 / 48.0 if id == "gold" else 18.0 / 48.0)
	d._icon.position = Vector2(0, -6)
	d._icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	d.add_child(d._icon)
	return d

## n spots within 24 px of center, skipping blocked ones (e.g. inside a post).
static func scatter(center: Vector2, n: int, rng: RandomNumberGenerator, blocked: Callable) -> Array:
	var out: Array = []
	var tries := 0
	while out.size() < n and tries < n * 40:
		tries += 1
		var p := center + Vector2(rng.randf_range(6, 24), 0).rotated(rng.randf_range(0, TAU))
		if not blocked.call(p): out.append(p)
	while out.size() < n: out.append(center)   # fall back to the corpse spot
	return out

func pop_out(from: Vector2, to: Vector2) -> void:
	_pop_from = from
	_pop_to = to
	position = from
	_popping = true
	_age = 0.0

func settle() -> void:
	_popping = false

## Returns true on the frame the item is collected.
func step(delta: float, hero: Hero, inv: Inventory) -> bool:
	if expired: return false
	_age += delta
	if _popping:
		var t := clampf(_age / POP_TIME, 0.0, 1.0)
		position = _pop_from.lerp(_pop_to, t) + Vector2(0, -18.0 * sin(PI * t))
		if t >= 1.0: _popping = false
		return false
	if _age >= Balance.num("pickup.lifetime"):
		_expire()
		return false
	if _icon: _icon.position.y = -6 + sin(_age * 4.0) * 1.5
	if hero == null or hero.state == "dead": return false
	var hp: Vector2 = hero.global_position if hero.is_inside_tree() else hero.position
	var to := hp - position
	if to.length() > Balance.num("pickup.magnet"): return false
	bag_full_notice = inv.is_full_for(item_id)
	if bag_full_notice: return false
	var stepd := Balance.num("pickup.speed") * delta
	if to.length() <= maxf(CONTACT, stepd):
		position = hp
		var left := inv.add(item_id, count)
		if left > 0:          # only part fitted
			count = left
			return false
		collected.emit(item_id, count)
		expired = true
		if is_inside_tree(): queue_free()
		return true
	position += to.normalized() * stepd
	return false

func _expire() -> void:
	expired = true
	if is_inside_tree(): queue_free()
