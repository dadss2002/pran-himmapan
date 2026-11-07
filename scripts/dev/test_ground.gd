extends Node2D
## The play ground: the forest rooms (data/rooms.json via RoomSet; one painted room at a time, joined by
## warps), the hero, and the current room's monsters; Y-sorted World. Walking into a warp swaps the room.

signal room_changed(id: String)

const HERO_SCENE := preload("res://scenes/hero.tscn")

var world: Node2D
## The room, its monsters and effects are drawn at the room's own pixel size in world_vp and shown
## enlarged with a sharp-pixel shader (owner 2026-11-07: blurry and slow on iPhone). UI, damage numbers
## and text stay at the screen's full resolution: overlay follows the camera.
var world_vp: SubViewport
var stage: Node2D
var view: TextureRect
var overlay: CanvasLayer
var _scale := 1.0
const SHARP := preload("res://shaders/sharp_pixels.gdshader")
var rooms: RoomSet
var room_id := ""
var warps: Array = []
var cam: Camera2D
var fade: ColorRect
const FADE_OUT := 0.25           # M4c §1 approved: screen goes dark, then the new room
const FADE_IN := 0.25
const CALM := 1.0                # the new room's monsters ignore the hero this long after arrival
var warping := false             # between touching a ring and the new room appearing
var _hero_was_on := true
var _fade_tween: Tween
var _navs := {}
var layout: PaintedLayout
var forest: PaintedMap
var hero: Hero
var hud: Hud
var saver := PerfSaver.new()                 # M3k: drops decoration while fps stays under 60
var watch_fps := DisplayServer.get_name() != "headless"
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
	get_viewport().size_changed.connect(_fit_camera)
	_fit_camera()

func build() -> void:
	if _built: return
	_built = true
	add_child(ScreenFit.new())          # portrait phones: 360 px wide UI; the camera covers the screen
	# M3k physics interpolation: only the world (moved on the physics tick) is blended between
	# ticks for 120 Hz screens; HUD, panels and damage text move in _process / tweens, so off.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	world_vp = SubViewport.new()
	world_vp.name = "WorldView"
	world_vp.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	world_vp.size = Vector2i(640, 360)
	world_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	world_vp.snap_2d_transforms_to_pixel = true
	world_vp.snap_2d_vertices_to_pixel = true
	add_child(world_vp)
	stage = Node2D.new()
	stage.name = "Stage"
	world_vp.add_child(stage)
	var view_layer := CanvasLayer.new()
	view_layer.layer = -1                 # under everything else on screen
	add_child(view_layer)
	view = TextureRect.new()
	view.texture = world_vp.get_texture()
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	view.stretch_mode = TextureRect.STRETCH_SCALE
	var m := ShaderMaterial.new()
	m.shader = SHARP
	view.material = m
	view_layer.add_child(view)
	overlay = CanvasLayer.new()
	overlay.name = "WorldText"
	overlay.layer = 1                     # damage numbers over the world, under the HUD
	add_child(overlay)
	world = Node2D.new()
	world.name = "World"
	world.y_sort_enabled = true
	rooms = RoomSet.open()
	stage.add_child(world)
	hero = HERO_SCENE.instantiate()
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
	cam = Camera2D.new()
	hero.add_child(cam)
	lock_ring = FxSprite.make("lock_on", true)
	lock_ring.visible = false
	world.add_child(lock_ring)        # y-sorted: sits just above the target's feet line
	world.move_child(lock_ring, 0)
	lock_ring.play("lock_on")
	hud = Hud.new()
	add_child(hud)
	if hud.hp_label == null: hud.build()
	hud.bind(hero)
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 50
	add_child(fade_layer)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_layer.add_child(fade)
	var saved := String(state.get("room", ""))
	go_to(saved if rooms.has(saved) else rooms.start, "", false)

