# ศึกษาวิธีทำแผนที่ผืนใหญ่ไม่ให้เห็นรอยต่อ (M4a, 2026-11-07)

เจ้าของสั่ง: "อยากให้ศึกษาวิธีทำแผนที่จากแหล่งอื่นเพิ่ม"

ปัญหาของตัวอย่าง J1 ตอนนี้:
- ทางเดินต่อกันแล้ว แต่ "ช่วงต่อไม่ต่อเนื่อง"
- ขอบของบริเวณที่วาดใหม่เป็นสี่เหลี่ยมตรง
- ต้นไม้ถูกตัดเป็นเส้นตรงทั้งแนวรอยต่อห้องและขอบหน้ากาก
- การไล่สีแบบสะท้อนทำให้บางจุดเบลอเป็นผี

ศึกษาจาก 18 แหล่ง (รายชื่อท้ายไฟล์) ได้ 6 วิธี

## 1. ขยายแผนที่จากของเดิมโดยเหลือพื้นที่อ้างอิง (วิธีของ PixelLab เอง)

- คู่มือ Create Map ของ PixelLab ขยายแผนที่ทีละบล็อก
- บล็อกใหม่ต้องทับของเดิมบางส่วน และห้ามวาดใหม่ทั้งช่อง
- ต้องเหลือส่วนเดิมไว้ให้โมเดลเห็นสไตล์และรอยต่อ จากนั้นค่อยใช้ inpaint เก็บรายละเอียด
- **ใช้กับเรา:**
  - หน้าต่าง inpaint ต้องคร่อมรอยต่อ และมีของเดิมทั้งสองฝั่งเหลืออยู่มาก
  - หน้ากากไม่ควรเป็นสี่เหลี่ยมเต็มกรอบ ซึ่ง J1 ทำแบบนั้นอยู่

## 2. ตัดตามเส้นที่ต่างกันน้อยที่สุด (Image Quilting, Efros & Freeman 2001)

- ในส่วนที่ภาพสองภาพทับกัน ให้คำนวณว่าแต่ละพิกเซลต่างกันแค่ไหน
- ใช้ dynamic programming หาเส้นทางที่ต่างกันน้อยที่สุด แล้วตัดตามเส้นนั้นแทนเส้นตรง
- เส้นตัดจะคดไปตามขอบต้นไม้หรือพุ่มไม้ จึงมองไม่เห็นรอย
- รุ่นปรับปรุง (Long & Mould 2007) กระจายจุดผิดให้ยาวขึ้นและเห็นน้อยลง
- **ใช้กับเรา (ฟรี):**
  - ผล inpaint กับภาพเดิมทับกันทั้งหน้าต่าง
  - ให้ตัดตามเส้นต่างน้อยสุดแทนขอบหน้ากากสี่เหลี่ยม
  - ใช้กับผล J1 ที่มีอยู่แล้วได้ทันที

## 3. ผสมแยกความถี่ (Laplacian pyramid / multiband blending)

- สีและแสงในภาพเป็นความถี่ต่ำ ให้ผสมในช่วงกว้าง
- รายละเอียดคมๆ เป็นความถี่สูง ให้ผสมในช่วงแคบ
- ผลคือสีกลมกลืนโดยไม่เบลอเป็นผี ซึ่งเป็นปัญหาของการไล่สีแบบเดิม
- กฎหน้าต่างผสม:
  - กว้างอย่างน้อยเท่าสิ่งที่ใหญ่ที่สุด จึงจะไม่เห็นรอย
  - ไม่เกิน 2 เท่าของสิ่งที่เล็กที่สุด จึงจะไม่เป็นผี
- **ใช้กับเรา (ฟรี):** ใช้แทน mirror blend ตรงรอยต่อห้องทุกเส้น

## 4. ชิ้นแผนที่ที่ออกแบบให้ต่อกันได้ (Diablo 1–4, Streets of Rogue 2, CURE 2)

- Diablo 2/3 สร้างด่านจากชิ้นที่ทำมือขนาดตายตัว
- แต่ละชิ้นมีจุดเชื่อมอยู่ตำแหน่งมาตรฐาน แล้วสุ่มต่อกัน
- Diablo 1 มี "miniset" ชิ้นเล็กไว้แปะซ่อมรอยต่อที่ผิด และมีชิ้นแปรผันเพื่อไม่ให้ซ้ำ
- Diablo 4 ใช้โลกทำมือ ส่วนดันเจี้ยนใช้ tile-set + props + แสง
- **ใช้กับเรา:**
  - ห้องใหม่ในอนาคต (เช่นถ้ำ M4b) ควรวาดให้ขอบทุกด้านเป็นแนวป่าแบบเดียวกัน
  - ทางเข้าออกควรอยู่ตำแหน่งมาตรฐาน เช่นกลางขอบ ชิ้นไหนก็จะต่อกันได้
  - จุดที่ยังต่อไม่ดีใช้ "miniset" แปะทับ ซึ่งก็คือ patch แบบที่เรากำลังทำ

