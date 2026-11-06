class_name Warp
extends Node2D
## A warp circle on the ground. step() reports, once, when the hero's feet come within RoomSet.WARP_RADIUS;
## after that it stays quiet until the hero has moved further than RoomSet.REARM away (so arriving
## next to a warp never sends you straight back).

var warp_id := ""
var to_room := ""
var to_warp := ""
var armed := true
var ring: FxSprite

static func make(w: Dictionary) -> Warp:
	var n := Warp.new()
	n.warp_id = String(w.id)
	n.to_room = String(w.to)
	n.to_warp = String(w.to_warp)
	n.position = Vector2(w.at[0], w.at[1])
	n.name = "Warp_" + n.warp_id
	n.z_index = -9
	if FxSprite._manifest().has("warp_ring"):
		n.ring = FxSprite.make("warp_ring", true)
		n.add_child(n.ring)
		n.ring.play("warp_ring")
	return n

func step(hero_pos: Vector2) -> bool:
	var d := hero_pos.distance_to(position)
	if not armed:
		if d > RoomSet.REARM: armed = true
		return false
	if d <= RoomSet.WARP_RADIUS:
		armed = false
		return true
	return false
