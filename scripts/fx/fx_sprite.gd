class_name FxSprite
extends AnimatedSprite2D
## A VFX sheet from assets/fx/manifest.json (PixelLab strips, and PixelFX grids: "sheet" = file, default <id>.png,
## "columns" = frames per row, default all in one row), anchored so the effect's origin sits on the node origin.
## One-shot effects free themselves unless `keep` is set.

const MANIFEST := "res://assets/fx/manifest.json"
static var _cache := {}

var keep := false
var _anchor := Vector2.ZERO
var _cell := Vector2.ZERO

static func _manifest() -> Dictionary:
	if _cache.is_empty():
		_cache = JSON.parse_string(FileAccess.open(MANIFEST, FileAccess.READ).get_as_text())
	return _cache

## Review (Task 3f): one SpriteFrames per effect id, made on first use and shared by every sprite of that effect;
## the cache holds it (and through its AtlasTextures the sheet), so a sheet is loaded once, not on every spawn.
static var _frames := {}
static var sheet_loads := 0          # sheets loaded by make_frames (tests: a second spawn loads nothing)

static func make_frames(fx_name: String) -> SpriteFrames:
	if _frames.has(fx_name): return _frames[fx_name]
	var m: Dictionary = _manifest()[fx_name]
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	sf.add_animation(fx_name)
	sf.set_animation_speed(fx_name, float(m.fps))
	sf.set_animation_loop(fx_name, bool(m.loop))
	var tex: Texture2D = load("res://assets/fx/" + String(m.get("sheet", fx_name + ".png")))
	sheet_loads += 1
	var cols := int(m.get("columns", m.frames))
	var cw := int(m.cell[0])
	var ch := int(m.cell[1])
	for i in int(m.frames):
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2((i % cols) * cw, floori(float(i) / cols) * ch, cw, ch)
		sf.add_frame(fx_name, at)
	_frames[fx_name] = sf
	return sf

## Drops the cached frames (tests; a re-exported sheet).
static func clear_cache() -> void:
	_frames.clear()

static func make(fx_name: String, keep_after := false) -> FxSprite:
	var m: Dictionary = _manifest()[fx_name]
	var s := FxSprite.new()
	s.keep = keep_after
	s.sprite_frames = make_frames(fx_name)
	s.centered = false
	s._anchor = Vector2(m.anchor[0], m.anchor[1])
	s._cell = Vector2(m.cell[0], m.cell[1])
	s.offset = -s._anchor
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.animation = fx_name
	s.animation_finished.connect(s._on_done)
	return s

## true for an effect exported from PixelFX (spec docs/superpowers/specs/2026-11-08-pixelfx.md).
static func is_pixelfx(fx_name: String) -> bool:
	return _manifest().get(fx_name, {}).has("pixelfx")

## Mirror left / right round the anchor (a directional hit flies along the blow).
func face(left: bool) -> void:
	flip_h = left
	offset = Vector2(-(_cell.x - _anchor.x) if left else -_anchor.x, -_anchor.y)

func _on_done() -> void:
	if not keep:
		queue_free()

