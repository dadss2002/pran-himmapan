"""Gem combo sim (docs/superpowers/specs/2026-11-08-gem-combos.md, "ตัวเลขเสนอ").
Run: python3 tools/gem_combo_sim.py   (add --all to list every combo on its skill)

Same rotation model as tools/gem_sim.py (docs/gems.md §7): basic shots always, skills used
by best damage-per-MP until cooldown or MP regen (6/s) runs out. Gem values at gem Lv1.
Adds: hit counts for a "pack of 6" (assumptions below), element side effects that exist in
the game (burn 20% of the hit/s for 3 s, lightning +1 target 80%), and the combo effects.
Every number marked in COMBO / ADV is a proposal (⚙) waiting for owner approval.
"""
import itertools, sys

def mit(d): return d / (d + 100)
REGEN = 6.0
GEAR = {  # bow ATK, enhance, ATK%, crit, crit dmg, attack speed (same as gem_sim.py)
    'ปกติ': dict(up=3, atkp=0.05, c=0.03, cd=0.0, asp=0.0),
    'สุดทาง': dict(up=10, atkp=0.24, c=0.15, cd=0.6, asp=0.30),
}
BOW = {5: 16, 10: 26}
# skill: unlock level, mult per hit, cooldown, MP, arrows, labels
SK = {
    'pierce': dict(u=1, m=1.8, cd=4, mp=8, lab={'arrow'}),
    'spread': dict(u=3, m=0.7, cd=6, mp=12, lab={'arrow'}),
    'rain':   dict(u=7, m=2.4, cd=10, mp=18, lab={'area', 'dot'}),
    'fire':   dict(u=10, m=2.0, cd=6, mp=14, lab={'arrow', 'area'}),
}
# pack-of-6 assumptions ⚙ : targets hit per cast (single target = 1 boss)
PACK = {'pierce': 3, 'pierce_split': 5, 'spread': 4, 'spread_split': 5, 'rain': 5, 'rain_big': 6, 'fire': 3, 'fire_big': 4}
GEM = {  # dmg mult, MP mult, labels (docs/gems.md §5, Lv1)
    'split': (1, 1.4, 'arrow'), 'ricochet': (1, 1.3, 'arrow'), 'pierce': (1, 1.2, 'arrow'), 'homing': (0.9, 1.2, 'arrow'),
    'multiply': (1.35, 1.5, 'any'), 'expand': (1, 1.3, 'area'), 'extend': (1, 1.2, 'dotrap'), 'execute': (1, 1.2, 'any'),
    'leech': (1, 1.2, 'any'), 'fire': (1.1, 1.3, 'any'), 'ice': (1.1, 1.3, 'any'), 'lightning': (1.1, 1.3, 'any'),
}
COMBO = {  # 2-gem combos ⚙
    frozenset({'split', 'fire'}): 'ศรพัดเพลิง', frozenset({'ricochet', 'lightning'}): 'ศรอสนีกระโดด',
    frozenset({'pierce', 'expand'}): 'ศรคลื่นกระแทก', frozenset({'homing', 'execute'}): 'ศรตาเหยี่ยว',
    frozenset({'expand', 'extend'}): 'อาณาเขตพราน', frozenset({'leech', 'multiply'}): 'ศรกระหายเลือด',
    frozenset({'ice', 'split'}): 'ศรเกล็ดน้ำแข็ง', frozenset({'fire', 'expand'}): 'ศรเพลิงระเบิด',
}
ADV = {  # 3-gem advanced combos ⚙
    frozenset({'split', 'fire', 'multiply'}): 'พัดเพลิงพรหมาสตร์', frozenset({'ricochet', 'lightning', 'split'}): 'ศรอสนีพันสาย',
    frozenset({'homing', 'execute', 'multiply'}): 'ศรเนตรพญาครุฑ', frozenset({'ice', 'split', 'execute'}): 'ศรผลึกอโนดาต',
    frozenset({'leech', 'multiply', 'execute'}): 'ศรราหูอมจันทร์', frozenset({'expand', 'extend', 'fire'}): 'ทุ่งเพลิงบรรลัยกัลป์',
    frozenset({'pierce', 'expand', 'fire'}): 'ศรอัคนีทะลวงพิภพ', frozenset({'split', 'fire', 'expand'}): 'ฝนดาวไฟ',
}

