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

## M4d addendum 3: what "เต็มจอ" shows on iPhone web, where Safari has no full-screen call.
const IOS_TIP := "กดแชร์ → เพิ่มไปยังหน้าจอโฮม"
## Tests force the iPhone check: -1 = detect, 0 = not iPhone web, 1 = iPhone web.
static var ios_override := -1
## Tests force the home-screen check: -1 = detect, 0 = in Safari, 1 = opened from the home screen.
static var standalone_override := -1

## Running in a browser on iPhone / iPod (owner 2026-11-08: "iPad กดแล้วเต็มจอจริง คำแนะนำเฉพาะ iPhone").
## iPad (also iPadOS Safari, which says "Macintosh") gets real full screen, so it does not count.
static func is_ios_web() -> bool:
	if ios_override >= 0: return ios_override == 1
	if not OS.has_feature("web"): return false
	var ua = JavaScriptBridge.eval("navigator.userAgent + '|' + (navigator.maxTouchPoints || 0)", true)
	return ua is String and ios_user_agent(ua)

## The user-agent rule on its own (unit-tested): iPhone / iPod only ("ua|maxTouchPoints"; the touch count
## is kept in the format but no longer matters, iPad and iPadOS "Macintosh" are not iPhone).
static func ios_user_agent(ua_and_touch: String) -> bool:
	var ua := ua_and_touch.split("|")[0]
	return ua.contains("iPhone") or ua.contains("iPod")

## Opened from the home screen (navigator.standalone, or display-mode standalone); false off the web.
static func is_standalone_web() -> bool:
	if standalone_override >= 0: return standalone_override == 1
	if not OS.has_feature("web"): return false
	var v = JavaScriptBridge.eval("!!(navigator.standalone || (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches))", true)
	return v == true

## What "เต็มจอ" does (unit-tested): "tip" on iPhone web in Safari, "none" on iPhone already opened from the
## home screen (it is full screen already; Safari has no full-screen call), "toggle" everywhere else.
static func fullscreen_action(iphone_web: bool, standalone: bool) -> String:
	if not iphone_web: return "toggle"
	return "none" if standalone else "tip"

## Full screen on/off (on the web it must come from a tap; iPhone Safari does not allow it: the HUD shows
## IOS_TIP there instead, Hud.press_fullscreen / fullscreen_action).
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
