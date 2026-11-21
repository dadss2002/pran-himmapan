"""Derive Wang corners of each 32px tile from pixels: compare each 12x12 corner patch to the
all-lower tile and all-upper tile (found as the tiles most like the rest at each extreme)."""
import sys, itertools
from PIL import Image
im = Image.open(sys.argv[1]).convert('RGB'); T = 32; P = 12
cols, rows = im.width // T, im.height // T
def patch(tx, ty, cx, cy):
    x0 = tx*T + (0 if cx == 0 else T-P); y0 = ty*T + (0 if cy == 0 else T-P)
    px = [im.getpixel((x, y)) for y in range(y0, y0+P) for x in range(x0, x0+P)]
    return tuple(sum(c[i] for c in px)/len(px) for i in range(3))
lo = tuple(int(v) for v in sys.argv[2].split(','))   # tile coords of all-lower
up = tuple(int(v) for v in sys.argv[3].split(','))   # tile coords of all-upper
def mean_tile(t): 
    ps=[patch(t[0],t[1],cx,cy) for cy in (0,1) for cx in (0,1)]
    return tuple(sum(p[i] for p in ps)/4 for i in range(3))
L, U = mean_tile(lo), mean_tile(up)
d = lambda a, b: sum((a[i]-b[i])**2 for i in range(3))
for ty in range(rows):
    for tx in range(cols):
        c = []
        for cy, cx in ((0,0),(0,1),(1,0),(1,1)):
            p = patch(tx, ty, cx, cy); c.append('upper' if d(p, U) < d(p, L) else 'lower')
        print(f"{tx*T},{ty*T}: {' '.join(c)}")
