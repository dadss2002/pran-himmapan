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
