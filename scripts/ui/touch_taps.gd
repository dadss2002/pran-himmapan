class_name TouchTaps
extends RefCounted
## Taps from any finger on a panel's buttons (owner report 2026-11-08: with a thumb on the joystick, tapping a
## waypoint row with another finger did nothing). Godot turns only one finger at a time into the mouse
## (pointing/emulate_mouse_from_touch: the first finger down while no other is the mouse); a Button only
## hears the mouse, so a second finger's tap is lost. A panel feeds every input event to feed():
## - the finger Godot turns into the mouse is left to the GUI (its emulated mouse press, device
##   InputEvent.DEVICE_ID_EMULATION, comes just before its touch press), so a one-finger tap fires once;
## - any other finger that goes down on a button and comes up on the same button presses it (pressed.emit());
## - feed() returns true for a touch of such a finger on a button or inside `area` (the panel): the panel marks
##   it handled so it does not reach the rest of the game.

const EVERYWHERE := Rect2(-1e6, -1e6, 2e6, 2e6)   # `area` of a full-screen pause screen (bag, skills, ตีบวก)

var _emu_next := false     # an emulated mouse press was just seen: the next touch press is that finger
var _emu_index := -1       # the finger the GUI has as the mouse (-1 = none)
var _held := {}            # other finger index -> the BaseButton it went down on

## One input event. `root`: the Control whose BaseButton descendants can be tapped; `area`: the screen rect the
## panel covers (HUD px); `active`: false while the panel is shut or covered (nothing is pressed or consumed,
## but the mouse finger is still tracked). true when the caller should mark the event handled.
func feed(e: InputEvent, root: Control, area: Rect2, active := true) -> bool:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.device == InputEvent.DEVICE_ID_EMULATION and mb.pressed: _emu_next = true
		return false
	if not (e is InputEventScreenTouch): return false
	var st := e as InputEventScreenTouch
	if st.pressed:
		if _emu_next:
			_emu_next = false
			_emu_index = st.index
			return false
		_held.erase(st.index)
		if not active or root == null: return false
		var b := button_at(root, st.position)
		if b: _held[st.index] = b
		return b != null or area.has_point(st.position)
	if st.index == _emu_index:
		_emu_index = -1
		return false
	var held = _held.get(st.index)
	_held.erase(st.index)
	if not active or root == null: return false
	if held != null and is_instance_valid(held) and _tappable(held) and (held as Control).get_global_rect().has_point(st.position):
		(held as BaseButton).pressed.emit()
		return true
	return held != null or area.has_point(st.position)

## Forgets every finger (a panel closing mid-touch).
func reset() -> void:
	_held.clear()

## The top-most tappable BaseButton under `pos` (HUD px) among root's descendants (later in the tree = drawn
## on top); null when none.
static func button_at(root: Control, pos: Vector2) -> BaseButton:
	var found: BaseButton = null
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is CanvasItem and not (n as CanvasItem).visible: continue
		if n is BaseButton and _tappable(n) and (n as Control).get_global_rect().has_point(pos):
			found = n
		var kids := n.get_children()
		for i in range(kids.size() - 1, -1, -1):
			if kids[i] is Control: stack.append(kids[i])
	return found

static func _tappable(b: BaseButton) -> bool:
	return b.is_visible_in_tree() and not b.disabled and b.mouse_filter != Control.MOUSE_FILTER_IGNORE
