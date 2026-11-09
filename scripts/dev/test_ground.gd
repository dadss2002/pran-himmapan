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
## Task 4 (RoomReset): monsters re-roll only on a new game (build: the session's layout seed) or waypoint travel
## (reroll()); walking out of a room and back keeps it as it was left (dead stay dead, the living where they
## stood). reset holds the pile seed and the kept rooms.
var reset := RoomReset.new()
## M4d addendum 4: the seed monster piles are placed from (MonsterPiles.room_seed with the room id): the layout
## seed at the start of a session (a new game), a new one at each reroll().
var pile_seed: int:
	get: return reset.pile_seed
var _piles := {}                  # "room|seed|groups hash" -> RoomSet.piles() result (this session)
var _room_groups: Array = []      # the current room's groups and piles as built (kept by RoomReset on leaving)
var _room_piles: Array = []
var _room_roll := -1              # reset.roll when the current room was built (an older roll is not kept)
## M4d addendum 2: e0's monster set this session (index into its monster_sets; -1 = not chosen yet). Chosen
## on the first entry after a new game or a re-roll (reroll() clears it; spec addendum 2: re-chosen at each
## re-roll), with the hero's level and the room he came from at that entry.
var arena_set := -1
var warps: Array = []
## Task 5 (M4c §2): the waypoint stones. `waypoints` holds which are unlocked (saved); `stone` is the current
## room's stone node (null in a room without one). Touching a stone unlocks it; standing on an unlocked one opens
## the HUD travel list while _stone_armed: arriving by waypoint (you land on the stone) or closing the list with
## its button disarms it until the hero steps off the stone, so the list does not pop up again at once.
var waypoints: Waypoints
var stone: WaypointStone
var _stone_armed := true
const WAYPOINT_ARRIVAL := "@waypoint"     # go_to(id, WAYPOINT_ARRIVAL): land next to the room's stone
## Task 6 (M4c §3): the fog grids (FogGrid; shown on the minimap only, never over the world). The hero reveals
## cells as he moves (step_fog, every physics frame, and on arriving in a room).
## Owner 2026-11-08 (spec addendum, "หมอกกลับมาใหม่ทุกเกมใหม่"): every new game starts with all fog; within a game
## the fog is kept per room. Loading = a new game, so the fog is not saved at all (an old save's "fog" key is
## dropped by SaveGame.load_or_new).
var fog: FogGrid
var cam: Camera2D
var fade: ColorRect
const FADE_OUT := 0.5            # M4c §1: screen goes dark, then the new room (owner 2026-11-09: 0.5 s, was 0.25, so the warp sparkle shows)
const FADE_IN := 0.25
const CALM := 1.0                # the new room's monsters ignore the hero this long after arrival
## M4d follow-up 3 (owner): the fade-in always plays its full FADE_IN. A slow room build makes the next frame's
## delta long, and a tween stepped by it would clear the screen at once; so the fade-in tween waits (paused)
## for the first frame after go_to shorter than FADE_GATE. It stays paused through at most FADE_GATE_FRAMES
## slower frames after go_to's own frame and starts on the next one whatever its delta (a device that is slow
## every frame still sees the room: the fade-in starts on frame FADE_GATE_FRAMES + 1 after go_to's).
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
var _warp_fx: FxSprite = null        # Task 3f: the warp sparkle while the screen fades (freed by go_to)
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
	reset.reroll_all(session_seed)          # Task 4: a new game re-rolls every room (piles from the layout seed)
	arena_set = -1
	stage.add_child(world)
	hero = HERO_SCENE.instantiate()
	world.add_child(hero)
	hero.setup_sprites()
	var state := SaveGame.load_or_new(save_path)
	hero.set_equipped(state.equipped)          # before set_progress, which fills HP/MP to the geared max
	hero.set_skill_gems(state.get("skills", {}))
	hero.set_progress(int(state.level), int(state.exp))
	hero.inventory.from_dict(state.inventory)
	waypoints = Waypoints.from_rooms(rooms, state.get("waypoints"))   # Task 5: c1r1's stone is always unlocked
	waypoints.traveller = travel_to_waypoint
	fog = FogGrid.from_rooms(rooms)          # owner 2026-11-08: a new game = all fog (never loaded from the save)
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
	hud.waypoint_list.chosen.connect(func(id): waypoints.travel(id))
	hud.waypoint_list.closed.connect(func(): _stone_armed = false)
	hud.minimap.bind_fog(fog)                # Task 7: the minimap's fog layer follows this game's fog
	hud.map_source = world_map_info          # Task 8: what the full map shows
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
	free_one_shots()                     # Task 3f review: sparks, crits, pickups, the warp sparkle belong to the room left
	_warp_fx = null
	Sfx.stop_world()                     # sound spec: the old room's hits and cries stop (the warp gong goes on)
	if hud: hud.close_map()              # Task 8: a room change never leaves the full map open (or the game paused)
	_keep_room()                         # Task 4: the room being left stays as it is (unless re-rolled since)
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
	if stone and is_instance_valid(stone): stone.free()
	stone = null
	if hud: hud.close_waypoints()
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
	if via_warp == WAYPOINT_ARRIVAL: hero.position = rooms.waypoint_landing(id)   # Task 5: in front of the stone
	else: hero.position = rooms.arrival(id, via_warp) if via_warp != "" else hero.spawn_point   # World sits at the origin
	_stone_armed = via_warp != WAYPOINT_ARRIVAL
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
	var wp := rooms.waypoint(id)
	if wp != Vector2.INF:
		stone = WaypointStone.make(id, wp, waypoints != null and waypoints.is_unlocked(id))
		world.add_child(stone)
	if not _navs.has(id): _navs[id] = layout.make_nav()
	# Task 4: a room left since the last re-roll comes back as it was (its groups, piles and monsters);
	# otherwise its groups (groups_for) stand on this roll's piles
	var kept := reset.state(id)
	var groups: Array = kept.groups if not kept.is_empty() else groups_for(id, from_id)
	# addendum 4 + follow-up: about half of each kind in piles of 2-4, the rest singles, spread over the room
	# (MonsterPiles); one pack per group, a single is its own pile
	var piles: Array = kept.piles if not kept.is_empty() else piles_for(id, groups)
	for gi in groups.size():
		var m: Dictionary = groups[gi].duplicate()
		m["piles"] = piles.filter(func(p): return int(p.group) == gi)
		_add_group(m, _navs[id])
	if not kept.is_empty():
		for gi in mini(packs.size(), kept.packs.size()): packs[gi].restore(kept.packs[gi])
	_room_groups = groups
	_room_piles = piles
	_room_roll = reset.roll
	if with_fade and is_inside_tree():
		fade.color.a = 1.0
		_new_fade().tween_property(fade, "color:a", 0.0, FADE_IN)
		_fade_tween.pause()                  # follow-up 3: started by _on_fade_gate on a short frame
		_fade_frame = Engine.get_process_frames()
		_fade_waited = 0
		_fade_gate.set_process(true)
		for p in packs: p.calm = CALM        # nobody notices the hero during the fade and just after
	if fog: fog.reveal(id, hero.position)    # Task 6: the arrival is seen at once
	show_minimap_room()                      # Task 7: picture, fog, exits and stone of the new room
	save_now()
	room_changed.emit(id)

