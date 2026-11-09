"""Re-lay an assets/fx sheet as a grid of `columns` frames per row (pixels unchanged), so no side of the sheet
is over 2048 px (phones' WebGL, risk B19), and write "columns" into its manifest entry.

Usage: python3 -I tools/fx_regrid.py <effect id> <columns>
"""
import json, math, os, sys
from PIL import Image

def main():
    fx_id, cols = sys.argv[1], int(sys.argv[2])
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    mpath = os.path.join(root, "assets/fx/manifest.json")
    man = json.load(open(mpath))
    e = man[fx_id]
    path = os.path.join(root, "assets/fx", e.get("sheet", fx_id + ".png"))
    cw, ch = e["cell"]; n = e["frames"]; old_cols = e.get("columns", n)
    src = Image.open(path).convert("RGBA")
    rows = math.ceil(n / cols)
    out = Image.new("RGBA", (cols * cw, rows * ch), (0, 0, 0, 0))
    for i in range(n):
        f = src.crop(((i % old_cols) * cw, (i // old_cols) * ch, (i % old_cols) * cw + cw, (i // old_cols) * ch + ch))
        out.paste(f, ((i % cols) * cw, (i // cols) * ch))
    assert out.size[0] <= 2048 and out.size[1] <= 2048, "%s: %s still over 2048" % (fx_id, out.size)
    out.save(path, optimize=True)
    e["columns"] = cols
    json.dump(man, open(mpath, "w"), indent=2, ensure_ascii=False)
    open(mpath, "a").write("\n")
    print("%s: %d frames, %d columns, sheet %dx%d" % (fx_id, n, cols, out.size[0], out.size[1]))

if __name__ == "__main__":
    main()
