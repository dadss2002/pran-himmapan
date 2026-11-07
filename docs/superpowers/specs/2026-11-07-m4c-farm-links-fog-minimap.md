# M4c — Farm-run connections, fog and minimap

Status: **approved by the owner 2026-11-07** (asked for: "ให้ Claude ออกแบบจุดเชื่อมต่อตอนวิ่งฟาร์ม และช่วยออกแบบระบบหมอก และมินิแมพให้ด้วย"; exits, waypoints, fog and minimap "ได้ ตาม spec"; monster reset changed, see 1). The ⚙ numbers below are the approved values.

Builds on M4b (16 rooms, one 512×512 picture each, joined by warps).

## 1. Connection points (exits) for farm runs

**What the player sees at an exit**
- The dirt path in the picture runs to the room edge. At its end: a soft glowing ring on the ground and a small arrow pointing out of the room.
- Walking within ⚙ 48 px of the ring shows a label with the next room's name (e.g. "→ ปรางค์ร้าง"). A boss arena's label is red with a skull icon.
- Walking into the ring changes room: ⚙ 0.25 s fade out, new room, ⚙ 0.25 s fade in (the fade exists today). No button press needed.

**Arrival**
- The hero appears ⚙ 40 px inside the matching exit of the next room, facing into the room (as today).
- Monsters stay calm for ⚙ 1.0 s after arrival, so you are never hit during the fade (the `calm` timer exists).

**Farm loop (the run Diablo players repeat)**
- Monsters re-roll **only when you use a waypoint or start the game again** (owner: "สุ่มใหม่เมื่อใช้ Waypoint หรือเข้าเกมใหม่เท่านั้น", the classic Diablo way). Walking between rooms keeps every room as you left it: dead monsters stay dead, living ones stay where they were.
- A re-roll puts every room's packs at new random spots on its open ground, with the same pack count and levels as the room's data.
- Boss arenas follow the same rule: the boss returns after a waypoint trip or a new game. The exit locks while the boss is alive (arena lock, as today).

**Suggested run** (uses the exits already painted): c1r1 start → c2r1 → c2r0 (prang) → e0 boss → back → c2r2 → e2 boss, about 6 rooms. A waypoint brings you back.

## 2. Waypoints (4)

| Waypoint | Room | Why |
|---|---|---|
| ศาลหินเริ่มต้น | c1r1 | start / safe spot |
| บึงในป่า | c0r2 | west side, near w1 and w3 bosses |
| ปรางค์ร้าง | c2r0 | east side, next to e0 boss |
| ทางแยกขอนไม้ | c2r1 | middle-east crossroads, near e2 boss |

- A waypoint is a carved stone with a glowing rune, placed on open ground in its room (a small PixelLab prop, ~10 gen, separate approval).
- Touching it the first time unlocks it ("ปลดล็อกจุดวาป"). Standing on any unlocked waypoint opens the travel list; tapping one travels there (same fade).
- Unlocked waypoints are saved.

## 3. Fog (on the minimap only — the game world is never darkened)

- Each room has a fog grid of ⚙ 16 × 16 cells (one cell = 32 × 32 px of the 512 × 512 room).
- A cell is revealed when the hero comes within ⚙ 96 px of it. Revealed cells stay revealed and are saved per room.
- Rooms never entered are fully fogged and are not shown on the full map at all; their neighbours show only a "?" at the connecting exit.

## 4. Minimap

**Corner minimap (always on)**
- Top-right, ⚙ 96 × 96 px in landscape, ⚙ 80 × 80 px in portrait, below the FPS line, semi-transparent ⚙ 85 % frame.
- Shows the **current room**: the room picture shrunk to fit, with unrevealed cells drawn as dark fog. The room fills the box, so the whole room is always visible.
- Marks: hero = white dot with a facing tick; exits = small arrows on the edge (red for a boss arena); waypoint = blue diamond (grey until unlocked); elite pack = gold dot once seen ⚙.
- It never covers the HUD or touch buttons (checked in both orientations).

**Full map (tap the minimap, or the M key)**
- Full screen, game paused in single-player.
- All visited rooms are laid out on their grid positions (c0–c2 columns, r0–r3 rows, w/e boss rooms at the sides), each as its shrunk picture with its own fog, joined by short path lines between linked exits.
- Current room has a bright outline and the hero dot; waypoints and boss rooms are labelled.
- Tap a room to see its name and level range; tap close (or the minimap again) to return.

## 5. Data and code (after approval)
- `data/rooms_src.json`: per room `name` (Thai), grid position, waypoint position; `tools/painted_rooms.py` copies them into `data/rooms.json`.
- New pure rule scripts with unit tests: `RoomReset` (re-roll on waypoint / new game), `FogGrid` (reveal + save), `Waypoints` (unlock + travel list).
- UI: `MiniMap` (corner) and `WorldMap` (full screen), drawn from the room pictures; tests for layout in both orientations.
- Save: per-room monster state since the last re-roll, fog grids (16 × 16 bits per room = 32 bytes), unlocked waypoints.

## Not in this step
New exits or new rooms; multi-floor caves; monster balance changes.
