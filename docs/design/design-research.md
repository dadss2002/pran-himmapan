# หลักออกแบบฉาก ลานสู้ ภาพพิกเซล และ UI มือถือ (PRAN)

ศึกษาเมื่อ 2026-11-07 ตามคำขอเจ้าของ: "เรียนสกิลออกแบบเพิ่ม ศึกษาจากแหล่งฟรีมาปรับใช้ ศึกษามากกว่า 8 เว็บไซต์"
ใช้ทั้งหมด 14 แหล่ง (รายชื่ออยู่ท้ายเอกสาร) ทุกข้อด้านล่างสรุปด้วยภาษาของเราเอง และบอกว่าใช้กับเกมนี้อย่างไร
สกิลที่ Claude ใช้ทำงาน: `pran-scene-design` (เนื้อหาเดียวกับเอกสารนี้ แต่สั้นกว่า)

## 1. จัดวางฉากและห้อง top-down
1. **วางพื้นที่ว่างก่อนรายละเอียด** — กำหนดก่อนว่าตรงไหนต้องโล่ง (ลานสู้ ทางเดิน) แล้วค่อยวางของรอบ ๆ [GamineAI]
2. **จุดเด่นจุดเดียวต่อหน้าจอ** — ของที่ไม่ใช่จุดเด่นให้ใช้ความต่างแสงต่ำ ขนาดเล็ก หรือซ้อนหลังของใหญ่ [GamineAI]
3. **จับกลุ่ม อย่ากระจายเท่า ๆ กัน** — บางที่แน่น บางที่โล่ง [Game Developer: forests]
4. **ของเล็กอยู่รอบโคนของใหญ่** — พุ่ม ดอก เห็ด อยู่รอบโคนต้นไม้และหิน หินเล็กอยู่ข้างหินใหญ่ ช่วยบังรอยต่อโคนกับพื้น [Game Developer: forests, Polycount]
5. **ขอบป่าใช้ต้นไม้ทรงกลมซ้อนแถวแบบสลับฟันปลา** — ทรงเรียบ ๆ ซ้ำได้โดยไม่ดูผิด ซ้ำแล้วเปลี่ยนสีแทนการวาดใหม่ ส่วนต้นไม้ทรงแปลกใช้เป็นจุดเด่นแค่จุดเดียว [Slynyrd]
6. **ทุกชิ้นใช้มุมมองเดียวกัน (3/4 top-down)** — ของที่ตั้งขึ้นต้องมีเงาสั้นและนุ่มใต้ฐาน ไม่ลากยาวไปทางเดียว [Slynyrd] เงาสีดำโปร่งราว 40% เยื้องเล็กน้อยใช้ได้ทั่วไป [Stardew modding wiki]
7. **วาดจากหลังไปหน้า (เรียงตามแนว y ของเท้า)** — แยก "พื้นที่ที่วาด" (render) กับ "พื้นที่ที่กันทางเดิน" (occupancy) ออกจากกัน [Byte Arcane]
8. **พื้นป่าไม่ใช่หญ้าสูงเรียบ ๆ** — มีเฟิร์น ใบไม้ หินหลายขนาด ของล้มอย่างขอนหรือตอ [Game Developer: forests]
9. **น้ำต้องวางก่อน** — แล้วจัดป่ารอบน้ำ ริมน้ำวางหิน [Game Developer: forests]

ที่ใช้ในเกม: `tools/compose_room.py` ทำตามข้อ 1–7 (ห้อง e2)
- ตัดพื้นหญ้าจากห้องวาดเดิม เลือกเฉพาะชิ้นที่โทนกลาง แล้วต่อด้วยขอบหยัก
- เงาสั้นนุ่มใต้ของทุกชิ้น และวาดจากหลังไปหน้า
- ทางเดินคำนวณจากรอยเท้าของพร็อพ ไม่ใช้สีภาพ

