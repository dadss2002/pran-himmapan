"""Fill transparent pixels INSIDE an icon's frame with the tile green, so the icon
doesn't show what is behind it. Transparent pixels connected to the image border
(rounded corners) stay transparent.
Usage: python3 tools/fill_icon_bg.py <icon.png> [--color 42,78,52]
"""
import argparse
from collections import deque
from PIL import Image

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("icon"); ap.add_argument("--color", default="42,78,52")
    a = ap.parse_args()
    fill = tuple(int(v) for v in a.color.split(",")) + (255,)
    im = Image.open(a.icon).convert("RGBA"); w, h = im.size; px = im.load()
    outside = set(); q = deque()
    for x in range(w):
        for y in (0, h - 1): q.append((x, y))
    for y in range(h):
        for x in (0, w - 1): q.append((x, y))
    while q:
        x, y = q.popleft()
        if (x, y) in outside or not (0 <= x < w and 0 <= y < h) or px[x, y][3] != 0: continue
        outside.add((x, y)); q.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
    n = 0
    for y in range(h):
        for x in range(w):
            if px[x, y][3] == 0 and (x, y) not in outside:
                px[x, y] = fill; n += 1
    im.save(a.icon); print(f"{a.icon}: filled {n} inner transparent px")

if __name__ == "__main__":
    main()