def fits(g, s):
    lab = GEM[g][2]; L = SK[s]['lab']
    return lab == 'any' or lab in L or (lab == 'dotrap' and ('dot' in L or 'trap' in L))

def combo_name(gems):
    s = frozenset(gems)
    for k, v in ADV.items():
        if k <= s: return v
    for k, v in COMBO.items():
        if k <= s: return v
    return ''

def cast(s, gems, L, c, cdm):
    """(single-target dmg, pack dmg, MP, cooldown, mark bonus) in ATK units, crit included."""
    k = SK[s]; sl = L - k['u'] + 1
    hit = k['m'] * (1 + 0.05 * (sl - 1)); cdv = k['cd'] * (1 - 0.01 * (sl - 1)); mp = k['mp']
    crit = c; dmgx = 1.0
    for g in gems: hit *= GEM[g][0]; mp *= GEM[g][1]
    G = set(gems); name = combo_name(gems)
    if 'execute' in G: crit += 0.15
    split = 'split' in G
    # hits per cast: single / pack, and distinct targets in the pack
    if s == 'pierce':
        if split: hit *= 0.6; n1, np_, d = 3, 7, 5
        else: n1, np_, d = 1, PACK['pierce'], 3
    elif s == 'spread':
        if split: hit *= 0.6; n1, np_, d = 3, 5, 5
        else: n1, np_, d = 3, PACK['spread'], 4
    elif s == 'rain':
        if 'extend' in G: hit *= 1.3
        n1 = 1; np_ = d = PACK['rain_big'] if 'expand' in G else PACK['rain']
    else:  # fire arrow: 200% + its own burn 60% (as gem_sim.py), explosion r32
        hit *= 1.3; n1 = 1; np_ = d = PACK['fire_big'] if 'expand' in G else PACK['fire']
        if split: hit *= 0.6; n1, np_, d = 3, np_ + 4, 5                   # 3 arrows, 3 blasts
        G.discard('fire')                                                  # already burns; burns do not stack
    one, pack = hit * n1, hit * np_
    if 'fire' in G: one += 0.6 * hit; pack += 0.6 * hit * d          # burn 20%/s x3 s, no stacking
    if 'lightning' in G: pack += 0.8 * hit * np_                       # +1 target per hit (none on a lone boss)
    # ricochet gem: 1 bounce per arrow that hits — ศรทะลวง / ศรเพลิง: 1 arrow per line (1, 3 with split); ศรกระจาย:
    # every arrow that hits bounces (np_ = 4, 5 with split), owner 2026-11-10 "คงไว้ แก้ตัวเลขอนุมัติให้นับทุกลูก"
    if 'ricochet' in G: pack += 0.8 * hit * (np_ if s == 'spread' else (3 if split else 1))
    mark = 0.0; refund = 0
    # ---- 2-gem combos ⚙
    if name == 'ศรพัดเพลิง': one += 0.4 * hit; pack += 0.4 * hit * d       # trail 20%/s x 2 s
    if name == 'ศรอสนีกระโดด': pack += (0.8 + 1.0) * hit * (3 if split else 1)  # +1 bounce (80%), bolt 50% per bounce
    if name == 'ศรคลื่นกระแทก': pack += hit + 0.8 * hit * 4               # pierce gem: +1 target; each pierce: shockwave r32 80%
    if name in ('ศรตาเหยี่ยว', 'ศรเนตรพญาครุฑ'): one /= 0.9; pack /= 0.9        # homing at full power (no -10%)
    if name == 'ศรตาเหยี่ยว': crit += 0.15; mark = 0.20                   # hit marks 4 s, +20% taken by all hits
    if name == 'อาณาเขตพราน': dmgx *= 1.10                                # in zone +10% taken, slow 30%
    # owner 2026-11-10 (Task 7 review, "แก้ตัวเลขอนุมัติตามเกม"): in the pack only a hit on a monster that is ALREADY slowed /
    # frozen gets the frost +25 % / อโนดาต sure crit and shatter. The ice gem's slow (3 s) runs out before the next press
    # (ศรทะลวง cooldown 3.64 s at Lv10), so a press starts on unchilled monsters and only the repeat hits of the same
    # press count: ch = hits - distinct targets (ศรทะลวง +split: 7 hits on 5, the near monster on all 3 lines -> 2).
    # "ช้า" = the ice slow / freeze only, not the อาณาเขตพราน zone slow nor a trap root ("นับเฉพาะน้ำแข็ง").
    ch = max(0, np_ - d)
    if name == 'ศรเกล็ดน้ำแข็ง': one += 0.25 * hit * n1 * 0.7; pack += 0.25 * hit * ch  # +25% on slowed/frozen
    if name == 'ศรเพลิงระเบิด': np_ += 1; pack += hit + 0.6 * hit        # r +20%: 1 more target, all burn
    # ---- 3-gem advanced ⚙
    if name == 'พัดเพลิงพรหมาสตร์': one += 0.9 * hit; pack += 0.9 * hit * d + 0.5 * hit * 3  # trail 30%/s 3 s + blast 50% x3 lines
    if name == 'ศรอสนีพันสาย': pack += 0.5 * hit * 3 * 2                    # every bounce: chain 50% to 2 targets
    if name == 'ศรเนตรพญาครุฑ': crit += 0.15; mark = 0.30                   # +30% taken, marked = sure crit (below)
    # shatter: a hit on a chilled monster = sure crit + 50% burst r32, once per struck monster per press, and each monster
    # takes at most ONE splash per press (owner 2026-11-10 "โดนแรงแตกได้ตัวละ 1 ครั้งต่อการกด"). Pack: only the monster
    # hit again this press shatters (1 with ch > 0); its splash is counted on itself (the pack's others stand > r32 apart,
    # as tests/test_arrow_combos.gd lays them out). Single target: unchanged (approved: 1 shatter, half the presses chilled).
    if name == 'ศรผลึกอโนดาต': one += 0.5 * hit; pack += 0.5 * hit * min(ch, 1)
    if name == 'ศรราหูอมจันทร์': dmgx *= 1 + 0.30 * 0.7; refund = 3 * 2      # +30% while HP >= 70% (~70% of time); kill +3 MP
    if name == 'ศรกระหายเลือด': refund = 2 * 2                              # kill +2 MP (pack: ~2 kills per cast)
    if name == 'ทุ่งเพลิงบรรลัยกัลป์': dmgx *= 1.2; pack += 0.3 * hit * d    # zone 4.5 s: +20% taken, burn
    if name == 'ศรอัคนีทะลวงพิภพ': pack += hit + 1.0 * hit * 5             # +1 target; each pierce: blast r40 100% (burning)
    if name == 'ฝนดาวไฟ': one += 0.8 * hit; pack += 0.8 * hit * 3            # 3 arrows, each explodes r40
    cf = 1 + min(1, crit) * (0.5 + cdm); cfp = cf; sure = 1.5 + cdm
    # ครุฑ: the 4 s mark outlasts the 3.64 s cooldown, so after the first press every press lands on a marked target
    # (owner 2026-11-10 "รับได้ คงไว้": the sim follows the game; was ~85% of presses marked)
    if name == 'ศรเนตรพญาครุฑ': cf = cfp = sure
    if name == 'ศรผลึกอโนดาต':
        cf = 0.5 * cf + 0.5 * sure                                         # single: ~half the casts land on frozen (approved)
        pack = pack * cfp + ch * hit * (sure - cfp); cfp = 1               # pack: the ch repeat hits are sure crits
    return one * cf * dmgx, pack * cfp * dmgx, mp, cdv, mark, name, refund