## 5. แยกชั้นพื้นกับชั้นวัตถุ (Godot TileMapLayer / Tiled)

- ชั้นพื้นเดินได้ทั้งหมด
- ชั้นวัตถุ (ต้นไม้ หิน) เปิด Y-sort และชนเฉพาะโคนต้น ตัวละครอยู่ใน Y-sort เดียวกัน
- ตรงกับที่เจ้าของสั่ง: แก้พื้นก่อน แล้วเติมต้นไม้เต็มต้นทับ

## 6. Autotile / Wang / dual-grid

- กำหนด "สีขอบ" ให้ทุกด้านของชิ้น ชิ้นที่สีขอบตรงกันวางติดกันได้
- dual-grid ใช้แค่ 16 ชิ้นต่อดิน 2 ชนิด
- **ใช้กับเรา:** หลักคิดเดียวกับข้อ 4 ภาพวาดของเราไม่ใช่ tile จึงไม่ใช้ตรงๆ

## สรุปวิธีที่เสนอสำหรับ M4a

1. **ฟรี:** เปลี่ยนรอยต่อห้องจาก mirror blend เป็น multiband blending (ข้อ 3)
2. **ฟรี:** ผล inpaint ทุกจุดใช้เส้นตัดต่างน้อยสุดแทนขอบสี่เหลี่ยม (ข้อ 2) โดยลองกับ J1 ก่อน
3. **ใช้ gen:** จุดที่ยังต่อไม่ได้ ทำหน้าต่าง inpaint คร่อมรอยต่อ (ข้อ 1)
   - หน้ากากเป็นรูปทรงตามแนวพื้นที่ต้องเปลี่ยน ไม่ใช่สี่เหลี่ยม
   - เหลือของเดิมไว้อ้างอิงรอบด้าน
4. **ใช้ gen:** ต้นไม้เต็มต้นเป็นชั้นวัตถุ Y-sort ชนที่โคน (ข้อ 5)
   - วาดด้วยเครื่องมือที่ใช้วาดป่า (create_image_pro + ภาพป่าเป็นต้นแบบ) เพราะเครื่องมือ object สไตล์ไม่เข้า
5. **ห้องใหม่ในอนาคต:** กำหนดขอบมาตรฐานและจุดเชื่อมมาตรฐาน (ข้อ 4, 6)

## แหล่งที่ศึกษา

1. PixelLab — Using the Create Map tool: https://pixellab.ai/docs/guides/map-tiles
2. PixelLab — Extend map (v2): https://www.pixellab.ai/docs/tools/extend-map-v2
3. PixelLab — Create map (pixflux): https://www.pixellab.ai/docs/tools/create-map
4. BorisTheBrave — Dungeon generation in Diablo 1: https://boristhebrave.com/2019/07/14/dungeon-generation-in-diablo-1
5. DiabloWiki — Random (map tiles ใน Diablo III): https://www.diablowiki.net/Random
6. GameDev.net — Procedural Map Generation (meta tiles แบบ Diablo): https://www.gamedev.net/forums/topic/662745-procedural-map-generation/
7. Blue's News — Diablo IV Art Update: https://www.bluesnews.com/s/246500/diablo-iv-art-update
8. CyberPost — Is Diablo 4 map procedurally generated?: https://cyberpost.co/is-diablo-4-map-procedurally-generated/
9. Streets of Rogue 2 wiki — Chunks and world generation: https://thegameswiki.com/streets-of-rogue-2/wiki/chunks-and-world-generation
10. Raptor Byte (CURE 2) — Procedural generation: https://www.patreon.com/RaptorByte/posts/procedural-118194440
11. IPOL — Efros and Freeman Image Quilting: https://ipol.im/pub/art/2017/171/article_lr.pdf
12. Berkeley CS194 — Image Quilting (seam finding): https://inst.eecs.berkeley.edu/~cs194-26/sp20/upload/files/projFinalAssigned/cs194-26-aes/image_quilting/website/
13. Long & Mould — Improved Image Quilting: https://gigl.scs.carleton.ca/papers/iiq.pdf
14. UW CSE 455 — Image Stitching II: https://courses.cs.washington.edu/courses/cse455/16wi/notes/9_ImageStitching2.pdf
15. MIT (Durand) — Blending: https://people.csail.mit.edu/fredo/comp-photo-book/10-multiple-exposure-imaging-07-blending.html
16. U of Toronto — Blending (optimal window): https://www.cs.toronto.edu/~guerzhoy/320/lec/blending.pdf
17. Godot Forum — Y-sort tilemap scene collection tiles: https://forum.godotengine.org/t/is-it-possible-to-y-sort-tilemap-scene-collection-tiles/77659
18. Red Blob Games — Autotiling: https://www.redblobgames.com/articles/autotile/claude/
