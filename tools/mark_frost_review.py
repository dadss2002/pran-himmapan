"""Owner review images for M5b Task 7 (mark and frost combos), from the in-game frames that
tests/screenshots_m5b_mark_frost.gd writes to /tmp/t7_shots (frames + meta.json). Run after that script:
    python3 -I tools/mark_frost_review.py
Writes docs/preview/m5b/t7_*.png: each case at game size (the 1280x720 frame, 1:1) and x3 (nearest), the r32 ring
(dotted, drawn here, not in the game) round the shatter, and t7_mark_frost_review.png with numbered red circles and a
Thai legend:
  1 ศรตาเหยี่ยว mark (white lock_on on the body) vs the targeting ring at the feet
  2 ศรเนตรพญาครุฑ mark (gold)
  3 plain / slowed / frozen, same kind, light ground (c1r0)
  4 the same on dark ground (c2r0)
  5 the อโนดาต shatter at 0.07 / 0.13 / 0.33 s vs the r32 ring (as played, and with the other hit effects hidden)
  6 the frost arrow streak (ศรเกล็ดน้ำแข็ง)
Nothing is drawn by hand except the labels, the dotted r32 ring and the red circles: every effect pixel is the game's.

Task 7 review fix (owner 2026-11-10): after `T7_FIX=1 xvfb-run -a godot ... --script tests/screenshots_m5b_mark_frost.gd`
    python3 -I tools/mark_frost_review.py --fix
writes docs/preview/m5b/t7_fix_*.png and t7_fix_review.png:
  1 the red ตาเหยี่ยว mark vs the targeting ring, game size and x3, light (c1r0) and dark (c2r0) ground
  2 plain / slowed / frozen with the ice block, light c1r0
  3 the same on c2r0
  4 the ครุฑ gold mark next to the red ตาเหยี่ยว mark (and the targeting ring on a third monster)
"""
import json, math, os
from PIL import Image, ImageDraw, ImageFont

SHOTS = "/tmp/t7_shots"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs/preview/m5b")
UI = 2.0            # screenshot px per root (UI) px, as tools/fire_fx_review.py
R = 32              # อโนดาต blast_radius (world px)
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


def badge(im, xy, n, r=22):
    d = ImageDraw.Draw(im)
    d.ellipse((xy[0] - r, xy[1] - r, xy[0] + r, xy[1] + r), fill=(214, 36, 36), outline=(255, 255, 255), width=3)
    w = d.textlength(str(n), font=f_big)
    d.text((xy[0] - w / 2, xy[1] - 14), str(n), font=f_big, fill=(255, 255, 255))


def circle(im, box, n):
    d = ImageDraw.Draw(im)
    d.ellipse(box, outline=(230, 30, 30), width=5)
    badge(im, (box[0] + 6, box[1] + 6), n)


def mark_case(case, tag):
    """Moments a (A marked + the ring on A) and b (ring moved to B, A keeps the mark): game size crops and x3."""
    out = {}
    for mo in ("a", "b"):
        full = shot(case, mo)
        save(full, "t7_%s_%s.png" % (tag, mo))
        m = meta[case]["moments"][mo]
        # every marked / targeted thing in view: A's body and feet, the targeting ring, B's feet (moment b)
        pts = [px(m["a_feet"]), px(m["a_hurt"]), px(m["ring"])] + ([px(m["b_feet"])] if "b_feet" in m else [])
        cx = (min(p[0] for p in pts) + max(p[0] for p in pts)) / 2
        cy = (min(p[1] for p in pts) + max(p[1] for p in pts)) / 2
        g1, o1 = crop(full, (cx, cy - 10), 420, 300)
        x3, o3 = crop(full, (cx, cy - 15), 260, 250, 3)
        out[mo] = (full, g1, o1, x3, o3)
    a_g, b_g = out["a"][1], out["b"][1]
    label(a_g, "game size: A marked + target ring on A")
    label(b_g, "game size: ring moved to B, A keeps the mark")
    a3, b3 = out["a"][3], out["b"][3]
    label(a3, "x3  A: mark (body) + ring (feet)")
    label(b3, "x3  A: mark only / B: ring only")
    save(row([a_g, b_g]), "t7_%s.png" % tag)
    save(row([a3, b3]), "t7_%s_x3.png" % tag)
    return out


