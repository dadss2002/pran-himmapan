class_name Hero
extends CharacterBody2D
## Pran: 8-direction walk / idle / shoot / roll / hurt / dead. Node origin = feet (for Y-sort).
## All timing is driven by step(delta, input) so headless tests can run it without a tree.

signal shot(arrow: Arrow)
signal died()
signal respawned()
signal rolled(dir: Vector2)
signal leveled_up(level: int)
signal exp_changed()
signal skill_released(id: String, at: Vector2)
signal gear_changed()
signal gems_changed()
signal gem_leveled(gem: Dictionary)

const MANIFEST := "res://assets/hero/manifest.json"
const ARROW_SCENE := preload("res://scenes/arrow.tscn")
const SHOOT_FPS := 14.0
const RELEASE_FRAME := 5      # shoot frame where the string is let go
const SHOOT_FRAMES := 9
const HURT_RED := Color(1.0, 0.25, 0.2)

var level := 1
var exp := 0
var mp := 0.0
var facing := 0               # index into Combat.DIRS
var state := "idle"           # idle | walk | shoot | roll | hurt | dead
var cooldown := 0.0           # shot cooldown
var spawn_point := Vector2.ZERO
var external_input := Vector2.ZERO   # touch joystick, added to keyboard input
var test_enemies: Array = []  # used instead of the "enemies" group when not in a tree
var inventory := Inventory.new()
var equipped := SaveGame.start_equipped()
var skill_gems := {"piercing": [], "spread": []}   # sockets: skill → [gem|null, …]   # bow, armor, ring, necklace → item or null
var _skill_cd := {}
var _pending_skill := ""
var _exp_carry := 0.0          # fractional EXP from bonus %, kept so +2.4% is never rounded away
var _gold_carry := 0.0
var _leech_carry := 0.0
var _queued_skill := ""      # pressed during a basic shot; starts once that arrow is out
var _potion_cd := 0.0

func _init() -> void:
	inventory.from_dict(SaveGame.new_state().inventory)   # start kit (save loading replaces it)

@onready var body: AnimatedSprite2D = $Body
@onready var bow: BowLayer = $Bow
@onready var health: Health = $Health

var _t := 0.0                 # time in the current timed state
var _released := false
var _aim_target: Node2D = null
var _aim_vec := Vector2.DOWN
var _dodge_cd := 0.0
var _roll_dir := Vector2.RIGHT
var _roll := {}
var _flash := 0.0

func _ready() -> void:
	setup_sprites()

## Safe to call before entering the tree (tests do).
func setup_sprites() -> void:
	if body == null: body = $Body
	if bow == null: bow = $Bow
	if health == null: health = $Health
	if body.sprite_frames != null: return
	body.sprite_frames = SpriteSet.build(MANIFEST)
	body.centered = false
	body.offset = -SpriteSet.anchor(MANIFEST, "idle")
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/flash.gdshader")
	mat.set_shader_parameter("flash_color", HURT_RED)
	body.material = mat
	health.setup(stats().hp)
	mp = max_mp()
	_show_bow()
	health.died.connect(_on_died)
	_refresh()

func max_mp() -> int:
	return stats().mp

## Sets level and stats without effects (loading a save).
func set_progress(new_level: int, new_exp: int) -> void:
	level = new_level
	exp = new_exp
	health.setup(stats().hp)
	mp = max_mp()
	exp_changed.emit()

func on_kill(monster_exp: int, monster_level: int) -> void:
	if state == "dead": return     # an arrow still flying after death earns nothing
	var raw: float = Progression.kill_exp(monster_exp, monster_level, level) * stats().exp_mult + _exp_carry
	var whole := int(floor(raw + 1e-6))
	_exp_carry = raw - whole
	gain_exp(whole)
	for id in skill_gems:
		for g in skill_gems[id]:
			if g == null: continue
			var amount := int(round(whole * (1.0 + Gem.option(g, "gem_exp"))))
			if Gem.add_exp(g, amount) > 0: gem_leveled.emit(g)