## Swap to room id. via_warp = the warp you come out of there ("" = the room's spawn). The old room's
## map, monsters, drops and warps go; the new room's are built fresh; the game saves.
func go_to(id: String, via_warp := "", with_fade := true) -> void:
	if warping:                          # the fade out ended (or anything else moved the hero on)
		warping = false
		hero.set_physics_process(_hero_was_on)
	for p in packs:
		if is_instance_valid(p): p.free()
	packs.clear()
	for d in drops:
		if is_instance_valid(d): d.free()
	drops.clear()
	for w in warps:
		if is_instance_valid(w):
			if is_instance_valid(w.label): w.label.free()
			w.free()
	warps.clear()
	if forest and is_instance_valid(forest): forest.free()
	room_id = id
	layout = rooms.layout(id)
	forest = PaintedMap.new()
	stage.add_child(forest)
	stage.move_child(forest, 0)
	forest.build(layout)
	forest.set_ambient(not saver.on)
	var sz := layout.size_px()
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(sz.x)
	cam.limit_bottom = int(sz.y)
	_fit_camera()
	hero.spawn_point = rooms.spawn(id)
	hero.position = rooms.arrival(id, via_warp) if via_warp != "" else hero.spawn_point   # World sits at the origin
	hero.velocity = Vector2.ZERO
	if hero.is_inside_tree():
		hero.reset_physics_interpolation()   # M3k: a warp is a jump; the camera rides on the hero
		cam.reset_physics_interpolation()
	for w in rooms.room(id).warps:
		var n := Warp.make(w, rooms.room(String(w.to)) if rooms.has(String(w.to)) else {})
		n.armed = String(w.id) != via_warp
		world.add_child(n)
		overlay.add_child(n.make_label())
		n.place_label(sz)
		warps.append(n)
	if not _navs.has(id): _navs[id] = layout.make_nav()
	for m in rooms.room(id).get("monsters", []):
		_add_group(m, _navs[id])
	if with_fade and is_inside_tree():
		fade.color.a = 1.0
		_new_fade().tween_property(fade, "color:a", 0.0, FADE_IN)
		for p in packs: p.calm = CALM        # nobody notices the hero during the fade and just after
	save_now()
	room_changed.emit(id)

## Touching a ring: the screen fades out (FADE_OUT), the room changes, then fades in (go_to). The hero
## stands still and the old room's monsters ignore him while it is dark.
func warp_through(w: Warp) -> void:
	if warping: return
	if not is_inside_tree():
		go_to(w.to_room, w.to_warp)
		return
	warping = true
	_hero_was_on = hero.is_physics_processing()
	hero.set_physics_process(false)
	hero.velocity = Vector2.ZERO
	for p in packs: p.calm = maxf(p.calm, FADE_OUT + 0.1)
	var to_room := w.to_room
	var to_warp := w.to_warp
	_new_fade().tween_property(fade, "color:a", 1.0, FADE_OUT)
	_fade_tween.tween_callback(func(): go_to(to_room, to_warp))

func _new_fade() -> Tween:
	if _fade_tween and _fade_tween.is_valid(): _fade_tween.kill()
	_fade_tween = create_tween()
	return _fade_tween

## The room covers the whole screen, portrait or landscape (ScreenFit): the world view is the room's
## pixels that fit on screen, shown enlarged by the cover scale.
func _fit_camera() -> void:
	if cam == null or layout == null or not is_inside_tree(): return
	var v := get_viewport().get_visible_rect().size
	_scale = ScreenFit.camera_zoom(v, layout.size_px())
	var px := Vector2i(ceili(v.x / _scale), ceili(v.y / _scale))
	world_vp.size = px
	view.position = Vector2.ZERO
	view.size = Vector2(px) * _scale
	(view.material as ShaderMaterial).set_shader_parameter("src_size", Vector2(px))
	cam.zoom = Vector2.ONE

