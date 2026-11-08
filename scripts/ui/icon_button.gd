class_name IconButton
extends Button
## An icon-only HUD button (M4d Task 3d): a 48x48 pixel-art picture (assets/ui/icons/) that is its own
## button face. The picture is drawn at a whole number of screen pixels per art pixel with the nearest
## filter, so it never blurs: on a screen that shows the HUD at `screen_scale` screen px per HUD px, the
## art scale is the smallest whole number k with 48 * k / screen_scale >= MIN_TOUCH HUD px, and the button
## is exactly that big (so it is always at least a 44 px touch target).

const ART := 48                 # the icons' pixel size
const MIN_TOUCH := 44.0         # HUD px (≈ 44 pt; docs/design/design-research.md §4)
const PRESSED_TINT := Color(0.78, 0.78, 0.78)

var art: Texture2D
var art_scale := 1              # screen px per art pixel (whole number)
var side := float(ART)          # button size in HUD px

static func make(path: String, node_name: String) -> IconButton:
	var b := IconButton.new()
	b.name = node_name
	b.art = load(path)
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	b.fit(1.0)
	return b

## The smallest whole art scale that still makes a MIN_TOUCH button at this screen scale.
static func art_scale_for(screen_scale: float) -> int:
	return maxi(1, ceili(MIN_TOUCH * screen_scale / ART - 0.0001))

## Resize for a screen showing the HUD at screen_scale screen px per HUD px.
func fit(screen_scale: float) -> void:
	screen_scale = maxf(screen_scale, 0.01)
	art_scale = art_scale_for(screen_scale)
	side = ART * art_scale / screen_scale
	custom_minimum_size = Vector2(side, side)
	size = custom_minimum_size
	queue_redraw()

func _draw() -> void:
	if art == null: return
	var down := get_draw_mode() in [DRAW_PRESSED, DRAW_HOVER_PRESSED]
	draw_texture_rect(art, Rect2((size - Vector2(side, side)) / 2.0, Vector2(side, side)), false,
		PRESSED_TINT if down else Color.WHITE)