## Heals from ดูดเลือด; fractions carry so 3% of small hits still adds up.
func leech_heal(amount: float) -> void:
	if state == "dead": return
	_leech_carry += amount
	var whole := int(floor(_leech_carry + 1e-6))
	_leech_carry -= whole
	if whole > 0: health.hp = mini(health.max_hp, health.hp + whole)

## Gold from a drop with the gear bonus; the fraction carries to the next drop.
func bonus_gold(amount: int) -> int:
	var raw: float = amount * stats().gold_mult + _gold_carry
	var whole := int(floor(raw + 1e-6))
	_gold_carry = raw - whole
	return whole

## Adds EXP; each level gained heals HP/MP fully and emits leveled_up once.
func gain_exp(amount: int) -> void:
	var r := Progression.add_exp(level, exp, amount)
	for i in r.levels_gained:
		level += 1
		health.setup(stats().hp)
		mp = max_mp()
		leveled_up.emit(level)
	exp = r.exp
	exp_changed.emit()

# ---------- gems ----------

## What a skill does now (level, gear and its gems).
func build(skill_id: String) -> Dictionary:
	return SkillBuild.of(skill_id, level, skill_gems.get(skill_id, []), stats())

func skill_mp(skill_id: String) -> float:
	return build(skill_id).mp

func gem_slots(skill_id: String) -> int:
	return Gem.slots_for(Skills.skill_level(skill_id, level))

## Puts the gem in bag slot bag_index into a skill slot; a gem already there goes back to the bag.
## Returns "" or the reason shown to the player.
func socket(skill_id: String, slot: int, bag_index: int) -> String:
	if level < Skills.unlock_level(skill_id): return "ยังไม่ปลด"
	if slot < 0 or slot >= gem_slots(skill_id): return "ช่องยังไม่เปิด"
	if bag_index < 0 or bag_index >= inventory.slots.size(): return "ไม่มีเจม"
	var entry: Dictionary = inventory.slots[bag_index]
	if not String(entry.id).begins_with("gem_") or entry.has("item"): return "ไม่ใช่เจม"
	if not Gem.fits(String(entry.id).trim_prefix("gem_"), skill_id): return "ป้ายไม่ตรง"
	var sockets: Array = skill_gems.get(skill_id, [])
	while sockets.size() <= slot: sockets.append(null)
	var type := String(entry.id).trim_prefix("gem_")
	for i in sockets.size():
		if i != slot and sockets[i] != null and String(sockets[i].type) == type: return "เจมชนิดนี้ใส่ในสกิลนี้แล้ว"
	var old = sockets[slot]
	var single: bool = entry.has("gem") or int(entry.count) == 1
	# a gem coming out needs a place: the slot the new gem leaves, a plain stack, or a free slot
	if old != null and not single and not inventory.has_free_slot() and not (Gem.is_plain(old) and _plain_stack_has_room(String(old.type))):
		return "กระเป๋าเต็ม"
	var taken := inventory.take_gem(bag_index)
	if old != null:
		if single and not Gem.is_plain(old):
			inventory.slots.insert(mini(bag_index, inventory.slots.size()), {"id": "gem_" + String(old.type), "count": 1, "gem": old})
		else:
			inventory.add_gem(old)
	sockets[slot] = taken
	skill_gems[skill_id] = sockets
	gems_changed.emit()
	return ""

func _plain_stack_has_room(type: String) -> bool:
	for s in inventory.slots:
		if s.id == "gem_" + type and not Inventory._unique(s) and int(s.count) < int(Balance.num("bag.stack")): return true
	return false

func unsocket(skill_id: String, slot: int) -> String:
	var sockets: Array = skill_gems.get(skill_id, [])
	if slot < 0 or slot >= sockets.size() or sockets[slot] == null: return "ช่องว่าง"
	if not inventory.add_gem(sockets[slot]): return "กระเป๋าเต็ม"
	sockets[slot] = null
	gems_changed.emit()
	return ""

