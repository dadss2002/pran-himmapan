"""Owner review images for the fire picks (T2 fire/campfire trail, B2 grenade line-end blast), from the in-game frames
that tests/screenshots_m5b_fire_fx.gd writes to /tmp/fire_shots (frames + meta.json). Run after that script:
    python3 -I tools/fire_fx_review.py
Writes docs/preview/m5b/fire_t2_b2_*.png: each case at game size (the 1280x720 frame, 1:1) and x3 (nearest), the
per-patch frame offsets (three moments 0.2 s apart), the r32 ring (dotted, drawn here, not in the game) round the
middle line's blast, the owner's sample row next to the game at the same scale, and fire_t2_b2_review.png with
numbered red circles on what the owner should judge. Nothing is drawn by hand: every pixel of fire is the game's.

    python3 -I tools/fire_fx_review.py --small
after FIRE_SET=small xvfb-run ... --script tests/screenshots_m5b_fire_fx.gd (frames in /tmp/fire_shots_small): the trail
patches at the sample's size (owner 2026-11-09, FireTrail.PATCH_SCALE 0.4) -> docs/preview/m5b/fire_t2_small_*.png and
the numbered fire_t2_small_review.png (1 size vs hero / monster, 2 the sample next to the game at the same scale,
3 dark ground, 4 PerfSaver on, 5 the trail's end fade).
"""
import json, math, os, sys
from PIL import Image, ImageDraw, ImageFont

SMALL = "--small" in sys.argv
SHOTS = "/tmp/fire_shots_small" if SMALL else "/tmp/fire_shots"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs/preview/m5b")
SAMPLE_T = "/home/claude/fx_samples/trail_candidates.png"
SAMPLE_B = "/home/claude/fx_samples/blast_candidates.png"
UI = 2.0            # screenshot px per root (UI) px: world_to_screen gives root px, the 1280x720 frame is twice that
R = 32              # พรหมาสตร์ blast_radius (world px)
FONT = "/usr/share/fonts/opentype/tlwg/Loma-Bold.otf"
FONT_S = "/usr/share/fonts/opentype/tlwg/Loma.otf"
INK, PAPER = (235, 232, 222), (24, 24, 30)

meta = json.load(open(os.path.join(SHOTS, "meta.json")))
f_big, f_small = ImageFont.truetype(FONT, 22), ImageFont.truetype(FONT_S, 17)


def shot(case, moment):
    return Image.open(meta[case]["moments"][moment]["file"]).convert("RGB")


def px(p):
    return (p[0] * UI, p[1] * UI)


def world(case):   # screen px per world px
    return meta[case]["scale"] * UI


def crop(im, c, w, h, z=1):
    x0 = int(round(min(max(c[0] - w / 2, 0), im.width - w)))
    y0 = int(round(min(max(c[1] - h / 2, 0), im.height - h)))
    out = im.crop((x0, y0, x0 + w, y0 + h))
    return (out.resize((w * z, h * z), Image.NEAREST) if z != 1 else out), (x0, y0)


def ring(im, c, r, z=1):
    d = ImageDraw.Draw(im)
    for a in range(0, 360, 6):
        t0, t1 = math.radians(a), math.radians(a + 3)
        d.line((c[0] + r * math.cos(t0), c[1] + r * math.sin(t0), c[0] + r * math.cos(t1), c[1] + r * math.sin(t1)), fill=(255, 255, 255), width=max(1, z))


def label(im, text, xy=(8, 6)):
    d = ImageDraw.Draw(im)
    w = d.textlength(text, font=f_small)
    d.rectangle((xy[0] - 4, xy[1] - 2, xy[0] + w + 4, xy[1] + 20), fill=(0, 0, 0))
    d.text(xy, text, font=f_small, fill=(255, 255, 255))


def row(ims, gap=8, bg=PAPER):
    out = Image.new("RGB", (sum(i.width for i in ims) + gap * (len(ims) - 1), max(i.height for i in ims)), bg)
    x = 0
    for i in ims:
        out.paste(i, (x, 0)); x += i.width + gap
    return out


