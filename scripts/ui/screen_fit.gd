class_name ScreenFit
extends Node
## Fit to the full screen, portrait and landscape (owner 2026-11-07: "ซูมเต็มจอ", "ปรับให้พอดีเต็มจอ
## ทั้งแนวตั้งและแนวนอน"): the UI view is 360 game pixels wide in portrait (640x360 in landscape), and
## the camera zooms in until the room covers the whole screen, no empty bands (camera_zoom). The HUD
## and touch controls sit over the game. toggle_fullscreen() hides the browser bars where allowed.

const LANDSCAPE := Vector2i(640, 360)
const PORTRAIT := Vector2i(360, 640)

static func base_for(window: Vector2i) -> Vector2i:
	return PORTRAIT if window.y > window.x else LANDSCAPE

static func is_portrait(view: Vector2) -> bool:
	return view.y > view.x

## Camera zoom so the room covers the whole view (like "cover"): never below 1.
static func camera_zoom(view: Vector2, room: Vector2) -> float:
	if room.x <= 0.0 or room.y <= 0.0: return 1.0
	return maxf(1.0, maxf(view.x / room.x, view.y / room.y))

## Full screen on/off (on the web it must come from a tap; iPhone Safari does not allow it).
static func toggle_fullscreen() -> void:
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _ready() -> void:
	var w := get_window()
	w.size_changed.connect(_fit)
	_fit()

func _fit() -> void:
	var w := get_window()
	var want := base_for(w.size)
	if w.content_scale_size != want:
		w.content_scale_size = want