func set_skill_gems(sk: Dictionary) -> void:
	skill_gems = {"piercing": [], "spread": []}
	for id in sk: skill_gems[id] = sk[id].duplicate(true)
	gems_changed.emit()

# ---------- equipment ----------

## Wears the item in bag slot i; whatever was worn goes into that same bag slot.
## Returns "" on success, otherwise the reason shown to the player.
func equip(slot_index: int) -> String:
	if slot_index < 0 or slot_index >= inventory.slots.size(): return "ไม่มีของ"
	var entry: Dictionary = inventory.slots[slot_index]
	if not entry.has("item"): return "สวมไม่ได้"
	var it: Dictionary = entry.item
	if level < Gear.req_level(it.base): return "ต้องเลเวล %d" % Gear.req_level(it.base)
	var slot := Gear.slot_of(it.base)
	if slot == "": return "สวมไม่ได้"
	var old = equipped.get(slot)
	equipped[slot] = it
	if old == null: inventory.slots.remove_at(slot_index)
	else: inventory.slots[slot_index] = {"id": String(old.base), "count": 1, "item": old}
	_on_gear_changed()
	return ""

func unequip(slot: String) -> String:
	if equipped.get(slot) == null: return "ไม่ได้สวม"
	if slot == "bow": return "ต้องถือธนูไว้"     # arrows need a bow: swap it instead
	if not inventory.add_item(equipped[slot]): return "กระเป๋าเต็ม"
	equipped[slot] = null
	_on_gear_changed()
	return ""

func set_equipped(eq: Dictionary) -> void:
	equipped = eq.duplicate(true)
	_on_gear_changed()

## Gear changes max HP/MP without healing; current values clamp to the new max.
func _on_gear_changed() -> void:
	if health:
		var hp := health.hp
		health.max_hp = stats().hp
		health.hp = mini(hp, health.max_hp)
	mp = minf(mp, max_mp())
	_show_bow()
	gear_changed.emit()

func _show_bow() -> void:
	if bow and equipped.get("bow") != null: bow.set_bow(String(equipped.bow.base))

func dodge_cooldown_left() -> float:
	return _dodge_cd

## Everything that depends on level and gear (M2c). Base numbers from balance.json.
func stats() -> Dictionary:
	var b := Balance.hero_base(level)
	var t := Gear.totals(equipped)
	return {
		"hp": b.hp + t.hp,
		"atk": (b.atk + t.atk) * (1.0 + t.atk_pct),   # float: small ATK% must still count
		"def": b.def + t.def,
		"mp": Balance.mp(level) + t.mp,
		"crit": Balance.num("crit.chance") + t.crit,
		"crit_mult": Balance.num("crit.mult") + t.crit_dmg,
		"shot_cd": Balance.num("shot.cooldown") / (1.0 + t.atk_speed),
		"walk": Balance.num("hero.walk") * (1.0 + t.move_speed),
		"skill_cd_cut": t.skill_cd,
		"mp_regen": Balance.num("mp.regen") + t.mp_regen,
		"exp_mult": 1.0 + t.exp_pct,
		"gold_mult": 1.0 + t.gold_pct,
		"element_dmg": t.element_dmg,   # no elements in M2: shown, no effect yet
	}

# ---------- actions ----------

func try_shoot() -> bool:
	if cooldown > 0.0 or state in ["roll", "hurt", "dead", "shoot"]:
		return false
	cooldown = stats().shot_cd
	_pending_skill = ""
	state = "shoot"
	_t = 0.0
	_released = false
	velocity = Vector2.ZERO
	_aim()
	_refresh(true)
	return true

func skill_cooldown_left(id: String) -> float:
	return _skill_cd.get(id, 0.0)

func potion_cooldown_left() -> float:
	return _potion_cd

