# M4d — Random Diablo-style room layout every time the game starts

Status: **approved by the owner 2026-11-08** ("อนุมัติ"). Owner 2026-11-08: "อยากได้ผังแบบ diablo" → "ผังห้องเชื่อมกันหลายทาง มีทางวน ไม่เป็นทางตันเยอะ, พื้นที่เดินกว้าง ทางเดินคดเคี้ยวเหมือน Diablo, สุ่มผังห้องใหม่ทุกครั้งเข้าเกม"; "อยากได้ห้องอีก 3 ห้อง" (all three 4-way crossroads); "ห้องเริ่ม c1r1 อยู่กลางเสมอ, ลาน e0 อยู่ไกลสุดเสมอ"; "อยากให้มีแมพบอสแค่ห้องเดียว ในแมพที่เหลือไว้สุ่ม".

## Rooms and their painted exits
Each picture has paths that reach the middle of some sides. Those sides are the room's **exits**; the layout may only join two rooms where both have an exit facing each other.

| Room | Exits |
|---|---|
| c1r1 start | N E W |
| c0r1, x1, x2, x3 (new 4-way rooms) | N E S W |
| c0r2 | N E S |
| c2r1 | N S W |
| c0r0 | E S |
| c0r3 | N W |
| c1r2 | S W |
| c1r3 | N E |
| c2r0 | E S |
| c2r2 | N E |
| c1r0 | S |
| c2r3 | W |
| e0 arena (only boss room) | W |

## How a layout is made (every time the game starts)
1. Put c1r1 in the middle of a 7 × 7 grid.
2. Grow outward: pick an open exit at random, pick at random an unused room that has the matching exit, and place it only if every side it touches agrees (exit meets exit, wall meets wall). A room that touches two placed rooms makes a **loop**.
3. Prefer rooms with more exits early so loops and branches appear; use every forest room once.
4. Put e0 last, on the open east-facing exit that is farthest (in rooms walked) from c1r1.
5. Any exit left without a neighbour stays a dead end: the path ends at the forest edge and there is no warp there (as approved for c0r0).
6. Check: every room can be reached from c1r1, and at least ⚙ 1 loop exists. If not, try again (up to ⚙ 200 tries, then use the fixed layout from M4b).

## What stays and what changes
- The hero always starts a session in c1r1 (a saved room position is not used, because the map has moved).
- Waypoints, fog and unlocked waypoints stay attached to the **room**, so they survive a new layout; the full-screen map draws rooms at their positions in the current layout.
- The monster re-roll happens at the same moments as before: waypoint travel and starting the game (M4c), so a new layout always comes with new monster positions.
- One boss room only: e0, with the four arena monster sets chosen by hero level (M4b).

## Data and code (after approval)
- `data/rooms_src.json`: per room `exits` (the table above); `tools/painted_rooms.py` writes a warp point for every exit side, links are no longer fixed.
- New pure rule `RoomLayout` (seeded): `generate(seed) -> Dictionary` with grid positions and links; unit tests: start in the middle, e0 farthest, all rooms reachable, exits always match, at least one loop, same seed gives the same layout, a bad seed falls back.
- RoomSet builds its warps from the layout's links; save keeps the seed of the current session only.

## Budget
The 3 new 4-way rooms: 75 gen (logged). No other art.

## Addendum 2026-11-08 — monster levels follow the layout (approved: "อนุมัติ")
Owner: "ตามระยะจากห้องเริ่มในผังนั้น"; x1 "หมาป่า+หมูป่า", x2 "ลิง+กองกอย", x3 "เห็ด+งู"; keep the "no room farther than e0" check ("คงไว้").
- d = rooms walked from c1r1 in the current layout (c1r1 d = 0); D = the largest d of any forest room.
- ⚙ Room level L = 1 when d = 0, otherwise round(1 + (d − 1) × 8 / max(D − 1, 1)) + 1, clamped to 2…10. So the rooms next to the start are Lv2 and the farthest forest room is Lv10.
- Each room keeps its monster kinds and counts; every group in the room uses L, except a group that was 1 level above the room's first group before (e.g. c2r2 macaque) keeps that +1 (cap 10).
- ⚙ x1: wolf 10 + boar 8; x2: macaque 10 + kongkoi 8; x3: shroom 10 + viper 8.
- e0 keeps its level-by-hero set choice (unchanged).

