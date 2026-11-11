extends RefCounted
## Hero sockets gems; skills fire from SkillBuild (M3a design §5).

const DT := 1.0 / 60.0
var _shots: Array = []

func _hero(level := 1) -> Hero:
	var h: Hero = load("res://scenes/hero.tscn").instantiate()
	h.setup_sprites()
	if level > 1: h.set_progress(level, 0)
	h.inventory.slots.clear()
	_shots = []
	h.shot.connect(func(a): _shots.append(a))
	return h

func _g(type: String, extra := {}) -> Dictionary:
	var g := {"type": type, "level": 1, "exp": 0, "rarity": "good", "opts": [{"k": "crit", "v": 0.03}]}
	g.merge(extra, true)
	return g

func _run(h: Hero, s: float) -> void:
	for i in int(round(s / DT)): h.step(DT, Vector2.ZERO)

func _done(h: Hero) -> void:
	for a in _shots: if is_instance_valid(a): a.free()
	h.free()

func test_socket_swap_and_label():
	var h := _hero()
	h.inventory.add_gem(_g("expand"))
	h.inventory.add_gem(_g("split"))
	h.inventory.add_gem(_g("multiply"))
	var r := ""
	if h.socket("piercing", 0, 0) != "ป้ายไม่ตรง": r = "expand into piercing should be refused"
	elif h.socket("spread", 0, 1) != "ยังไม่ปลด": r = "spread is locked at Lv1"
	elif h.socket("piercing", 2, 1) != "ช่องยังไม่เปิด": r = "slot 3 opens at skill level 10"   # owner 2026-11-08: 2 slots from unlock
	elif h.socket("piercing", 0, 1) != "" or h.skill_gems.piercing[0].type != "split": r = "split not socketed"
	elif h.inventory.slots.size() != 2: r = "split should leave the bag (%d slots)" % h.inventory.slots.size()
	elif h.socket("piercing", 0, 1) != "" or h.skill_gems.piercing[0].type != "multiply": r = "swap failed"
	elif h.inventory.slots.back().get("gem", {}).get("type", "") != "split": r = "swapped-out gem should be back in the bag"
	_done(h)
	return r

func test_unsocket_full_bag():
	var h := _hero()
	h.inventory.add_gem(_g("split"))
	h.socket("piercing", 0, 0)
	for i in 24: h.inventory.add("junk_%d" % i, 1)
	var r := ""
	if h.unsocket("piercing", 0) != "กระเป๋าเต็ม" or h.skill_gems.piercing[0] == null: r = "unsocket into a full bag must be refused"
	h.inventory.slots.pop_back()
	if r == "" and (h.unsocket("piercing", 0) != "" or h.skill_gems.piercing[0] != null): r = "unsocket failed with room"
	_done(h)
	return r

func test_piercing_with_split_fires_three():
	var h := _hero()
	h.facing = 2
	h.inventory.add_gem(_g("split"))
	h.socket("piercing", 0, 0)
	h.try_skill("piercing")
	_run(h, 0.6)
	var r := ""
	if _shots.size() != 3: r = "%d arrows, want 3" % _shots.size()
	else:
		var angles := []
		for a in _shots: angles.append(rad_to_deg(a.dir.angle()))
		angles.sort()
		if absf(angles[1] - angles[0] - 12.0) > 0.1 or absf(angles[2] - angles[1] - 12.0) > 0.1: r = "angles %s, want 12° apart" % [angles]
		elif absf(_shots[0].mult - 1.08) > 1e-4 or not _shots[0].pierce: r = "mult %.3f pierce %s" % [_shots[0].mult, _shots[0].pierce]
		elif absf(h.mp - (50.0 - 11.2 + 6.0 * (0.6 - 5.0 / 14.0))) > 0.2: r = "mp %.2f, want 11.2 spent" % h.mp
	_done(h)
	return r

