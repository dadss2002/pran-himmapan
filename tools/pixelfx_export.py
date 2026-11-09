"""Export the owner's PixelFX picks (spec docs/superpowers/specs/2026-11-08-pixelfx.md) into assets/fx.

PixelFX: https://github.com/patch-gg/pixelfx, commit a841596, MIT (assets/fx/PIXELFX_LICENSE.txt).
Each effect is rendered with PixelFX's own tool, run inside a separate checkout:
    node tools/render.mjs <id> --sheet --fps <old fps> --opts '{"palette": [...], ...}'
and then post-processed here (no drawing by hand):
  - palette: the exact colour ramp of the PixelLab effect it replaces (dark -> light, read from that sheet);
  - fps: the old effect's fps, kept within 14-16 (spec), chosen so a loop's length is a whole number of frames;
  - status effects (burning, frozen) get a monster-shaped actor (the feet-aligned average silhouette of every
    monster pose in assets/, instead of PixelFX's stock character) and every pixel on that body is cut away,
    so only flames / frost round the edges remain and our own monster sprite shows through;
  - warp (blink-out) gets the hero's own silhouette (idle south) as its actor;
  - crop to a box round the anchor (crit <= 2x the 48 px hero, poison mist about the old mist's width), with the
    alpha eased out over the last EDGE px wherever the box cuts the effect, then a grid sheet <= 2048 px a side.
Writes assets/fx/pfx_<name>.png and the manifest entry <name> (with "sheet" and "pixelfx" metadata). The old
PixelLab entry is kept as "pixellab_<name>" (sheet <name>.png) when <name> was a PixelLab effect.

Usage: python3 -I tools/pixelfx_export.py --pixelfx /path/to/pixelfx-checkout [--only name,...] [--work DIR]
"""
import argparse, json, os, subprocess, sys, tempfile
from PIL import Image

COMMIT = "a841596"
EDGE = 6          # px of alpha fade where a crop box cuts the effect
MAX_SIDE = 2048
ALPHA_FLOOR = 6   # alpha below this counts as empty (keeps crops tight)

def old_palette(fx_dir, name):
    """The old sheet's opaque colours, dark to light (PixelLab effects use 5-9 exact colours)."""
    im = Image.open(os.path.join(fx_dir, name + ".png")).convert("RGBA")
    seen = {}
    for p in im.get_flattened_data() if hasattr(im, "get_flattened_data") else im.getdata():
        if p[3] >= 160: seen[p[:3]] = seen.get(p[:3], 0) + 1
    luma = lambda c: 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]
    return ["#%02x%02x%02x" % c for c in sorted(seen, key=luma)]

# name: what the game calls; old: the PixelLab effect whose palette / fps it takes; point: the PixelFX-space
# point (from its origin) that sits on the node origin; box: crop box round that point (x0, y0, x1, y1).
EFFECTS = {
    "hit_spark":    dict(id="impacts/hit-spark",    old="hit_spark",    fps=16, opts={"height": 12}, point=(0, -12), box=(-32, -34, 32, 16)),
    "crit_hit":     dict(id="impacts/crit-hit",     old="hit_spark",    fps=16, opts={"height": 12}, point=(0, -12), box=(-48, -40, 48, 16), edge=16),
    "poison_mist":  dict(id="nature/poison-cloud",  old="poison_mist",  fps=14, opts={"spread": 0.34}, point=(0, 0), box=(-44, -44, 44, 10)),
    "status_burn":  dict(id="status/burning",       old="status_burn",  fps=15, actor="monster", cut=True, point=(0, 0), box=(-36, -70, 36, 10)),
    "status_frost": dict(id="status/frozen",        old="status_frost", fps=14, actor="monster", cut=True, cut_dx=1, point=(0, 0), box=(-28, -60, 28, 10)),
    "pickup_pop":   dict(id="pickups/collect-burst", old="pickup_pop",  fps=15, point=(0, -30), box=(-36, -36, 36, 34)),
    "warp_blink":   dict(id="arcane/blink-out",     old="warp_ring",    fps=14, actor="hero", point=(0, 0), box=(-40, -72, 40, 12), t0=0.13, t1=1.25),
}

