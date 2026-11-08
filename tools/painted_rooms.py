#!/usr/bin/env python3
"""Builds the forest rooms (M3c) from the raw painted chunks.

Inputs
  assets/map/painted/raw/<id>.png          one PixelLab scene per room; the room's size is its picture's
                                            (512x512 since M4b, 688x384 before)
  data/rooms_src.json                       hand data: start room, exits (painted path sides) per room,
                                            spawns, optional exit hints, walk edits, fx, monsters
Outputs
  data/rooms.json                           what the game reads (see RoomSet)
  assets/map/painted/rooms/overlay_<id>.png leaves hanging over walkable ground, drawn above characters
  docs/preview/m3c_rooms_debug.png          every room at half size on its grid place: blocked tinted red, exit
                                            points blue, spawn white, monster homes orange

Walkable is guessed from colour (small palette): yellow-greens = grass, light low-saturation greys and
browns = stone/dirt; blue-greens, teal, purples (canopy, water, trunks, cliffs) block. The 8 px grid is
then smoothed so edges are not jagged: closing (fills 1-cell blocked notches), opening (drops 1-cell walk
spurs), then blocked islands under 10 cells become walkable and walkable islands under 8 cells block.
Every exit side (M4d) gets an exit point: the walkable cell (with room for a hero-sized body) nearest to the
middle of that side's edge, or to the src "hint" point. Which exits are joined (and so get a warp) is decided
each game session by RoomLayout (scripts/rules/room_layout.gd); rooms.json holds every exit point.

Usage: python3 tools/painted_rooms.py
"""
import colorsys
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = "."
CELL = 8
# M4c §2 waypoints (Task 5): the stone's footprint, from its base point [x, y] (bottom middle): [x-16, x+16) x
# [y-16, y) is blocked; the hero lands on the open cell nearest [x, y+20] (RoomSet.WAYPOINT_* in the game)
WAYPOINT_HALF_W = 16
WAYPOINT_H = 16
WAYPOINT_LAND = 20
OVERHANG_UP = 48
OVERHANG_SIDE = 12
SIDES = {"north": (0.5, 0.0), "south": (0.5, 1.0), "west": (0.0, 0.5), "east": (1.0, 0.5)}
OPPOSITE = {"north": "south", "south": "north", "east": "west", "west": "east"}


def classify(rgb: np.ndarray):
    """Per-pixel walkable and canopy masks from an HxWx3 uint8 image."""
    flat = rgb.reshape(-1, 3)
    cols, inv = np.unique(flat, axis=0, return_inverse=True)
    walk_c = np.zeros(len(cols), bool)
    canopy_c = np.zeros(len(cols), bool)
    for i, c in enumerate(cols):
        h, s, v = colorsys.rgb_to_hsv(*(c / 255.0))
        h *= 360
        grass = 40 <= h <= 118 and v >= 0.50 and s >= 0.3
        ground = s < 0.30 and v >= 0.38
        dirt = (h <= 45 or h >= 350) and s < 0.5 and v >= 0.45
        walk_c[i] = grass or ground or dirt
        water = 172 <= h <= 192 and v >= 0.45
        canopy_c[i] = 120 <= h <= 215 and s > 0.4 and not water
    shape = rgb.shape[:2]
    return walk_c[inv].reshape(shape), canopy_c[inv].reshape(shape)


def roomy_mask(walk: np.ndarray) -> np.ndarray:
    """Cells where a hero-sized body fits with its feet there (x +-1, three rows up to the feet row)."""
    rows, cols = walk.shape
    pad = np.pad(~walk, 2, constant_values=True)
    out = np.ones_like(walk)
    for dy in (-2, -1, 0):
        for dx in (-1, 0, 1):
            out &= ~pad[2 + dy:2 + dy + rows, 2 + dx:2 + dx + cols]
    return out