def frost_case(case, tag, title):
    full = shot(case, "a")
    save(full, "t7_%s_full.png" % tag)
    feet = [px(p) for p in meta[case]["feet"]]
    c = (sum(p[0] for p in feet) / 3, feet[0][1] - 45)
    g1, o1 = crop(full, c, 480, 240)
    label(g1, "%s game size: plain / slowed / frozen" % title)
    x3, o3 = crop(full, (c[0], c[1] + 5), 430, 170, 3)
    label(x3, "%s x3: plain | slowed | frozen (%s)" % (title, meta[case]["kind"]))
    d = ImageDraw.Draw(x3)
    for i, t in enumerate(("plain", "slowed", "frozen")):
        x = (feet[i][0] - o3[0]) * 3
        w = d.textlength(t, font=f_small)
        d.rectangle((x - w / 2 - 4, x3.height - 30, x + w / 2 + 4, x3.height - 8), fill=(0, 0, 0))
        d.text((x - w / 2, x3.height - 30), t, font=f_small, fill=(255, 255, 255))
    save(g1, "t7_%s.png" % tag)
    save(x3, "t7_%s_x3.png" % tag)
    return g1, x3


def shatter_case():
    m = meta["shatter"]
    c = px(m["burst"])
    r = R * world("shatter")
    names = {"1": "0.07 s", "2": "0.13 s", "5": "0.33 s"}
    rows = []
    for kind, what in (("f", "as played"), ("o", "shatter only (glare, sparks, numbers hidden)")):
        panels = []
        for fr in ("1", "2", "5"):
            z, (x0, y0) = crop(shot("shatter", kind + fr), (c[0], c[1]), 200, 200, 3)
            ring(z, ((c[0] - x0) * 3, (c[1] - y0) * 3), r * 3, 2)
            label(z, "%s  %s" % (what, names[fr]))
            panels.append(z)
        rows.append(row(panels))
    save(shot("shatter", "f2"), "t7_shatter_full.png")
    g, _ = crop(shot("shatter", "f2"), (c[0] - 60, c[1] - 20), 420, 260)
    label(g, "game size 0.13 s (as played)")
    save(g, "t7_shatter.png")
    x3 = save(col(rows), "t7_shatter_x3.png")
    return g, x3