## Room id's monster groups for this roll, entered from room from_id. M4d addendum: forest rooms spawn at the
## level of their distance from c1r1 in this session's layout; e0 spawns its chosen monster set (addendum 2;
## chosen here when arena_set < 0) at the previous room's level + 1, max Lv11 (addendum 3); a room off the map
## keeps the levels in rooms.json.
func groups_for(id: String, from_id: String) -> Array:
	var groups: Array = rooms.room(id).get("monsters", [])
	var levels := rooms.room_levels()
	if levels.has(id): groups = RoomLevels.groups(groups, int(levels[id]))
	var sets: Array = rooms.room(id).get("monster_sets", [])
	if not sets.is_empty():
		var prev := arena_from(from_id) if id == RoomLayout.BOSS else from_id
		if arena_set < 0: choose_arena_set(prev)
		# addendum 3: the set's kinds and counts at the previous room's level + 1 (max Lv11)
		groups = RoomLevels.arena_groups(sets[clampi(arena_set, 0, sets.size() - 1)], int(levels.get(prev, 0)))
	return groups

## Review fix: the room e0's set and levels follow (addenda 2-3, "the room the hero came from"): from_id when it
## is joined to e0 in this session's layout, else the room behind e0's exit (entering e0 from e0 itself, e.g. a
## reload of the room, or from a room not next to it), never e0's own (it has no layout level).
func arena_from(from_id: String) -> String:
	if not rooms.has(RoomLayout.BOSS): return from_id
	var behind := ""
	for w in rooms.room(RoomLayout.BOSS).get("warps", []):
		if String(w.to) == from_id: return from_id
		if behind == "": behind = String(w.to)
	return behind if behind != "" else from_id

