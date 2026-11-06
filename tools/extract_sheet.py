"""Turn a PixelLab workbench preview sheet into a transparent game sprite sheet.

Why: the sandbox cannot download from api.pixellab.ai, but `pixelart_workbench join ... --as sheet`
returns a lossless 1x image with a label strip on top and an opaque background #1f252c.
This crops the label strip, keys out the background, and verifies nothing else was lost.

Usage:
  python3 tools/extract_sheet.py <preview.png> <out.png> --cell 48x48 --cols 8 --rows 1 [--expect-colors N]
"""
import argparse
from collections import Counter
from PIL import Image

BG = (31, 37, 44, 255)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src"); ap.add_argument("out")
    ap.add_argument("--cell", default="48x48")
    ap.add_argument("--cols", type=int, required=True)
    ap.add_argument("--rows", type=int, default=1)
    ap.add_argument("--expect-colors", type=int, default=None,
                    help="palette size the workbench reported; checks the extraction is lossless")
    a = ap.parse_args()
    cw, ch = (int(v) for v in a.cell.split("x"))
    W, H = cw * a.cols, ch * a.rows
    im = Image.open(a.src).convert("RGBA")
    if im.width != W or im.height < H:
        raise SystemExit(f"unexpected preview size {im.size}, want width {W} and height >= {H}")
    sheet = im.crop((0, im.height - H, W, im.height))  # label strip sits on top
    px = sheet.load()
    for y in range(H):
        for x in range(W):
            if px[x, y] == BG:
                px[x, y] = (0, 0, 0, 0)
    colors = Counter(c for c in sheet.getdata() if c[3] == 255)
    if a.expect_colors is not None and len(colors) != a.expect_colors:
        raise SystemExit(f"colour check failed: got {len(colors)} opaque colours, workbench said {a.expect_colors}")
    sheet.save(a.out)
    print(f"ok {a.out} {W}x{H} colours={len(colors)}")

if __name__ == "__main__":
    main()
