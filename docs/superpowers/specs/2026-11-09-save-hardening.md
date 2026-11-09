# Save hardening — range checks + signature

Status: **approved by the owner 2026-11-09** (Q1 a, Q2 a, Q3 a, Q4 9,999,999 — see the end).

Owner 2026-11-09: protect the save at a moderate level ("range checks + signature"), after Tasks 7–8 and before Task 9.
Risk register: docs/risks.md S5 (save editable in the browser) and S6 (game files can be read).

## 1. What it protects against (and what it doesn't)
- **Stops:** casual editing of the save file (user://save.json; on the web it lives in the browser's IndexedDB), e.g. typing
  gold 999999, level 50, an item +20, or copying another player's save text with a changed number.
- **Does not stop:** someone who unpacks the game (.pck/.wasm) and finds the signing key, or who edits memory while
  playing. A game that runs only on the player's device cannot fully stop that; only a server can (S1–S4). This work is
  a speed bump for single-player, not protection for trade, co-op or a cash shop.

## 2. Signature
- The save gets a field `sig` = HMAC-SHA256 of the save text (without `sig`), key built into the game (Godot `HMACContext`).
- On load: the signature is checked before anything else.
- Old saves (version 3, no `sig`) — see decision Q2.
- A wrong signature — see decision Q1.

## 3. Range checks (added to the existing ones)
Already checked today (save_game.gd): version, level 1..cap, EXP < next level, bag size and stack, item base/slot/rarity,
option keys, plus 0..max, gem type/level/rarity/options, sockets, waypoint ids, fog dropped.

New:
- Every bag id is a known item (unknown ids today load as a stack of a nameless item).
- Item level ≤ the highest drop level (Lv10, owner: "คงของตกสูงสุด Lv10") — already clamped; now a mismatch fails the check
  instead of being silently clamped (Q3 a).
- Gold ≤ ⚙ 9,999,999 (Q4, approved; `data/balance.json` "save.gold_cap").
- Unlocked waypoints must be rooms the layout has (already) and the start stone is always unlocked (already).
- Skill levels / passive points: none saved yet; the passive tree (after M4) adds its own checks.

## 4. Tests
Signed round trip; one changed character fails; old unsigned save handled per Q2; each new range check (pass and fail);
a save larger than ⚙ 256 KB is refused before parsing (a huge file cannot freeze the phone).

## Decisions for the owner
- **Q1** Wrong signature → (a) treat as a broken save: keep it as save.bad.json and start a new game; (b) load it but mark it
  "แก้ไขแล้ว" (marked saves can never be uploaded when online arrives); (c) load it with a warning toast only.
- **Q2** Old unsigned saves → (a) accept once and sign them (players keep progress); (b) refuse.
- **Q3** A value out of range → (a) refuse the whole save like today's checks; (b) clamp it into range and keep the rest.
- **Q4** Gold cap ⚙ → proposed 9,999,999 (far above anything earnable in M4).

**Owner answers 2026-11-09:**
- Q1 (a) "ไม่รับเซฟนั้น เริ่มเกมใหม่": a wrong signature = broken save → save.bad.json + new game.
- Q2 (a) "รับครั้งเดียวแล้วใส่ลายเซ็นให้": an unsigned version-3 save is checked, accepted once and re-saved signed (version 4).
- Q3 (a) "ไม่รับทั้งเซฟ": any value out of range fails the whole save (→ .bad.json, new game).
- Q4 "9,999,999".
