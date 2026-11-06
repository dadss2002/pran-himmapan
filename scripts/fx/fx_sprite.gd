class_name FxSprite
extends AnimatedSprite2D
## A PixelLab VFX strip from assets/fx/manifest.json, anchored so the effect's origin sits on
## the node origin. One-shot effects free themselves unless `keep` is set.

const MANIFEST := "res://assets/fx/manifest.json"
static var _cache := {}

var keep := false

static func _manifest() -> Dictionary:
	if _cache.is_empty():
		_cache = JSON.parse_string(FileAccess.open(MANIFEST, FileAccess.READ).get_as_text())
	return _cache

static func make(fx_name: String, keep_after := false) -> FxSprite:
	var m: Dictionary = _manifest()[fx_name]
	var s := FxSprite.new()
	s.keep = keep_after
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	sf.add_animation(fx_name)
	sf.set_animation_speed(fx_name, float(m.fps))
	sf.set_animation_loop(fx_name, bool(m.loop))
	var tex: Texture2D = load("res://assets/fx/%s.png" % fx_name)
	for i in int(m.frames):
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(i * m.cell[0], 0, m.cell[0], m.cell[1])
		sf.add_frame(fx_name, at)
	s.sprite_frames = sf
	s.centered = false
	s.offset = -Vector2(m.anchor[0], m.anchor[1])
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.animation = fx_name
	s.animation_finished.connect(s._on_done)
	return s

func _on_done() -> void:
	if not keep:
		queue_free()
