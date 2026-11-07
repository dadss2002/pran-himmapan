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

## ภาคต่อ: วิธีแก้ภาพฟรี (เจ้าของ: "เรียนรู้วิธีแก้ภาพเพิ่มได้ไหม", 2026-11-07)

### 1. ตัวเติมภาพ AI ฟรีที่รันในเครื่อง: LaMa
- **ที่มา:** Samsung AI, WACV 2022, Apache-2.0
- **ทำไมเหมาะ:** ใช้ Fourier convolution จึงมองเห็นทั้งภาพ เติมพื้นที่ใหญ่และลายซ้ำได้ดี
- **วิธีรันในงานนี้:**
  - ใช้รุ่น ONNX (`lama_fp32.onnx`) กับ onnxruntime บน CPU ซึ่งไม่ใช้ gen เลย
  - เครื่องมืออยู่ที่ `tools/lama_fill.py`
  - ดาวน์โหลดโมเดลจาก GitHub mirror แล้วตรวจ SHA-256 ตรงกับต้นฉบับ
  - หลังเติม จะดึงสีของพิกเซลใหม่เข้าจานสีของบริเวณรอบๆ ให้ภาพยังคม
- **ทดลองกับ J3:**
  - ลบเส้นตั้งในพุ่มไม้ด้านบนได้ดี
  - พุ่มไม้ใต้ทางกลายเป็นก้อนเขียวเรียบ เพราะ LaMa ไม่วาดรูปทรงวัตถุ
  - สรุป: เหมาะกับลบเส้นในเนื้อพื้นผิว (ใบไม้ หญ้า ดิน) ไม่เหมาะกับวาดต้นไม้หรือพุ่มไม้ใหม่
- **ทางเลือกอื่นที่ดูแล้ว:**
  - OpenCV inpaint (Telea/NS) เบลอมากกับภาพพิกเซล
  - PatchMatch / content-aware fill ต้อง compile
  - PyTorch โหลดไม่ได้ในเครื่องนี้ (โดเมนถูกปิด)

### 2. เครื่องมือฟรีของ PixelLab (pixelart_workbench)
- **ฟรีสำหรับสมาชิก**
- **คำสั่งที่ใช้ได้:**
  - `crop`/`paste`: ตัดบริเวณเล็กออกมาเป็นตัวอักษรแล้วแก้ทีละพิกเซล
  - `cluster`: เปลี่ยนสีหรือลบกลุ่มสีเดียวกัน
  - `repair`: ลบพิกเซลหลง เติมรู
  - `edit`: ใช้ copy_region / patch_pixels / map_colors
- **ข้อจำกัด:**
  - เหมาะกับการเก็บรายละเอียดจุดเล็ก เช่นโคนต้นไม้ซ้ำหรือเส้นขอบไม่กี่พิกเซล
  - ไม่เหมาะกับบริเวณใหญ่
  - ต้องส่งภาพเป็น URL ที่ PixelLab เปิดได้ ซึ่งใช้ raw.githubusercontent.com ได้

### ลำดับใช้งานที่แนะนำ
1. เส้นในเนื้อพื้นผิว → LaMa (ฟรี)
2. สีสองฝั่งไม่เท่ากัน → tone_seam / multiband (ฟรี)
3. จุดเล็กไม่กี่พิกเซล → pixelart_workbench (ฟรี)
4. รูปทรงต้นไม้หรือพุ่มไม้ผิด → PixelLab inpaint (ใช้ gen) หรือคัดลอกวัตถุทั้งชิ้นจากภาพเดียวกัน (ฟรี แต่ซ้ำได้)

แหล่งเพิ่ม:
- LaMa paper (arXiv 2109.07161): https://arxiv.org/pdf/2109.07161
- Carve LaMa-ONNX: https://huggingface.co/Carve/LaMa-ONNX
- GitHub mirror: https://github.com/neureps/carousel-fit-models/releases

## ภาคต่อ 2: เครื่องมือฟรีจาก GitHub / เว็บ / สกิล (เจ้าของสั่ง 2026-11-07)