## Addendum 2 (2026-11-08, owner-approved after the Task 3c review)
- x2: spread its groups over the grass around the rise, allowed closer to the entrances than the usual aggro+12 rule (monsters are calm 1 s on arrival) ("กระจายไปลานหญ้ารอบเนิน ยอมให้ใกล้ทางเข้าขึ้น").
- x1: the two wolf groups (and the boars) go to the four corners of the meadow, off the central crossing ("กระจายไปมุมทุ่ง 4 มุม").
- e0 set choice: target = max(hero level, level of the room the hero came from); e0 takes the set whose average level is closest to the target, ties to the higher set ("สูงกว่าเลเวลฮีโร่กับห้องก่อนหน้า เลือกชุดที่ใกล้ค่านั้น"). Re-chosen at each re-roll (waypoint / new game) and when the set has never been chosen this session.
- Every monster spawn point (each group's spawn ring) must be on open ground in every room.

## Addendum 3 (2026-11-08, owner-approved after the Task 3d review)
- e0 monster level = level of the room the hero came from + 1, max Lv11 (an arena-only level). The set (kinds and counts) is still chosen by addendum 2's rule ("มอนใน e0 เลเวล = ห้องก่อนหน้า +1 (สูงสุด Lv11) ใช้ชนิดตามชุดที่เลือก").
- x1 may also place groups closer to the entrances (approved "อนุมัติ"), same ≥ 48 px floor as x2, measured for every spawn point, not only the home.
- iPhone: "เต็มจอ" shows a tip "กดแชร์ → เพิ่มไปยังหน้าจอโฮม" instead of doing nothing.

## Addendum 4 (2026-11-08, owner-approved: monster piles + smaller monsters)
Owner: "แก้เรื่องมอนกระจุกแบบนี้ด้วย สุ่มกองแบบ 2-4 ตัว และลดขนาดมอนเตอร์ทั้งหมดให้หน่อยสัก 15%". Answers: "จำนวนเท่าเดิม แต่แตกเป็นกองเล็กหลายกอง"; "สุ่มใหม่ทุกครั้งที่รีเซ็ต บนพื้นที่เดินได้ กองห่างกันอย่างน้อย 80 px"; "ห่างกันอย่างน้อย 1 ตัว + ตอนไล่ตีดันกันเบา ๆ ไม่ให้ซ้อน"; "ภาพ + จุดชน/ระยะโจมตีตามสัดส่วน".

**Piles**
- Every room keeps its kinds, counts and levels (addenda 1–3). Each group is split into piles of one kind, ⚙ 2–4 monsters each, sizes chosen at random (a group of 1 stays 1; 5 → 2+3; 6 → 2+4, 3+3 or 2+2+2). Bosses are never piled.
- Pile positions are random at every re-roll (new game, waypoint travel; Task 4) from a seed made of the session layout seed and the room id, so the same session shows the same piles. Walking out and back does not move them.
- Each pile's whole spawn ring is on open (walkable) ground; ⚙ pile centres ≥ 80 px apart; every spawn point keeps the existing arrival rules (aggro + 12 from arrivals; x1/x2 ≥ 48 px, addenda 2–3). If no placement passes after a fixed number of tries, the room falls back to the built homes from rooms.json and the game keeps running.
- e0: boss stays at its home; any non-boss group in the set follows the pile rule.

**Spacing inside a pile**
- ⚙ Spawn points in a pile are at least 2 × body width apart centre to centre (a gap of one monster between two monsters).
- While chasing/fighting, monsters push each other apart gently when their centres are closer than ⚙ 1 body width: separation speed ⚙ ≤ 40 px/s, never through walls, never pushing the hero.

**Size ×0.85 (all monsters, bosses included)**
- ⚙ Sprite drawn at 0.85 scale, collision/hurt box at 0.85, and body-centred attack reach at 0.85 (melee bite/hit ranges, lunge hit radius, ring/cloud radii centred on the monster), with HP bar, elite tag and shadow following the smaller body.
- Unchanged: aggro, leash, wander, movement speeds, lunge distance, projectile/throw range, damage and all stat numbers.
- Addendum 3 follow-up (owner 2026-11-08): Lv11 e0 monsters drop rings/necklaces at Lv10 max ("คงของตกสูงสุด Lv10"); the iPhone tip toast stays ⚙ 4 s, other toasts keep 1.5 s ("ข้อความนี้ค้าง 4 วินาที").
- iPad (owner 2026-11-08: "iPad กดแล้วเต็มจอจริง คำแนะนำเฉพาะ iPhone"): only iPhone/iPod web shows the tip; iPad uses real full screen; no tip when already opened from the home screen (standalone).
- Addendum 4 follow-up (owner 2026-11-08, after seeing docs/preview/m4b/piles_sheet.png; c0r1 boar piles 1, 3, 4 still read as one cluster): "มอนกองบ้างกระจายบ้าง" → ⚙ about half of each room's monsters (per kind, rounded) stand in piles of 2–4 and the other half are singles spread over the room; singles keep ⚙ ≥ 60 px from every other single and every pile centre; piles keep ≥ 80 px from each other; all spawn points keep the walkable/arrival rules; random at every re-roll. Bosses unchanged.
- Approved implementer choices (owner): seeing or hitting a pile (or a single) wakes only that pile ("ปลุกแค่กองที่โดน/เห็น"); push-apart runs at all times, idle included ("ดันกันทุกตอน รวมตอนยืนเฉย").
