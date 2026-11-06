# ทดลอง export เว็บ (ในเครื่อง ไม่ publish) — 2026-11-07

- โค้ดที่ทดสอบ: branch m3a/gems-enhance commit b4e683d (M3a)
- เครื่องมือ: `python3 tools/fetch_web_template.py` ติดตั้งเฉพาะ template เว็บ (9.4 MB จากไฟล์เต็ม 1.35 GB)
- คำสั่ง: `godot --headless --path . --export-release "Web" /tmp/webbuild/index.html` → สำเร็จ
- ขนาด: รวม 38 MB · ไฟล์เกม `index.pck` 0.8 MB · เอนจิน `index.wasm` 36.3 MiB
  - GitHub Pages รับได้ (จำกัด 100 MB ต่อไฟล์)
  - Cloudflare Pages ยังไม่ได้ (จำกัด 25 MiB ต่อไฟล์) ตรงกับที่ design-brief บันทึกไว้
- ในไฟล์เกม: ไม่มีเอกสาร/เครื่องมือ · สคริปต์ถูกเก็บเป็นไบต์โค้ด `.gdc` ไม่ใช่ซอร์ส `.gd` · ชื่อไฟล์เทสต์ปรากฏเฉพาะในตาราง uid (ไม่มีโค้ดเทสต์)
- เปิดใน Chrome headless (WebGL 2 ผ่าน SwiftShader): โหลดได้ เห็นเกม + HUD · console error 0 (มีแค่คำเตือนความเร็ว ReadPixels ของ WebGL ซอฟต์แวร์)
- ยังไม่ได้ทดสอบบนมือถือจริง · ยังไม่ publish (รอเจ้าของตัดสินเรื่องแยก 2 รีโป)