## Task 4: the room being left is kept by RoomReset (its groups, piles and each monster's state), unless a
## re-roll came after it was built (then it spawns fresh from the new roll next time).
func _keep_room() -> void:
	if room_id == "" or _room_roll != reset.roll: return
	var states: Array = []
	for p in packs:
		states.append(p.snapshot() if is_instance_valid(p) else [])
	reset.keep(room_id, states, _room_groups, _room_piles)

## The piles for room id's groups this session (seed from pile_seed and the room id): follow-up 3, the baked
## bank's entry, or live placement when the bank is stale (RoomSet.piles).
func piles_for(id: String, groups: Array) -> Array:
	var key := "%s|%d|%d" % [id, pile_seed, hash(groups)]
	if not _piles.has(key):
		_piles[key] = rooms.piles(id, groups, MonsterPiles.room_seed(pile_seed, id))
	return _piles[key]

## Task 4 re-roll, the waypoint hook (Task 5: call reroll() and then go_to() the destination): a new pile seed
## (new_seed, or a random one when < 0), every kept room forgotten (the current room too: it is not kept when
## left), e0's set chosen again on its next entry (addendum 2). Every room entered after this spawns fresh,
## its piles from the baked bank with the new seed. Returns the seed used.
func reroll(new_seed := -1) -> int:
	reset.reroll_all(new_seed if new_seed >= 0 else RoomReset.new_seed())
	_piles.clear()
	arena_set = -1
	return reset.pile_seed

## M4d addendum 2: pick e0's set for a hero coming from room from_id (RoomLevels.arena_set).
func choose_arena_set(from_id: String) -> void:
	var sets: Array = rooms.room(RoomLayout.BOSS).get("monster_sets", []) if rooms.has(RoomLayout.BOSS) else []
	arena_set = RoomLevels.arena_set(sets, hero.level, int(rooms.room_levels().get(from_id, 0)))

## Touching a ring: the screen fades out (FADE_OUT), the room changes, then fades in (go_to). The hero
## stands still and cannot be hurt; the old room's monsters and their shots stop while it is dark.
func warp_through(w: Warp) -> void:
	if warping: return
	_trip(w.to_room, w.to_warp)

## Task 5: a tap on the travel list (Waypoints.travel): Task 4's re-roll (every room spawns fresh, the room being
## left too), the warp gong, the same fade as an exit, and the hero lands next to room id's stone (go_to with
## WAYPOINT_ARRIVAL) with the arrival calm. The room the hero stands in may be chosen too: that resets it.
func travel_to_waypoint(id: String) -> void:
	if warping or not rooms.has(id) or rooms.waypoint(id) == Vector2.INF: return
	if hud: hud.close_waypoints()
	reroll()
	_trip(id, WAYPOINT_ARRIVAL)

## Task 3f review: frees every one-shot effect playing on the stage or in the world (hit sparks, crits, pickups,
## level-up, chain zaps, the warp sparkle); kept effects (the lock ring, exit rings, map ambience) stay.
func free_one_shots() -> void:
	for parent in [stage, world]:
		if parent == null: continue
		for c in parent.get_children():
			if c is FxSprite and not c.keep: c.free()

## The fade out to room to_room (coming out of to_warp there), shared by exits and waypoints.
func _trip(to_room: String, to_warp: String) -> void:
	Sfx.play("warp")
	if not is_inside_tree():
		go_to(to_room, to_warp)
		return
	warping = true
	_warp_fx = _fx("warp_blink", hero.global_position)   # Task 3f ⑦: green sparkle at his feet as the screen fades
	_hero_was_on = hero.is_physics_processing()
	hero.set_physics_process(false)
	hero.begin_warp()                    # no damage, poison or knockback while it is dark
	for p in packs:                      # the old room stops: no bite, lunge or spit lands mid-fade
		p.calm = maxf(p.calm, FADE_OUT + 0.1)
		p.set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)   # safe mid physics tick
	_new_fade().tween_property(fade, "color:a", 1.0, FADE_OUT)
	_fade_tween.tween_callback(func(): go_to(to_room, to_warp))