def col(ims, gap=8, bg=PAPER):
    out = Image.new("RGB", (max(i.width for i in ims), sum(i.height for i in ims) + gap * (len(ims) - 1)), bg)
    y = 0
    for i in ims:
        out.paste(i, (0, y)); y += i.height + gap
    return out


def save(im, name):
    p = os.path.join(OUT, name)
    im.save(p, optimize=True)
    print("wrote", os.path.relpath(p, ROOT), im.size)
    return im


def centre(pts):
    return (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))


def mid_blast(case):
    b = sorted((px(p) for p in meta[case]["blasts"]), key=lambda p: p[1])
    return b[len(b) // 2]


def trail_case(case, tag):
    full = save(shot(case, "a"), "fire_t2_b2_%s.png" % tag)
    pts = [px(p) for p in meta[case]["patches"]]
    c = centre(pts)
    near = min(pts, key=lambda p: (p[0] - c[0]) ** 2 + (p[1] - c[1]) ** 2)
    x3, _ = crop(full, (near[0], near[1] - 50), 240, 200, 3)
    label(x3, "%s  x3  (%s)" % (tag, meta[case]["room"]))
    save(x3, "fire_t2_b2_%s_x3.png" % tag)
    return full, x3, c


def blast_case(case, tag, moments=("f1", "f2", "f5")):
    full = save(shot(case, "f2"), "fire_t2_b2_%s.png" % tag)
    c = mid_blast(case)
    r = R * world(case)
    panels = []
    names = {"none": "no blast (same moment)", "f1": "0.07 s", "f2": "0.13 s", "f5": "0.33 s"}
    for m in moments:
        z, (x0, y0) = crop(shot(case, m), (c[0], c[1] - 20), 200, 200, 3)
        ring(z, ((c[0] - x0) * 3, (c[1] - y0) * 3), r * 3, 2)
        label(z, "%s  %s" % (tag, names[m]))
        panels.append(z)
    x3 = save(row(panels), "fire_t2_b2_%s_x3.png" % tag)
    return full, x3, c


def badge(im, xy, n, r=22):
    d = ImageDraw.Draw(im)
    d.ellipse((xy[0] - r, xy[1] - r, xy[0] + r, xy[1] + r), fill=(214, 36, 36), outline=(255, 255, 255), width=3)
    w = d.textlength(str(n), font=f_big)
    d.text((xy[0] - w / 2, xy[1] - 14), str(n), font=f_big, fill=(255, 255, 255))


def circle(im, box, n):
    d = ImageDraw.Draw(im)
    d.ellipse(box, outline=(230, 30, 30), width=5)
    badge(im, (box[0] + 6, box[1] + 6), n)


def main():
    os.makedirs(OUT, exist_ok=True)
    tl_full, tl_x3, tl_c = trail_case("trail_light", "trail_light")
    td_full, td_x3, _ = trail_case("trail_dark", "trail_dark")
    fa_full, fa_x3, fa_c = trail_case("fade", "fade")
    # flicker: the light lines at game size, three moments 0.2 s apart (every patch 3 frames on)
    seq = []
    for m, t in zip("abc", ("0.0", "0.2", "0.4")):
        z, _ = crop(shot("trail_light", m), (tl_c[0], tl_c[1] - 40), 560, 330)
        label(z, "game size, t = +%s s  frames %s" % (t, meta["trail_light"]["moments"][m]["frames"][:5]))
        seq.append(z)
    flick = save(row(seq), "fire_t2_b2_flicker.png")
    bl_full, bl_x3, _ = blast_case("blast_light", "blast_light")
    bd_full, bd_x3, _ = blast_case("blast_dark", "blast_dark")
    bm_full, bm_x3, _ = blast_case("blast_monster", "blast_monster", ("none", "f1", "f2", "f5"))
    sv_full, sv_x3, _ = blast_case("saver", "saver")
    # sample vs game at the same scale: the owner's T2 / B2 sample rows were drawn 1 sheet px = 1 screenshot px; the game
    # draws 1 world px = 2.5 screenshot px at 1280x720, so the sample is shown here x2.5 (nearest) next to the game 1:1
    k = world("trail_light")
    st = Image.open(SAMPLE_T).convert("RGB").crop((298, 356, 538, 536))          # T2 row, t = 0.4 s (240x180)
    st = st.resize((round(st.width * k), round(st.height * k)), Image.NEAREST)
    label(st, "owner's sample T2 (t=0.4 s) enlarged x%.1f = game scale" % k)
    gt, _ = crop(shot("trail_light", "a"), (tl_c[0], tl_c[1] - 40), st.width, st.height)
    label(gt, "in game, game size (1:1)")
    sb = Image.open(SAMPLE_B).convert("RGB").crop((50, 374, 178, 502))           # B2 row, 0.07 s (frame 1, 128x128)
    sb = sb.resize((round(sb.width * k), round(sb.height * k)), Image.NEAREST)
    label(sb, "sample B2 (0.07 s) x%.1f" % k)
    c = mid_blast("blast_light")
    gb, _ = crop(shot("blast_light", "f1"), (c[0], c[1] - 16), sb.width, sb.height)
    label(gb, "in game 0.07 s (1:1)")
    vs = save(col([row([st, gt]), row([sb, gb])]), "fire_t2_b2_vs_sample.png")

    # the review sheet: one panel per thing to judge, a numbered red circle on it
    W = 1290
    def fit(im, w=W):
        return im if im.width <= w else im.resize((w, round(im.height * w / im.width)), Image.NEAREST)
    p1 = fit(row([tl_x3, td_x3]))
    circle(p1, (p1.width // 4 - 150, 40, p1.width // 4 + 150, p1.height - 20), 1)
    p2 = fit(flick)
    circle(p2, (40, 30, p2.width // 3 - 30, p2.height - 10), 2)
    p3 = fit(row([fa_x3, crop(fa_full, (fa_c[0], fa_c[1] - 40), 560, 330)[0]]))
    circle(p3, (60, 60, 600, p3.height - 30), 3)
    p4 = fit(bl_x3)
    circle(p4, (p4.width // 3 + 40, 40, 2 * p4.width // 3 - 30, p4.height - 30), 4)
    p5 = fit(bm_x3)
    circle(p5, (p5.width // 4 + 30, 20, p5.width // 2 + 10, p5.height - 40), 5)
    p6 = sv_full.copy()                                      # the whole frame, game size: every patch and blast is there
    label(p6, "saver on (PerfSaver), game size, blasts at 0.13 s", (300, 690))
    pts = [px(q) for q in meta["saver"]["patches"]] + [px(q) for q in meta["saver"]["blasts"]]
    circle(p6, (min(q[0] for q in pts) - 70, min(q[1] for q in pts) - 150, max(q[0] for q in pts) + 90, max(q[1] for q in pts) + 50), 6)
    p7 = fit(bd_x3)
    circle(p7, (p7.width // 3 + 40, 40, 2 * p7.width // 3 - 30, p7.height - 30), 7)
    p8 = fit(vs)
    circle(p8, (20, 20, p8.width // 2 - 20, p8.height // 2), 8)
    legend = [
        "1. หน้าตากองไฟ T2 บนหญ้าสว่าง (ซ้าย) และพื้นเข้ม (ขวา) ซูม ×3 — ทุกกองคือสไปรต์ชีตเดียวกับตัวอย่าง (พิกเซลตรงกันทุกจุด)",
        "2. กองไฟไม่กะพริบพร้อมกัน: ภาพจริงขนาดเกม 3 ช่วง ห่างกัน 0.2 วิ แต่ละกองเริ่มเฟรมต่างกัน 3–11 เฟรม (ตัวเลขเฟรมที่หัวภาพ)",
        "3. ตอนเส้นไฟจะดับ: ทั้งเส้นจางลงใน 0.3 วิสุดท้าย (ภาพนี้จางเหลือ 44 %)",
        "4. ระเบิด B2 เทียบวงดาเมจ r32 (วงจุดขาว วาดเพิ่มในภาพนี้เท่านั้น ไม่มีในเกม) ที่ 0.07 / 0.13 / 0.33 วิ",
        "5. ระเบิดทับมอนสีเข้ม (หมูป่า): ก่อนระเบิด / 0.07 / 0.13 / 0.33 วิ (ประกายสีเหลืองบนตัวหมูคือ hit spark ของลูกศรที่ทะลุ)",
        "6. เปิดโหมดประหยัด (PerfSaver): กองไฟทุกกองและระเบิดยังอยู่ครบ เพราะเป็นพื้นที่ดาเมจ",
        "7. ระเบิดบนพื้นเข้ม (ห้อง c2r0)",
        "8. ตัวอย่างที่เจ้าของเลือก ขยายให้เท่าสเกลเกม (×2.5) เทียบกับในเกมจริง: ในเกมไฟใหญ่กว่าในภาพตัวอย่าง 2.5 เท่าเมื่อเทียบกับฉาก",
        "   (ตัวอย่างวางชีตลงบนภาพหน้าจอแบบ 1:1 แต่เกมวาดโลก ×2.5 ที่ 1280×720; สัดส่วนกับความยาวเส้น 220 และวง r32 เท่าเดิม)",
    ]
    lh = 30
    leg = Image.new("RGB", (W, lh * len(legend) + 20), PAPER)
    d = ImageDraw.Draw(leg)
    for i, t in enumerate(legend):
        d.text((12, 10 + i * lh), t, font=f_small, fill=INK)
    title = Image.new("RGB", (W, 44), PAPER)
    ImageDraw.Draw(title).text((12, 8), "ไฟใหม่ PixelFX: เส้นไฟ T2 (fire/campfire) + ระเบิดปลายเส้น B2 (explosions/grenade) — ภาพจริงในเกม",
                               font=f_big, fill=INK)
    save(col([title, p1, p2, p3, p4, p5, p6, p7, p8, leg]), "fire_t2_b2_review.png")


def main_small():
    """The trail patches at the sample's size (PATCH_SCALE 0.4): game size and x3 per case, the sample comparison and
    the numbered review image. Every patch in meta must be drawn at 0.4 and visible (checked here, not assumed)."""
    os.makedirs(OUT, exist_ok=True)
    for case in ("trail_light", "trail_dark", "fade", "trail_saver"):
        m = meta[case]
        bad = [q for q in m["patch_scale"] if abs(q[0] - 0.4) > 1e-3 or abs(q[1] - 0.4) > 1e-3]
        if bad or not all(m["patch_visible"]) or not m["patches"]:
            raise SystemExit("%s: patches %d, scales off %s, all visible %s" % (case, len(m["patches"]), bad, all(m["patch_visible"])))
    k = world("trail_light")                              # 2.5 screen px per world px

    def cases(case, tag, title):
        full = shot(case, "a")
        save(full, "fire_t2_small_%s.png" % tag)
        pts = [px(p) for p in meta[case]["patches"]]
        c = centre(pts)
        near = min(pts, key=lambda p: (p[0] - c[0]) ** 2 + (p[1] - c[1]) ** 2)
        x3, _ = crop(full, (near[0], near[1] - 20), 200, 150, 3)
        label(x3, "%s  x3  (%s)" % (title, meta[case]["room"]))
        save(x3, "fire_t2_small_%s_x3.png" % tag)
        return full, x3, c, near

    tl_full, tl_x3, tl_c, tl_near = cases("trail_light", "trail_light", "light ground")
    td_full, td_x3, td_c, _ = cases("trail_dark", "trail_dark", "dark ground")
    sv_full, sv_x3, sv_c, _ = cases("trail_saver", "saver", "PerfSaver on")
    fa_full, fa_x3, fa_c, _ = cases("fade", "fade", "fade, alpha %.2f" % meta["fade"]["trail_alpha"][0])

    # 1: size vs the hero and the monster on the line, game size (1:1) and x3 round the monster
    hero, aim = px(meta["trail_light"]["hero"]), px(meta["trail_light"]["aim"])
    g1, o1 = crop(tl_full, (hero[0] - 100 + 280, aim[1] - 30), 560, 330)       # the hero 100 px in from the left
    label(g1, "game size 1:1 (1280x720)")
    z1, oz = crop(tl_full, (aim[0], aim[1] - 30), 200, 150, 3)
    label(z1, "x3 round the monster")
    p1 = row([g1, z1])
    hx, hy = hero[0] - o1[0], hero[1] - o1[1]
    circle(p1, (hx - 60, hy - 150, aim[0] - o1[0] + 70, hy + 40), 1)

    # 2: the owner's T2 sample row next to the game, both x2.5 (nearest) from 240x180 screen px: the sample was pasted
    # 1 sheet px = 1 screen px on a 1:1 game screenshot, so at the same zoom the patches must now be the same size
    st = Image.open(SAMPLE_T).convert("RGB").crop((298, 356, 538, 536))          # T2 row, t = 0.4 s (240x180)
    gt, og = crop(tl_full, (tl_near[0] + 30, tl_near[1] - 40), 240, 180)
    pair1 = row([st, gt])
    st2 = st.resize((round(st.width * k), round(st.height * k)), Image.NEAREST)
    gt2 = gt.resize((round(gt.width * k), round(gt.height * k)), Image.NEAREST)
    label(st2, "owner's sample T2 (t=0.4 s)  x%.1f" % k)
    label(gt2, "in game now (patch 0.4)  x%.1f" % k)
    label(pair1, "both 1:1 (screen px)")
    # one patch x6: its sheet frame as the sample drew it (1 sheet px = 1 screen px, on the patch's own grass) next to
    # the same frame in game (the world viewport point-samples the 0.4 patch to world pixels, 2.5 screen px each)
    sheet = Image.open(os.path.join(ROOT, "assets/fx/pfx_fire_trail.png")).convert("RGBA")
    pts = [px(p) for p in meta["trail_light"]["patches"]]
    j = min(range(len(pts)), key=lambda i: (pts[i][0] - tl_c[0]) ** 2 + (pts[i][1] - tl_c[1]) ** 2)
    fr_n = meta["trail_light"]["moments"]["a"]["frames"][j]
    fx0, fy0 = int(round(pts[j][0] - 22)), int(round(pts[j][1] - 44)) - 1
    game1 = tl_full.crop((fx0 - 8, fy0 - 4, fx0 + 52, fy0 + 53))
    grass = Image.new("RGBA", game1.size, tl_full.getpixel((fx0 - 6, fy0 + 50)) + (255,))
    grass.alpha_composite(sheet.crop((fr_n * 44, 0, fr_n * 44 + 44, 49)), (8, 4))
    z6 = lambda im: im.convert("RGB").resize((im.width * 6, im.height * 6), Image.NEAREST)
    sa6, ga6 = z6(grass), z6(game1)
    label(sa6, "sample: frame %d, 1 px = 1 screen  x6" % fr_n)
    label(ga6, "in game: same frame  x6")
    vs = save(col([row([st2, gt2]), pair1, row([sa6, ga6])]), "fire_t2_small_vs_sample.png")
    p2 = vs.crop((0, 0, vs.width, st2.height + 8 + pair1.height))      # the x6 pair is in fire_t2_small_vs_sample.png
    p2b = row([sa6, ga6])
    inside = [(q[0] - og[0], q[1] - og[1]) for q in (px(p) for p in meta["trail_light"]["patches"])
              if 20 <= q[0] - og[0] <= 220 and 50 <= q[1] - og[1] <= 175]
    q = min(inside, key=lambda q: (q[0] - 120) ** 2 + (q[1] - 135) ** 2)    # a patch low in the crop (feet), clear of the label
    qx, qy = st2.width + 8 + q[0] * k, q[1] * k
    circle(p2, (qx - 90, qy - 160, qx + 90, qy + 40), 2)

    # 3: dark ground
    g3, _ = crop(td_full, (td_c[0], td_c[1] - 40), 560, 330)
    label(g3, "dark ground c2r0, game size")
    p3 = row([td_x3, g3])
    circle(p3, (150, 120, 470, 430), 3)

    # 4: PerfSaver on: every patch stays, the same size
    g4, o4 = crop(sv_full, (sv_c[0], sv_c[1] - 40), 560, 330)
    label(g4, "PerfSaver on, game size: %d patches (saver off: %d)" % (len(meta["trail_saver"]["patches"]), len(meta["trail_light"]["patches"])))
    p4 = row([sv_x3, g4])
    sp = [px(q) for q in meta["trail_saver"]["patches"]]
    x0 = sv_x3.width + 8
    circle(p4, (x0 + min(q[0] for q in sp) - o4[0] - 40, max(30, min(q[1] for q in sp) - o4[1] - 70),
                x0 + min(560, max(q[0] for q in sp) - o4[0] + 40), min(p4.height - 5, max(q[1] for q in sp) - o4[1] + 40)), 4)

    # 5: the trail's end: the same lines full (left) and fading (right), x3 at the same spot
    fp = [px(p) for p in meta["fade"]["patches"]]
    fc = centre(fp)
    fnear = min(fp, key=lambda p: (p[0] - fc[0]) ** 2 + (p[1] - fc[1]) ** 2)
    a5, _ = crop(tl_full, (fnear[0], fnear[1] - 20), 200, 150, 3)
    label(a5, "burning (alpha 1.0)  x3")
    b5, _ = crop(fa_full, (fnear[0], fnear[1] - 20), 200, 150, 3)
    label(b5, "last 0.3 s, alpha %.2f  x3" % meta["fade"]["trail_alpha"][0])
    p5 = row([a5, b5])
    circle(p5, (a5.width + 120, 100, a5.width + 480, 420), 5)

    W = 1290
    def fit(im, w=W):
        return im if im.width <= w else im.resize((w, round(im.height * w / im.width)), Image.NEAREST)
    legend = [
        "1. ขนาดกองไฟเทียบฮีโร่และมอน (ภาพขนาดเกม 1:1 ซ้าย, ซูม ×3 รอบมอนขวา): กองไฟสูงราว 49 พิกเซลจอ ราว 2/5 ของฮีโร่ เท้ากองอยู่บนทางลูกศร",
        "2. เทียบภาพตัวอย่าง T2: ขยาย ×2.5 ทั้งคู่ (บน), 1:1 ทั้งคู่ (กลาง), กองเดียวซูม ×6 (ล่าง) — ขนาดกองไฟเท่าตัวอย่างแล้ว",
        "   ที่ยังต่าง: (ก) พิกเซลไฟในเกมหยาบกว่าตัวอย่าง 2.5 เท่า: เกมวาดโลกที่ความละเอียดพิกเซลโลกแล้วค่อยขยาย กองไฟ 0.4 จึงถูกสุ่มจุด",
        "   เหลือราว 2 ใน 5 ของพิกเซลชีตต่อแกน (ประกายเล็กหลุด ขอบเป็นบล็อก)  (ข) กองห่างกัน 44 พิกเซลโลก = 110 พิกเซลจอ (ตัวอย่างห่าง ~44–55)",
        "3. บนพื้นเข้ม (ห้อง c2r0) ซูม ×3 และขนาดเกม",
        "4. เปิดโหมดประหยัด (PerfSaver): กองไฟอยู่ครบทุกจุด (13 กอง เท่าตอนปิด) ขนาดเท่าเดิม เพราะเป็นพื้นที่ดาเมจ",
        "5. ตอนเส้นไฟจะดับ: ซ้ายยังติดเต็ม ขวาคือ 0.3 วิสุดท้าย ทั้งเส้นจางลงพร้อมกัน (ภาพนี้เหลือ 44 %)",
        "   ดาเมจ/ระยะ/จำนวนกอง/ระเบิด B2 (1:1 = วง r32) ไม่เปลี่ยน · ในเกมพิกเซลไฟเท่ากริดโลก (ยังไม่ใช่ mixels ละเอียดแบบตัวอย่าง ดูข้อ 2)",
    ]
    lh = 30
    leg = Image.new("RGB", (W, lh * len(legend) + 20), PAPER)
    d = ImageDraw.Draw(leg)
    for i, t in enumerate(legend):
        d.text((12, 10 + i * lh), t, font=f_small, fill=INK)
    title = Image.new("RGB", (W, 44), PAPER)
    ImageDraw.Draw(title).text((12, 8), "เส้นไฟ T2 ย่อเท่าภาพตัวอย่าง (สเกล 0.4 ในโลก) — ภาพจริงในเกม 1280×720",
                               font=f_big, fill=INK)
    save(col([title, fit(p1), fit(p2), fit(p2b), fit(p3), fit(p4), fit(p5), leg]), "fire_t2_small_review.png")


if __name__ == "__main__":
    main_small() if SMALL else main()
