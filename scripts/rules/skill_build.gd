class_name SkillBuild
## What one active skill does with its gems (M3a design §5.2, §5.4). Pure; used by the hero,
## the HUD and the skill screen so they always agree.

static func _base(skill_id: String) -> Dictionary:
	match skill_id:
		"spread":
			return {"arrows": int(Balance.num("skills.spread.arrows")), "fan_deg": Balance.num("skills.spread.fan_deg"), "pierce_all": false}
		_:
			return {"arrows": 1, "fan_deg": 0.0, "pierce_all": true}

## gems: the skill's sockets (nulls and gems whose labels do not fit are ignored).
## hero_stats needs crit, skill_cd_cut and element_dmg (Hero.stats()).
static func of(skill_id: String, char_level: int, gems: Array, hero_stats: Dictionary) -> Dictionary:
	var b := _base(skill_id)
	var mp := Skills.mp_cost(skill_id)
	var dmg := 1.0
	var dmg_pct := 0.0
	var mp_cut := 0.0
	var cd_cut := 0.0
	var crit := float(hero_stats.get("crit", Balance.num("crit.chance")))
	var out := {"pierce_extra": 0, "bounces": 0, "bounce_mult": 0.0, "homing": false, "leech": 0.0, "element": "", "element_mult": 1.0}
	var per_arrow := 1.0
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
				per_arrow *= e
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
		"fan_deg": b.fan_deg,
		"pierce_all": b.pierce_all,
	})
	return out
