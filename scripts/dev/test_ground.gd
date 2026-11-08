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
var layout_seed := -1             # M4d: -1 = a new random room layout every session; tests set one
var session_seed := 0             # the seed this session's layout was made from (saved for reference only)
## M4d addendum 4: the seed monster piles are placed from (MonsterPiles.room_seed with the room id): made from
## the layout seed at the start of a session, so walking out and back shows the same piles; Task 4's re-roll
## (waypoint travel / new game) sets a new one with reroll_piles().
var pile_seed := 0
var _piles := {}                  # "room|seed|groups hash" -> RoomSet.piles() result (this session)
## M4d addendum 2: e0's monster set this session (index into its monster_sets; -1 = not chosen yet). Chosen
## on the first entry each session (a new game is a new session); Task 4 re-chooses it on every re-roll.
var arena_set := -1
var warps: Array = []
var cam: Camera2D
var fade: ColorRect
const FADE_OUT := 0.25           # M4c §1 approved: screen goes dark, then the new room
const FADE_IN := 0.25
const CALM := 1.0                # the new room's monsters ignore the hero this long after arrival
## M4d follow-up 3 (owner): the fade-in always plays its full FADE_IN. A slow room build makes the next frame's
## delta long, and a tween stepped by it would clear the screen at once; so the fade-in tween waits (paused)
## for the first frame after go_to shorter than FADE_GATE, or at most FADE_GATE_FRAMES frames (a device that is
## slow every frame still sees the room).
const FADE_GATE := 0.05
const FADE_GATE_FRAMES := 3
var _fade_gate: FadeGate
var _fade_frame := -1            # the process frame go_to ran in (its own frame never starts the fade-in)
var _fade_waited := 0
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
var settings_path := GameSettings.PATH   # the HUD's settings file (tests / screenshots set a scratch one)
var _autosave_t := 0.0

func _ready() -> void:
	build()
	get_viewport().size_changed.connect(_fit_camera)
	_fit_camera()

func build() -> void:
	if _built: return
	_built = true
	add_child(ScreenFit.new())          # portrait phones: 360 px wide UI; the camera covers the screen
	Sfx.attach(self)                    # Task 3g: the sound players (the HUD applies the sound settings)
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
	session_seed = layout_seed if layout_seed >= 0 else int(randi() & 0x7fffffff)
	rooms.use_layout(RoomLayout.generate(session_seed, rooms.exit_table()))
	pile_seed = session_seed
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
	hud.settings_path = settings_path        # before the HUD builds (it reads the file in build())
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
	_fade_gate = FadeGate.new()
	_fade_gate.name = "FadeGate"
	_fade_gate.process_mode = Node.PROCESS_MODE_ALWAYS    # as the fade tween: a paused tree never stays dark
	_fade_gate.on_frame = _on_fade_gate
	_fade_gate.set_process(false)
	add_child(_fade_gate)
	# M4d: the map is new every session, so the saved room is not used: always start in c1r1.
	go_to(rooms.start, "", false)

## Swap to room id. via_warp = the warp you come out of there ("" = the room's spawn). The old room's
## map, monsters, drops and warps go; the new room's are built fresh; the game saves.
func go_to(id: String, via_warp := "", with_fade := true) -> void:
	# Any fade still running belongs to the old room: stop it, so its callback cannot move us again.
	if _fade_tween and _fade_tween.is_valid(): _fade_tween.kill()
	_fade_tween = null
	if _fade_gate: _fade_gate.set_process(false)
	if fade: fade.color.a = 0.0
	Sfx.stop_world()                     # sound spec: the old room's hits and cries stop (the warp gong goes on)
	if warping:                          # the fade out ended (or anything else moved the hero on)
		warping = false
		hero.set_physics_process(_hero_was_on)
		hero.end_warp()
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
	var from_id := room_id
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
		n.room_size = sz
		world.add_child(n)
		overlay.add_child(n.make_label())
		n.place_label(sz)
		warps.append(n)
	if not _navs.has(id): _navs[id] = layout.make_nav()
	# M4d addendum: forest rooms spawn at the level of their distance from c1r1 in this session's layout;
	# e0 spawns its chosen monster set (addendum 2) at the previous room's level + 1, max Lv11 (addendum 3);
	# a room off the map keeps the levels in rooms.json.
	var groups: Array = rooms.room(id).get("monsters", [])
	var levels := rooms.room_levels()
	if levels.has(id): groups = RoomLevels.groups(groups, int(levels[id]))
	var sets: Array = rooms.room(id).get("monster_sets", [])
	if not sets.is_empty():
		if arena_set < 0: choose_arena_set(from_id)
		# addendum 3: the set's kinds and counts at the previous room's level + 1 (max Lv11)
		groups = RoomLevels.arena_groups(sets[clampi(arena_set, 0, sets.size() - 1)], int(levels.get(from_id, 0)))
	# addendum 4 + follow-up: about half of each kind in piles of 2-4, the rest singles, spread over the room
	# (MonsterPiles); one pack per group, a single is its own pile
	var piles := piles_for(id, groups)
	for gi in groups.size():
		var m: Dictionary = groups[gi].duplicate()
		m["piles"] = piles.filter(func(p): return int(p.group) == gi)
		_add_group(m, _navs[id])
	if with_fade and is_inside_tree():
		fade.color.a = 1.0
		_new_fade().tween_property(fade, "color:a", 0.0, FADE_IN)
		_fade_tween.pause()                  # follow-up 3: started by _on_fade_gate on a short frame
		_fade_frame = Engine.get_process_frames()
		_fade_waited = 0
		_fade_gate.set_process(true)
		for p in packs: p.calm = CALM        # nobody notices the hero during the fade and just after
	save_now()
	room_changed.emit(id)