func test_spread_with_split_fires_seven():
	var h := _hero(3)
	h.facing = 2
	h.inventory.add_gem(_g("split"))
	h.socket("spread", 0, 0)
	h.try_skill("spread")
	_run(h, 0.6)
	var r := ""
	if _shots.size() != 7: r = "%d arrows, want 7" % _shots.size()
	else:
		var lo := INF
		var hi := -INF
		for a in _shots:
			lo = minf(lo, rad_to_deg(a.dir.angle())); hi = maxf(hi, rad_to_deg(a.dir.angle()))
		if absf(hi - lo - 63.0) > 0.2: r = "fan %.1f°, want 63°" % (hi - lo)
	_done(h)
	return r

func test_mp_too_high_refused():
	var h := _hero(3)
	for t in ["split"]: h.inventory.add_gem(_g(t))
	h.socket("spread", 0, 0)                 # 12 × 1.4 = 16.8
	h.mp = 16.0
	var r := ""
	if h.try_skill("spread") or h.mp != 16.0: r = "fired or spent with 16 MP (cost 16.8)"
	elif absf(h.skill_mp("spread") - 16.8) > 1e-6: r = "skill_mp %.2f" % h.skill_mp("spread")
	_done(h)
	return r

func test_gem_exp_from_kill_and_at_cap():
	var h := _hero()
	h.inventory.add_gem(_g("split", {"opts": [{"k": "gem_exp", "v": 0.2}]}))
	h.socket("piercing", 0, 0)
	h.on_kill(100, 1)
	var g: Dictionary = h.skill_gems.piercing[0]
	var r := "" if g.exp == 120 else "gem exp %d, want 120 (100 × 1.2)" % g.exp
	h.set_progress(Progression.cap(), 0)
	h.on_kill(10, Progression.cap())
	if r == "" and g.exp != 132: r = "at the character cap the gem should still gain (exp %d, want 132)" % g.exp
	_done(h)
	return r

func test_hud_shows_real_mp_and_cooldown():
	var h := _hero(3)
	h.inventory.add_gem(_g("split"))
	h.socket("spread", 0, 0)
	h.mp = 14.0
	var hud := Hud.new()
	hud.build()
	hud.bind(h)
	hud.refresh()
	var r := "" if not hud.buttons.buttons["skill2"].enabled else "spread shown usable with 14 MP (needs 16.8)"
	hud.free()
	_done(h)
	return r

func _full_bag(h: Hero, keep := 0) -> void:
	var i := 0
	while h.inventory.slots.size() < 24 - keep:
		h.inventory.add("junk_%d" % i, 1)
		i += 1

func test_swap_from_single_gem_always_works_full_bag():
	var h := _hero()
	h.inventory.add_gem(_g("split"))
	h.socket("piercing", 0, 0)
	h.inventory.add_gem(_g("multiply"))
	_full_bag(h)
	var i := h.inventory.slots.size() - 1
	for k in h.inventory.slots.size():
		if h.inventory.slots[k].get("gem", {}).get("type", "") == "multiply": i = k
	var r := ""
	if h.socket("piercing", 0, i) != "": r = "swap with a full bag refused"
	elif h.skill_gems.piercing[0].type != "multiply": r = "multiply not socketed"
	elif h.inventory.slots[i].get("gem", {}).get("type", "") != "split": r = "split should take multiply's bag slot"
	_done(h)
	return r

func test_swap_from_stack_full_bag_refused_nothing_lost():
	var h := _hero()
	h.inventory.add_gem(_g("split"))
	h.socket("piercing", 0, 0)
	h.inventory.add("gem_element", 3)
	_full_bag(h)
	var gems_before := _count_gems(h)
	var r := ""
	if h.socket("piercing", 0, 0) != "กระเป๋าเต็ม": r = "should be refused: no room for the gem that comes out"
	elif _count_gems(h) != gems_before or h.inventory.slots[0].count != 3: r = "a gem was lost or the stack changed"
	elif h.skill_gems.piercing[0].type != "split": r = "socket changed"
	_done(h)
	return r

func _count_gems(h: Hero) -> int:
	var n := 0
	for s in h.inventory.slots:
		if String(s.id).begins_with("gem_"): n += int(s.count)
	for id in h.skill_gems:
		for g in h.skill_gems[id]: if g != null: n += 1
	return n

