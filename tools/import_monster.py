#!/usr/bin/env python3
"""Import a PixelLab monster (5 generated directions) into assets/monsters/<id>/.

Input sheets are pixelart_workbench previews (a label strip on top, opaque #1f252c background):
  --pose  <sheet>  `join character:<id>:<dir> x5 --as sheet --columns 5`   (S, SE, E, NE, N rotations)
  --anim  <name>=<sheet>:<frames>  `join character:<id>:<dir>:<anim> x5 --as rows` (rows S, SE, E, NE, N)
          several --anim may share one sheet when it was joined as consecutive row blocks:
          <name>=<sheet>:<frames>@<first row>
The west-facing directions are the mirrored east-facing ones (SW<-SE, W<-E, NW<-NE).
Writes <anim>_<dir>.png strips (one row of cells) and manifest.json in the wolf's format
(directions, cell, fps, anchor, frames). The anchor is the feet: bottom of the south pose, centred.

Usage:
  python3 tools/import_monster.py boar --cell 48 --pose pose.png \
      --anim run=sheet.png:6@0 --anim attack=sheet.png:8@5 --fps run=12 attack=14
"""
import argparse
import json
import os

from PIL import Image

BG = (31, 37, 44)
GEN = ["south", "south-east", "east", "north-east", "north"]
MIRROR = {"south-west": "south-east", "west": "east", "north-west": "north-east"}
ORDER = ["south", "south-east", "east", "north-east", "north", "north-west", "west", "south-west"]


def key(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            if px[x, y][:3] == BG: px[x, y] = (0, 0, 0, 0)
    return im


def body(sheet: Image.Image, cell: int, cols: int, rows: int) -> Image.Image:
    return sheet.crop((0, sheet.height - rows * cell, cols * cell, sheet.height))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("id")
    ap.add_argument("--cell", type=int, default=48)
    ap.add_argument("--pose", required=True)
    ap.add_argument("--anim", action="append", default=[])
    ap.add_argument("--fps", nargs="*", default=[])
    ap.add_argument("--animcell", nargs="*", default=[], help="name=px for animations on a bigger canvas (v3: 64)")
    a = ap.parse_args()
    c = a.cell
    out = os.path.join(os.path.dirname(__file__), "..", "assets", "monsters", a.id)
    os.makedirs(out, exist_ok=True)
    man = {"directions": ORDER, "cell": {}, "fps": {"pose": 1}, "anchor": {}, "frames": {}}
    fps = dict(f.split("=") for f in a.fps)
    acell = {k: int(v) for k, v in (f.split("=") for f in a.animcell)}

    pose = key(body(Image.open(a.pose), c, 5, 1))
    cells = {d: pose.crop((i * c, 0, (i + 1) * c, c)) for i, d in enumerate(GEN)}
    for d, src in MIRROR.items():
        cells[d] = cells[src].transpose(Image.FLIP_LEFT_RIGHT)
    for d in ORDER:
        cells[d].save(os.path.join(out, f"pose_{d}.png"))
    bb = cells["south"].getbbox()
    anchor = [c // 2, bb[3] - 2]
    man["cell"]["pose"] = [c, c]
    man["anchor"]["pose"] = anchor
    man["frames"]["pose"] = {d: 1 for d in ORDER}

    for spec in a.anim:
        name, rest = spec.split("=", 1)
        path, fr = rest.rsplit(":", 1)
        first = 0
        if "@" in fr:
            fr, first = fr.split("@")
        frames, first = int(fr), int(first)
        c = acell.get(name, a.cell)
        sheet = Image.open(path)
        cols = sheet.width // c
        total_rows = (sheet.height - (sheet.height % c)) // c
        grid = key(body(sheet, c, cols, total_rows))
        strips = {}
        for i, d in enumerate(GEN):
            row = first + i
            strip = Image.new("RGBA", (frames * c, c))
            for f in range(frames):
                strip.paste(grid.crop((f * c, row * c, (f + 1) * c, (row + 1) * c)), (f * c, 0))
            strips[d] = strip
        for d, src in MIRROR.items():
            s = Image.new("RGBA", (frames * c, c))
            for f in range(frames):
                s.paste(strips[src].crop((f * c, 0, (f + 1) * c, c)).transpose(Image.FLIP_LEFT_RIGHT), (f * c, 0))
            strips[d] = s
        for d in ORDER:
            strips[d].save(os.path.join(out, f"{name}_{d}.png"))
        man["cell"][name] = [c, c]
        # A bigger canvas keeps the body centred: the feet are the bottom of the south frame 0.
        man["anchor"][name] = anchor if c == a.cell else [c // 2, strips["south"].crop((0, 0, c, c)).getbbox()[3] - 2]
        man["fps"][name] = int(fps.get(name, 12))
        man["frames"][name] = {d: frames for d in ORDER}
    with open(os.path.join(out, "manifest.json"), "w") as f:
        json.dump(man, f, indent=1)
    print(a.id, "anchor", anchor, "anims", list(man["frames"]))


if __name__ == "__main__":
    main()