## 2. ลานสู้และการวางมอน
1. **ให้ผู้เล่นได้ยืนดูก่อน (foothold)** — จากทางเข้าควรเห็นมอนที่ยังไม่รู้ตัว จะได้วางแผนก่อนเข้าไป ถ้าไม่มีจังหวะนี้ ผู้เล่นมักสู้อยู่หน้าประตู [Level Design Book: Encounter]
2. **มอนในห้องเดียวกันมี 1–2 แบบดีที่สุด** — 3 แบบเริ่มอ่านยาก 4 แบบควรแบ่งเป็นสองฝ่าย ถ้าใช้ 2 แบบให้มีความสัมพันธ์กัน เช่น ตัวประชิดคู่ตัวยิงไกล [Level Design Book: Encounter]
3. **ที่หลบคือการเคลื่อนที่** — วางสิ่งกีดขวาง 3–5 จุดให้วิ่งอ้อม/หลบกระสุนได้ (ในเกมนี้คือหลบลิงปาผลไม้) และต้องมีทางหนีเสมอ [Level Design Book: Encounter, Cover]
4. **บอกล่วงหน้าทุกท่าโจมตี (telegraph)** — ให้เวลาพอตอบสนอง และอ่านผังลานได้ง่าย ไม่ซับซ้อนเกิน [Level Design Book: Encounter]
5. **ลานต่อสู้คือสนามสเก็ต** — วิ่งวนได้รอบ มีของ "เกินกว่าที่รับไหวไปอีกนิด" แต่ไม่ล้นจนงง [Staffordshire level documentation]
6. **ทำให้ชัดว่าเคลียร์ห้องแล้ว** [Level Design Book: Encounter]

ที่ใช้ในเกม:
- กลุ่มมอนที่โจมตีก่อนต้องอยู่ห่างจุดโผล่วาร์ปเกินระยะ aggro (มีเทสต์คุมอยู่แล้ว)
- ห้อง e2 มีต้น/พุ่ม 4 จุดกลางลานไว้หลบ
- **ข้อสังเกตรอเจ้าของตัดสิน:** e2 และ w3 มีมอน 3 ชนิด ตามหลักข้อ 2 จะอ่านยากกว่า 2 ชนิด แต่ยังไม่แก้ เพราะเป็นตัวเลขที่อนุมัติแล้ว

## 3. ภาพพิกเซล: สี แสง เงา และความอ่านง่าย
1. **ค่าความสว่าง (value) มาก่อนสี** — ลองแปลงภาพเป็นขาวดำ ถ้ายังแยกตัวละคร มอน และพื้นออกจากกันได้ แปลว่าดี [Wayline, Icewyrm, pixnote]
2. **ตัวละครและมอนต้องสว่างและต่างแสงมากที่สุด** — พื้นและฉากหลังอยู่ในช่วงแสงแคบกว่าและมืดกว่า [Icewyrm]
3. **ใช้ความต่างแสงสูงเฉพาะจุดที่อยากให้มอง** — ถ้าทุกอย่างดึงสายตา ก็ไม่มีอะไรเด่น [Icewyrm]
4. **ความสดของสีต้องคงที่ทั้งฉาก** — อย่าเอาสีสดจัดไปปนกับสีหม่นแบบไม่ตั้งใจ [Pixel Palette Swap]
5. **รูปทรง (silhouette) สำคัญกว่ารายละเอียด** — ที่ขนาดเล็ก ความชัดสำคัญกว่าความละเอียด [Bugnet, GamineAI]

ที่ใช้ในเกม:
- ห้อง e2 หรี่พื้นลงเหลือ 86% และลดความสดลงเล็กน้อย
- ต้นไม้และพุ่มกลางลานหรี่ลงเหลือ 84% มอนและฮีโร่จึงเด่นที่สุด
- ขอบป่าหรี่ลง 78–90%