func test_duplicate_gem_type_refused():
	var h := _hero(10)
	h.inventory.add_gem(_g("element", {"element": "fire"}))
	h.inventory.add_gem(_g("element", {"element": "ice"}))
	h.socket("piercing", 0, 0)
	var r := "" if h.socket("piercing", 1, 0) == "เจมชนิดนี้ใส่ในสกิลนี้แล้ว" else "two element gems in one skill"
	if r == "" and h.socket("piercing", 0, 0) != "": r = "replacing the same slot with the same type should work"
	_done(h)
	return r

func test_hud_skill_button_shows_mp():
	var h := _hero(3)
	h.inventory.add_gem(_g("split"))
	h.socket("spread", 0, 0)
	var hud := Hud.new()
	hud.build()
	hud.bind(h)
	hud.refresh()
	var r := "" if hud.buttons.buttons["skill2"].note == "MP 16.8" else "skill2 note '%s', want MP 16.8" % hud.buttons.buttons["skill2"].note
	hud.free()
	_done(h)
	return r

# ---------- M5b Task 1: 2 slots from unlock (owner 2026-11-08), closed-slot gems back to the bag (owner 2026-11-09) ----------

func _bag_index(h: Hero, type: String) -> int:
	for i in h.inventory.slots.size():
		if String(h.inventory.slots[i].id) == "gem_" + type: return i
	return -1

func test_two_slots_from_unlock():
	var h := _hero(3)          # piercing skill Lv3, spread skill Lv1
	for t in ["split", "multiply", "split", "multiply", "execute"]: h.inventory.add_gem(_g(t))
	var r := ""
	if h.gem_slots("piercing") != 2 or h.gem_slots("spread") != 2: r = "slots %d / %d, want 2 / 2" % [h.gem_slots("piercing"), h.gem_slots("spread")]
	elif h.socket("piercing", 0, _bag_index(h, "split")) != "": r = "piercing slot 1 refused"
	elif h.socket("piercing", 1, _bag_index(h, "multiply")) != "": r = "piercing slot 2 refused at skill Lv3"
	elif h.socket("spread", 0, _bag_index(h, "split")) != "": r = "spread slot 1 refused"
	elif h.socket("spread", 1, _bag_index(h, "multiply")) != "": r = "spread slot 2 refused at skill Lv1"
	elif h.socket("piercing", 2, _bag_index(h, "execute")) != "ช่องยังไม่เปิด": r = "piercing slot 3 should be closed at skill Lv3"
	elif not is_equal_approx(h.skill_mp("spread"), 12.0 * 1.4 * 1.5): r = "spread MP %.3f, want both gems counted" % h.skill_mp("spread")
	_done(h)
	return r

func test_slot_three_at_skill_level_ten():
	var r := ""
	for lv in [9, 10]:
		var h := _hero(lv)
		for t in ["split", "multiply", "execute", "leech"]: h.inventory.add_gem(_g(t))
		h.socket("piercing", 0, _bag_index(h, "split"))
		h.socket("piercing", 1, _bag_index(h, "multiply"))
		var res := h.socket("piercing", 2, _bag_index(h, "execute"))
		var want := "" if lv == 10 else "ช่องยังไม่เปิด"
		if res != want: r = "char Lv%d piercing slot 3: '%s', want '%s'" % [lv, res, want]
		# spread unlocks at 3: at char Lv10 it is skill Lv8, still 2 slots
		elif h.socket("spread", 2, _bag_index(h, "leech")) != "ช่องยังไม่เปิด": r = "char Lv%d spread slot 3 should be closed" % lv
		elif h.socket("piercing", 3, _bag_index(h, "leech")) != "ช่องยังไม่เปิด": r = "char Lv%d piercing slot 4 should be closed" % lv
		_done(h)
		if r != "": return r
	return ""