def walk_grid(rgb: np.ndarray, edits: list, walk_px=None) -> np.ndarray:
    """Walk cells from the picture's colours, or from an exact mask (rooms composed from props)."""
    exact = walk_px is not None
    if not exact:
        walk_px, _ = classify(rgb)
    h, w = rgb.shape[:2]
    ch, cw = h // CELL, w // CELL
    walk = walk_px[:ch * CELL, :cw * CELL].reshape(ch, CELL, cw, CELL).mean(axis=(1, 3)) >= 0.55
    if not exact:
        walk = ndimage.binary_closing(walk, structure=np.ones((3, 3), bool), border_value=1)
        walk = ndimage.binary_opening(walk, structure=ndimage.generate_binary_structure(2, 1))
    lab, n = ndimage.label(~walk)
    for i, s in enumerate(ndimage.sum(np.ones_like(lab), lab, range(1, n + 1)), 1):
        if s < 10: walk[lab == i] = True
    lab, n = ndimage.label(walk)
    for i, s in enumerate(ndimage.sum(np.ones_like(lab), lab, range(1, n + 1)), 1):
        if s < 8: walk[lab == i] = False
    for e in edits:
        x, y, ew, eh = e["rect"]
        walk[y // CELL:(y + eh + CELL - 1) // CELL, x // CELL:(x + ew + CELL - 1) // CELL] = e["op"] == "walk"
    walk[0, :] = walk[-1, :] = False
    walk[:, 0] = walk[:, -1] = False
    return walk


def nearest_roomy(roomy: np.ndarray, target) -> list:
    ys, xs = np.nonzero(roomy)
    if len(xs) == 0: raise SystemExit("room has no open ground")
    cx, cy = (xs + 0.5) * CELL, (ys + 0.5) * CELL
    i = int(np.argmin((cx - target[0]) ** 2 + (cy - target[1]) ** 2))
    return [int(cx[i]), int(cy[i])]


GROUP_MAX = 6
ARRIVAL = 40          # scripts/map/room_set.gd ARRIVAL
EDGE_CELLS = 3        # homes keep this many cells from blocked ground so the group's ring fits
_BAL = json.load(open(f"{ROOT}/data/balance.json"))


def _mon(kind: str, key: str, default=None):
    if kind == "wolf":
        return _BAL["wolf"].get(key, default)
    return _BAL["monsters"][kind].get(key, _BAL["wolf"].get(key, default))


def attacks_first(kind: str) -> bool:
    return kind == "wolf" or _mon(kind, "temper") in ("aggressive", "ambush")


def aggro_of(kind: str) -> float:
    return float(_mon(kind, "aggro", 160))


def ring(home, count: int) -> list:
    """The points a group's monsters spawn on (PaintedLayout.ring / WolfPack.spawn: radius pack_ring,
    flattened to 0.7 vertically)."""
    r = float(_BAL["wolf"]["pack_ring"])
    return [(home[0] + r * math.cos(math.tau * i / count), home[1] + r * math.sin(math.tau * i / count) * 0.7)
            for i in range(count)]


def ring_fits(roomy: np.ndarray, home, count: int) -> bool:
    """Every spawn point of a group of `count` at `home` stands on open ground (the room's main area)."""
    rows, cols = roomy.shape
    for x, y in ring(home, count):
        cx, cy = int(x) // CELL, int(y) // CELL
        if x < 0 or y < 0 or cx >= cols or cy >= rows or not roomy[cy, cx]: return False
    return True


def ring_clear(home, count: int, arrivals: list, floor: float) -> bool:
    """Every spawn point of the group is at least `floor` px from every arrival (M4d addendum 3)."""
    return all(math.hypot(x - a[0], y - a[1]) >= floor for x, y in ring(home, count) for a in arrivals)


def ring_mask(roomy: np.ndarray, count: int, arrivals=(), floor: float = 0.0) -> np.ndarray:
    """Open cells where a group of `count` can be homed with its whole spawn ring on open ground and, when
    floor > 0, every spawn point at least floor px from every arrival."""
    out = np.zeros_like(roomy)
    for cy, cx in zip(*np.nonzero(roomy)):
        home = ((cx + 0.5) * CELL, (cy + 0.5) * CELL)
        out[cy, cx] = ring_fits(roomy, home, count) and (floor <= 0 or ring_clear(home, count, arrivals, floor))
    return out


def spread_home(roomy: np.ndarray, homes: list, arrivals: list, keep_off: float, hard_off: float,
                count: int = 1, floor: float = 0.0) -> list:
    """The open cell farthest from every other group home (and the arrivals), keep_off from each
    arrival if the room allows, else at least hard_off (the test's minimum), else as far as possible.
    Cells EDGE_CELLS from blocked ground come first; when none of them is hard_off from the arrivals
    (M4d x2: open ground only on a narrow plateau), any open cell that is (keep_off, else hard_off) is used.
    Every candidate, fallbacks included, has the group's whole spawn ring on open ground (M4d addendum 2)
    and, with floor > 0, every spawn point floor px from each arrival (addendum 3)."""
    fit = ring_mask(roomy, count, arrivals, floor)
    if not fit.any(): raise SystemExit("no open ground fits a group of %d" % count)
    inner = ndimage.binary_erosion(roomy, np.ones((2 * EDGE_CELLS + 1, 2 * EDGE_CELLS + 1), bool)) & fit
    if not inner.any(): inner = fit

    def cells(mask):
        ys, xs = np.nonzero(mask)
        cx, cy = (xs + 0.5) * CELL, (ys + 0.5) * CELL
        d_arr = np.full(len(xs), 1e9)
        for a in arrivals:
            d_arr = np.minimum(d_arr, np.hypot(cx - a[0], cy - a[1]))
        d_home = np.full(len(xs), 1e9)
        for h in homes:
            d_home = np.minimum(d_home, np.hypot(cx - h[0], cy - h[1]))
        return cx, cy, d_arr, np.minimum(d_home, d_arr * 0.75)

    for mask in (inner, fit):
        cx, cy, d_arr, score = cells(mask)
        for off in (keep_off, hard_off):
            ok = d_arr >= off
            if ok.any():
                i = int(np.argmax(np.where(ok, score, -1.0)))
                return [int(cx[i]), int(cy[i])]
    cx, cy, d_arr, score = cells(inner)
    i = int(np.argmax(score))
    return [int(cx[i]), int(cy[i])]


NEAR_ARRIVAL_MIN = 48.0   # M4d addendum 2/3: near_arrival_ok rooms keep every spawn point this far from arrivals


def place_monsters(src_monsters: list, roomy: np.ndarray, arrivals: list, near_ok: bool = False):
    """Group homes for one monster list: given "at" points move to the nearest cell whose whole spawn ring
    is on the main open ground; others are split into groups of at most GROUP_MAX and spread over the room
    (farthest from the other homes), out of aggro range of every warp arrival for kinds that attack first
    (M3g). In a near_arrival_ok room every spawn point of every group keeps NEAR_ARRIVAL_MIN px from each
    arrival (M4d addendum 3: measured for the whole spawn ring, not only the home)."""
    floor = NEAR_ARRIVAL_MIN if near_ok else 0.0
    monsters = []
    homes = []
    for m in src_monsters:
        m = dict(m)
        if "at" in m:
            fit = ring_mask(roomy, int(m["count"]), arrivals, floor)
            if not fit.any(): raise SystemExit("no open ground fits a %s group of %d" % (m["kind"], m["count"]))
            want = m["at"]
            m["at"] = nearest_roomy(fit, want)
            if math.hypot(m["at"][0] - want[0], m["at"][1] - want[1]) > 16:
                print("  note: %s home %s moved to %s so its spawn ring fits" % (m["kind"], want, m["at"]))
            homes.append(m["at"])
            monsters.append(m)
            continue
        n = -(-int(m["count"]) // GROUP_MAX)
        sizes = [int(m["count"]) // n + (1 if i < int(m["count"]) % n else 0) for i in range(n)]
        first = attacks_first(m["kind"])
        keep_off = aggro_of(m["kind"]) + 40 if first else 90
        hard_off = aggro_of(m["kind"]) + 12 if first else 60
        for sz in sizes:
            at = spread_home(roomy, homes, arrivals, keep_off, hard_off, sz, floor)
            homes.append(at)
            monsters.append({"kind": m["kind"], "level": m["level"], "count": sz, "at": at})
    return monsters, homes


def overlay(rgb: np.ndarray, walk: np.ndarray):
    _, canopy = classify(rgb)
    h, w = rgb.shape[:2]
    walk_full = np.kron(walk, np.ones((CELL, CELL), bool))[:h, :w]
    near = np.zeros_like(walk_full)
    for dy in range(0, OVERHANG_UP + 1, 2):
        shifted = np.zeros_like(walk_full)
        shifted[:h - dy] = walk_full[dy:]
        near |= shifted
    near = ndimage.binary_dilation(near, structure=np.ones((1, 2 * OVERHANG_SIDE + 1), bool))
    return canopy & near & ~walk_full


def main():
    src = json.load(open(f"{ROOT}/data/rooms_src.json"))
    rooms = {}
    debug = []
    for rid, rs in src["rooms"].items():
        rgb = np.asarray(Image.open(f"{ROOT}/assets/map/painted/raw/{rid}.png").convert("RGB"))
        size = (rgb.shape[1], rgb.shape[0])
        # rooms composed from props (tools/compose_room.py) bring exact walk / over-the-hero masks
        walk_file = Path(f"{ROOT}/assets/map/painted/raw/{rid}_walk.png")
        over_file = Path(f"{ROOT}/assets/map/painted/raw/{rid}_over.png")
        walk_px = np.asarray(Image.open(walk_file).convert("L")) > 127 if walk_file.exists() else None
        edits = list(rs.get("edits", []))
        stone = rs.get("waypoint")
        if stone:   # the stone blocks its footprint (the hero walks around it)
            edits.append({"op": "block", "rect": [stone[0] - WAYPOINT_HALF_W, stone[1] - WAYPOINT_H,
                                                  2 * WAYPOINT_HALF_W, WAYPOINT_H]})
        walk = walk_grid(rgb, edits, walk_px)
        roomy = roomy_mask(walk)
        # warps and spawn only on the main open area (the spawn's, else the largest), never in a pocket
        lab, n = ndimage.label(roomy)
        if "spawn" in rs:
            main = lab[int(rs["spawn"][1]) // CELL, int(rs["spawn"][0]) // CELL]
        else:
            main = 0
        if main == 0:
            main = int(np.bincount(lab.ravel())[1:].argmax()) + 1
        roomy = lab == main
        exits = []   # M4d: a point for every painted exit; the session's layout decides which become warps
        for side in sorted(rs.get("exits", [])):
            fx, fy = SIDES[side]
            hint = rs.get("hints", {}).get(side, [fx * size[0], fy * size[1]])
            exits.append({"id": side, "at": nearest_roomy(roomy, hint)})
        warps = exits
        spawn = nearest_roomy(roomy, rs["spawn"]) if "spawn" in rs else None
        arrivals = []
        for wp in warps:
            ax, ay = wp["at"]
            dx, dy = size[0] / 2 - ax, size[1] / 2 - ay
            ln = max((dx * dx + dy * dy) ** 0.5, 1e-6)
            arrivals.append(nearest_roomy(roomy, [ax + dx / ln * ARRIVAL, ay + dy / ln * ARRIVAL]))
        if "spawn" in rs:
            arrivals.append(nearest_roomy(roomy, rs["spawn"]))   # the hero's start point counts too
        if stone:   # so does the landing next to the waypoint stone (waypoint travel arrives there)
            arrivals.append(nearest_roomy(roomy, [stone[0], stone[1] + WAYPOINT_LAND]))
        near_ok = bool(rs.get("near_arrival_ok"))
        monsters, homes = place_monsters(rs.get("monsters", []), roomy, arrivals, near_ok)
        # e0 (M4b): the arena sets in level order; each set is placed on its own like "monsters"
        sets = [place_monsters(ms, roomy, arrivals, near_ok)[0] for ms in rs.get("monster_sets", [])]
        over = np.asarray(Image.open(over_file).convert("L")) > 127 if over_file.exists() else overlay(rgb, walk)
        if stone:   # the stone's blocked footprint is no leaf overhang (it would draw over the stone's base)
            over = over.copy()
            over[stone[1] - WAYPOINT_H:stone[1], stone[0] - WAYPOINT_HALF_W:stone[0] + WAYPOINT_HALF_W] = False
        ov_file = None
        if over.any():
            ov_file = f"res://assets/map/painted/rooms/overlay_{rid}.png"
            Image.fromarray(np.dstack([rgb, (over * 255).astype(np.uint8)]), "RGBA").save(
                f"{ROOT}/assets/map/painted/rooms/overlay_{rid}.png")
        room = {"image": f"res://assets/map/painted/raw/{rid}.png", "overlay": ov_file, "size": list(size),
                "blocked": ["".join("." if v else "#" for v in row) for row in walk],
                "exits": exits, "fx": rs.get("fx", []), "monsters": monsters}
        if sets: room["monster_sets"] = sets
        if rs.get("name"): room["name"] = rs["name"]       # M4c: exit labels "→ <name>"
        if stone: room["waypoint"] = list(stone)                    # M4c §2: the waypoint stone's base point
        if rs.get("arena"): room["arena"] = True
        # M4d addendum 2/3: groups may sit closer to the arrivals than their aggro (calm 1 s on arrival),
        # but no spawn point nearer than NEAR_ARRIVAL_MIN (place_monsters; tests/test_monsters.gd)
        if rs.get("near_arrival_ok"): room["near_arrival_ok"] = True
        if spawn: room["spawn"] = spawn
        rooms[rid] = room
        # debug tile
        im = Image.fromarray(rgb).convert("RGBA")
        tint = np.zeros((rgb.shape[0], rgb.shape[1], 4), np.uint8)
        tint[~np.kron(walk, np.ones((CELL, CELL), bool))[:rgb.shape[0], :rgb.shape[1]]] = (255, 0, 0, 80)
        tint[over] = (255, 255, 0, 90)
        im.alpha_composite(Image.fromarray(tint, "RGBA"))
        d = ImageDraw.Draw(im)
        for wp in warps:
            x, y = wp["at"]
            d.ellipse((x - 14, y - 9, x + 14, y + 9), outline=(80, 160, 255, 255), width=3)
            d.text((x - 18, y - 24), f"{wp['id']}", fill=(255, 255, 255, 255))
        for m in monsters:
            x, y = m["at"]
            d.ellipse((x - 4, y - 4, x + 4, y + 4), fill=(255, 150, 0, 255))
        if stone:
            d.rectangle((stone[0] - WAYPOINT_HALF_W, stone[1] - WAYPOINT_H, stone[0] + WAYPOINT_HALF_W - 1,
                         stone[1] - 1),
                        outline=(120, 220, 255, 255), width=2)
        if spawn:
            d.ellipse((spawn[0] - 5, spawn[1] - 5, spawn[0] + 5, spawn[1] + 5), fill=(255, 255, 255, 255))
        d.text((6, 6), rid, fill=(255, 255, 255, 255))
        grid = rs.get("grid") or [int(rid[1]), int(rid[3])]   # c?r? rooms; others give their place
        debug.append((tuple(grid), im))
    # top-level size: the start room's (older readers / rooms without their own size fall back to it)
    out = {"start": src["start"], "size": rooms[src["start"]]["size"], "cell": CELL, "rooms": rooms}
    with open(f"{ROOT}/data/rooms.json", "w") as f:
        json.dump(out, f, ensure_ascii=False, indent=0)
    c0 = min(g[0] for g, _ in debug)
    r0 = min(g[1] for g, _ in debug)
    gc = max(g[0] for g, _ in debug) - c0 + 1
    gr = max(g[1] for g, _ in debug) - r0 + 1
    # one slot per grid place, as big as the largest room at half size; smaller rooms sit top-left
    tw = max(im.width for _, im in debug) // 2
    th = max(im.height for _, im in debug) // 2
    sheet = Image.new("RGBA", (gc * tw, gr * th), (0, 0, 0, 255))
    for (gx, gy), im in debug:
        sheet.paste(im.resize((im.width // 2, im.height // 2), Image.NEAREST), ((gx - c0) * tw, (gy - r0) * th))
    sheet.save(f"{ROOT}/docs/preview/m3c_rooms_debug.png")
    print("rooms %d, exits %d" % (len(rooms), sum(len(r["exits"]) for r in rooms.values())))
    # M4d follow-up 3: the monster-pile bank is keyed to this data (room picture, blocked grid, exits, groups)
    print("reminder: if any room's data changed, rebake the monster piles: "
          "godot --headless --script tools/bake_piles.gd (tests/test_monster_piles.gd fails on a stale bank)")


if __name__ == "__main__":
    main()