## 4. UI เกมมือถือ
1. **ปุ่มแตะต้องใหญ่พอ**
   - Apple ให้อย่างน้อย 44×44 pt ส่วน Material ให้ 48×48 dp และเว้นระยะห่างปุ่มอย่างน้อย 8 dp [OpenReplay]
   - ปุ่มควบคุมในเกมควรใหญ่ขนาดนิ้วโป้ง ราว 10 มม. [Smashing Magazine, UX Mag]
2. **ปุ่มหลักอยู่ในโซนนิ้วโป้ง** — คือส่วนล่างของจอ ถือแนวนอนจะใช้สองมือ [UX Mag, OpenReplay]
3. **ตัวอักษรขั้นต่ำ** — ข้อความทั่วไปบนมือถือราว 16 px เป็นมาตรฐาน และขนาดต้องโตตาม DPI ของจอ (Xbox XAG: 18 px ที่ 100 DPI, 36 px ที่ 200 DPI) [Xbox Accessibility Guidelines]
4. **ข้อความกับพื้นหลังด้านหลังต้องต่างแสงชัด** — ดูที่พื้นหลังตรงตำแหน่งข้อความ ไม่ใช่ค่าเฉลี่ยทั้งจอ [GamineAI UI readability]
5. **ฟอนต์ต้องวาดที่ความละเอียดจริงของจอ** — ไม่ขยายจากภาพเล็ก (เราแก้แล้วด้วย stretch mode canvas_items)

ที่ใช้ในเกม (ยังไม่ได้แก้ เสนอเป็นงานถัดไป):
- ปุ่มสกิลปัจจุบันรัศมี 20 px บนจอ UI กว้าง 360 คือราว 40 pt เล็กกว่า 44 pt เล็กน้อย
- ฟอนต์บางจุดใช้ 8–9 px ในพิกัดเกม บนมือถือจริงเท่ากับราว 9–10 pt เล็กกว่าที่แนะนำ

## แหล่งที่ศึกษา (14)
1. The Level Design Book — Encounter: https://book.leveldesignbook.com/process/combat/encounter (อ่านผ่าน mirror)
2. The Level Design Book — Cover: https://book.leveldesignbook.com/process/combat/cover
3. Slynyrd Pixelblog 21 — Top Down Objects: https://www.slynyrd.com/blog/2019/9/18/pixelblog-21-top-down-objects
4. Game Developer — Art Tips for Building Forests: https://www.gamedeveloper.com/art/art-tips-for-building-forests
5. Icewyrm Games — Reducing Visual Confusion: https://icewyrmgames.github.io/research/reducing-visual-confusion-in-your-game
6. Wayline — Color & Palettes, value before hue: https://www.wayline.io/learn/color-palettes/1
7. Polycount — natural environment placement: https://polycount.com/discussion/comment/1268633
8. Byte Arcane (Sigil of Kings) — props placement and render order: https://byte-arcane.github.io/sigil-of-kings-website/2018/04/05/autotiling-adventures-part-iv-mountains-trees-and-props
9. GamineAI — 10 Pixel Art Composition Rules: https://gamineai.com/blog/10-pixel-art-composition-rules-readability-in-game-2026
10. Pixel Palette Swap — Common Palette Mistakes: https://pixelpaletteswap.pages.dev/guides/common-palette-mistakes.html
11. Smashing Magazine — Finger-Friendly Design: https://www.smashingmagazine.com/2012/02/finger-friendly-design-ideal-mobile-touchscreen-target-sizes/
12. OpenReplay — Improving Tap Targets: https://blog.openreplay.com/improving-tap-targets-mobile-ux/
13. UX Mag — The Mobile Frontier (thumb zone): https://uxmag.com/articles/excerpt-from-the-new-book-the-mobile-frontier
14. Xbox Accessibility Guidelines 101 — Text display: https://devdocs.xbox.com/build/game-principles/accessibility/xag-deep-dives/xag-101-text-display.md

อ่านประกอบ: Stardew Valley modding wiki (เงา), pixnote (คำศัพท์ value), Bugnet (readability), Staffordshire level documentation (ลานสู้เหมือนสนามสเก็ต)
