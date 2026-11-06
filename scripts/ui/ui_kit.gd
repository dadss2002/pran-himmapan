class_name UiKit
## Small shared builders for the pause-screen panels (skill screen, enhance window).

static func label(t: String, font_size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", c)
	return l

static func icon(path: String, px: int) -> TextureRect:
	var t := TextureRect.new()
	if path != "": t.texture = load(path)
	t.custom_minimum_size = Vector2(px, px)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

static func box(bg: Color, border: Color, radius: int, margin: int, width := 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width if border.a > 0 else 0)
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin; s.content_margin_right = margin
	s.content_margin_top = margin * 0.6; s.content_margin_bottom = margin * 0.6
	return s

## A button styled as a slot/cell, with an icon child named "Icon".
static func cell(px: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(px, px)
	b.focus_mode = Control.FOCUS_NONE
	var ic := icon("", px - 8)
	ic.name = "Icon"
	ic.position = Vector2(4, 4)
	ic.size = Vector2(px - 8, px - 8)
	b.add_child(ic)
	return b

static func style_cell(b: Button, border: Color, filled: bool, selected: bool) -> void:
	var sb := box(Color(0, 0, 0, 0.35 if filled else 0.15), Color("#fde39a") if selected else border, 7, 2, 2)
	for k in ["normal", "hover", "pressed", "disabled"]: b.add_theme_stylebox_override(k, sb)

static func style_action(b: Button, ok: bool) -> void:
	var gold := Color("#edbb55")
	b.disabled = not ok
	b.add_theme_color_override("font_color", Color("#1a2a12") if ok else Color("#a59c86"))
	b.add_theme_color_override("font_disabled_color", Color("#a59c86"))
	b.add_theme_stylebox_override("normal", box(gold if ok else Color(1, 1, 1, 0.06), gold if ok else Color("#6b6450"), 8, 4))
	b.add_theme_stylebox_override("disabled", box(Color(1, 1, 1, 0.06), Color("#6b6450"), 8, 4))