def run(L, gear, build, mode='one', regen=REGEN):
    """build: {skill: [gems]} -> hero DPS (single boss or pack of 6) and MP/s spent."""
    gq = GEAR[gear]; A = (10 + 2 * (L - 1) + BOW[L] * (1 + 0.06 * min(gq['up'], 6) + 0.10 * max(0, gq['up'] - 6))) * (1 + gq['atkp'])
    c = 0.05 + gq['c']; basic = A * 1.25 * (1 + gq['asp']) * (1 + min(1, c) * (0.5 + gq['cd']))
    opts = []
    for s, k in SK.items():
        if k['u'] > L: continue
        o, p, mp, cdv, mark, _, rf = cast(s, build.get(s, []), L, c, gq['cd'])
        opts.append((o if mode == 'one' else p, cdv, mp if mode == 'one' else max(1, mp - rf), mark))
    budget, dps, use, mk = regen, basic, 0.0, 0.0
    for d, cdv, mp, mark in sorted(opts, key=lambda o: -(o[0] * (1 + o[3])) / o[2]):
        rate = min(1 / cdv, budget / mp); dps += A * d * rate; budget -= rate * mp; use += rate * mp
        if mark: mk = max(mk, mark * min(1, rate * 4) * (1 if mode == 'one' else 0.5))  # 4 s; half a pack marked
    return dps * (1 + mk), use