## Task 5, every physics frame: feet within Waypoints.RADIUS of the stone unlock it the first time (toast
## "ปลดล็อกจุดวาป" with its notify sound, saved at once); while they stay there, alive and not mid-fade, the travel
## list is open (the unlocked stones) unless disarmed (_stone_armed); stepping off closes it and re-arms.
func step_waypoint() -> void:
	if stone == null or not is_instance_valid(stone) or hero == null: return
	var on := hero.state != "dead" and not warping and Waypoints.touching(stone.position, hero.global_position)
	if on and waypoints.unlock(room_id):
		stone.set_unlocked(true)
		if hud: hud.minimap.set_stone_unlocked(true)   # Task 7: the diamond turns blue
		if hud: hud.show_toast("ปลดล็อกจุดวาป")
		save_now()
	if not on: _stone_armed = true
	if hud == null: return
	var want: bool = on and _stone_armed and waypoints.is_unlocked(room_id)
	if want and not hud.waypoints_open():
		if cam and cam.is_inside_tree(): _set_waypoint_avoid()
		hud.open_waypoints(waypoint_entries(), room_id)
	elif not want and hud.waypoints_open(): hud.close_waypoints()

## Task 6, every physics frame: the fog cells within FogGrid.RADIUS of the hero's feet are revealed (FogGrid skips
## a frame where he has not moved). Not while warping (the old room is going). The new cells are saved with the
## next save (room change, autosave, level up, pick-up, leaving / hiding the app).
func step_fog() -> void:
	if fog == null or hero == null or warping or room_id == "": return
	fog.reveal(room_id, hero.global_position)

## Task 7: the corner minimap shows the current room: its picture, its joined exits (this layout's warps; red into
## the boss arena) and its waypoint stone (blue when unlocked); the fog follows FogGrid.changed; the dot is placed at
## once (then every frame, _process).
func show_minimap_room() -> void:
	if hud == null or hud.minimap == null: return
	var ex: Array = []
	for w in rooms.room(room_id).get("warps", []):
		var to := String(w.to)
		ex.append({"side": String(w.id), "at": Vector2(w.at[0], w.at[1]), "arena": rooms.has(to) and bool(rooms.room(to).get("arena", false))})
	var pic: Texture2D = load(String(layout.chunks[0].file)) if not layout.chunks.is_empty() else null
	hud.minimap.show_room(room_id, layout.size_px(), pic, ex, rooms.waypoint(room_id), waypoints != null and waypoints.is_unlocked(room_id))
	track_minimap()

## Task 7, every frame: the hero's dot and facing tick, and his body on screen (the minimap fades over him).
func track_minimap() -> void:
	if hud == null or hud.minimap == null or hero == null: return
	var on_screen := hero_screen_rect() if cam and cam.is_inside_tree() else Rect2()
	hud.minimap.track(hero.global_position, BowLayer.dir_vector(hero.facing), on_screen)

## Task 8: what the full map shows (WorldMap.open's data): this game's fog, the hero's room, feet and facing, and
## every room on this session's layout with its grid place, size, picture, Thai name, level range, joined exits
## (this layout's warps; arena flag), waypoint stone and the arena flag. WorldMap draws only the visited ones.
func world_map_info() -> Dictionary:
	var out := {}
	for id in rooms.active.get("pos", {}):
		id = String(id)
		if not rooms.has(id): continue
		var r: Dictionary = rooms.room(id)
		var ex: Array = []
		for w in r.get("warps", []):
			var to := String(w.to)
			ex.append({"side": String(w.id), "at": Vector2(w.at[0], w.at[1]), "to": to, "arena": rooms.has(to) and bool(rooms.room(to).get("arena", false))})
		out[id] = {"grid": rooms.grid_pos(id), "size": rooms.room_size(id), "picture": String(r.get("image", "")),
			"name": String(r.get("name", id)), "levels": level_range(id), "exits": ex, "stone": rooms.waypoint(id),
			"stone_unlocked": waypoints != null and waypoints.is_unlocked(id), "arena": bool(r.get("arena", false))}
	return {"fog": fog, "current": room_id, "hero": hero.global_position if hero else Vector2.ZERO,
		"facing": BowLayer.dir_vector(hero.facing) if hero else Vector2.DOWN, "rooms": out}

