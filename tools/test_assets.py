"""Checks the hero sprite strips match assets/hero/manifest.json. Run: python3 tools/test_assets.py"""
import json, os, sys
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..", "assets", "hero")
REQUIRED = {"idle", "walk", "shoot"}

def main():
    m = json.load(open(os.path.join(ROOT, "manifest.json")))
    fails = []
    missing = REQUIRED - set(m["frames"])
    if missing: fails.append(f"missing animations: {sorted(missing)}")
    for anim, per_dir in m["frames"].items():
        cw, ch = m["cell"][anim]
        for d in m["directions"]:
            p = os.path.join(ROOT, f"{anim}_{d}.png")
            if not os.path.exists(p): fails.append(f"missing {p}"); continue
            im = Image.open(p).convert("RGBA")
            if im.size != (cw * per_dir[d], ch): fails.append(f"{p}: size {im.size} != {(cw*per_dir[d], ch)}")
            if im.getextrema()[3][0] != 0: fails.append(f"{p}: no transparent pixels")
            if im.getextrema()[3][1] != 255: fails.append(f"{p}: empty strip")
            if [cw, ch] != [64, 64]: fails.append(f"{anim}: cell {cw}x{ch}, expected 64x64 (run normalize_cells.py pad)")
            # feet must sit on the shared anchor row (within 2 px) so animations don't jump
            ax, ay = m.get("anchor", {}).get(anim, [None, None])
            if ay is None: fails.append(f"{anim}: no anchor in manifest")
            else:
                bottom = max((im.crop((i*cw, 0, (i+1)*cw, ch)).getbbox() or (0,0,0,0))[3] for i in range(per_dir[d]))
                if abs(bottom - ay) > 2: fails.append(f"{p}: feet row {bottom} far from anchor {ay}")
    print("\n".join(fails) if fails else f"PASS {sum(len(v) for v in m['frames'].values())} strips")
    sys.exit(1 if fails else 0)

if __name__ == "__main__":
    main()
