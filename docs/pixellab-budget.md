# บันทึกการใช้ PixelLab

โควตา: 5,000 gen ต่อรอบ (Tier 2) · รอบปัจจุบันรีเซ็ต 2026-12-06 · เริ่มใช้ 2026-11-06

| วันที่ | งาน | เครื่องมือ | gen | id |
|---|---|---|---|---|
| 2026-11-06 | ฮีโร่ Pran ชุดพรานฝึกหัด 48px 8 ทิศ (เจ้าของไม่ผ่าน: สัดส่วนสมจริงเกินไป) | create_character v3 | 2 | c50f27ec-51d4-4d17-af4e-b0dd351be41d |
| 2026-11-06 | ฮีโร่ chibi แบบ A (ฮู้ดผ้าคลุมเขียว) | create_character v3 | 2 | 5916b571-120d-4633-83d8-ea09079fc5d5 |
| 2026-11-06 | ฮีโร่ chibi แบบ B (ผ้าคาดหัวเขียว) | create_character v3 | 2 | 0ba6b789-efc6-45e7-bc9b-4f1d5e79fa9b |

| 2026-11-06 | ฮีโร่ A ท่ายืน (breathing-idle) 8 ทิศ — ธนูหายในท่านี้ | animate template | 8 | group 3d6a38ff |
| 2026-11-06 | ฮีโร่ A ท่ายิงธนู ทดสอบทิศใต้ | animate v3 | 1 | group 0bbe57ac |
| 2026-11-06 | ฮีโร่ A สถานะไม่ถือธนู (ฐานสำหรับธนูชั้นแยก) | create_character_state | 10 | 6dfecdec-c546-49f2-b270-145e616d1ca1 |
| 2026-11-06 | ฐานไม่ถือธนู ท่าเดิน 8 ทิศ | animate template walking-8-frames | 8 | group 14e0bc25 |
| 2026-11-06 | ฐานไม่ถือธนู ท่าน้าวสาย ทดสอบทิศใต้ | animate v3 | 1 | group 68fa223c |
| 2026-11-06 | ฐานไม่ถือธนู ท่ายืน (breathing-idle) 8 ทิศ | animate template | 8 | group 85c1f339 |
| 2026-11-06 | ฐานไม่ถือธนู ท่าน้าวสาย อีก 7 ทิศ | animate v3 | 7 | group 68fa223c |
| 2026-11-06 | ท่าเดินแก้ SE/W (template ใส่ธนูผีมา) | animate skeleton v3 | 6 | group b11926d0 |
| 2026-11-06 | ไอเทมชุดแรก 16 ชิ้น (ธนู 3, ลูกศร, ยา 2, เจม 3, เหรียญ, กระบอกลูกศร, ชุด 3, หนังเสือ, +1) | create_1_direction_object | 10 | tag pran-items-batch1 |

| 2026-11-06 | ไอคอนสกิลนักธนูฝึกหัด 7 สกิล × 2 แบบ + ช่องล็อก/ว่าง | create_1_direction_object | 10 | tag pran-skill-icons-1 |

ใช้รวม: 75 gen

หมายเหตุ: `docs/preview/pran_base_rotations_x4.png` เป็นภาพตัวอย่างขยาย 4 เท่าบนพื้นหลังทึบ ไม่ใช่ไฟล์สไปรต์ที่ใช้ในเกม ไฟล์จริงต้องดาวน์โหลดจาก api.pixellab.ai ซึ่งตอนนี้เครื่องของ Claude เข้าไม่ได้

## M2a (ประเมินก่อนเจน 2026-11-06): ไม่เกิน 114 gen
หมาป่าผี pro + style 10 · วิ่ง 8 · กัด/โดดพุ่ง/ล้ม skeleton-v3 72 · ฮีโร่กลิ้ง v3 8 · โดนตี 8 · ตาย 8 · VFX 0

| วันที่ | งาน | เครื่องมือ | gen | id |
|---|---|---|---|---|
| 2026-11-06 | หมาป่าผี 48px 8 ทิศ (style = ฮีโร่ A) | create_character pro quadruped dog | 10 | 4af7a8b2-17e1-4fe1-823b-d58c22a012a3 |
| 2026-11-06 | ฮีโร่ท่าโดนตี — **ทิ้ง**: template ใส่ธนูผี/มีดใน 6 จาก 8 ทิศ | animate template taking-punch | 8 | group 449683af |
| 2026-11-06 | ฮีโร่ท่าตาย — **ทิ้ง**: template ใส่ธนูผีและหน้าตาเพี้ยน | animate template falling-back-death | 8 | group 86a6b3f4 |
| 2026-11-06 | ฮีโร่ท่าตาย (ทำใหม่) | animate skeleton-v3 falling-back-death | 24 | group 2a06d00c |

บทเรียน: ตัวละครฐานไม่ถือธนู (6dfecdec) ใช้ template animation ไม่ได้ เพราะ template ชอบวาดธนูกลับมา ให้ใช้ skeleton-v3 เสมอ
ประเมิน M2a ใหม่: ~150 gen (เดิม 114) เพราะทิ้งไป 16 และท่าตาย/กลิ้งต้องใช้ skeleton-v3 ท่าละ 24 · ท่าโดนตีของฮีโร่ใช้กะพริบสี+ผลักถอยแทน ไม่ทำท่า
| 2026-11-06 | ฮีโร่ท่ากลิ้ง 8 ทิศ | animate skeleton-v3 move dodge_roll | 24 | group fdd593d9 |
| 2026-11-06 | เอฟเฟกต์วงเตือน / ประกายโดนตี / ฝุ่นกลิ้ง | vfx_workbench | 0 | c8dc78a6 / a9fdd80b / 27a9b652 |
| 2026-11-06 | หมาป่าวิ่ง template — **ทิ้ง**: ตัวเล็ก/เตี้ยกว่าท่าอื่นมาก (สูง 29 vs 44 px) | animate template running-8-frames | 8 | group 3f86cebf |
| 2026-11-06 | หมาป่ากัด ทดสอบทิศใต้ | animate skeleton-v3 move bite | 3 | group 4da922be |
| 2026-11-06 | หมาป่าวิ่ง (ทำใหม่) 8 ทิศ | animate skeleton-v3 move run | 24 | group e39cdd86 |
บทเรียน: หมาป่าตัวนี้ (pro, หัวโต) ใช้ template แล้วสัดส่วนหด ให้ใช้ skeleton-v3 ทุกท่า
| 2026-11-06 | หมาป่ากัด อีก 7 ทิศ | animate skeleton-v3 move bite | 21 | group 4da922be |
| 2026-11-06 | หมาป่าโดดพุ่ง 8 ทิศ | animate skeleton-v3 move pounce | 24 | group 22e91f3a |
| 2026-11-06 | หมาป่าล้มตาย 8 ทิศ | animate skeleton-v3 move fall_over | 24 | group 8fe343dd |

**รวม M2a: 178 gen** (ทิ้ง 24: template ท่าโดนตี/ตายของฮีโร่ และท่าวิ่งหมาป่า) · ทิศ north-west ของท่าล้มหมาป่าล้มที่ฝั่งเซิร์ฟเวอร์ (520) แล้วทำใหม่ ไม่คิดซ้ำ
**ใช้รวมทั้งหมด: 253 gen** (ตรงกับ get_balance 2026-11-06: ใช้ 253 / เหลือ 4,747)

## M2b
| 2026-11-06 | เอฟเฟกต์เลเวลอัป / เก็บของ / หางศรทะลวง / วงศรกระจาย | vfx_workbench | 0 | 6aa71090 / da056813 / 20160e5b / c54f014c |
