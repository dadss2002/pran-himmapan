"""Bring hero strips onto one 64x64 cell with the feet at the same point.

PixelLab gives template animations (idle, walk) on the character's 48x48 canvas and custom /
skeleton animations (shoot, walk_fix) on a 64x64 canvas. Measured bounding boxes show the 48 art
sits at offset (8, 12) inside the 64 canvas (feet row 42 -> 54, centre x 24 -> 32), so padding
with that offset lines every animation up on the anchor (32, 54).

Usage:
  python3 tools/normalize_cells.py pad <anim> [--offset 8,12]
  python3 tools/normalize_cells.py replace <anim> <dir> <sheet.png> --row N --frames F
     (copy row N of a 64x64-cell sheet over assets/hero/<anim>_<dir>.png)
"""
import argparse, json, os
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..", "assets", "hero")  # overridden by --root
CELL = 64
ANCHOR = [32, 54]

def load_manifest():
    return json.load(open(os.path.join(ROOT, "manifest.json")))

def save_manifest(m):
    json.dump(m, open(os.path.join(ROOT, "manifest.json"), "w"), indent=2)

def pad(anim, ox, oy):
    m = load_manifest()
    cw, ch = m["cell"][anim]
    if [cw, ch] == [CELL, CELL]:
        print(f"{anim} already {CELL}x{CELL}"); return
    for d in m["directions"]:
        p = os.path.join(ROOT, f"{anim}_{d}.png")
        src = Image.open(p).convert("RGBA")
        n = m["frames"][anim][d]
        out = Image.new("RGBA", (CELL * n, CELL), (0, 0, 0, 0))
        for i in range(n):
            out.paste(src.crop((i * cw, 0, (i + 1) * cw, ch)), (i * CELL + ox, oy))
        out.save(p)
    m["cell"][anim] = [CELL, CELL]
    m.setdefault("anchor", {})[anim] = ANCHOR
    save_manifest(m)
    print(f"padded {anim} {cw}x{ch} -> {CELL}x{CELL} at offset ({ox},{oy})")

def replace(anim, d, sheet, row, frames):
    m = load_manifest()
    assert m["cell"][anim] == [CELL, CELL], f"{anim} must be padded to {CELL} first"
    assert m["frames"][anim][d] == frames, "frame count differs from manifest"
    im = Image.open(sheet).convert("RGBA")
    im.crop((0, row * CELL, frames * CELL, (row + 1) * CELL)).save(os.path.join(ROOT, f"{anim}_{d}.png"))
    print(f"replaced {anim}_{d} with row {row} of {sheet}")

def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("pad"); a.add_argument("anim"); a.add_argument("--offset", default="8,12")
    b = sub.add_parser("replace"); b.add_argument("anim"); b.add_argument("dir"); b.add_argument("sheet")
    b.add_argument("--row", type=int, required=True); b.add_argument("--frames", type=int, required=True)
    c = sub.add_parser("anchor"); c.add_argument("anim")
    ap.add_argument("--root", default="assets/hero")
    ap.add_argument("--anchor", default="32,54")
    a_ = ap.parse_args()
    global ROOT, ANCHOR
    ROOT = os.path.join(os.path.dirname(__file__), "..", a_.root)
    ANCHOR = [int(v) for v in a_.anchor.split(",")]
    if a_.cmd == "pad":
        ox, oy = (int(v) for v in a_.offset.split(","))
        pad(a_.anim, ox, oy)
    elif a_.cmd == "replace":
        replace(a_.anim, a_.dir, a_.sheet, a_.row, a_.frames)
    else:
        m = load_manifest(); m.setdefault("anchor", {})[a_.anim] = ANCHOR; save_manifest(m)

if __name__ == "__main__":
    main()
