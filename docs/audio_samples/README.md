# Sound samples (owner review)

Listening page: claude.ai artifact "PRAN ตัวอย่างเสียง".

## Thai sounds (made in code, ours, no licence needed) — owner 2026-11-08: "กลิ่นไทยผ่านหมด ยกเว้นระนาดคริ"
Passed (page no. → file in thai/): 21 ranat_levelup_a, 22 ranat_levelup_b, 23 ranat_chest, 24 ranat_coin, 26 gong_levelup, 27 gong_chest, 28 gong_warp.
Failed: 25 ranat_crit (not kept). Regenerate with `python3 tools/audio/thai_synth.py` (seeded; 7-tone equal Thai tuning, pentatonic subset).
Which of the level-up / chest pairs goes in the game is decided when sound is wired in.

## Critical hit — owner 2026-11-08: "ใช้ 52"
Wanted a Ragnarok-Online-like feel (not RO's own sound: Gravity's copyright). Rounds: 29–33 too mixed; 34–39 not close; 40 "ป้าง" and 32 close; 46 = 32 + 40; 52 = 46 without the bell → chosen.
File: crit/crit_hit.wav (0.7 s), made by `python3 tools/audio/crit_mix.py` from:
- src_blade_03.wav, src_metal_sheet_03.wav, src_bang_05.wav — rubberduck (OpenGameArt, CC0), via github.com/EternityForest/Free-SFX (CC0 collection)
- src_impact_punch_heavy_000.wav — Kenney Impact Sounds (CC0), via github.com/Boyquotes/kenney-impact-sounds-for-godot
No attribution required (CC0); credits list may still name Kenney and rubberduck.

## Picked 2026-11-08 (owner: "ยิงธนูใช้ 55 / ลูกศรโดน60 / เก็บของ 77 / ปุ่ม 82 / เปิดกระเป๋า 85 / แจ้งเตือน 92")
Files in picked/ (made by tools/audio/sfx_set5.py from CC0 sources + our Thai synth):
- bow_shot.wav (55) — Superpowers western-fps-2d/arrow (CC0)
- arrow_hit.wav (60) — rubberduck SFX100 hit_01 (CC0)
- pickup.wav (77) — ranat, two notes up (ours)
- ui_button.wav (82) — rubberduck SFX100 switch_01 (CC0)
- ui_bag_open.wav (85) — Kenney RPG Audio cloth_1 (CC0)
- ui_notify.wav (92) — ranat struck twice (ours)
Sources via github.com/EternityForest/Free-SFX and Kenney ports on GitHub. Leveled sounds: level-up/chest/coin/warp = Thai set above; critical = crit/crit_hit.wav.

## Monster cries — owner: "มอนตาย 67-70 อยากให้เสียงมอนหลากหลาย", base 67–70 for hurt and death, per kind by animal + pitch by size
Base: 67 rubberduck creature_misc_01, 68 Superpowers medieval-fantasy/monster-1, 69 rubberduck creature_misc_07, 70 rubberduck creature_die_01 (all CC0); shroom uses rubberduck creature_slime_01; viper hiss and kongkoi gong are ours.
Per-kind candidates (page 95–108): monsters/<kind>_{hurt,die}.wav from tools/audio/monster_cries.py — waiting for the owner's review.

## Still open
- Bow shot: waiting for the owner to attach OpenGameArt "Medieval Sound Effects – Weapon Textures" (CC0).
- Music: later.