## Screen position of a world point (for the overlay and tests).
func world_to_screen(p: Vector2) -> Vector2:
	return (p - _view_origin()) * _scale

func _view_origin() -> Vector2:
	return cam.get_screen_center_position() - Vector2(world_vp.size) / 2.0

func _add_group(m: Dictionary, nav: AStarGrid2D) -> void:
	var pack := WolfPack.new()
	pack.kind = String(m.get("kind", "wolf"))
	pack.blocked = layout.blocked_at
	pack.level = int(m.level)
	pack.count = int(m.count)
	pack.home = Vector2(m.at[0], m.at[1])
	pack.nav = nav
	pack.y_sort_enabled = true
	pack.hero = hero
	world.add_child(pack)
	if pack.wolves.is_empty(): pack.spawn()
	for w in pack.wolves:
		var wolf: Wolf = w
		wolf.health.damaged.connect(func(a, c): _on_wolf_hit(wolf, a, c))
		wolf.died.connect(_on_wolf_died)
	packs.append(pack)

func _on_level_up(lv: int) -> void:
	_fx("level_up", hero.global_position)
	_text(hero.global_position + Vector2(0, -60), "Lv ขึ้น! %d" % lv, Color("#ffd36a"))

func _on_wolf_hit(w: Wolf, amount: int, crit: bool) -> void:
	_number(w.hurt_point() + Vector2(randf_range(-6, 6), -30), amount, crit, false)
	_fx("hit_spark", w.hurt_point())

func save_now() -> bool:
	return SaveGame.save({"level": hero.level, "exp": hero.exp, "inventory": hero.inventory.to_dict(), "equipped": hero.equipped, "skills": hero.skill_gems, "room": room_id}, save_path)

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
	var table := "wolf"
	var gold_mult := 1.0
	if w is Monster:
		table = w.loot_table()
		gold_mult = w.gold_mult()
	var items := Loot.roll(table, w.level, loot_rng, w.elite)
	for it in items:
		if it.id == "gold": it.count = hero.bonus_gold(int(round(it.count * gold_mult)))   # deer ×2, gear "ทอง +%"
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
	_follow_lock_ring()
	if hero and hero.state != "dead" and not warping:
		for w in warps:
			if is_instance_valid(w) and w.step(hero.global_position):
				warp_through.call_deferred(w)
				break
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
	overlay.add_child(d)
func _process(delta: float) -> void:
	if overlay and cam and cam.is_inside_tree():
		overlay.transform = Transform2D(0.0, Vector2(_scale, _scale), 0.0, -_view_origin() * _scale)
	if hero:
		for w in warps:
			if is_instance_valid(w) and w.label: w.label.visible = w.show_label(hero.global_position) and not warping
	if watch_fps and saver.step(delta, Engine.get_frames_per_second()): apply_saver()

## Saver on: pond ripples hidden and stopped; dust and pickup puffs skipped (PerfSaver.decorative).
func apply_saver() -> void:
	if forest and is_instance_valid(forest): forest.set_ambient(not saver.on)
	if hud: hud.saver_on = saver.on

## M3k: moved to the physics tick so the ring is interpolated together with its target.
func _follow_lock_ring() -> void:
	if lock_ring == null or hero == null: return
	var t := hero.current_target() if hero.state != "dead" else null
	lock_ring.visible = t != null
	if t: lock_ring.global_position = t.global_position - Vector2(0, 0.5)

func _number(at: Vector2, amount: int, crit: bool, hurt: bool) -> void:
	if not is_inside_tree(): return
	var d := DamageNumber.make(amount, crit, hurt)
	d.position = at
	overlay.add_child(d)

func _fx(fx_name: String, at: Vector2) -> void:
	if not is_inside_tree(): return
	if saver.on and PerfSaver.decorative(fx_name): return
	var f := FxSprite.make(fx_name)
	f.position = at
	f.z_index = 40
	stage.add_child(f)
	f.play(fx_name)