## ศรทะลวง / ศรกระจาย: needs the unlock level, no cooldown, enough MP, and a free hero.
## Pressed during a basic shot, the skill waits and starts as soon as that arrow is out.
## MP and cooldown are taken when the skill's arrow leaves, so a cancelled skill costs nothing.
func try_skill(id: String) -> bool:
	if state in ["roll", "hurt", "dead"]: return false
	if level < Skills.unlock_level(id): return false
	if _skill_cd.get(id, 0.0) > 0.0: return false
	if mp < skill_mp(id): return false
	if state == "shoot":
		if _pending_skill != "": return false      # another skill is drawing
		_queued_skill = id
		return true
	_start_skill(id)
	return true

func _start_skill(id: String) -> void:
	_queued_skill = ""
	_pending_skill = id
	state = "shoot"
	_t = 0.0
	_released = false
	velocity = Vector2.ZERO
	_aim()
	_refresh(true)

## Potions heal 40% of max HP or MP; one shared cooldown. Refused when that bar is full.
func try_potion(kind: String) -> bool:
	if state == "dead" or _potion_cd > 0.0: return false
	var item := "potion_" + kind
	if inventory.count_of(item) <= 0: return false
	if kind == "hp" and health.hp >= health.max_hp: return false
	if kind == "mp" and mp >= max_mp(): return false
	var frac := Balance.num("potion.heal_frac")
	if kind == "hp":
		health.hp = mini(health.max_hp, health.hp + int(round(frac * health.max_hp)))
	else:
		mp = minf(max_mp(), mp + frac * max_mp())
	inventory.remove(item, 1)
	_potion_cd = Balance.num("potion.cooldown")
	return true

func try_dodge(dir: Vector2) -> bool:
	if state == "dead" or _dodge_cd > 0.0:
		return false
	_roll = Balance.dodge(level)
	_dodge_cd = _roll.cooldown
	_roll_dir = dir.normalized() if dir.length() > 0.01 else BowLayer.dir_vector(facing)
	facing = Combat.facing_from_vector(_roll_dir, facing)
	_released = true          # a shot in progress is cancelled: no arrow later
	_pending_skill = ""
	_queued_skill = ""
	state = "roll"
	_t = 0.0
	rolled.emit(_roll_dir)
	_refresh(true)
	return true

## Damage from a monster. Returns the damage dealt, 0 when ignored (dead, invulnerable, rolling).
func receive_hit(atk: float, mult: float, from: Vector2) -> int:
	if state == "dead" or health.is_invulnerable():
		return 0
	if state == "roll" and _t < _roll.iframe:
		return 0
	var r := Combat.roll_damage(atk, mult, stats().def, false)
	health.take_hit(r.amount, false)
	if health.is_dead():
		return r.amount
	health.set_invulnerable(Balance.num("hero.hurt_iframe"))
	_knockback(from)
	_flash = Balance.num("hero.hurt_flash")
	_released = true          # getting hit cancels a pending shot
	_pending_skill = ""
	_queued_skill = ""
	state = "hurt"
	_t = 0.0
	_refresh(true)
	return r.amount

## Poison from a monster (mushroom spores): per_tick damage once a second for duration seconds,
## no knockback (blocked while invulnerable, like any hit). A new dose restarts it, keeping the higher tick.
var poison_tick := 0
var poison_left := 0.0
var _poison_t := 0.0

func apply_poison(per_tick: int, duration: float) -> void:
	if state == "dead" or per_tick <= 0: return
	poison_tick = maxi(poison_tick, per_tick) if poison_left > 0.0 else per_tick
	poison_left = duration
	_poison_t = 0.0

func _tick_poison(delta: float) -> void:
	if poison_left <= 0.0: return
	if state == "dead":
		poison_left = 0.0
		return
	poison_left -= delta
	_poison_t += delta
	if _poison_t >= 1.0:
		_poison_t -= 1.0
		health.take_hit(poison_tick, false)

# ---------- simulation ----------

