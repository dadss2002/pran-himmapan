"""Checks tools/pixelfx_export.py's checkout guard (review Minor #6, 2026-11-09): the export stops unless the PixelFX
checkout is at COMMIT *and* clean (`git status --porcelain` empty: no edited, staged or untracked files), so every
sheet in assets/fx is what that commit renders. Run: python3 -I tools/test_pixelfx_export.py
Uses throwaway git repos in a temp dir (COMMIT is pointed at their HEAD); needs git and Pillow (the tool imports it)."""
import importlib.util, os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))

def load_tool():
    spec = importlib.util.spec_from_file_location("pixelfx_export", os.path.join(HERE, "pixelfx_export.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

def git(d, *args):
    return subprocess.run(["git", "-C", d, *args], check=True, capture_output=True, text=True).stdout.strip()

def make_repo(root):
    d = tempfile.mkdtemp(dir=root)
    git(d, "init", "-q")
    git(d, "config", "user.email", "t@example.invalid")
    git(d, "config", "user.name", "t")
    git(d, "config", "commit.gpgsign", "false")
    with open(os.path.join(d, "a.txt"), "w") as f: f.write("a\n")
    git(d, "add", "a.txt")
    git(d, "commit", "-q", "-m", "a")
    return d

def stops(tool, d):
    try:
        tool.check_commit(d)
    except SystemExit as e:
        return str(e.code)
    return ""

def main():
    tool = load_tool()
    fails = []
    with tempfile.TemporaryDirectory() as root:
        d = make_repo(root)
        tool.COMMIT = git(d, "rev-parse", "--short=7", "HEAD")
        if stops(tool, d): fails.append("clean checkout at COMMIT stopped: " + stops(tool, d))
        with open(os.path.join(d, "a.txt"), "w") as f: f.write("edited\n")
        msg = stops(tool, d)
        if not msg: fails.append("edited tracked file: export not stopped")
        elif "uncommitted" not in msg: fails.append("edited tracked file: message lacks 'uncommitted': " + msg)
        git(d, "checkout", "-q", "--", "a.txt")
        with open(os.path.join(d, "new.mjs"), "w") as f: f.write("x\n")
        if not stops(tool, d): fails.append("untracked file: export not stopped")
        os.remove(os.path.join(d, "new.mjs"))
        with open(os.path.join(d, "a.txt"), "w") as f: f.write("staged\n")
        git(d, "add", "a.txt")
        if not stops(tool, d): fails.append("staged change: export not stopped")
        git(d, "reset", "-q", "--hard")
        if stops(tool, d): fails.append("clean again: stopped: " + stops(tool, d))
        tool.COMMIT = "0000000"
        if not stops(tool, d): fails.append("wrong commit: export not stopped")
    fails += shrink_cases(tool)
    print("\n".join(fails) if fails else "PASS pixelfx_export checkout guard (6 cases) + shrink_cells (4 cases)")
    sys.exit(1 if fails else 0)

def shrink_cases(tool):
    """Owner 2026-11-10 pre-shrunk trail sheet (shrink_cells): crisp, no blur halo, anchor kept, size 0.4."""
    from PIL import Image
    data = lambda im: list(im.get_flattened_data() if hasattr(im, "get_flattened_data") else im.getdata())
    fails = []
    pal = ["#1b0404", "#7a1410", "#c22a14", "#f05a1c", "#ff9a2a", "#ffd04a", "#fff3a8"]
    # 1. an opaque 20x20 flame block on nothing: only alpha 0 / 255 come out (no translucent ring round its edge)
    c = Image.new("RGBA", (44, 49), (0, 0, 0, 0))
    for y in range(20, 40):
        for x in range(12, 32): c.putpixel((x, y), (255, 154, 42, 255))
    out, size, anchor, levels, used = tool.shrink_cells([c], (22, 44), 0.4, pal)
    alphas = {p[3] for p in data(out[0])}
    if size != (18, 20) or anchor != (9, 18): fails.append("shrink: size %s anchor %s, want (18, 20) / (9, 18)" % (size, anchor))
    if alphas - {0, 255}: fails.append("shrink: a solid block came out with alphas %s (blur halo)" % sorted(alphas))
    if sum(1 for p in data(out[0]) if p[3] == 255) != 64: fails.append("shrink: the 20x20 block is not 8x8 opaque (0.4)")
    # 2. colours snap to the palette (a blend of two ramp colours becomes one of them)
    c2 = Image.new("RGBA", (44, 49), (0, 0, 0, 0))
    for y in range(49):
        for x in range(44): c2.putpixel((x, y), (255, 208, 74, 255) if (x + y) % 2 else (240, 90, 28, 255))
    o2 = tool.shrink_cells([c2], (22, 44), 0.4, pal)[0][0]
    hexes = {"#%02x%02x%02x" % p[:3] for p in data(o2) if p[3]}
    if not hexes <= set(pal): fails.append("shrink: colours %s off the palette" % sorted(hexes - set(pal)))
    # 3. a glow (translucent, alpha 100) next to the block keeps a level from the sheet, never an in-between alpha
    c3 = c.copy()
    for y in range(20, 40):
        for x in range(32, 44): c3.putpixel((x, y), (255, 154, 42, 100))
    o3, _, _, lv3, _ = tool.shrink_cells([c3], (22, 44), 0.4, pal)
    al3 = {p[3] for p in data(o3[0])}
    if al3 - ({0, 255} | set(lv3)): fails.append("shrink: glow alphas %s not in the levels %s" % (sorted(al3), lv3))
    # 4. the feet: a 1 px column at the anchor (22, 40..44) lands on output column 9, just above row 18
    c4 = Image.new("RGBA", (44, 49), (0, 0, 0, 0))
    for y in range(36, 44):
        for x in range(21, 24): c4.putpixel((x, y), (255, 243, 168, 255))
    o4 = tool.shrink_cells([c4], (22, 44), 0.4, pal)[0][0]
    xs = {x for y in range(20) for x in range(18) if o4.getpixel((x, y))[3]}
    ys = {y for y in range(20) for x in range(18) if o4.getpixel((x, y))[3]}
    if xs != {8, 9} and xs != {9}: fails.append("shrink: a column at the anchor came out at x %s, want 9 (centred)" % sorted(xs))
    if not ys or max(ys) != 17: fails.append("shrink: the feet row came out at %s, want 17 (just above the anchor row 18)" % sorted(ys))
    return fails

if __name__ == "__main__":
    main()
