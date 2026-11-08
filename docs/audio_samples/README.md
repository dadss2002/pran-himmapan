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

## Still open
- Bow shot: waiting for the owner to attach OpenGameArt "Medieval Sound Effects – Weapon Textures" (CC0).
- Kenney CC0 page 1–20: waiting for the owner's review. Music: later.