## Review Focus 1: sockets on a skill with no numbers (arrow_rain), on a locked skill, and in a closed slot (only a
## hand-made save or a later rule change can hold these). Loading must not crash; those gems go back to the bag.
func test_after_load_returns_gems_from_unknown_and_closed_slots():
	var h := _hero(1)
	var split := _g("split")
	var mult := _g("multiply")
	var execute := _g("execute", {"level": 4, "exp": 33})
	var expand := _g("expand", {"opts": [{"k": "dmg_pct", "v": 0.041}]})
	var leech := _g("leech")
	h.set_skill_gems({"piercing": [split, mult, execute], "arrow_rain": [expand], "spread": [leech]})
	var changed := [0]
	h.gems_changed.connect(func(): changed[0] += 1)
	var r := ""
	if h.gem_slots("arrow_rain") != 0: r = "arrow_rain has no numbers: 0 slots, got %d" % h.gem_slots("arrow_rain")
	elif not is_equal_approx(h.build("piercing").mp, 8 * 1.4 * 1.5): r = "build reads a closed slot before the return: MP %.3f" % h.build("piercing").mp
	if r == "":
		var moved := h.return_closed_gems()
		if moved != 3: r = "moved %d gems, want 3 (execute, expand, leech)" % moved
		elif changed[0] != 1: r = "gems_changed emitted %d times, want 1" % changed[0]
		elif h.skill_gems.piercing.size() < 2 or h.skill_gems.piercing[0] != split or h.skill_gems.piercing[1] != mult:
			r = "open-slot gems must stay where they are: %s" % [h.skill_gems.piercing]
		elif h.skill_gems.piercing.size() > 2 and h.skill_gems.piercing[2] != null: r = "slot 3 still holds %s" % [h.skill_gems.piercing[2]]
		else:
			for id in ["arrow_rain", "spread"]:
				for g in h.skill_gems.get(id, []):
					if g != null: r = "%s still holds %s" % [id, g]
			if r == "":
				var bag := {}
				for s in h.inventory.slots: if s.has("gem"): bag[String(s.gem.type)] = s.gem
				for g in [execute, expand, leech]:
					if bag.get(String(g.type)) != g: r = "%s back in the bag changed or missing: %s" % [g.type, bag.get(String(g.type))]
	if r == "" and h.return_closed_gems() != 0: r = "a second return moved gems again"
	if r == "" and changed[0] != 1: r = "nothing moved, but gems_changed fired again"
	_done(h)
	return r

## Owner 2026-11-09: never lost. With a full bag the gem stays socketed (no effect, no EXP) until there is room.
func test_closed_gem_stays_when_bag_full_and_is_inert():
	var h := _hero(1)
	_full_bag(h)
	var split := _g("split")
	var mult := _g("multiply")
	var execute := _g("execute")
	h.set_skill_gems({"piercing": [split, mult, execute]})
	var r := ""
	if h.return_closed_gems() != 0: r = "moved a gem into a full bag"
	elif h.skill_gems.piercing.size() != 3 or h.skill_gems.piercing[2] != execute: r = "the closed-slot gem was lost: %s" % [h.skill_gems.piercing]
	elif not is_equal_approx(h.build("piercing").mp, 8 * 1.4 * 1.5): r = "MP %.3f: the closed slot's execute (×1.2) must be ignored" % h.build("piercing").mp
	elif not is_equal_approx(h.build("piercing").crit, SkillBuild.of("piercing", 1, [split, mult], h.stats()).crit): r = "crit counts the closed slot"
	elif h.open_gems("piercing") != [split, mult]: r = "open_gems %s" % [h.open_gems("piercing")]
	if r == "":
		h.on_kill(100, 1)      # set_skill_gems keeps copies: read the hero's own gems
		if int(h.skill_gems.piercing[2].exp) != 0: r = "an inert gem gained EXP (%d)" % h.skill_gems.piercing[2].exp
		elif int(h.skill_gems.piercing[0].exp) <= 0: r = "an open-slot gem gained no EXP"
	if r == "":
		h.inventory.slots.pop_back()      # room in the bag: the next return moves it
		if h.return_closed_gems() != 1 or h.skill_gems.piercing.size() > 2 and h.skill_gems.piercing[2] != null: r = "with room the gem should go back"
		elif _bag_index(h, "execute") == -1: r = "execute not in the bag"
	_done(h)
	return r