func step(delta: float, input: Vector2) -> void:
	_tick_poison(delta)
	cooldown = maxf(0.0, cooldown - delta)
	_dodge_cd = maxf(0.0, _dodge_cd - delta)
	_potion_cd = maxf(0.0, _potion_cd - delta)
	for k in _skill_cd: _skill_cd[k] = maxf(0.0, _skill_cd[k] - delta)
	health.tick(delta)
	if state != "dead":
		mp = minf(max_mp(), mp + stats().mp_regen * delta)
	_flash = maxf(0.0, _flash - delta)
	_t += delta
	match state:
		"dead":
			velocity = Vector2.ZERO
			if _t >= Balance.num("hero.death_delay"):
				_respawn()
		"roll":
			var speed: float = _roll.distance / _roll.duration
			var dt := minf(delta, _roll.duration - (_t - delta))
			_move(_roll_dir * speed, maxf(dt, 0.0))
			if _t >= _roll.duration - 0.000001:
				state = "idle"
		"hurt":
			velocity = Vector2.ZERO
			if _t >= Balance.num("hero.hurt_lock"):
				state = "idle"
		"shoot":
			velocity = Vector2.ZERO
			if not _released and _t >= RELEASE_FRAME / SHOOT_FPS:
				_release()
			if _released and _queued_skill != "" and _pending_skill == "":
				_start_skill(_queued_skill)          # cut the basic shot's follow-through
			elif _t >= SHOOT_FRAMES / SHOOT_FPS:
				state = "idle"
		_:
			if input.length() > 0.01:
				facing = Combat.facing_from_vector(input, facing)
				state = "walk"
				velocity = input.normalized() * stats().walk
				if is_inside_tree(): move_and_slide()     # slide along posts while walking
				else: position += velocity * delta
			else:
				velocity = Vector2.ZERO
				state = "idle"
	_refresh()

func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down") + external_input
	input = input.limit_length(1.0)
	if Input.is_action_just_pressed("dodge"):
		try_dodge(input)
	if Input.is_action_just_pressed("skill_1"): try_skill("piercing")
	if Input.is_action_just_pressed("skill_2"): try_skill("spread")
	if Input.is_action_just_pressed("potion_hp"): try_potion("hp")
	if Input.is_action_just_pressed("potion_mp"): try_potion("mp")
	if Input.is_action_pressed("attack"):
		try_shoot()
	step(delta, input)

func _move(v: Vector2, dt: float) -> void:
	velocity = v
	if is_inside_tree():
		move_and_collide(v * dt)
	else:
		position += v * dt

func _knockback(from: Vector2) -> void:
	var away := (_pos() - from)
	if away.length() < 0.01: away = -BowLayer.dir_vector(facing)
	var push := away.normalized() * Balance.num("hero.hurt_knockback")
	if is_inside_tree(): move_and_collide(push)
	else: position += push

func _pos() -> Vector2:
	return global_position if is_inside_tree() else position

func _on_died() -> void:
	exp = Progression.after_death(level, exp)
	exp_changed.emit()
	state = "dead"
	_t = 0.0
	_released = true
	velocity = Vector2.ZERO
	died.emit()
	_refresh(true)

func _respawn() -> void:
	if is_inside_tree(): global_position = spawn_point
	else: position = spawn_point
	health.reset_full()
	mp = max_mp()
	health.set_invulnerable(Balance.num("hero.respawn_iframe"))
	state = "idle"
	_t = 0.0
	respawned.emit()
	_refresh(true)

# ---------- aiming & arrows ----------

func _enemies() -> Array:
	return get_tree().get_nodes_in_group("enemies") if is_inside_tree() else test_enemies

func _arrow_origin() -> Vector2:
	var v := BowLayer.dir_vector(facing)
	return _pos() + BowLayer.CHEST + Vector2(v.x, v.y * 0.6) * 18.0

