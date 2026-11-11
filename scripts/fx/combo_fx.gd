class_name ComboFx
## M5b gem combos (spec docs/superpowers/specs/2026-11-08-gem-combos.md "เอฟเฟกต์ที่ใช้ซ้ำ", plan Task 5): plays a
## recipe's effect for one event by REUSING manifest effects (assets/fx/manifest.json), recoloured through modulate
## only: 0 PixelLab gen. The rows live in balance.json gem_combos.recipes[*].fx: {event: [{"fx": id, "tint": "#hex"}]}
## ("#ffffff" = no recolour).
## PerfSaver: decorative extras (PerfSaver.DECORATIVE: the burning / frozen overlays, the crit glare, the pickup
## burst) are shed while the saver is on, or replaced by their fallback (crit_hit → hit_spark); everything else, the
## fire trail's patches (they show where the fire burns) and the blasts, always plays.
## Owner 2026-11-09: fire_fan / brahmastra use new PixelFX fire instead of a reuse: "trail" → fire_trail_small (T2 campfire, pre-shrunk
## patches, FireTrail starts each at its own frame), brahmastra "line_end" → fire_blast (B2 grenade blast, one-shot).

## Effects that point along a line (their art points east): turned to `dir` when one is given.
const DIRECTIONAL := ["piercing_trail"]
static var _tints := {}          # "#hex" → Color, parsed once
static var _recolors := {}       # Color → ShaderMaterial (recolor), made once per tint
const RECOLOR := preload("res://shaders/recolor.gdshader")

## Spawns recipe `combo_id`'s effects for `event` as children of `parent` at `at` (parent-local) and plays them.
## dir: the line's direction for DIRECTIONAL effects (ZERO = no turn). decor = false skips the decorative extras
## (PerfSaver.DECORATIVE) outright. No game caller passes it today: FireTrail never sheds a patch (owner 2026-11-10),
## and PerfSaver never hides hazards, telegraphs or hit effects (only DECORATIVE extras are shed or swapped for their
## fallback). Returns the FxSprites spawned ([] for no parent, no combo, no
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

## True when recipe `combo_id` has at least one effect row for `event`.
static func has(combo_id: String, event: String) -> bool:
	if combo_id == "": return false
	var fx = GemCombo.recipe(combo_id).get("fx", {})
	if typeof(fx) != TYPE_DICTIONARY: return false
	var rows = fx.get(event, [])
	return typeof(rows) == TYPE_ARRAY and not rows.is_empty()

static func tint(hex: String) -> Color:
	if not _tints.has(hex): _tints[hex] = Color.html(hex) if Color.html_is_valid(hex) else Color.WHITE
	return _tints[hex]

## Owner 2026-11-11 (Task 8 review, "ย้อมสีประกายตีแทน"): the sustain recipes show their hits by recolouring the normal
## hit spark instead of an extra effect. The tint = the recipe's "hit" row whose fx is hit_spark (ศรกระหายเลือด
## #ff4a4a, ศรราหูอมจันทร์ #6a2a8a); WHITE for any other recipe or none (no recolour).
static func spark_tint(combo_id: String) -> Color:
	if combo_id == "": return Color.WHITE
	var fx = GemCombo.recipe(combo_id).get("fx", {})
	if typeof(fx) != TYPE_DICTIONARY: return Color.WHITE
	var rows = fx.get("hit", [])
	if typeof(rows) != TYPE_ARRAY: return Color.WHITE
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY and String(row.get("fx", "")) == "hit_spark": return tint(String(row.get("tint", "#ffffff")))
	return Color.WHITE

## Recolours sprite `s` to `c` by brightness (shaders/recolor.gdshader): the orange hit spark's brightest pixels become
## the tint, darker ones a darker tint, alpha kept. Plain modulate cannot do it (orange × dark purple = dark red).
## WHITE removes the recolour. One shared material per tint.
static func recolor(s: CanvasItem, c: Color) -> void:
	if s == null: return
	if c == Color.WHITE:
		s.material = null
		return
	if not _recolors.has(c):
		var m := ShaderMaterial.new()
		m.shader = RECOLOR
		m.set_shader_parameter("tint", c)
		_recolors[c] = m
	s.material = _recolors[c]
