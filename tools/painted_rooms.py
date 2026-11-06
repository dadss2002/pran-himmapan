#!/usr/bin/env python3
"""Builds the forest rooms (M3c) from the raw painted chunks.

Inputs
  assets/map/painted/raw/c{col}r{row}.png   one 688x384 PixelLab scene per room (seamless on its own)
  data/rooms_src.json                       hand data: start room, links (room/side pairs), spawns,
                                            optional warp hints, walk edits, fx, monsters
Outputs
  data/rooms.json                           what the game reads (see RoomSet)
  assets/map/painted/rooms/overlay_<id>.png leaves hanging over walkable ground, drawn above characters
  docs/preview/m3c_rooms_debug.png          every room at half size: blocked tinted red, warps blue, spawn white

Walkable is guessed from colour (small palette): yellow-greens = grass, light low-saturation greys and
browns = stone/dirt; blue-greens, teal, purples (canopy, water, trunks, cliffs) block. The 8 px grid is
then smoothed so edges are not jagged: closing (fills 1-cell blocked notches), opening (drops 1-cell walk
spurs), then blocked islands under 10 cells become walkable and walkable islands under 8 cells block.
Warps go on the walkable cell (with room for a hero-sized body) nearest to the middle of their side's edge,
or to the src "hint" point.

Usage: python3 tools/painted_rooms.py
"""
import colorsys
import json

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = "."
CELL = 8
SIZE = (688, 384)
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


def walk_grid(rgb: np.ndarray, edits: list) -> np.ndarray:
    walk_px, _ = classify(rgb)
    h, w = rgb.shape[:2]
    ch, cw = h // CELL, w // CELL
    walk = walk_px[:ch * CELL, :cw * CELL].reshape(ch, CELL, cw, CELL).mean(axis=(1, 3)) >= 0.55
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
    links = {}   # (room, side) -> (room, side)
    for a, b in src["links"]:
        ra, sa = a.split(":")
        rb, sb = b.split(":")
        links[(ra, sa)] = (rb, sb)
        links[(rb, sb)] = (ra, sa)
    debug = []
    for rid, rs in src["rooms"].items():
        rgb = np.asarray(Image.open(f"{ROOT}/assets/map/painted/raw/{rid}.png").convert("RGB"))
        walk = walk_grid(rgb, rs.get("edits", []))
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
        warps = []
        for (r, side), (to, to_side) in sorted(links.items()):
            if r != rid: continue
            fx, fy = SIDES[side]
            hint = rs.get("hints", {}).get(side, [fx * SIZE[0], fy * SIZE[1]])
            warps.append({"id": side, "at": nearest_roomy(roomy, hint), "to": to, "to_warp": to_side})
        spawn = nearest_roomy(roomy, rs["spawn"]) if "spawn" in rs else None
        over = overlay(rgb, walk)
        ov_file = None
        if over.any():
            ov_file = f"res://assets/map/painted/rooms/overlay_{rid}.png"
            Image.fromarray(np.dstack([rgb, (over * 255).astype(np.uint8)]), "RGBA").save(
                f"{ROOT}/assets/map/painted/rooms/overlay_{rid}.png")
        room = {"image": f"res://assets/map/painted/raw/{rid}.png", "overlay": ov_file,
                "blocked": ["".join("." if v else "#" for v in row) for row in walk],
                "warps": warps, "fx": rs.get("fx", []), "monsters": rs.get("monsters", [])}
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
            d.text((x - 18, y - 24), f"{wp['id']}>{wp['to']}", fill=(255, 255, 255, 255))
        if spawn:
            d.ellipse((spawn[0] - 5, spawn[1] - 5, spawn[0] + 5, spawn[1] + 5), fill=(255, 255, 255, 255))
        d.text((6, 6), rid, fill=(255, 255, 255, 255))
        debug.append((rid, im))
    out = {"start": src["start"], "size": list(SIZE), "cell": CELL, "rooms": rooms}
    with open(f"{ROOT}/data/rooms.json", "w") as f:
        json.dump(out, f, ensure_ascii=False, indent=0)
    order = sorted(debug, key=lambda t: (int(t[0][3]), int(t[0][1])))
    gc = max(int(r[1]) for r, _ in order) + 1
    gr = max(int(r[3]) for r, _ in order) + 1
    sheet = Image.new("RGBA", (gc * SIZE[0] // 2, gr * SIZE[1] // 2), (0, 0, 0, 255))
    for rid, im in order:
        sheet.paste(im.resize((SIZE[0] // 2, SIZE[1] // 2), Image.NEAREST), (int(rid[1]) * SIZE[0] // 2, int(rid[3]) * SIZE[1] // 2))
    sheet.save(f"{ROOT}/docs/preview/m3c_rooms_debug.png")
    print("rooms %d, links %d" % (len(rooms), len(src["links"])))


if __name__ == "__main__":
    main()