def _packed(r, g, b):
    v = (255 << 24) | (b << 16) | (g << 8) | r
    return v - (1 << 32) if v >= (1 << 31) else v

STATUS_FX_SCALE = 1.5   # scripts/monsters/wolf.gd draws status effects at this x size_scale() (as the PixelLab ones)

def monster_actor(root, thresh=0.7, k=1.0 / STATUS_FX_SCALE):
    """The core of a typical monster body: pixels covered by >= thresh of all pose frames (every kind, every
    facing), feet-aligned on each sheet's pose anchor, shrunk by k (the sheet is drawn STATUS_FX_SCALE larger,
    so on screen it sits inside the monster's outline). As a PixelFX actor: feet at (0, 0), mid-grey pixels."""
    W, H, FX, FY = 64, 64, 32, 56
    cov = [0] * (W * H); n = 0
    mans = sorted(os.path.join(root, "assets/monsters", k, "manifest.json") for k in os.listdir(os.path.join(root, "assets/monsters")))
    mans.append(os.path.join(root, "assets/wolf/manifest.json"))
    for mf in mans:
        if not os.path.exists(mf): continue
        m = json.load(open(mf)); d = os.path.dirname(mf)
        ax, ay = m["anchor"]["pose"]
        cw, ch = m["cell"]["pose"]
        for di in m["directions"]:
            p = os.path.join(d, "pose_%s.png" % di)
            if not os.path.exists(p): continue
            a = Image.open(p).convert("RGBA").getchannel("A")
            for y in range(min(ch, a.size[1])):
                for x in range(min(cw, a.size[0])):
                    if a.getpixel((x, y)) > 40:
                        X, Y = x - ax + FX, y - ay + FY
                        if 0 <= X < W and 0 <= Y < H: cov[Y * W + X] += 1
            n += 1
    on = [c >= thresh * n for c in cov]
    xs = [i % W for i in range(W * H) if on[i]]; ys = [i // W for i in range(W * H) if on[i]]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    w, h = x1 - x0 + 1, y1 - y0 + 1
    img = Image.new("L", (w, h))
    img.putdata([255 if on[(y0 + y) * W + x0 + x] else 0 for y in range(h) for x in range(w)])
    fx_, fy_ = FX - x0, FY - y0                     # feet inside the mask
    w, h = max(1, round(w * k)), max(1, round(h * k))
    img = img.resize((w, h), Image.NEAREST)
    data = [1 if v > 127 else 0 for v in (img.get_flattened_data() if hasattr(img, "get_flattened_data") else img.getdata())]
    x0, y0 = FX - round(fx_ * k), FY - round(fy_ * k)
    grey = _packed(128, 120, 112)
    return {"mask": {"w": w, "h": h, "data": data}, "pixels": [grey if v else 0 for v in data],
            "x": x0 - FX, "y": y0 - FY, "w": w, "h": h, "k": 2, "head": [0, y0 - FY], "chest": [0, y0 - FY + h // 2]}

def hero_actor(root):
    """The hero, idle facing south, frame 0, feet on his anchor: his own silhouette and colours."""
    m = json.load(open(os.path.join(root, "assets/hero/manifest.json")))
    cw, ch = m["cell"]["idle"]; ax, ay = m["anchor"]["idle"]
    im = Image.open(os.path.join(root, "assets/hero/idle_south.png")).convert("RGBA").crop((0, 0, cw, ch))
    bb = im.getchannel("A").point(lambda a: 255 if a > 40 else 0).getbbox()
    x0, y0, x1, y1 = bb
    w, h = x1 - x0, y1 - y0
    data, pix = [], []
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b, a = im.getpixel((x, y))
            data.append(1 if a > 40 else 0)
            pix.append(_packed(r, g, b) if a > 40 else 0)
    return {"mask": {"w": w, "h": h, "data": data}, "pixels": pix, "x": x0 - ax, "y": y0 - ay, "w": w, "h": h, "k": 2,
            "head": [0, y0 - ay], "chest": [0, y0 - ay + h // 3]}

def unpremultiply(f):
    """PixelFX's sheet writer pastes each frame onto a transparent black canvas as src*a + dst*(1-a), so a
    translucent pixel's colour comes out multiplied by its alpha while the alpha stays straight: glows and light
    would darken the ground. Each cell is pasted once onto zeros, so colour / alpha gives the real colour back."""
    f = f.copy(); px = f.load()
    for y in range(f.size[1]):
        for x in range(f.size[0]):
            r, g, b, a = px[x, y]
            if 0 < a < 255:
                k = 255.0 / a
                px[x, y] = (min(255, round(r * k)), min(255, round(g * k)), min(255, round(b * k)), a)
    return f

def render(pfx_dir, cfg, opts, work):
    out = os.path.join(work, "render")
    cmd = ["node", "tools/render.mjs", cfg["id"], "--sheet", "--fps", str(cfg["fps"]), "--opts", json.dumps(opts), "--out", out]
    subprocess.run(cmd, cwd=pfx_dir, check=True, stdout=subprocess.DEVNULL)
    name = cfg["id"].split("/")[1]
    d = os.path.join(out, cfg["id"])
    meta = json.load(open(os.path.join(d, name + ".json")))
    sheet = Image.open(os.path.join(d, name + ".png")).convert("RGBA")
    frames = [sheet.crop((f["frame"]["x"], f["frame"]["y"], f["frame"]["x"] + f["frame"]["w"], f["frame"]["y"] + f["frame"]["h"])) for f in meta["frames"]]
    return frames, meta["meta"]["pixelfx"]

def export(root, pfx_dir, name, cfg, work, actors):
    fx_dir = os.path.join(root, "assets/fx")
    pal = old_palette(fx_dir, cfg["old"])
    opts = dict(cfg.get("opts", {})); opts["palette"] = pal
    if cfg.get("actor"): opts["actor"] = actors[cfg["actor"]]
    frames, pm = render(pfx_dir, cfg, opts, work)
    fw, fh = pm["frameSize"]; ox, oy = pm["pivot"]; fps = pm["fps"]; loop = pm["loop"]
    # trim (one-shots only)
    t0, t1 = cfg.get("t0", 0.0), cfg.get("t1", 1e9)
    if not loop:
        frames = [f for i, f in enumerate(frames) if t0 - 1e-6 <= i / fps <= t1 + 1e-6]
    frames = [unpremultiply(f) for f in frames]
    # cut the body (status effects): every pixel of the actor's mask, widened by cut_dx for a shivering body
    if cfg.get("cut"):
        A = actors[cfg["actor"]]; mw, mh, md = A["mask"]["w"], A["mask"]["h"], A["mask"]["data"]
        dx = cfg.get("cut_dx", 0)
        for f in frames:
            px = f.load()
            for my in range(mh):
                for mx in range(mw):
                    if not md[my * mw + mx]: continue
                    for s in range(-dx, dx + 1):
                        x, y = ox + A["x"] + mx + s, oy + A["y"] + my
                        if 0 <= x < fw and 0 <= y < fh: px[x, y] = (0, 0, 0, 0)
    for f in frames:
        px = f.load()
        for y in range(fh):
            for x in range(fw):
                if px[x, y][3] < ALPHA_FLOOR: px[x, y] = (0, 0, 0, 0)
    if not loop:
        while len(frames) > 1 and frames[-1].getbbox() is None: frames.pop()
    # crop: union bbox of the frames, inside the box round the anchor point
    px0, py0 = ox + cfg["point"][0], oy + cfg["point"][1]
    bx0, by0, bx1, by1 = (px0 + cfg["box"][0], py0 + cfg["box"][1], px0 + cfg["box"][2], py0 + cfg["box"][3])
    ux0, uy0, ux1, uy1 = fw, fh, 0, 0
    for f in frames:
        b = f.getbbox()
        if b: ux0, uy0, ux1, uy1 = min(ux0, b[0]), min(uy0, b[1]), max(ux1, b[2]), max(uy1, b[3])
    cx0, cy0, cx1, cy1 = max(ux0, bx0, 0), max(uy0, by0, 0), min(ux1, bx1, fw), min(uy1, by1, fh)
    clipped = {"l": ux0 < cx0, "t": uy0 < cy0, "r": ux1 > cx1, "b": uy1 > cy1}
    cw, ch = cx1 - cx0, cy1 - cy0
    out = []
    for f in frames:
        c = f.crop((cx0, cy0, cx1, cy1)); px = c.load()
        if any(clipped.values()):
            for y in range(ch):
                for x in range(cw):
                    E = cfg.get("edge", EDGE); d = E
                    if clipped["l"]: d = min(d, x)
                    if clipped["r"]: d = min(d, cw - 1 - x)
                    if clipped["t"]: d = min(d, y)
                    if clipped["b"]: d = min(d, ch - 1 - y)
                    if d < E:
                        r, g, b, a = px[x, y]
                        u = (d + 0.5) / E
                        px[x, y] = (r, g, b, int(round(a * u * u * (3 - 2 * u))))
        out.append(c)
    n = len(out)
    cols = max(1, min(n, MAX_SIDE // cw))
    rows = (n + cols - 1) // cols
    assert rows * ch <= MAX_SIDE, "%s: sheet too tall" % name
    sheet = Image.new("RGBA", (cols * cw, rows * ch), (0, 0, 0, 0))
    for i, c in enumerate(out): sheet.paste(c, ((i % cols) * cw, (i // cols) * ch))
    sheet_name = "pfx_%s.png" % name
    sheet.save(os.path.join(fx_dir, sheet_name), optimize=True)
    shown_opts = {k: v for k, v in opts.items() if k != "actor"}
    if cfg.get("actor"): shown_opts["actor"] = {"monster": "average monster silhouette (assets/monsters + assets/wolf poses)", "hero": "hero idle_south frame 0"}[cfg["actor"]]
    entry = {"cell": [cw, ch], "frames": n, "fps": fps, "anchor": [px0 - cx0, py0 - cy0], "loop": loop, "columns": cols,
             "sheet": sheet_name,
             "pixelfx": {"id": cfg["id"], "commit": COMMIT, "options": shown_opts, "palette_from": cfg["old"] + ".png",
                         "trim_s": [t0, min(t1, (len(frames) - 1) / fps + t0)] if not loop else None,
                         "body_cut": bool(cfg.get("cut")), "crop": [cx0 - px0, cy0 - py0, cx1 - px0, cy1 - py0]}}
    return entry

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pixelfx", required=True)
    ap.add_argument("--only", default="")
    ap.add_argument("--work", default="")
    a = ap.parse_args()
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    work = a.work or tempfile.mkdtemp(prefix="pixelfx_")
    actors = {"monster": monster_actor(root), "hero": hero_actor(root)}
    mpath = os.path.join(root, "assets/fx/manifest.json")
    man = json.load(open(mpath))
    names = [n for n in EFFECTS if not a.only or n in a.only.split(",")]
    for name in names:
        e = export(root, a.pixelfx, name, EFFECTS[name], work, actors)
        old = man.get(name)
        if old and "pixelfx" not in old:          # keep the PixelLab effect it replaces, under its own id
            old = dict(old); old["sheet"] = name + ".png"; old["replaced_by"] = name
            man["pixellab_" + name] = old
        man[name] = e
        print("%-13s %2d frames @%d fps  cell %dx%d  anchor %s  cols %d" % (name, e["frames"], e["fps"], e["cell"][0], e["cell"][1], e["anchor"], e["columns"]))
    man["_doc"] = ("PixelLab vfx_workbench exports (effects saved in My effects) and PixelFX exports (\"pixelfx\": "
                   "tools/pixelfx_export.py, MIT, assets/fx/PIXELFX_LICENSE.txt). anchor = pixel in a cell that sits on the "
                   "node origin; sheet = file in assets/fx (default <id>.png); columns = frames per row (default all).")
    json.dump(man, open(mpath, "w"), indent=2, ensure_ascii=False)
    open(mpath, "a").write("\n")

if __name__ == "__main__":
    main()
