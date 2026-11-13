class_name SkillHit
## M5b Task 8b: ONE hit of an area skill press on one monster (a ห่าศร tick; Task 8c: a thorn trap's trigger), shared
## so every area skill deals damage, leeches, applies its element gem and reports kills / crits the same way.
## Area hits are PRIMARY hits of the press (plan Global Constraints): they roll the press's crit chance, leech, apply
## the element gem's status and report to THE one kill / crit hook (Hero.combo_hit) with the press's ledger (the
## ComboCast in src.cast), so a rain's kills share the press's one MP cap (6 / 9) with everything else it did.
## They never produce the arrow-only combo effects: no trail, bounce, bolt, mark, freeze count or shatter.
## Client-side only (risks.md S1): online play needs the server to deal these hits and own the ledger.
##
## src (Hero.hit_source, built once per press; the per-tick keys are reset by the caller at each tick):
##   atk, crit, crit_mult   the hero's ATK, the build's crit chance and the crit damage at the press
##   build                  the press's build (leech, element, combo)
##   shooter                the hero (leech_heal / on_combo_kill / on_combo_crit); may be freed
##   cast                   the press's ComboCast, or null
##   targets                the monsters of the press (the lightning gem's chain picks from them)
##   quiet (per tick)       true after the first hit of the tick that landed: the rest play no hit sound (Sfx.hit_quiet)
##   zapped (per tick)      true after the tick's one chain_zap effect
##   fx_parent              where the chain_zap is shown (null = none: tests, no tree)

## A monster's feet: its node origin (global in a tree, plain position outside one, as in tests).
static func feet(t: Node2D) -> Vector2:
	return t.global_position if t.is_inside_tree() else t.position

## One hit of `mult` × ATK on t, pushed from `at` (the area's centre). Returns the damage dealt (0: dead / freed).
static func hit(t: Node2D, src: Dictionary, mult: float, at: Vector2) -> int:
	if not is_instance_valid(t) or not t.is_alive(): return 0
	var b: Dictionary = src.get("build", {})
	var amount := _deal(t, src, mult, at)
	if amount <= 0 or not is_instance_valid(t): return amount
	match String(b.get("element", "")):
		"fire":
			if t.has_method("apply_status"):
				t.apply_status("burn", amount * Balance.num("elements.fire.burn_frac"), float(b.get("leech", 0.0)), src.get("shooter"), src.get("cast"))
		"ice":
			if t.has_method("apply_status"): t.apply_status("slow")
		"lightning":
			# as the arrow's lightning gem: one chain to the nearest other live monster, × elements.lightning.mult;
			# the chained hit applies nothing further
			var from: Vector2 = t.hurt_point()
			var other := _nearest(src.get("targets", []), from, Balance.num("elements.lightning.range"), t)
			if other != null:
				_deal(other, src, mult * Balance.num("elements.lightning.mult"), from)
				var parent = src.get("fx_parent")
				if not src.get("zapped", false) and is_instance_valid(parent) and is_instance_valid(other):
					src["zapped"] = true                       # plan: at most one chain_zap per tick
					var z := FxSprite.make("chain_zap")
					z.position = other.hurt_point()
					parent.add_child(z)
					z.play("chain_zap")
	return amount

## The damage itself: receive_hit (the target's taken_mult applies inside), then the kill / crit hook and the leech.
## A sustain recipe's press tints the hit spark for this one hit, as Arrow._receive does (owner 2026-11-11).
static func _deal(t: Node2D, src: Dictionary, mult: float, from: Vector2) -> int:
	var b: Dictionary = src.get("build", {})
	var shooter = src.get("shooter")
	var was: bool = t.is_alive()
	var tint := _tint(src)
	var tinted := tint != Color.WHITE and "spark_tint" in t
	if tinted: t.spark_tint = tint
	var quiet := bool(src.get("quiet", false))
	if quiet: Sfx.hit_quiet = true
	var amount: int = t.receive_hit(float(src.atk), mult, from, float(src.get("crit", -1.0)), float(src.get("crit_mult", -1.0)))
	if quiet: Sfx.hit_quiet = false
	if amount > 0: src["quiet"] = true
	if not is_instance_valid(t): return amount
	if tinted: t.spark_tint = Color.WHITE
	Hero.combo_hit(shooter, src.get("cast"), t, was, amount, t.get("last_hit_crit") == true)
	var frac := float(b.get("leech", 0.0))
	if frac > 0.0 and amount > 0 and is_instance_valid(shooter) and shooter.has_method("leech_heal"):
		shooter.leech_heal(amount * frac)
	return amount

## The press's hit-spark tint (ComboFx.spark_tint of its recipe), read once per press and kept in src.
static func _tint(src: Dictionary) -> Color:
	if not src.has("spark"):
		var c = src.get("build", {}).get("combo", {})
		src["spark"] = ComboFx.spark_tint(String(c.get("id", "")) if typeof(c) == TYPE_DICTIONARY else "")
	return src.spark

static func _nearest(targets: Array, from: Vector2, max_dist: float, skip: Node2D) -> Node2D:
	var best: Node2D = null
	var best_d := max_dist
	for t in targets:
		if not is_instance_valid(t) or t == skip or not t.is_alive(): continue
		var d: float = from.distance_to(t.hurt_point())
		if d <= best_d:
			best_d = d
			best = t
	return best
