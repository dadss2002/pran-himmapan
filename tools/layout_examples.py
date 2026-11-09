#!/usr/bin/env python3
"""M4d: picture of example random room layouts (RoomLayout), from tools/layout_examples.gd's JSON.

Each layout: the 7x7 grid, every room's picture shrunk onto its cell, gold bars for links (warps),
red stubs for dead-end exits, c1r1 outlined white, e0 outlined red; title shows seed, loops, dead ends.

Usage:
  godot --headless --script tools/layout_examples.gd -- /tmp/layouts.json 200 3,17,42
  python3 tools/layout_examples.py /tmp/layouts.json docs/preview/m4b/layout_examples.png
"""
import json
import sys

from PIL import Image, ImageDraw

ROOT = "."
CELL = 96          # px per grid cell on the sheet
GAP = 12           # space between rooms (where link bars are drawn)
GRID = 7
DIRS = {"north": (0, -1), "south": (0, 1), "east": (1, 0), "west": (-1, 0)}


def draw_layout(ex: dict, names: dict) -> Image.Image:
    step = CELL + GAP
    head = 34
    im = Image.new("RGB", (GRID * step + GAP, GRID * step + GAP + head), (18, 22, 20))
    d = ImageDraw.Draw(im)
    d.text((GAP, 8), "seed %d   loops %d   dead ends %d%s" % (ex["seed"], ex["loops"], len(ex["dead_ends"]),
                                                             "   FALLBACK" if ex["fallback"] else ""), fill=(255, 240, 200))

    def box(c):
        x = GAP + c[0] * step
        y = head + GAP + c[1] * step
        return x, y

    for gx in range(GRID):
        for gy in range(GRID):
            x, y = box((gx, gy))
            d.rectangle((x, y, x + CELL - 1, y + CELL - 1), outline=(40, 48, 44))
    for rid, c in ex["pos"].items():
        x, y = box(c)
        pic = Image.open(f"{ROOT}/assets/map/painted/raw/{rid}.png").convert("RGB").resize((CELL, CELL), Image.BILINEAR)
        im.paste(pic, (x, y))
        col = (255, 255, 255) if rid == "c1r1" else (255, 70, 60) if rid == "e0" else (70, 80, 70)
        d.rectangle((x - 1, y - 1, x + CELL, y + CELL), outline=col, width=3 if col != (70, 80, 70) else 1)
        d.rectangle((x + 2, y + 2, x + 30, y + 13), fill=(0, 0, 0))
        d.text((x + 4, y + 2), rid, fill=(255, 255, 255))
    for a, sa, b, sb in ex["links"]:
        ax, ay = box(ex["pos"][a])
        dx, dy = DIRS[sa]
        cx, cy = ax + CELL // 2, ay + CELL // 2
        if dx:   # east: bar across the gap at mid height
            x0 = ax + CELL - 10
            d.rectangle((x0, cy - 4, x0 + GAP + 20, cy + 4), fill=(255, 205, 60), outline=(60, 40, 0))
        else:    # south
            y0 = ay + CELL - 10
            d.rectangle((cx - 4, y0, cx + 4, y0 + GAP + 20), fill=(255, 205, 60), outline=(60, 40, 0))
    for rid, s in ex["dead_ends"]:
        x, y = box(ex["pos"][rid])
        dx, dy = DIRS[s]
        cx, cy = x + CELL // 2 + dx * (CELL // 2), y + CELL // 2 + dy * (CELL // 2)
        d.rectangle((cx - 5, cy - 5, cx + 5, cy + 5), fill=(220, 40, 40), outline=(0, 0, 0))
    return im


def main():
    src = json.load(open(sys.argv[1]))
    out = sys.argv[2]
    names = {}
    tiles = [draw_layout(ex, names) for ex in src["examples"]]
    st = src["stats"]
    foot = 40
    sheet = Image.new("RGB", (sum(t.width for t in tiles) + 8 * (len(tiles) - 1), tiles[0].height + foot), (8, 10, 9))
    x = 0
    for t in tiles:
        sheet.paste(t, (x, 0))
        x += t.width + 8
    d = ImageDraw.Draw(sheet)
    fmt = lambda h: ", ".join("%s:%d" % (k, h[k]) for k in sorted(h, key=int))
    d.text((12, tiles[0].height + 4), "%d seeds, fallback %d | loops %s | dead-end exits %s" % (
        st["seeds"], st["fallback"], fmt(st["loops"]), fmt(st["dead_ends"])), fill=(220, 220, 220))
    d.text((12, tiles[0].height + 20), "e0 rooms walked from c1r1: %s   (gold bar = warp pair, red square = dead end)" % fmt(st["boss_steps"]),
           fill=(220, 220, 220))
    sheet.save(out)


if __name__ == "__main__":
    main()
