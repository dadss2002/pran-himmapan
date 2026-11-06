class_name LootDrop
extends Node2D
## An item lying on the ground. Pops out of the corpse, bobs, and flies to the hero once it is
## within pickup.magnet px (pickup.speed px/s). Gone after pickup.lifetime s. If the bag has no
## room it stays put and raises bag_full_notice (gold always fits: it is a wallet).

signal collected(item_id: String, count: int)

var item_id := ""
var count := 1
var expired := false
var bag_full_notice := false
var _age := 0.0
var _pop_from := Vector2.ZERO
var _pop_to := Vector2.ZERO
var _popping := false
var _icon: Sprite2D
var glint: FxSprite = null     # gems twinkle (item_glint) so they stand out from ore
var item: Dictionary = {}      # equipment: {base, rarity, level, opts}; empty for stackables
var beam: FxSprite = null      # rarity_beam under rare-and-up equipment, tinted by rarity

static func icon_path(id: String) -> String:
	if id == "gold": return "res://assets/items/coin_gold.png"
	if Gear.is_gear(id): return "res://assets/items/%s.png" % Gear.icon_name(id)
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
	if id.begins_with("gem_"):
		d.glint = FxSprite.make("item_glint", true)
		d.glint.position = d._icon.position
		d.add_child(d.glint)
		d.glint.play("item_glint")
	return d

## Equipment on the ground. Rare and up stand in a light beam of their rarity colour.
static func make_item(it: Dictionary) -> LootDrop:
	var d := make(String(it.base), 1)
	d.item = it.duplicate(true)
	if Gear.rarity_rank(String(it.rarity)) >= Gear.rarity_rank(String(Balance.data()["beam_from_rarity"])):
		d.beam = FxSprite.make("rarity_beam", true)
		d.beam.modulate = Color(Gear.rarity_color(String(it.rarity)), 0.6)
		d.beam.show_behind_parent = true
		d.add_child(d.beam)
		d.move_child(d.beam, 0)
		d.beam.play("rarity_beam")
	return d

## n spots pickup.scatter_min–scatter_max px from of center, skipping blocked ones (e.g. inside a post).
static func scatter(center: Vector2, n: int, rng: RandomNumberGenerator, blocked: Callable) -> Array:
	var out: Array = []
	var tries := 0
	while out.size() < n and tries < n * 40:
		tries += 1
		var p := center + Vector2(rng.randf_range(Balance.num("pickup.scatter_min"), Balance.num("pickup.scatter_max")), 0).rotated(rng.randf_range(0, TAU))
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
	bag_full_notice = false
	_age += delta
	if _popping:
		var t := clampf(_age / Balance.num("pickup.pop_time"), 0.0, 1.0)
		position = _pop_from.lerp(_pop_to, t) + Vector2(0, -18.0 * sin(PI * t))
		if t >= 1.0: _popping = false
		return false
	if _age >= Balance.num("pickup.lifetime"):
		_expire()
		return false
	if _icon: _icon.position.y = -6 + sin(_age * 4.0) * 1.5
	if glint and _icon: glint.position = _icon.position
	if hero == null or hero.state == "dead": return false
	var hp: Vector2 = hero.global_position if hero.is_inside_tree() else hero.position
	var to := hp - position
	if to.length() > Balance.num("pickup.magnet"): return false
	bag_full_notice = (not inv.has_free_slot()) if not item.is_empty() else inv.is_full_for(item_id)
	if bag_full_notice: return false
	var stepd := Balance.num("pickup.speed") * delta
	if to.length() <= maxf(Balance.num("pickup.contact"), stepd):
		position = hp
		if not item.is_empty():
			if not inv.add_item(item): return false
			collected.emit(item_id, 1)
			expired = true
			if is_inside_tree(): queue_free()
			return true
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
