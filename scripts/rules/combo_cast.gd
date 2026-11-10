class_name ComboCast
extends RefCounted
## The per-press ledger of a gem combo (M5b, docs/superpowers/specs/2026-11-08-gem-combos.md). Pure rules, no scene
## access (risks.md §3). The hero makes ONE per skill press; every hit of that press (primary arrows, blasts, bolts,
## trail and burn ticks it applied, area ticks) reports through the same instance, so the caps hold per press:
## - MP on kill: bloodthirst +2 / kill, at most 6 per press; rahu +3 / kill, at most 9 (owner 2026-11-08).
##   Burn / fire-trail kills count too (owner 2026-11-09 "นับทุกแบบ"), through the press that applied them: every
##   monster status keeps the ComboCast of the press that applied it (StatusEffects.*_cast, M5b Task 4).
##   Every damage source reports through ONE hook (Hero.combo_hit, Task 8): a kill (alive before, dead after) is
##   credited once (claim_kill) to the ledger of the press that dealt it.
## - once(tag, target): once-per-target-per-press effects (shatter, freeze, ...).
## - count_hit(target): hits of this press on one target (frost: freeze on the 3rd).
## - dmg_bonus(): rahu +30 % when HP ≥ 70 % at the press.
## The numbers are copied once, at the press: from the build's combo_p (from_build, the one source the press's hits
## also read), or from balance.json when made from an id. Hits never look them up.
## Client-side only (risks.md S1): online play needs a server to own this ledger.

var id: String
var kill_mp := 0
var kill_mp_cap := 0
var kill_heal_frac := 0.0
var crit_heal_frac := 0.0
var _hp_bonus := 0.0
var _mp_given := 0
var _hits := {}       # target_key → hits this press
var _once := {}       # tag → {target_key: true}   (no string built per call, Task 3 review M3)

## combo_id: the press's combo (build.combo.id, "" for none). hp_frac: the hero's HP / max HP at the press.
## numbers: the recipe's numbers (a build's combo_p); null = read GemCombo.numbers(combo_id).
func _init(combo_id := "", hp_frac := 1.0, numbers = null) -> void:
	id = combo_id
	if id == "": return
	var cp: Dictionary = numbers if typeof(numbers) == TYPE_DICTIONARY else GemCombo.numbers(id)
	kill_mp = int(cp.get("kill_mp", 0.0))
	kill_mp_cap = int(cp.get("kill_mp_cap", 0.0))
	kill_heal_frac = float(cp.get("kill_heal_frac", 0.0))
	crit_heal_frac = float(cp.get("crit_heal_frac", 0.0))
	if cp.has("hp_min") and hp_frac >= float(cp.hp_min): _hp_bonus = float(cp.get("hp_bonus", 0.0))

## The ledger of one press of build `b` (SkillBuild.of): its combo id and its combo_p numbers, so the ledger and the
## press's hits read the same copy (Task 3 review M5). A build without a combo (or junk) gives an empty ledger.
static func from_build(b: Dictionary, hp_frac := 1.0) -> ComboCast:
	var combo = b.get("combo", {})
	var cid := String(combo.get("id", "")) if typeof(combo) == TYPE_DICTIONARY else ""
	var cp = b.get("combo_p", {})
	return ComboCast.new(cid, hp_frac, cp if typeof(cp) == TYPE_DICTIONARY else {})

## Rahu's damage bonus for this press: hp_bonus if the hero had ≥ hp_min HP at the press, else 0.
func dmg_bonus() -> float:
	return _hp_bonus

## MP granted for one kill at this press's own kill_mp, after the cap (0 when the combo has no MP on kill).
## The caller still clamps to max MP.
func refund_kill() -> int:
	return refund_mp(kill_mp)

## MP granted for one kill of `per_kill` MP after this press's cap (kept for callers that pass the amount;
## shares the cap with refund_kill). The caller still clamps to max MP.
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

## M5b Task 8: true the first time this press credits the kill of `target_key` (once("kill", …)), false after. The kill
## hook (Hero.combo_hit) already credits only a hit that kills (alive before, dead after); this is the second guard, so
## two sources of one press landing on the same death can never pay twice. A press's ledger lives ≤ ~3.9 s (its last
## trail / burn), far less than any respawn (wolf.respawn 9 s; a re-roll clears statuses), so a revived monster is
## never refused by a key left from its earlier death.
func claim_kill(target_key: int) -> bool:
	return once("kill", target_key)

## True the first time (tag, target) is seen in this press, false after.
func once(tag: String, target_key: int) -> bool:
	var seen = _once.get(tag)
	if seen == null:
		seen = {}
		_once[tag] = seen
	elif seen.has(target_key):
		return false
	seen[target_key] = true
	return true
