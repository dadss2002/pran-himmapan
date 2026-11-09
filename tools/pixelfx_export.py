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
  - warp (blink-out): owner 2026-11-09 wants only the green sparkle, no hero ghost, so its actor is an invisible
    chest-high box (empty mask: no lit body, outline, squeezed figure or afterimage; the burst comes out of the
    chest as a ball), trimmed to the 0.5 s the warp fade shows;
  - owner 2026-11-09 for the hit spark: stronger orange/gold, bigger, less white: the ramp leaves out the old
    sheet's lightest colours (ramp_drop), PixelFX's hard-coded white is recoloured (white_to / pale_to) and the
    frames are enlarged (scale, nearest, about the anchor);
  - one-shot tails that are only stray dots are dropped (tail_px), loops can be trimmed to what the game shows (t0/t1);
  - crop to a box round the anchor (crit <= 2x the 48 px hero, poison mist about the old mist's width), with the
    alpha eased out over the last EDGE px wherever the box cuts the effect, then a grid sheet <= 2048 px a side;
  - owner 2026-11-09 fire picks (samples /home/claude/fx_samples, notes.md; rows T2 and B2, exported exactly as sampled):
    marker (a prop PixelFX draws in a marker colour is cut: the campfire's logs are drawn pure blue, then every blue
    pixel goes, leaving flames and coals), symmetric (the crop keeps the anchor centred across, so trail patches line
    up on the path), glow_fade (translucent pixels, alpha < glow_fade: PixelFX's soft light and thin smoke, fade out
    radially from the cell centre: no rectangular orange glow box on the ground; solid flame is untouched) and
    fade_out (the last N frames of a one-shot trimmed mid-effect ease out instead of popping off).
Writes assets/fx/pfx_<name>.png and the manifest entry <name> (with "sheet" and "pixelfx" metadata). The old
PixelLab entry is kept as "pixellab_<name>" (sheet <name>.png) when <name> was a PixelLab effect.

The checkout must be at COMMIT and clean (checked with git; the script stops otherwise). Test: tools/test_pixelfx_export.py.

Usage: python3 -I tools/pixelfx_export.py --pixelfx /path/to/pixelfx-checkout [--only name,...] [--work DIR]
"""
import argparse, colorsys, json, math, os, subprocess, sys, tempfile
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
# Optional: ramp_drop (leave the old sheet's N lightest colours out of the ramp), white_to / pale_to (recolour
# near-white / pale pixels, see recolour), scale (nearest enlargement about the anchor point, box in scaled px),
# tail_px (drop trailing one-shot frames with fewer opaque pixels), t0 / t1 (keep frames in [t0, t1] s, loops too),
# marker (name in MARKERS: cut pixels drawn in a marker colour), symmetric, glow_fade (alpha threshold), fade_out (frames).
EFFECTS = {
    "hit_spark":    dict(id="impacts/hit-spark",    old="hit_spark",    fps=16, opts={"height": 12}, point=(0, -12), box=(-36, -44, 52, 20),
                         ramp_drop=3, white_to="#ffc23d", pale_to="#f08a24", scale=1.5, tail_px=24),
    "crit_hit":     dict(id="impacts/crit-hit",     old="hit_spark",    fps=16, opts={"height": 12}, point=(0, -12), box=(-48, -40, 48, 16), edge=16,
                         tail_px=24),
    # the hazard cloud lives balance monsters.<kind>.cloud_time = 2.0 s: only its first 2.0 s (28 frames) are shown
    "poison_mist":  dict(id="nature/poison-cloud",  old="poison_mist",  fps=14, opts={"spread": 0.34}, point=(0, 0), box=(-44, -44, 44, 10),
                         t1=27 / 14),
    "status_burn":  dict(id="status/burning",       old="status_burn",  fps=15, actor="monster", cut=True, point=(0, 0), box=(-36, -70, 36, 10)),
    "status_frost": dict(id="status/frozen",        old="status_frost", fps=14, actor="monster", cut=True, cut_dx=1, point=(0, 0), box=(-28, -60, 28, 10)),
    "pickup_pop":   dict(id="pickups/collect-burst", old="pickup_pop",  fps=15, point=(0, -30), box=(-36, -36, 36, 34)),
    # the warp fade-out (test_ground FADE_OUT) is 0.5 s: 7 frames at 14 fps from just after the burst (PixelFX POP
    # = 0.52 s; its first frame at 0.57 s is a solid ball over the hero's head, so the sheet starts one frame later)
    "warp_blink":   dict(id="arcane/blink-out",     old="warp_ring",    fps=14, actor="spark", point=(0, 0), box=(-48, -64, 48, 12),
                         t0=9 / 14, t1=15 / 14, white_to="#86f07a"),
}

# The fire ramp (= the old PixelLab status_burn sheet's colours, as status_burn's own PixelFX palette).
# Owner 2026-11-09 fire picks (spec 2026-11-08-gem-combos.md last addendum; samples: /home/claude/fx_samples/notes.md):
# fire_trail = T2 fire/campfire (the trail patches of ศรพัดเพลิง / พรหมาสตร์), fire_blast = B2 explosions/grenade (the
# line-end blast of พรหมาสตร์, the grenade's blast only: 1.667-2.2 s, its anchor on the burst 39 px from PixelFX's pivot).
WOOD_MARK = ["#0000ff", "#0008f8", "#0010f0", "#0018e8", "#0020e0", "#0028d8"]   # campfire logs in pure-blue marker shades
EFFECTS["fire_trail"] = dict(id="fire/campfire", old="status_burn", fps=15, opts={"wood": WOOD_MARK, "height": 20, "seed": 3},
                             marker="blue", point=(0, 0), box=(-22, -44, 22, 5), symmetric=True, glow_fade=200)
EFFECTS["fire_blast"] = dict(id="explosions/grenade", old="status_burn", fps=15, opts={"seed": 6}, point=(39, 0), box=(-32, -52, 32, 10),
                             t0=25 / 15, t1=25 / 15 + 8 / 15, tail_px=8, symmetric=True, glow_fade=200, fade_out=3)

# Marker tests: a pixel drawn in the marker colour (no fire colour has blue 40 above red and green).
MARKERS = {"blue": lambda p: p[2] > p[0] + 40 and p[2] > p[1] + 40}

def marker_cut(f, test):
    """Cut every pixel the test calls a marker (a prop drawn in a marker colour, e.g. the campfire's logs)."""
    f = f.copy(); px = f.load()
    for y in range(f.size[1]):
        for x in range(f.size[0]):
            p = px[x, y]
            if p[3] and test(p): px[x, y] = (0, 0, 0, 0)
    return f

def glow_fade(c, gf):
    """Translucent pixels (0 < alpha < gf: PixelFX's soft light, thin smoke) fade out radially from the cell centre
    (smoothstep over the outer 55 % of the ellipse), so the light never shows as a rectangle; solid pixels are kept."""
    cw, ch = c.size; px = c.load()
    rx, ry = cw / 2.0, ch / 2.0
    for y in range(ch):
        for x in range(cw):
            r, g, b, a = px[x, y]
            if 0 < a < gf:
                dd = math.hypot((x + 0.5 - rx) / rx, (y + 0.5 - ry) / ry)
                u = min(1.0, max(0.0, (1.0 - dd) / 0.55))
                a2 = int(round(a * u * u * (3 - 2 * u)))
                px[x, y] = (r, g, b, a2) if a2 >= ALPHA_FLOOR else (0, 0, 0, 0)
    return c

def check_commit(pfx_dir):
    """The PixelFX checkout must be the commit the licence notice and manifest name, with nothing changed in it."""
    try:
        head = subprocess.run(["git", "-C", pfx_dir, "rev-parse", "--short=%d" % len(COMMIT), "HEAD"], check=True, capture_output=True, text=True).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        sys.exit("pixelfx_export: cannot read the PixelFX checkout's commit (%s)" % e)
    if head != COMMIT:
        sys.exit("pixelfx_export: PixelFX checkout is at %s, want %s (check out %s first)" % (head, COMMIT, COMMIT))
    # review 2026-11-09: also clean (no edited, staged or untracked files), so the sheets are what COMMIT renders
    try:
        dirty = subprocess.run(["git", "-C", pfx_dir, "status", "--porcelain"], check=True, capture_output=True, text=True).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        sys.exit("pixelfx_export: cannot read the PixelFX checkout's status (%s)" % e)
    if dirty:
        sys.exit("pixelfx_export: PixelFX checkout has uncommitted changes (git status --porcelain):\n%s\n"
                 "stash or reset them first (the export must be exactly %s)" % (dirty, COMMIT))

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

def spark_actor(w=8, h=8, chest=-26):
    """An invisible actor for the warp sparkle: a box round the hero's chest with an empty mask and no pixels, so
    blink-out draws no lit body, outline, squeezed figure or afterimage, and bursts out of the chest as a ball."""
    y0 = chest - h // 2
    return {"mask": {"w": w, "h": h, "data": [0] * (w * h)}, "pixels": [0] * (w * h), "x": -w // 2, "y": y0, "w": w, "h": h,
            "k": 2, "head": [0, y0], "chest": [0, chest]}

def recolour(f, white_to=None, pale_to=None):
    """Owner 2026-11-09: less white. Near-white pixels (saturation < 0.2, value > 0.88; PixelFX draws cores, ray
    roots and sparks in hard-coded white, and its light brightens pixels to white) take white_to; pale ones
    (saturation < 0.45, value > 0.9) take pale_to. Alpha is kept."""
    if not white_to and not pale_to: return f
    hx = lambda c: tuple(int(c[i:i + 2], 16) for i in (1, 3, 5))
    w = hx(white_to) if white_to else None
    q = hx(pale_to) if pale_to else None
    f = f.copy(); px = f.load()
    for y in range(f.size[1]):
        for x in range(f.size[0]):
            r, g, b, a = px[x, y]
            if a == 0: continue
            _, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
            if w and s < 0.2 and v > 0.88: px[x, y] = w + (a,)
            elif q and s < 0.45 and v > 0.9: px[x, y] = q + (a,)
    return f

def opaque_px(f, a_min=128):
    a_ = f.getchannel("A")
    return sum(1 for a in (a_.get_flattened_data() if hasattr(a_, "get_flattened_data") else a_.getdata()) if a >= a_min)

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
    if cfg.get("ramp_drop"): pal = pal[:-cfg["ramp_drop"]]
    opts = dict(cfg.get("opts", {})); opts["palette"] = pal
    if cfg.get("actor"): opts["actor"] = actors[cfg["actor"]]
    frames, pm = render(pfx_dir, cfg, opts, work)
    fw, fh = pm["frameSize"]; ox, oy = pm["pivot"]; fps = pm["fps"]; loop = pm["loop"]
    # trim (one-shots only)
    t0, t1 = cfg.get("t0", 0.0), cfg.get("t1", 1e9)
    frames = [f for i, f in enumerate(frames) if t0 - 1e-6 <= i / fps <= t1 + 1e-6]
    frames = [recolour(unpremultiply(f), cfg.get("white_to"), cfg.get("pale_to")) for f in frames]
    if cfg.get("marker"): frames = [marker_cut(f, MARKERS[cfg["marker"]]) for f in frames]
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
    k = cfg.get("scale", 1)
    if k != 1:   # enlarge about the anchor point: it stays on a whole pixel, the rest is nearest-neighbour
        ax, ay = ox + cfg["point"][0], oy + cfg["point"][1]
        nw, nh = round(fw * k), round(fh * k)
        nax, nay = round(ax * k), round(ay * k)
        frames = [f.resize((nw, nh), Image.NEAREST) for f in frames]
        ox, oy = nax - cfg["point"][0], nay - cfg["point"][1]
        fw, fh = nw, nh
    # crop: union bbox of the frames, inside the box round the anchor point
    px0, py0 = ox + cfg["point"][0], oy + cfg["point"][1]
    bx0, by0, bx1, by1 = (px0 + cfg["box"][0], py0 + cfg["box"][1], px0 + cfg["box"][2], py0 + cfg["box"][3])
    ux0, uy0, ux1, uy1 = fw, fh, 0, 0
    for f in frames:
        b = f.getbbox()
        if b: ux0, uy0, ux1, uy1 = min(ux0, b[0]), min(uy0, b[1]), max(ux1, b[2]), max(uy1, b[3])
    cx0, cy0, cx1, cy1 = max(ux0, bx0, 0), max(uy0, by0, 0), min(ux1, bx1, fw), min(uy1, by1, fh)
    if cfg.get("symmetric"):   # the anchor centred across the cell (trail patches line up on the path)
        half = max(px0 - cx0, cx1 - px0); cx0, cx1 = max(0, px0 - half), min(fw, px0 + half)
    clipped = {"l": ux0 < cx0, "t": uy0 < cy0, "r": ux1 > cx1, "b": uy1 > cy1}
    cw, ch = cx1 - cx0, cy1 - cy0
    out = []
    for f in frames:
        c = f.crop((cx0, cy0, cx1, cy1))
        if cfg.get("glow_fade"): glow_fade(c, cfg["glow_fade"])
        px = c.load()
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
    if not loop:   # tail frames of only stray dots (counted in the cropped cell, as the game shows it)
        while len(out) > 1 and opaque_px(out[-1]) < cfg.get("tail_px", 1): out.pop()
        frames = frames[:len(out)]
    k_out = cfg.get("fade_out", 0)   # a one-shot trimmed mid-effect: its last frames ease out instead of popping off
    for j in range(k_out):
        f = out[len(out) - k_out + j]; px = f.load(); m = (k_out - j) / (k_out + 1.0)
        for y in range(ch):
            for x in range(cw):
                r, g, b, a = px[x, y]
                if a: px[x, y] = (r, g, b, int(a * m)) if a * m >= ALPHA_FLOOR else (0, 0, 0, 0)
    n = len(out)
    rows = (n + max(1, MAX_SIDE // cw) - 1) // max(1, MAX_SIDE // cw)   # fewest rows that fit 2048 px across,
    cols = (n + rows - 1) // rows                                        # then the frames spread evenly (no empty row tail)
    assert rows * ch <= MAX_SIDE, "%s: sheet too tall" % name
    sheet = Image.new("RGBA", (cols * cw, rows * ch), (0, 0, 0, 0))
    for i, c in enumerate(out): sheet.paste(c, ((i % cols) * cw, (i // cols) * ch))
    sheet_name = "pfx_%s.png" % name
    sheet.save(os.path.join(fx_dir, sheet_name), optimize=True)
    shown_opts = {k: v for k, v in opts.items() if k != "actor"}
    if cfg.get("actor"): shown_opts["actor"] = {"monster": "average monster silhouette (assets/monsters + assets/wolf poses)", "hero": "hero idle_south frame 0",
                                                "spark": "invisible 8x8 box at the hero's chest (no figure drawn)"}[cfg["actor"]]
    entry = {"cell": [cw, ch], "frames": n, "fps": fps, "anchor": [px0 - cx0, py0 - cy0], "loop": loop, "columns": cols,
             "sheet": sheet_name,
             "pixelfx": {"id": cfg["id"], "commit": COMMIT, "options": shown_opts, "palette_from": cfg["old"] + ".png",
                         "trim_s": [t0, min(t1, (len(frames) - 1) / fps + t0)] if (not loop or "t1" in cfg) else None,
                         "post": {k_: cfg[k_] for k_ in ("ramp_drop", "white_to", "pale_to", "scale", "tail_px", "marker", "symmetric", "glow_fade", "fade_out")
                                  if k_ in cfg} or None,
                         "body_cut": bool(cfg.get("cut")), "crop": [cx0 - px0, cy0 - py0, cx1 - px0, cy1 - py0]}}
    return entry

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pixelfx", required=True)
    ap.add_argument("--only", default="")
    ap.add_argument("--work", default="")
    a = ap.parse_args()
    check_commit(a.pixelfx)
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    work = a.work or tempfile.mkdtemp(prefix="pixelfx_")
    actors = {"monster": monster_actor(root), "hero": hero_actor(root), "spark": spark_actor()}
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