| เครื่องมือ | ทำอะไร | เหมาะกับเรา | สถานะในเครื่องนี้ |
|---|---|---|---|
| **EmbarkStudios/texture-synthesis** (Rust, Apache-2.0, มี CLI) | เติมภาพแบบอิงตัวอย่าง คัดลอกพิกเซลจริงจากภาพตัวอย่างมาเรียงต่อ มีโหมด inpaint และ guided | เหมาะมาก เพราะใช้พิกเซลจริงจึงคมแบบพิกเซลอาร์ต ไม่เบลอเหมือน LaMa | ระบบความปลอดภัยไม่ให้ติดตั้ง binary จากภายนอกเอง ต้องให้เจ้าของอนุญาต |
| **PyPatchMatch** (MIT; PatchMatch, Barnes 2009 = content-aware fill ของ Photoshop) | เติมรูด้วย patch จากส่วนอื่นของภาพ | เหมาะ คมแบบพิกเซลอาร์ต | ต้อง compile C++ จึงติดเรื่องเดียวกัน |
| **Resynthesizer** (GIMP "Heal selection") | เติมภาพแบบอิงตัวอย่าง วิธีเดียวกับ PatchMatch | ใช้ได้ถ้ามี GIMP | ไม่มีในเครื่อง |
| **LaMa ONNX** (ทำแล้ว) | เติมภาพด้วย AI | ลบเส้นในเนื้อพื้นผิวได้ดี แต่วาดรูปทรงวัตถุไม่ได้ | ใช้ได้แล้ว `tools/lama_fill.py` |
| **SpriteCook** (plugin ใน Claude directory) | สร้าง sprite, tileset, dual-grid tileset สำหรับ Godot | สร้างของใหม่ได้ แต่ไม่ได้ไว้ซ่อมภาพเดิม | ยังไม่ติดตั้ง และอาจเป็นบริการเสียเงิน |
| skill สำหรับซ่อมภาพหรือแผนที่ | — | — | ค้นแล้วไม่พบใน catalog |

บทเรียนจากเว็บและบทความนักทำเกม:
- **Nectarmancer:** โลกไร้รอยต่อทำจาก "ห้อง" ที่เรียงขอบให้ตรงกันด้วยมือ ซึ่งยุ่งแต่ได้ผลจริง
- **Sprite AI:** ใช้เทคนิค offset ของ tile คือเลื่อนภาพครึ่งหนึ่งแล้ววาดทับรอยที่โผล่กลางภาพ หลักการเดียวกับการซ่อมรอยต่อของเรา
- **สรุป:** เกมพิกเซลที่โลกใหญ่ส่วนมากใช้ tile หรือชิ้นที่ออกแบบขอบให้ต่อกันได้ตั้งแต่แรก ส่วนภาพวาดผืนเดียวแบบของเราต้องซ่อมรอยต่อทีละจุด ซึ่งเป็นงานที่เราทำอยู่

แหล่ง:
- texture-synthesis: https://github.com/EmbarkStudios/texture-synthesis
- PyPatchMatch: https://pypi.org/project/pypatchmatch
- Resynthesizer: https://github.com/bootchk/resynthesizerJulia
- Nectarmancer (80.lv): https://80.lv/articles/how-pixel-art-lighting-was-set-up-in-seamless-world-of-nectarmancer
- Sprite AI seamless tiles: https://www.sprite-ai.art/guides/seamless-tiles

### ทดลอง texture-synthesis กับ J3 (เจ้าของอนุญาตให้ติดตั้ง 2026-11-07)
- ติดตั้ง binary 0.8.2 x86_64-musl จาก GitHub release ทางการ (Apache-2.0/MIT)
- โหมด inpaint: `--inpaint mask.png` โดยในหน้ากาก **สีขาว = เก็บไว้ ดำ = เติม**
- `--sample-masks` บอกว่าให้คัดลอกพิกเซลจากบริเวณไหน ถ้าให้คัดลอกจากพุ่มไม้/ต้นไม้เท่านั้น ส่วนที่เติมจะเป็นพุ่มไม้ ไม่ใช่หินหรือดิน
- ผล: เส้นตั้งบนและล่างหาย พิกเซลคมเหมือนภาพเดิม ไม่ต้องใช้ gen
- ข้อเสีย: ขอบวงรีของบริเวณที่เติมยังเห็นจางๆ ครั้งหน้าควรใช้หน้ากากขอบไม่เรียบ
- PyPatchMatch ยังติดตั้งไม่ได้ เพราะเครื่องไม่มี OpenCV dev headers สำหรับ compile
