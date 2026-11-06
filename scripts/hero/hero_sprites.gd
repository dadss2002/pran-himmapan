class_name HeroSprites
## Builds SpriteFrames from assets/hero/manifest.json + the per-direction strips
## (<anim>_<dir>.png, one row of equal cells). Animation names are "<anim>_<dir>".

const LOOPING := ["idle", "walk"]

static func _manifest(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "manifest not found: " + path)
	return JSON.parse_string(f.get_as_text())

static func build(manifest_path: String) -> SpriteFrames:
	var m := _manifest(manifest_path)
	var base := manifest_path.get_base_dir()
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for anim in m["frames"]:
		var cell: Array = m["cell"][anim]
		for d in m["directions"]:
			var name := "%s_%s" % [anim, d]
			var tex: Texture2D = load("%s/%s.png" % [base, name])
			sf.add_animation(name)
			sf.set_animation_speed(name, float(m["fps"][anim]))
			sf.set_animation_loop(name, anim in LOOPING)
			for i in int(m["frames"][anim][d]):
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(i * cell[0], 0, cell[0], cell[1])
				sf.add_frame(name, at)
	return sf

## Pixel inside a cell where the feet are; the sprite is offset by -anchor so feet sit on the node origin.
static func anchor(manifest_path: String, anim: String) -> Vector2:
	var a: Array = _manifest(manifest_path)["anchor"][anim]
	return Vector2(a[0], a[1])
