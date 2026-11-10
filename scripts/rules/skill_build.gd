class_name SkillBuild
## What one active skill does with its gems (M3a design §5.2, §5.4). Pure; used by the hero,
## the HUD and the skill screen so they always agree.

static func _base(skill_id: String) -> Dictionary:
	match skill_id:
		"spread":
			return {"arrows": int(Balance.num("skills.spread.arrows")), "fan_deg": Balance.num("skills.spread.fan_deg"), "pierce_all": false}
		_:
			return {"arrows": 1, "fan_deg": 0.0, "pierce_all": true}

## gems: the skill's OPEN sockets (Hero.open_gems; nulls and gems whose labels do not fit are ignored).
## hero_stats needs crit, skill_cd_cut and element_dmg (Hero.stats()).
## M5b combos (docs/superpowers/specs/2026-11-08-gem-combos.md): "combo" = GemCombo.resolve, "combo_p" = a copy
## of that recipe's numbers (read once per press; hits read the build, not the data), "extra_bounces".
## Stat-level parts folded in here: crit_bonus → crit, leech_add → leech (owner 2026-11-09: the leech gem's own
## leech + a flat 3 %), homing_full → homing keeps full damage. Combos add no MP multiplier. Combo numbers are
## flat at any gem level (owner 2026-11-09); the gems' own effects keep scaling.
static func of(skill_id: String, char_level: int, gems: Array, hero_stats: Dictionary) -> Dictionary:
	var combo := GemCombo.resolve(skill_id, gems)
	var cp := GemCombo.numbers(String(combo.get("id", "")))
	var b := _base(skill_id)
	var mp := Skills.mp_cost(skill_id)
	var dmg := 1.0
	var dmg_pct := 0.0
	var mp_cut := 0.0
	var cd_cut := 0.0
	var crit := float(hero_stats.get("crit", Balance.num("crit.chance"))) + float(cp.get("crit_bonus", 0.0))
	var out := {"pierce_extra": 0, "bounces": 0, "bounce_mult": 0.0, "homing": false, "leech": float(cp.get("leech_add", 0.0)), "element": "", "element_mult": 1.0,
		"combo": combo, "combo_p": cp, "extra_bounces": int(cp.get("extra_bounces", 0.0))}
	var per_arrow := 1.0
	var lines := 1
	for g in gems:
		if typeof(g) != TYPE_DICTIONARY or not Gem.fits(String(g.type), skill_id): continue
		var t := String(g.type)
		var d := Gem.data(t)
		var e := Gem.effect(g)
		mp *= Gem.mp_mult(t)
		dmg_pct += Gem.option(g, "dmg_pct")
		mp_cut += Gem.option(g, "mp_cut")
		cd_cut += Gem.option(g, "cd_cut")
		crit += Gem.option(g, "crit")
		var high := int(g.level) >= int(Balance.num("gem_exp.strong_level"))
		match t:
			"split":
				b.arrows += int(d.extra_arrows)
				lines += int(d.extra_arrows)
				per_arrow *= e
				if skill_id == "spread": b.fan_deg = Balance.num("gem_split.spread_fan_deg")
				else: b.fan_deg = Balance.num("gem_split.piercing_step_deg") * (b.arrows - 1)
			"ricochet":
				out.bounces = int(d.bounces_at_10) if high else int(d.bounces)
				out.bounce_mult = e
			"pierce":
				out.pierce_extra = int(d.extra_at_10) if high else int(d.extra)
			"homing":
				out.homing = true
				if cp.get("homing_full", 0.0) == 0.0: per_arrow *= e
			"multiply":
				dmg *= e
			"execute":
				crit += e
			"leech":
				out.leech += e
			"element":
				out.element = String(g.get("element", ""))
				out.element_mult = e + float(hero_stats.get("element_dmg", 0.0))
				dmg *= out.element_mult
	var total_mult := dmg * (1.0 + dmg_pct)
	out.merge({
		"mp": mp * (1.0 - mp_cut),
		"dmg_mult": total_mult,
		"arrow_mult": Skills.damage_mult(skill_id, char_level) * total_mult * per_arrow,
		"crit": crit,
		"cooldown": Skills.cooldown(skill_id, char_level, float(hero_stats.get("skill_cd_cut", 0.0)) + cd_cut),
		"arrows": b.arrows,
		"lines": lines,
		"fan_deg": b.fan_deg,
		"pierce_all": b.pierce_all,
	})
	return out

## The line (0 .. b.lines − 1) of arrow i of a press of build `b` (Hero._release's fan order). Lines = the approved sim's
## "arrow lines" (tools/gem_combo_sim.py: 1, 3 with the split gem): ศรทะลวง 1 arrow per line; ศรกระจาย 5 arrows = 1 line,
## +split 7 arrows in 3 lines, in fan order and symmetric (2 / 3 / 2). Owner 2026-11-10: the lightning combo's +1 bounce
## and bolts come from one arrow per line per press (Arrow.carries_lightning).
static func line_of(b: Dictionary, i: int) -> int:
	var n := int(b.get("arrows", 1))
	var lines := int(b.get("lines", 1))
	if n <= 1 or lines <= 1: return 0
	return clampi(roundi(float(i) * (lines - 1) / (n - 1)), 0, lines - 1)