def sustain(L, build):
    """seconds of pressing every skill on cooldown before MP runs out (None = forever)."""
    need = 0.0
    for s in SK:
        if SK[s]['u'] > L: continue
        _, _, mp, cdv, *_ = cast(s, build.get(s, []), L, 0.08, 0.0); need += mp / cdv
    return None if need <= REGEN else (50 + 5 * (L - 1)) / (need - REGEN)

def slots(L, s): sl = L - SK[s]['u'] + 1; return 0 if sl < 1 else 2 + (sl >= 10) + (sl >= 50)   # gem_slots [1,1,10,50], owner 2026-11-08

def options(L, s, n):
    """every legal gem set of size n for a skill (one element gem max)."""
    pool = [g for g in GEM if fits(g, s)]
    out = []
    for comb in itertools.combinations(pool, n):
        if sum(g in ('fire', 'ice', 'lightning') for g in comb) > 1: continue
        out.append(list(comb))
    return out

def best(L, gear, tier, mode):
    """tier 0..3: 0 none, 1 = best 1 gem per skill, 2/3 = ศรทะลวง carries the best 2-gem combo / 3-gem
    advanced combo; every other skill takes its best legal gems (combo or not) up to its slots."""
    build = {}; label = ''
    for s in SK:
        if SK[s]['u'] > L: continue
        n = min(tier, slots(L, s))
        if n == 0: continue
        if s == 'pierce' and n == tier and n >= 2:   # the skill under test must carry a tier-n combo
            cands = [o for o in options(L, s, n) if frozenset(o) in (ADV if n == 3 else COMBO)]
        else:                                         # other skills: best legal set up to their slots
            cands = [o for k in range(1, n + 1) for o in options(L, s, k)]
        top = max(cands, key=lambda o: run(L, gear, {**build, s: o}, mode)[0])
        build[s] = top
    return build

def fmt(b): return ' · '.join(f"{s}:{'+'.join(g)}" + (f'({combo_name(g)})' if combo_name(g) else '') for s, g in b.items())

