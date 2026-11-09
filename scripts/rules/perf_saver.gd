class_name PerfSaver
extends RefCounted
## M3k (owner: "เพิ่มปิดเอฟเฟกต์เมื่อ fps ร่วงต่ำกว่า 60"): watches the frame rate and turns the
## saver on when it stays under LOW for ENTER_AFTER seconds, and off again once it stays at or
## above HIGH for LEAVE_AFTER seconds. The saver only hides decoration (pond ripples, dust, pickup puffs and the
## PixelFX extras in DECORATIVE); hits, level-up, skill effects and telegraphs stay, and no game number changes.

const LOW := 57.0          # a 60 Hz screen reports 59-60; under 57 the player can feel it
const HIGH := 59.0
const ENTER_AFTER := 3.0   # seconds - a room switch spike must not trip it
const LEAVE_AFTER := 10.0

var on := false
var _t := 0.0

## Feed one frame. Returns true when `on` changed on this frame.
func step(delta: float, fps: float) -> bool:
	var want_change := (fps < LOW) if not on else (fps >= HIGH)
	if not want_change:
		_t = 0.0
		return false
	_t += delta
	if _t < (ENTER_AFTER if not on else LEAVE_AFTER): return false
	on = not on
	_t = 0.0
	return true

## Decorative effects skipped while the saver is on. Task 3f review: also the PixelFX extras: the burning /
## frozen overlays (the monster's tint stays, so the status is still readable), the crit glare (a hit spark plays
## instead, fallback) and the warp sparkle. Never a gameplay telegraph (lunge_warning, the poison cloud's mist:
## the cloud is a hazard) or the plain hit spark.
const DECORATIVE := ["roll_dust", "pickup_pop", "status_burn", "status_frost", "crit_hit", "warp_blink"]
const FALLBACK := {"crit_hit": "hit_spark"}

## true while a test ground's saver is on (Wolf reads it for its status overlays); the test ground sets it in
## apply_saver and clears it when it leaves the tree.
static var active := false

static func decorative(fx_name: String) -> bool:
	return fx_name in DECORATIVE

## What plays instead of a shed effect ("" = nothing).
static func fallback(fx_name: String) -> String:
	return FALLBACK.get(fx_name, "")

