"""Split a workbench `join ... --as rows` preview (one direction per row, order below) into
per-direction strips assets/hero/<anim>_<dir>.png and record them in assets/hero/manifest.json.

Usage:
  python3 tools/build_hero_manifest.py <preview.png> <anim> --cell 48x48 --frames 4 --fps 6 --expect-colors 138
"""
import argparse, json, os, subprocess, sys, tempfile
from PIL import Image

DIRS = ["south", "south-east", "east", "north-east", "north", "north-west", "west", "south-west"]
HERE = os.path.dirname(__file__)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("preview"); ap.add_argument("anim")
    ap.add_argument("--cell", required=True); ap.add_argument("--frames", type=int, required=True)
    ap.add_argument("--fps", type=int, required=True); ap.add_argument("--expect-colors", type=int)
    ap.add_argument("--root", default="assets/hero", help="actor folder, e.g. assets/wolf")
    a = ap.parse_args()
    OUT = os.path.join(HERE, "..", a.root)
    cw, ch = (int(v) for v in a.cell.split("x"))
    os.makedirs(OUT, exist_ok=True)
    sheet_path = os.path.join(tempfile.gettempdir(), f"{a.anim}_sheet.png")
    cmd = [sys.executable, os.path.join(os.path.dirname(__file__), "extract_sheet.py"), a.preview, sheet_path,
           "--cell", a.cell, "--cols", str(a.frames), "--rows", str(len(DIRS))]
    if a.expect_colors: cmd += ["--expect-colors", str(a.expect_colors)]
    subprocess.run(cmd, check=True)
    sheet = Image.open(sheet_path)
    for i, d in enumerate(DIRS):
        sheet.crop((0, i * ch, a.frames * cw, (i + 1) * ch)).save(os.path.join(OUT, f"{a.anim}_{d}.png"))
    mpath = os.path.join(OUT, "manifest.json")
    m = json.load(open(mpath)) if os.path.exists(mpath) else {"directions": DIRS, "cell": {}, "frames": {}, "fps": {}}
    m["cell"][a.anim] = [cw, ch]
    m["frames"][a.anim] = {d: a.frames for d in DIRS}
    m["fps"][a.anim] = a.fps
    json.dump(m, open(mpath, "w"), indent=2)
    print(f"ok {a.anim}: 8 strips of {a.frames}x {cw}x{ch}")

if __name__ == "__main__":
    main()