## Task 8: room id's monster level range this roll as Vector2i(lowest, highest) (0 = unknown): the groups as built
## (the hero's room, or one kept since the last re-roll), else what entering it would give: a forest room's groups at
## its layout level (RoomLevels.groups), e0's set at the level of any room joined to it + 1 (max Lv11; addendum 3,
## the set's own levels when nothing is joined); a room without monsters shows its layout level.
func level_range(id: String) -> Vector2i:
	if not rooms.has(id): return Vector2i.ZERO
	var groups: Array = []
	var kept := reset.state(id)
	if id == room_id and not _room_groups.is_empty(): groups = _room_groups
	elif not kept.is_empty(): groups = kept.groups
	else:
		var levels := rooms.room_levels()
		var sets: Array = rooms.room(id).get("monster_sets", [])
		if not sets.is_empty():
			var lo := 0
			var hi := 0
			for w in rooms.room(id).get("warps", []):
				var lv := RoomLevels.arena_level(int(levels.get(String(w.to), 0)))
				if lv <= 0: continue
				lo = lv if lo == 0 else mini(lo, lv)
				hi = maxi(hi, lv)
			if lo > 0: return Vector2i(lo, hi)
			for st in sets: groups.append_array(st)
		else:
			groups = rooms.room(id).get("monsters", [])
			if levels.has(id): groups = RoomLevels.groups(groups, int(levels[id]))
			if groups.is_empty() and levels.has(id): return Vector2i(int(levels[id]), int(levels[id]))
	if groups.is_empty(): return Vector2i.ZERO
	var lo := 1 << 20
	var hi := 0
	for g in groups:
		lo = mini(lo, int(g.level))
		hi = maxi(hi, int(g.level))
	return Vector2i(lo, hi)

## The travel list's rows: the unlocked stones in list order with their rooms' Thai names.
func waypoint_entries() -> Array:
	var out: Array = []
	for id in waypoints.list():
		if rooms.has(id): out.append({"id": id, "name": String(rooms.room(id).get("name", id))})
	return out

## The hero's body on screen (HUD px), for keeping labels and the travel list off him.
func hero_screen_rect() -> Rect2:
	return Rect2(world_to_screen(hero.global_position + HERO_BOX.position), HERO_BOX.size * _scale)

## The drawn stone on screen (HUD px; empty without one): the travel list keeps clear of it when it can.
func stone_screen_rect() -> Rect2:
	if stone == null or not is_instance_valid(stone): return Rect2()
	return Rect2(world_to_screen(stone.position + WaypointStone.ART_BOX.position), WaypointStone.ART_BOX.size * _scale)

func _set_waypoint_avoid() -> void:
	hud.waypoint_avoid = hero_screen_rect()
	hud.waypoint_avoid_stone = stone_screen_rect()

## Follow-up 3: each frame while the fade-in waits: start it on the first frame after go_to's own frame whose
## delta is under FADE_GATE (tweens are stepped later in that same frame by that delta); after FADE_GATE_FRAMES
## slower frames have been skipped (_fade_waited counts them) the next frame starts it whatever its delta.
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
	pack.respawns = false               # spec addendum (owner 2026-11-08): the dead stay dead until a re-roll / new game
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

## Task 3f (PixelFX): a critical shows crit_hit instead of hit_spark (as crit_hit replaces arrow_hit in sound);
## both fly along the blow, so they are mirrored when it goes left (the hero on the monster's right). A burn tick
## (Wolf.dot_tick) is not a blow: its number shows, no spark.
func _on_wolf_hit(w: Wolf, amount: int, crit: bool) -> void:
	_number(w.hurt_point() + Vector2(randf_range(-6, 6), -30 * Wolf.size_scale()), amount, crit, false)
	if w.dot_tick: return
	var f := _fx("crit_hit" if crit else "hit_spark", w.hurt_point())
	if f and hero: f.face(hero.global_position.x > w.global_position.x)

func save_now() -> bool:
	return SaveGame.save({"level": hero.level, "exp": hero.exp, "inventory": hero.inventory.to_dict(), "equipped": hero.equipped, "skills": hero.skill_gems, "room": room_id, "seed": session_seed,
		"waypoints": waypoints.to_save() if waypoints else []}, save_path)

func tick_autosave(delta: float) -> void:
	_autosave_t += delta
	if _autosave_t >= Balance.num("save.autosave_every"):
		_autosave_t = 0.0
		save_now()

func _exit_tree() -> void:
	PerfSaver.active = false             # the saver flag Wolf reads belongs to this test ground

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
	step_waypoint()
	step_fog()
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
	if hero and hud: track_minimap()
	if hero and hud and hud.waypoints_open() and cam and cam.is_inside_tree():
		_set_waypoint_avoid()
		hud.place_waypoints()
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
	PerfSaver.active = saver.on          # Task 3f review: monsters drop their status overlays (keep the tint)
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

func _fx(fx_name: String, at: Vector2) -> FxSprite:
	if not is_inside_tree(): return null
	if saver.on and PerfSaver.decorative(fx_name):
		fx_name = PerfSaver.fallback(fx_name)   # a crit under load: the plain hit spark
		if fx_name == "": return null
	var f := FxSprite.make(fx_name)
	f.position = at
	f.z_index = 40
	stage.add_child(f)
	f.play(fx_name)
	return f