## The enemy a shot would lock on to right now (nearest live one within shot.range), or null.
func current_target() -> Node2D:
	var live: Array = []
	var pts: Array = []
	var hps: Array = []
	for e in _enemies():
		if is_instance_valid(e) and e.is_alive() and not (e.has_method("is_hidden") and e.is_hidden()):
			live.append(e)
			pts.append(e.hurt_point())
			hps.append(e.hp if "hp" in e else 0)
	var i := Combat.pick_target(_pos(), pts, hps, Balance.num("shot.range"))
	return live[i] if i >= 0 else null

## Lock on to the nearest live enemy within shot.range and turn to face it.
func _aim() -> void:
	var live: Array = []
	var pts: Array = []
	var hps: Array = []
	for e in _enemies():
		if is_instance_valid(e) and e.is_alive() and not (e.has_method("is_hidden") and e.is_hidden()):
			live.append(e)
			pts.append(e.hurt_point())
			hps.append(e.hp if "hp" in e else 0)
	var i := Combat.pick_target(_pos(), pts, hps, Balance.num("shot.range"))
	_aim_target = live[i] if i >= 0 else null
	if _aim_target != null:
		facing = Combat.facing_from_vector(pts[i] - _pos(), facing)
		_aim_vec = (pts[i] - _arrow_origin()).normalized()
	else:
		_aim_vec = BowLayer.dir_vector(facing)

func _release() -> void:
	_released = true
	var start := _arrow_origin()
	var v := _aim_vec
	if is_instance_valid(_aim_target) and _aim_target.is_alive():
		v = (_aim_target.hurt_point() - start).normalized()
	if _pending_skill != "":
		var id := _pending_skill
		var b := build(id)
		if mp < b.mp:                         # cannot happen today (MP only drops here); stay safe
			_pending_skill = ""
			return
		mp -= b.mp
		_skill_cd[id] = b.cooldown
		skill_released.emit(id, start)
		var range_px := Balance.num("skills.%s.range" % id) if Balance.has("skills.%s.range" % id) else -1.0
		var n := int(b.arrows)
		var fan := deg_to_rad(b.fan_deg)
		for i in n:
			var dir := v if n == 1 else v.rotated(-fan / 2.0 + fan * i / (n - 1))
			_fire(start, dir, b.arrow_mult, b.pierce_all, range_px, b)
	else:
		_fire(start, v, 1.0, false)
	_pending_skill = ""

func _fire(start: Vector2, v: Vector2, mult: float, pierce: bool, range_px := -1.0, b := {}) -> void:
	var a: Arrow = ARROW_SCENE.instantiate()
	a.position = start
	var st := stats()
	a.launch(v, st.atk, _enemies(), mult, pierce, range_px)
	a.crit_chance = float(b.get("crit", st.crit))
	a.crit_mult = st.crit_mult
	if not b.is_empty():
		a.configure(b, self)
		a.spawned.connect(_on_arrow_spawned)
	if is_inside_tree():
		get_parent().add_child(a)
	shot.emit(a)

func _on_arrow_spawned(a: Arrow) -> void:
	a.spawned.connect(_on_arrow_spawned)
	shot.emit(a)

# ---------- visuals ----------

const ANIM_OF_STATE := {"dead": "death"}

func _anim_for(s: String) -> String:
	var name := "%s_%s" % [ANIM_OF_STATE.get(s, s), Combat.DIRS[facing]]
	if body.sprite_frames.has_animation(name):
		return name
	# fallbacks until the art exists: hurt/roll show idle/walk
	return "%s_%s" % [("walk" if s == "roll" else "idle"), Combat.DIRS[facing]]

func _refresh(restart := false) -> void:
	var name := _anim_for(state)
	if restart or body.animation != name:
		var keep := body.frame if (not restart and body.animation == name) else 0
		body.play(name)
		body.frame = keep
	if body.material:
		body.material.set_shader_parameter("flash_amount", 0.75 if _flash > 0.0 else 0.0)
	bow.visible = state != "dead"
	bow.apply("shoot" if state == "shoot" else "walk", facing)