func test_open_gems_padded_to_open_slots():
	var h := _hero(10)
	var split := _g("split")
	h.set_skill_gems({"piercing": [split]})
	var r := ""
	if h.open_gems("piercing") != [split, null, null]: r = "piercing %s, want [split, null, null]" % [h.open_gems("piercing")]
	elif h.open_gems("spread") != [null, null]: r = "spread %s, want [null, null]" % [h.open_gems("spread")]
	elif h.open_gems("arrow_rain") != []: r = "arrow_rain %s, want []" % [h.open_gems("arrow_rain")]
	_done(h)
	return r

# ---------- M5b Task 8: the hero's side of the sustain combos (on_combo_kill / on_combo_crit) ----------

## Each kill credited to a bloodthirst ledger refunds +2 under the press's cap of 6 and never lifts MP above max; the
## 3 % heal never lifts HP above max. Owner 2026-11-11 ("นับเฉพาะ MP ที่ได้จริง"): from max − 3 the kills give 2, then the
## 1 MP left below max, then 0 at full MP: the ledger counts 3, not 6.
func test_combo_kill_pays_under_cap_and_max():
	var h := _hero(10)
	var c := ComboCast.new("bloodthirst")
	h.mp = h.max_mp() - 3.0
	h.health.hp = h.health.max_hp - 1
	var got: Array = []
	for i in 4: got.append(h.on_combo_kill(c))
	var r := ""
	if got != [2.0, 1.0, 0.0, 0.0]: r = "refunds %s, want [2, 1, 0, 0] (only MP below max)" % [got]
	elif h.mp != float(h.max_mp()): r = "MP %.2f, want max %d" % [h.mp, h.max_mp()]
	elif h.health.hp != h.health.max_hp: r = "HP %d, want max %d" % [h.health.hp, h.health.max_hp]
	elif c.mp_refunded() != 3.0: r = "ledger %.2f, want 3 (MP really gained)" % c.mp_refunded()
	_done(h)
	return r

## Owner 2026-11-11 (Task 8 review, "นับเฉพาะ MP ที่ได้จริง"), normal: well below max MP every kill gains its full
## kill_mp until the cap: bloodthirst 2, 2, 2, 0 (6); ราหู 3, 3, 3, 0 (9).
func test_combo_kill_cap_normal_counts_full_gain():
	var r := ""
	for row in [["bloodthirst", [2.0, 2.0, 2.0, 0.0], 6.0], ["rahu", [3.0, 3.0, 3.0, 0.0], 9.0]]:
		var h := _hero(10)
		var c := ComboCast.new(row[0])
		h.mp = 1.0
		var got: Array = []
		for i in 4: got.append(h.on_combo_kill(c))
		if got != row[1]: r = "%s: refunds %s, want %s" % [row[0], got, row[1]]
		elif c.mp_refunded() != row[2] or h.mp != 1.0 + row[2]: r = "%s: ledger %.2f / MP %.2f, want %s / %s" % [row[0], c.mp_refunded(), h.mp, row[2], 1.0 + row[2]]
		_done(h)
		if r != "": break
	return r

## Full MP: a kill gains 0 and does NOT use up the cap; after MP is spent the same press still pays its whole 6 / 9.
func test_combo_kill_at_full_mp_keeps_the_cap():
	var r := ""
	for row in [["bloodthirst", 3, 2.0, 6.0], ["rahu", 3, 3.0, 9.0]]:
		var h := _hero(10)
		var c := ComboCast.new(row[0])
		h.mp = float(h.max_mp())
		var full: Array = []
		for i in 5: full.append(h.on_combo_kill(c))
		if full != [0.0, 0.0, 0.0, 0.0, 0.0]: r = "%s at full MP: refunds %s, want all 0" % [row[0], full]
		elif c.mp_refunded() != 0.0: r = "%s: kills at full MP used up %.2f of the cap" % [row[0], c.mp_refunded()]
		if r == "":
			h.mp = 0.0
			var later := 0.0
			for i in row[1] + 1: later += h.on_combo_kill(c)
			if later != row[3] or h.mp != row[3]: r = "%s: after spending MP the press paid %.2f, want its whole cap %s" % [row[0], later, row[3]]
		_done(h)
		if r != "": break
	return r