## The piles for room id's groups this session (seed from pile_seed and the room id): follow-up 3, the baked
## bank's entry, or live placement when the bank is stale (RoomSet.piles).
func piles_for(id: String, groups: Array) -> Array:
	var key := "%s|%d|%d" % [id, pile_seed, hash(groups)]
	if not _piles.has(key):
		_piles[key] = rooms.piles(id, groups, MonsterPiles.room_seed(pile_seed, id))
	return _piles[key]

## Task 4 hook: new piles everywhere from a new seed (the next room entered uses them).
func reroll_piles(new_seed: int) -> void:
	pile_seed = new_seed
	_piles.clear()

## M4d addendum 2: pick e0's set for a hero coming from room from_id (RoomLevels.arena_set).
func choose_arena_set(from_id: String) -> void:
	var sets: Array = rooms.room(RoomLayout.BOSS).get("monster_sets", []) if rooms.has(RoomLayout.BOSS) else []
	arena_set = RoomLevels.arena_set(sets, hero.level, int(rooms.room_levels().get(from_id, 0)))

## Touching a ring: the screen fades out (FADE_OUT), the room changes, then fades in (go_to). The hero
## stands still and cannot be hurt; the old room's monsters and their shots stop while it is dark.
func warp_through(w: Warp) -> void:
	if warping: return
	Sfx.play("warp")
	if not is_inside_tree():
		go_to(w.to_room, w.to_warp)
		return
	warping = true
	_hero_was_on = hero.is_physics_processing()
	hero.set_physics_process(false)
	hero.begin_warp()                    # no damage, poison or knockback while it is dark
	for p in packs:                      # the old room stops: no bite, lunge or spit lands mid-fade
		p.calm = maxf(p.calm, FADE_OUT + 0.1)
		p.set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)   # safe mid physics tick
	var to_room := w.to_room
	var to_warp := w.to_warp
	_new_fade().tween_property(fade, "color:a", 1.0, FADE_OUT)
	_fade_tween.tween_callback(func(): go_to(to_room, to_warp))

## Follow-up 3: each frame while the fade-in waits: start it on the first frame after go_to's own frame whose
## delta is under FADE_GATE (tweens are stepped later in that same frame by that delta), or after
## FADE_GATE_FRAMES slower frames.
func _on_fade_gate(delta: float) -> void:
	if _fade_tween == null or not _fade_tween.is_valid():
		_fade_gate.set_process(false)
		return
	if Engine.get_process_frames() == _fade_frame: return
	_fade_waited += 1
	if delta < FADE_GATE or _fade_waited > FADE_GATE_FRAMES:
		_fade_gate.set_process(false)
		_fade_tween.play()

## Calls on_frame(delta) every process frame while processing (PROCESS_MODE_ALWAYS; see _on_fade_gate).
class FadeGate extends Node:
	var on_frame: Callable
	func _process(delta: float) -> void:
		on_frame.call(delta)

func _new_fade() -> Tween:
	if _fade_gate: _fade_gate.set_process(false)    # a waiting fade-in is replaced
	if _fade_tween and _fade_tween.is_valid(): _fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)   # a paused tree never leaves the screen half dark
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
	for p in m.get("piles", []): pack.piles.append({"home": p.home, "points": p.points})
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
	_number(w.hurt_point() + Vector2(randf_range(-6, 6), -30 * Wolf.size_scale()), amount, crit, false)
	_fx("hit_spark", w.hurt_point())

func save_now() -> bool:
	return SaveGame.save({"level": hero.level, "exp": hero.exp, "inventory": hero.inventory.to_dict(), "equipped": hero.equipped, "skills": hero.skill_gems, "room": room_id, "seed": session_seed}, save_path)

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
				warp_through(w)          # at once: a bite later in this physics frame must not land
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
			if is_instance_valid(w) and w.label:
				w.label.visible = w.show_label(hero.global_position) and not warping
				if w.label.visible: place_label_on_screen(w)
	if watch_fps and saver.step(delta, Engine.get_frames_per_second()): apply_saver()

## M4c review: an exit label is placed by its screen rect, inside the HUD-safe area and clear of the
## HUD panels, the FPS line and the touch buttons, in portrait and landscape (Warp.screen_spot).
func place_label_on_screen(w: Warp) -> void:
	if hud == null or cam == null or not cam.is_inside_tree(): return
	var hero_s := Rect2(world_to_screen(hero.global_position + HERO_BOX.position), HERO_BOX.size * _scale)
	var at := w.screen_spot(world_to_screen(w.position), _scale, hud.safe_rect(), hud.blocked_rects(), hero_s)
	w.label.size = w.label.get_combined_minimum_size()
	w.label.position = _view_origin() + at / _scale

const HERO_BOX := Rect2(-12, -42, 24, 44)    # the hero's body round his feet (world px)

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
