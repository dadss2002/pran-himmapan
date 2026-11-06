extends Node2D
## The play ground: the PixelLab forest (data/map_forest.json via ForestLayout/ForestMap), the hero,
## three ghost-wolf packs (level/count from balance.json "packs", homes from the map); Y-sorted World.

const HERO_SCENE := preload("res://scenes/hero.tscn")

var world: Node2D
var layout: ForestLayout
var forest: ForestMap
var hero: Hero
var hud: Hud
var packs: Array = []
var drops: Array = []
var loot_rng := RandomNumberGenerator.new()
var _built := false
var _bag_full_cd := 0.0
var lock_ring: FxSprite
var save_path := SaveGame.PATH
var _autosave_t := 0.0

func _ready() -> void:
	build()

func build() -> void:
	if _built: return
	_built = true
	world = Node2D.new()
	world.name = "World"
	world.y_sort_enabled = true
	layout = ForestLayout.open()
	forest = ForestMap.new()
	add_child(forest)
	move_child(forest, 0)
	add_child(world)
	forest.build(layout, world)
	hero = HERO_SCENE.instantiate()
	hero.spawn_point = layout.hero_spawn
	hero.position = hero.spawn_point
	world.add_child(hero)
	hero.setup_sprites()
	var state := SaveGame.load_or_new(save_path)
	hero.set_equipped(state.equipped)          # before set_progress, which fills HP/MP to the geared max
	hero.set_skill_gems(state.get("skills", {}))
	hero.set_progress(int(state.level), int(state.exp))
	hero.inventory.from_dict(state.inventory)
	hero.gear_changed.connect(func(): save_now())
	hero.gems_changed.connect(func(): save_now())
	hero.leveled_up.connect(func(_l): save_now())
	hero.skill_released.connect(_on_skill_released)
	hero.shot.connect(_on_arrow)
	hero.health.damaged.connect(func(a, c): _number(hero.global_position + Vector2(0, -40), a, c, true))
	hero.rolled.connect(func(_d): _fx("roll_dust", hero.global_position))
	hero.leveled_up.connect(_on_level_up)
	var cam := Camera2D.new()
	var size: Array = Balance.data()["map_size"]
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(size[0])
	cam.limit_bottom = int(size[1])
	hero.add_child(cam)
	var specs: Array = Balance.data()["packs"]
	for i in specs.size():
		var spec: Dictionary = specs[i]
		var pack := WolfPack.new()
		pack.level = int(spec.level)
		pack.count = int(spec.count)
		pack.home = layout.pack_homes[i]
		pack.y_sort_enabled = true
		pack.hero = hero
		world.add_child(pack)
		if pack.wolves.is_empty(): pack.spawn()
		for w in pack.wolves:
			var wolf: Wolf = w
			wolf.health.damaged.connect(func(a, c): _on_wolf_hit(wolf, a, c))
			wolf.died.connect(_on_wolf_died)
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

func _on_level_up(lv: int) -> void:
	_fx("level_up", hero.global_position)
	_text(hero.global_position + Vector2(0, -60), "Lv ขึ้น! %d" % lv, Color("#ffd36a"))

func _on_wolf_hit(w: Wolf, amount: int, crit: bool) -> void:
	_number(w.hurt_point() + Vector2(randf_range(-6, 6), -30), amount, crit, false)
	_fx("hit_spark", w.hurt_point())

func save_now() -> bool:
	return SaveGame.save({"level": hero.level, "exp": hero.exp, "inventory": hero.inventory.to_dict(), "equipped": hero.equipped, "skills": hero.skill_gems}, save_path)

func tick_autosave(delta: float) -> void:
	_autosave_t += delta
	if _autosave_t >= Balance.num("save.autosave_every"):
		_autosave_t = 0.0
		save_now()

func _notification(what: int) -> void:
	# Desktop sends WM_CLOSE_REQUEST; phones and browser tabs send PAUSED / FOCUS_OUT instead.
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT] and hero:
		save_now()

func _on_arrow(a: Arrow) -> void:
	if a.pierce and is_inside_tree():
		var trail := FxSprite.make("piercing_trail", true)
		trail.show_behind_parent = true
		a.add_child(trail)
		trail.play("piercing_trail")

func _on_skill_released(id: String, at: Vector2) -> void:
	if id == "spread": _fx("spread_burst", at)

func _on_wolf_died(w: Wolf) -> void:
	hero.on_kill(w.stats().exp, w.level)
	var at := w.global_position if w.is_inside_tree() else w.position
	var items := Loot.roll("wolf", w.level, loot_rng)
	for it in items:
		if it.id == "gold": it.count = hero.bonus_gold(it.count)   # gear "ทอง +%"
	var spots := LootDrop.scatter(at, items.size(), loot_rng, _blocked)
	for i in items.size():
		var d: LootDrop
		if items[i].has("item"): d = LootDrop.make_item(items[i].item)
		elif items[i].has("gem"): d = LootDrop.make_gem(items[i].gem)
		else: d = LootDrop.make(items[i].id, items[i].count)
		d.pop_out(at, spots[i])
		d.collected.connect(func(id, n):
			_fx("pickup_pop", hero.global_position + Vector2(0, -20))
			save_now())
		drops.append(d)
		if world: world.add_child(d)

## true where a drop must not land: water, a prop's feet, outside the map.
func _blocked(p: Vector2) -> bool:
	return layout.blocked_at(p)

func _physics_process(delta: float) -> void:
	tick_autosave(delta)
	_bag_full_cd = maxf(0.0, _bag_full_cd - delta)
	for d in drops.duplicate():
		if not is_instance_valid(d) or d.expired:
			drops.erase(d)
			continue
		d.step(delta, hero, hero.inventory)
		if d.bag_full_notice and _bag_full_cd <= 0.0:
			_bag_full_cd = Balance.num("pickup.bag_full_notice_every")
			_text(hero.global_position + Vector2(0, -52), "กระเป๋าเต็ม", Color("#ffb37a"))

func _text(at: Vector2, t: String, c: Color) -> void:
	if not is_inside_tree(): return
	var d := DamageNumber.make(0, false)
	d.text = t
	d.add_theme_color_override("font_color", c)
	d.size = Vector2(80, 16)
	d.position = at - Vector2(20, 0)
	add_child(d)
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