def streak_case():
    m = meta["streak"]
    full = shot("streak", "a")
    save(full, "t7_streak_full.png")
    arrows = sorted((px(p) for p in m["arrows"]), key=lambda p: p[1])
    mid = arrows[len(arrows) // 2]
    hero = px(m["hero"])
    g, _ = crop(full, ((hero[0] + mid[0]) / 2 + 40, mid[1] - 10), 520, 260)
    label(g, "game size, 0.25 s after the release")
    x3, _ = crop(full, (mid[0] - 30, mid[1]), 200, 120, 3)
    label(x3, "x3 the three arrows")
    save(g, "t7_streak.png")
    save(x3, "t7_streak_x3.png")
    return g, x3


def main():
    os.makedirs(OUT, exist_ok=True)
    hk = mark_case("mark_hawk", "mark_hawk")
    gd = mark_case("mark_garuda", "mark_garuda")
    fl = frost_case("frost_light", "frost_light", "light c1r0")
    fd = frost_case("frost_dark", "frost_dark", "dark c2r0")
    sh = shatter_case()
    st = streak_case()

    W = 1290
    def fit(im, w=W):
        return im if im.width <= w else im.resize((w, round(im.height * w / im.width)), Image.NEAREST)

    def mark_panel(out, case, n):
        a3, b3 = out["a"][3], out["b"][3]
        p = fit(row([a3, b3]))
        k = p.width / (a3.width + 8 + b3.width)
        ma = meta[case]["moments"]["a"]
        _, _, _, _, o3 = out["a"]
        hx, hy = (px(ma["a_hurt"])[0] - o3[0]) * 3 * k, (px(ma["a_hurt"])[1] - o3[1]) * 3 * k
        fy = (px(ma["a_feet"])[1] - o3[1]) * 3 * k
        circle(p, (hx - 110 * k, hy - 80 * k, hx + 110 * k, fy + 50 * k), n)
        return p

    p1 = mark_panel(hk, "mark_hawk", 1)
    p1g = fit(row([hk["a"][1], hk["b"][1]]))
    p2 = mark_panel(gd, "mark_garuda", 2)
    p3 = fit(fl[1])
    circle(p3, (p3.width // 3 - 20, 30, p3.width - 20, p3.height - 30), 3)
    p4 = fit(fd[1])
    circle(p4, (p4.width // 3 - 20, 30, p4.width - 20, p4.height - 30), 4)
    p5 = fit(sh[1])
    circle(p5, (20, 20, p5.width // 3 - 20, p5.height // 2 - 10), 5)
    p6 = fit(row([st[1], st[0]]))
    circle(p6, (30, 40, st[1].width * p6.width / (st[1].width + 8 + st[0].width) - 30, p6.height - 20), 6)
    k = meta["frost_light"]["kind"]
    legend = [
        "1. ศรตาเหยี่ยว: มาร์กสีขาว (lock_on) บนลำตัว เทียบวงล็อกเป้าปกติที่เท้า — ซ้าย A ติดมาร์กและเป็นเป้า (มีทั้งสองวง) · ขวา B เป็นเป้า A ติดมาร์กอย่างเดียว",
        "   (แถวกลาง: ขนาดเกม 1:1 คู่เดียวกัน)",
        "2. ศรเนตรพญาครุฑ: มาร์กสีทอง (#edbb55) บนลำตัว เทียบวงล็อกเป้าที่เท้า (ซ้าย/ขวา แบบเดียวกับข้อ 1)",
        "3. พื้นสว่าง (c1r0) %s ตัวเดียวกัน 3 ตัว: ปกติ / ช้า (เจมน้ำแข็ง) / แข็ง (คอมโบ) ขนาดเกม" % k,
        "4. พื้นเข้ม (c2r0) ปกติ / ช้า / แข็ง (%s)" % meta["frost_dark"]["kind"],
        "5. แตกผลึกอโนดาต (spread_burst สีฟ้า) เทียบวงดาเมจ r32 (วงจุดขาว วาดเพิ่มในภาพนี้เท่านั้น) ที่ 0.07 / 0.13 / 0.33 วิ",
        "   แถวบน: ตามที่เล่นจริง (มีประกายคริ/ลูกศรทับ) · แถวล่าง: ซ่อนเอฟเฟกต์โดนอื่นให้เห็นผลึกอย่างเดียว",
        "6. ศรเกล็ดน้ำแข็ง: แสงหางน้ำแข็ง (piercing_trail สีฟ้า) ติดลูกศร 3 ดอก 0.25 วิหลังยิง (ซ้าย ×3 ดอกกลาง, ขวาขนาดเกม)",
    ]
    lh = 30
    leg = Image.new("RGB", (W, lh * len(legend) + 20), PAPER)
    d = ImageDraw.Draw(leg)
    for i, t in enumerate(legend):
        d.text((12, 10 + i * lh), t, font=f_small, fill=INK)
    title = Image.new("RGB", (W, 44), PAPER)
    ImageDraw.Draw(title).text((12, 8), "M5b Task 7: มาร์ก (ตาเหยี่ยว / ครุฑ) และน้ำแข็ง (เกล็ดน้ำแข็ง / อโนดาต) — ภาพจริงในเกม 1280×720",
                               font=f_big, fill=INK)
    save(col([title, p1, p1g, p2, p3, p4, p5, p6, leg]), "t7_mark_frost_review.png")


def fix_main():
    os.makedirs(OUT, exist_ok=True)
    hk = mark_case("mark_hawk", "fix_mark_hawk")
    hd = mark_case("mark_hawk_dark", "fix_mark_hawk_dark")
    fl = frost_case("frost_light", "fix_frost_light", "light c1r0")
    fd = frost_case("frost_dark", "fix_frost_dark", "dark c2r0")
    pm = meta["marks_pair"]
    full = shot("marks_pair", "a")
    save(full, "t7_fix_marks_pair_full.png")
    feet = [px(p) for p in pm["feet"]]
    hurt = [px(p) for p in pm["hurt"]]
    cx = (min(p[0] for p in feet) + max(p[0] for p in feet)) / 2
    cy = (min(p[1] for p in hurt) + max(p[1] for p in feet)) / 2
    pg, _ = crop(full, (cx, cy - 40), 420, 300)
    label(pg, "game size: A red (ตาเหยี่ยว) / B gold (ครุฑ) / C target ring")
    ab = ((hurt[0][0] + hurt[1][0]) / 2, (hurt[0][1] + hurt[1][1]) / 2)
    p3, o3 = crop(full, (ab[0], ab[1] - 5), 300, 150, 3)
    label(p3, "x3  A red mark (ตาเหยี่ยว) | B gold mark (ครุฑ)")
    save(pg, "t7_fix_marks_pair.png")
    save(p3, "t7_fix_marks_pair_x3.png")

    W = 1290
    def fit(im, w=W):
        return im if im.width <= w else im.resize((w, round(im.height * w / im.width)), Image.NEAREST)

    def x3_pair(out):
        return row([out["a"][3], out["b"][3]])

    p1 = fit(col([x3_pair(hk), row([hk["a"][1], hk["b"][1]]), x3_pair(hd), row([hd["a"][1], hd["b"][1]])]))
    k1 = p1.width / max(x3_pair(hk).width, 1)
    ma = meta["mark_hawk"]["moments"]["a"]; o = hk["a"][4]
    hx, hy = (px(ma["a_hurt"])[0] - o[0]) * 3 * k1, (px(ma["a_hurt"])[1] - o[1]) * 3 * k1
    circle(p1, (hx - 120 * k1, hy - 90 * k1, hx + 120 * k1, hy + 90 * k1), 1)
    p2 = fit(col([fl[1], fl[0]]))
    circle(p2, (p2.width // 3 - 20, 30, p2.width - 20, fl[1].height * p2.width / max(fl[1].width, 1) - 30), 2)
    p3b = fit(col([fd[1], fd[0]]))
    circle(p3b, (p3b.width // 3 - 20, 30, p3b.width - 20, fd[1].height * p3b.width / max(fd[1].width, 1) - 30), 3)
    p4 = fit(col([p3, pg]))
    k4 = p4.width / p3.width
    xa, ya = (hurt[0][0] - o3[0]) * 3 * k4, (hurt[0][1] - o3[1]) * 3 * k4
    xb = (hurt[1][0] - o3[0]) * 3 * k4
    circle(p4, (max(4, xa - 110 * k4), max(4, ya - 100 * k4), min(p4.width - 4, xb + 110 * k4), min(p3.height * k4 - 4, ya + 100 * k4)), 4)
    kl, kd = meta["frost_light"]["kind"], meta["frost_dark"]["kind"]
    legend = [
        "1. ศรตาเหยี่ยว: มาร์กเปลี่ยนเป็นสีแดง #ff3050 (lock_on ย้อมแดง) บนลำตัว เทียบวงล็อกเป้าปกติ (สีเหลือง) ที่เท้า",
        "   แถว 1–2 พื้นสว่าง c1r0 (×3 แล้วขนาดเกม) · แถว 3–4 พื้นเข้ม c2r0 · ซ้าย A ติดมาร์กและเป็นเป้า · ขวา เป้าย้ายไป B A ติดมาร์กอย่างเดียว",
        "2. พื้นสว่าง c1r0 (%s): ปกติ / ช้า (เหมือนเดิม) / แข็ง = สีซีดขาวขึ้น #dcf3ff + ก้อนน้ำแข็งรอบตัว (วาดเอง 0 gen) · ×3 แล้วขนาดเกม" % kl,
        "3. พื้นเข้ม c2r0 (%s): ปกติ / ช้า / แข็ง (ก้อนน้ำแข็งพอดีลำตัวตามชนิดและทิศที่หัน)" % kd,
        "4. มาร์กครุฑสีทอง #edbb55 (B) ข้างมาร์กตาเหยี่ยวสีแดง (A) ×3 · ภาพล่างขนาดเกม: C ที่ใกล้ฮีโร่สุดมีวงล็อกเป้าที่เท้า",
        "   ก้อนน้ำแข็งหายทันทีเมื่อหมดแข็ง และไม่ถูกโหมดประหยัด (PerfSaver) ตัดทิ้ง · มาร์กไม่ถูกตัดเช่นกัน",
    ]
    lh = 30
    leg = Image.new("RGB", (W, lh * len(legend) + 20), PAPER)
    d = ImageDraw.Draw(leg)
    for i, t in enumerate(legend):
        d.text((12, 10 + i * lh), t, font=f_small, fill=INK)
    title = Image.new("RGB", (W, 44), PAPER)
    ImageDraw.Draw(title).text((12, 8), "M5b Task 7 แก้ตามรีวิว: มาร์กตาเหยี่ยวสีแดง · แข็ง = ก้อนน้ำแข็ง — ภาพจริงในเกม 1280×720",
                               font=f_big, fill=INK)
    save(col([title, p1, p2, p3b, p4, leg]), "t7_fix_review.png")


if __name__ == "__main__":
    import sys
    fix_main() if "--fix" in sys.argv else main()
