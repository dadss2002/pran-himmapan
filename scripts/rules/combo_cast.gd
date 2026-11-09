class_name ComboCast
extends RefCounted
## The per-press ledger of a gem combo (M5b, docs/superpowers/specs/2026-11-08-gem-combos.md). Pure rules, no scene
## access (risks.md §3). The hero makes ONE per skill press; every hit of that press (primary arrows, blasts, bolts,
## trail and burn ticks it applied, area ticks) reports through the same instance, so the caps hold per press:
## - MP on kill: bloodthirst +2 / kill, at most 6 per press; rahu +3 / kill, at most 9 (owner 2026-11-08).
##   Burn / fire-trail kills count too (owner 2026-11-09 "นับทุกแบบ"), through the press that applied them.
## - once(tag, target): once-per-target-per-press effects (shatter, freeze, ...).
## - count_hit(target): hits of this press on one target (frost: freeze on the 3rd).
## - dmg_bonus(): rahu +30 % when HP ≥ 70 % at the press.
## The numbers are copied from balance.json once, here: hits never look them up.
## Client-side only (risks.md S1): online play needs a server to own this ledger.

var id: String
var kill_mp := 0
var kill_mp_cap := 0
var kill_heal_frac := 0.0
var crit_heal_frac := 0.0
var _hp_bonus := 0.0
var _mp_given := 0
var _hits := {}       # target_key → hits this press
var _once := {}       # "tag:target_key" → true

## combo_id: the press's combo (build.combo.id, "" for none). hp_frac: the hero's HP / max HP at the press.
func _init(combo_id := "", hp_frac := 1.0) -> void:
	id = combo_id
	if id == "": return
	kill_mp = int(GemCombo.p(id, "kill_mp"))
	kill_mp_cap = int(GemCombo.p(id, "kill_mp_cap"))
	kill_heal_frac = GemCombo.p(id, "kill_heal_frac")
	crit_heal_frac = GemCombo.p(id, "crit_heal_frac")
	if hp_frac >= GemCombo.p(id, "hp_min", INF): _hp_bonus = GemCombo.p(id, "hp_bonus")

## Rahu's damage bonus for this press: hp_bonus if the hero had ≥ hp_min HP at the press, else 0.
func dmg_bonus() -> float:
	return _hp_bonus

## MP granted for one kill of `per_kill` MP after this press's cap (0 when the combo has no MP on kill).
## The caller still clamps to max MP.
func refund_mp(per_kill: int) -> int:
	if per_kill <= 0 or kill_mp_cap <= 0: return 0
	var grant := mini(per_kill, kill_mp_cap - _mp_given)
	if grant <= 0: return 0
	_mp_given += grant
	return grant

## MP this press has refunded so far.
func mp_refunded() -> int:
	return _mp_given

## Counts one hit of this press on a target; returns the new count (1 on the first hit).
func count_hit(target_key: int) -> int:
	var n := int(_hits.get(target_key, 0)) + 1
	_hits[target_key] = n
	return n

## True the first time (tag, target) is seen in this press, false after.
func once(tag: String, target_key: int) -> bool:
	var k := "%s:%d" % [tag, target_key]
	if _once.has(k): return false
	_once[k] = true
	return true
