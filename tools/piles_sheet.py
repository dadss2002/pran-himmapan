#!/usr/bin/env python3
"""M4d addendum 4 follow-up evidence: mark piles and singles on the room shots and build the before/after sheet.

Input: <shots>/piles_after_<room>.png and piles_after.json from tests/screenshots_m4b_piles.gd (raw shots, no
marks), plus the "before" shots already in docs/preview/m4b (kept as they are) and their monster count.
Output (in <out>): piles_after_<room>.png with a numbered red circle round every pile (2+ monsters of one pile)
and a small red dot under every single, and piles_sheet.png (before | after, one row per room).

  python3 tools/piles_sheet.py /tmp/shots docs/preview/m4b
"""
import json
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

RED = (235, 40, 40)
WHITE = (255, 255, 255)
BG = (18, 22, 22)
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"


def font(size):
    try:
        return ImageFont.truetype(FONT, size)
    except OSError:
        return ImageFont.load_default()


def groups_of(monsters):
    """[(members)] per pile, in pack then pile order; a pile of one member is a single."""
    piles = {}
    for m in monsters:
        piles.setdefault((m["pack"], m["pile"]), []).append(m)
    return [piles[k] for k in sorted(piles)]


def mark(img, monsters):
    """Numbered circles on piles, small dots on singles; returns (piles, singles)."""
    d = ImageDraw.Draw(img)
    f = font(13)
    n_piles = 0
    n_single = 0
    for members in groups_of(monsters):
        pts = [(m["pos"][0], m["pos"][1] - 10) for m in members]   # round the bodies, not just the feet
        if len(members) == 1:
            n_single += 1
            x, y = members[0]["pos"]
            y += 5
            d.ellipse((x - 4.5, y - 4.5, x + 4.5, y + 4.5), fill=WHITE)
            d.ellipse((x - 3.5, y - 3.5, x + 3.5, y + 3.5), fill=RED)
            continue
        n_piles += 1
        cx = sum(p[0] for p in pts) / len(pts)
        cy = sum(p[1] for p in pts) / len(pts)
        r = max(math.dist((cx, cy), p) for p in pts) + 18
        d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=RED, width=2)
        bx, by = cx + r * 0.72, cy - r * 0.72
        d.ellipse((bx - 9, by - 9, bx + 9, by + 9), fill=RED)
        d.text((bx, by), str(n_piles), fill=WHITE, font=f, anchor="mm")
    return n_piles, n_single


def main():
    shots = Path(sys.argv[1])
    out = Path(sys.argv[2])
    after = json.loads((shots / "piles_after.json").read_text())
    before_counts = {}
    bj = shots / "piles_before.json"
    if bj.exists():
        b = json.loads(bj.read_text())
        for room in b["rooms"]:
            before_counts[room] = (len(b["monsters"][room]), len({m["pack"] for m in b["monsters"][room]}))
    rooms = after["rooms"]
    cell = 512
    pad = 8
    head = 46
    label = 22
    sheet = Image.new("RGB", (pad * 3 + cell * 2, head + len(rooms) * (label + cell + pad)), BG)
    d = ImageDraw.Draw(sheet)
    d.text((pad, 8), "BEFORE (built homes)", fill=WHITE, font=font(20))
    d.text((pad * 2 + cell, 8), "AFTER (half piles, half singles, x0.85)", fill=WHITE, font=font(20))
    for i, room in enumerate(rooms):
        y = head + i * (label + cell + pad)
        mons = after["monsters"][room]
        img = Image.open(shots / f"piles_after_{room}.png").convert("RGB")
        piles, singles = mark(img, mons)
        img.save(out / f"piles_after_{room}.png")
        print(f"{room}: {len(mons)} monsters, {piles} piles, {singles} singles")
        before = Image.open(out / f"piles_before_{room}.png").convert("RGB")
        bn = before_counts.get(room)
        btxt = f"{room}: {bn[0]} monsters, {bn[1]} groups" if bn else f"{room}"
        d.text((pad, y), btxt, fill=(220, 220, 220), font=font(14))
        d.text((pad * 2 + cell, y), f"{room}: {len(mons)} monsters, {piles} piles (circled) + {singles} singles (dots)",
               fill=(220, 220, 220), font=font(14))
        sheet.paste(before, (pad, y + label - 4))
        sheet.paste(img, (pad * 2 + cell, y + label - 4))
    sheet.save(out / "piles_sheet.png")


if __name__ == "__main__":
    main()