## Partial: 1 MP below max a kill gains 1 and uses up only that 1 (bloodthirst then has 5 left: 2, 2, 1); a fraction
## below max (0.25) gains and spends exactly that fraction.
func test_combo_kill_partial_gain_uses_only_the_gain():
	var h := _hero(10)
	var c := ComboCast.new("bloodthirst")
	h.mp = h.max_mp() - 1.0
	var r := ""
	var first := h.on_combo_kill(c)
	if first != 1.0 or c.mp_refunded() != 1.0: r = "1 below max: gained %.2f, ledger %.2f, want 1 / 1" % [first, c.mp_refunded()]
	if r == "":
		h.mp = 0.0
		var rest: Array = []
		for i in 4: rest.append(h.on_combo_kill(c))
		if rest != [2.0, 2.0, 1.0, 0.0] or c.mp_refunded() != 6.0: r = "after the partial kill: refunds %s (ledger %.2f), want [2, 2, 1, 0] (6)" % [rest, c.mp_refunded()]
	if r == "":
		var d := ComboCast.new("rahu")
		h.mp = h.max_mp() - 0.25
		var g := h.on_combo_kill(d)
		if not is_equal_approx(g, 0.25) or not is_equal_approx(d.mp_refunded(), 0.25) or h.mp != float(h.max_mp()): r = "0.25 below max: gained %.3f, ledger %.3f, MP %.3f" % [g, d.mp_refunded(), h.mp]
	_done(h)
	return r

## Dead: a kill pays nothing (like on_kill's EXP and leech_heal) and does not spend the press's cap.
func test_combo_kill_while_dead_pays_nothing_and_keeps_cap():
	var h := _hero(10)
	var c := ComboCast.new("bloodthirst")
	h.mp = 10.0
	h.health.hp = 50
	h.state = "dead"
	var r := ""
	if h.on_combo_kill(c) != 0.0 or h.mp != 10.0 or h.health.hp != 50: r = "a dead hero was paid"
	elif c.mp_refunded() != 0.0: r = "the cap was spent while dead (%.2f)" % c.mp_refunded()
	h.on_combo_crit(ComboCast.new("rahu"))
	if r == "" and h.health.hp != 50: r = "a dead hero was healed by a crit"
	_done(h)
	return r

## During a warp the hook pays as on_kill gives EXP (the existing behaviour; no kill can land then: arrows and trails
## halt and the old room's packs stop, B20).
func test_combo_kill_during_warp_pays_like_on_kill():
	var h := _hero(5)                     # below the level cap, so a kill gives EXP
	h.begin_warp()
	h.mp = 10.0
	var exp0 := h.exp
	h.on_kill(10, 5)
	var r := ""
	if h.exp == exp0: r = "setup: on_kill gives no EXP while warping"
	elif h.on_combo_kill(ComboCast.new("bloodthirst")) != 2.0 or h.mp != 12.0: r = "a kill during a warp did not pay like on_kill (MP %.2f)" % h.mp
	h.end_warp()
	_done(h)
	return r

## ราหู: a crit heals 1 % of max HP, never above max; a ledger without crit_heal_frac heals nothing.
func test_combo_crit_heals_1pct_never_over_max():
	var h := _hero(10)
	h.health.hp = h.health.max_hp / 2
	var hp0 := h.health.hp
	var carry0 := h._leech_carry
	h.on_combo_crit(ComboCast.new("rahu"))
	var r := ""
	var want := int(floor(carry0 + 0.01 * h.health.max_hp + 1e-6))
	if h.health.hp - hp0 != want: r = "a crit healed %d, want %d" % [h.health.hp - hp0, want]
	var hp1 := h.health.hp
	h.on_combo_crit(ComboCast.new("bloodthirst"))
	if r == "" and h.health.hp != hp1: r = "a bloodthirst crit healed"
	h.health.hp = h.health.max_hp
	h.on_combo_crit(ComboCast.new("rahu"))
	if r == "" and h.health.hp != h.health.max_hp: r = "a crit lifted HP above max"
	_done(h)
	return r
