extends RefCounted
## Burn / slow on wolves (M3a design §5.3) and kill credit from burn.

var tree: SceneTree
func setup(t: SceneTree) -> void:
	tree = t

const DT := 1.0 / 60.0

func test_burn_ticks_and_refresh():
	var s := StatusEffects.new()
	s.apply_burn(5.0)
	var total := 0
	for i in 60: total += s.tick(DT)
	var r := "" if total == 5 else "1 s of burn dealt %d, want 5" % total
	for i in 90: total += s.tick(DT)
	s.apply_burn(3.0)                          # weaker re-hit: restart 3 s, keep 5 per tick
	for i in 180: total += s.tick(DT)
	if r == "" and total != 10 + 15: r = "after refresh total %d, want 25 (2 ticks + 3 ticks of 5)" % total
	for i in 120: total += s.tick(DT)
	if r == "" and total != 25: r = "burn kept going after it ended (%d)" % total
	return r

func test_slow_40_on_chase_and_lunge():
	var s := StatusEffects.new()
	var r := "" if absf(s.speed_mult() - 1.0) < 1e-6 else "no slow should be ×1"
	s.apply_slow()
	if r == "" and absf(s.speed_mult() - 0.6) > 1e-6: r = "slow ×%.2f, want 0.6" % s.speed_mult()
	for i in 181: s.tick(DT)
	if r == "" and absf(s.speed_mult() - 1.0) > 1e-6: r = "slow should end after 3 s"
	var w: Wolf = load("res://scenes/wolf.tscn").instantiate()
	w.setup()
	w.status.apply_slow()
	var before := w.position
	w._move(Vector2(100, 0), 1.0)
	if r == "" and absf(w.position.x - before.x - 60.0) > 0.01: r = "slowed wolf moved %.1f, want 60" % (w.position.x - before.x)
	w.free()
	return r

func test_burn_kill_credited_once():
	var g = load("res://scenes/test_ground.tscn").instantiate()
	g.save_path = "user://test_status_save.json"
	g.build()
	g.go_to("c1r0", "", false)          # the Lv1 wolf room
	var w: Wolf = g.packs[0].wolves[0]
	var exp_before: int = g.hero.exp
	var drops_before: int = g.drops.size()
	w.health.hp = 3
	w.status.apply_burn(5.0)
	for i in 90: w.step(DT, null)
	var r := ""
	if w.is_alive(): r = "wolf survived the burn"
	elif g.hero.exp == exp_before: r = "no EXP for a burn kill"
	var exp_after: int = g.hero.exp
	for i in 120: w.step(DT, null)
	if r == "" and g.hero.exp != exp_after: r = "EXP credited more than once"
	elif r == "" and g.drops.size() == drops_before: r = "no loot rolled"
	g.free()
	if FileAccess.file_exists("user://test_status_save.json"): DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_status_save.json"))
	return r