if __name__ == '__main__':
    base = run(10, 'ปกติ', {})[0]
    print(f'check: Lv10 ปกติ no gem {base:.0f} (gems.md §7 = 178) · สุดทาง {run(10, "สุดทาง", {})[0]:.0f} (352) · ceiling 540 (3.03x)')
    print(f"{'':6}{'tier':7}{'single':>8}{'x':>6}{'pack6':>8}{'x':>6}{'MP/s':>6}  build (single / pack)")
    for L in (5, 10):
        for gear in ('ปกติ', 'สุดทาง'):
            b0 = run(L, gear, {})[0]; p0 = run(L, gear, {}, 'pack')[0]
            for tier, nm in enumerate(('none', '1gem', '2gem', '3gem')):
                if tier == 3 and L < 10: continue
                bo = best(L, gear, tier, 'one'); bp = best(L, gear, tier, 'pack')
                o, use = run(L, gear, bo); p, _ = run(L, gear, bp, 'pack')
                print(f"Lv{L} {gear:6}{nm:5}{o:8.0f}{o / b0:6.2f}{p:8.0f}{p / p0:6.2f}{use:6.1f}  {fmt(bo)} / {fmt(bp)}")
    print('ceiling check: best single-target build vs Lv10 ปกติ no gem:', f"{run(10, 'สุดทาง', best(10, 'สุดทาง', 3, 'one'))[0] / base:.2f}x (must be <= 3.03)")
    if '--press' in sys.argv:  # per press, pack of 6, crit off, gem Lv1, in units of the press's first hit (tests/test_arrow_combos.gd SIM_PRESS)
        for s_, nm_ in (('pierce', 'ศรทะลวง'), ('spread', 'ศรกระจาย')):
            for o in (['ricochet', 'lightning'], ['ricochet', 'lightning', 'split']):
                _, pk, *_rest = cast(s_, o, 10, 0.0, 0.0)
                k = SK[s_]; h = k['m'] * (1 + 0.05 * (10 - k['u'])) * GEM['lightning'][0] * (0.6 if 'split' in o else 1)
                print(f"press {nm_} {combo_name(o)}: {pk / h:.2f} x first hit")
        # mark / frost (M5b Task 7): ศรทะลวง Lv10, crit counted (hero 0.05, crit dmg x1.5 = cdm 0), units of the press's
        # first hit (homing_full: the game's arrow has no x0.9, the sim's one/pack are divided back by 0.9 too)
        for o in (['homing', 'execute'], ['homing', 'execute', 'multiply'], ['ice', 'split'], ['ice', 'split', 'execute']):
            on, pk, *_rest = cast('pierce', o, 10, 0.05, 0.0)
            h = SK['pierce']['m'] * (1 + 0.05 * 9) * (0.6 if 'split' in o else 1)
            for g in o: h *= 1 if g == 'homing' else GEM[g][0]
            print(f"press ศรทะลวง {combo_name(o)}: single {on / h:.3f} · pack {pk / h:.3f} x first hit (crit counted)")
        # sustain (M5b Task 8): ศรทะลวง Lv10, crit counted (hero 0.05, crit dmg x1.5), units of the press's first hit
        # before ราหู's bonus. ราหู's +30 % is the sim's time mix (HP >= 70 % on ~70 % of the presses: x1.21); the MP
        # refund is the pack's ~2 kills per press (2 x 2 / 2 x 3), so a pack press costs MP - refund (tests SIM_SUSTAIN)
        for o in (['leech', 'multiply'], ['leech', 'multiply', 'execute']):
            on, pk, mp, cdv, _mk, nm, rf = cast('pierce', o, 10, 0.05, 0.0)
            h = SK['pierce']['m'] * (1 + 0.05 * 9)
            for g in o: h *= GEM[g][0]
            print(f"press ศรทะลวง {nm}: single {on / h:.3f} x first hit (crit counted) · MP {mp:.2f} - refund {rf} = {max(1, mp - rf):.2f} per pack press")
    if '--all' in sys.argv:  # each combo on one skill, other skills no gem, Lv10 ปกติ
        L, g = 10, 'ปกติ'; b0, p0 = run(L, g, {})[0], run(L, g, {}, 'pack')[0]
        one1 = {s_: max(run(L, g, {s_: [x]})[0] for x in GEM if fits(x, s_)) / b0 for s_ in SK}
        pk1 = {s_: max(run(L, g, {s_: [x]}, 'pack')[0] for x in GEM if fits(x, s_)) / p0 for s_ in SK}
        print('best single gem on the same skill (hero x1 / x pack):', {k: f'{one1[k]:.2f}/{pk1[k]:.2f}' for k in SK})
        print(f"{'skill':7}{'combo':22}{'MP':>6}{'MP/s':>6}{'hero x1':>8}{'x pack':>7}{'cast x1':>8}{'cast xpack':>11}  burst")
        for s_ in SK:
            for n in (2, 3):
                for o in options(L, s_, n):
                    if frozenset(o) not in (ADV if n == 3 else COMBO): continue
                    on, pk, mp, cdv, _, nm, _ = cast(s_, o, L, 0.08, 0.0); b1, b2, *_ = cast(s_, [], L, 0.08, 0.0)
                    t = sustain(L, {s_: o})
                    print(f"{s_:7}{nm:22}{mp:6.1f}{mp / cdv:6.1f}{run(L, g, {s_: o})[0] / b0:8.2f}{run(L, g, {s_: o}, 'pack')[0] / p0:7.2f}"
                          f"{on / b1:8.2f}{pk / b2:11.2f}  {'ตลอด' if t is None else f'{t:.0f}s'}")
