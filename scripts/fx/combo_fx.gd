class_name ComboFx
## M5b gem combos (spec docs/superpowers/specs/2026-11-08-gem-combos.md "เอฟเฟกต์ที่ใช้ซ้ำ", plan Task 5): plays a
## recipe's effect for one event by REUSING manifest effects (assets/fx/manifest.json), recoloured through modulate
## only: 0 PixelLab gen. The rows live in balance.json gem_combos.recipes[*].fx: {event: [{"fx": id, "tint": "#hex"}]}
## ("#ffffff" = no recolour).
## PerfSaver: decorative extras (PerfSaver.DECORATIVE: the burning / frozen overlays, the crit glare, the pickup
## burst) are shed while the saver is on, or replaced by their fallback (crit_hit → hit_spark); everything else, the
## fire trail's streak (it shows where the fire burns) and the blasts, always plays.

## Effects that point along a line (their art points east): turned to `dir` when one is given.
const DIRECTIONAL := ["piercing_trail"]
static var _tints := {}          # "#hex" → Color, parsed once

## Spawns recipe `combo_id`'s effects for `event` as children of `parent` at `at` (parent-local) and plays them.
## dir: the line's direction for DIRECTIONAL effects (ZERO = no turn). decor = false skips the decorative extras
## (a trail lays flames on every other mark only). Returns the FxSprites spawned ([] for no parent, no combo, no
## entry, or all shed). One-shot effects free themselves; looping ones live as long as their parent.
static func play(parent: Node, combo_id: String, event: String, at: Vector2, dir := Vector2.ZERO, decor := true) -> Array:
	var out: Array = []
	if parent == null or combo_id == "": return out
	var fx = GemCombo.recipe(combo_id).get("fx", {})
	if typeof(fx) != TYPE_DICTIONARY: return out
	var rows = fx.get(event, [])
	if typeof(rows) != TYPE_ARRAY: return out
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY: continue
		var id := String(row.get("fx", ""))
		if PerfSaver.decorative(id):
			if not decor: continue
			if PerfSaver.active: id = PerfSaver.fallback(id)
		if id == "" or not FxSprite._manifest().has(id): continue
		var s := FxSprite.make(id)
		s.modulate = tint(String(row.get("tint", "#ffffff")))
		s.position = at
		if dir != Vector2.ZERO and id in DIRECTIONAL: s.rotation = dir.angle()
		parent.add_child(s)
		s.play(id)
		out.append(s)
	return out

static func tint(hex: String) -> Color:
	if not _tints.has(hex): _tints[hex] = Color.html(hex) if Color.html_is_valid(hex) else Color.WHITE
	return _tints[hex]
