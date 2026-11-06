"""Balance sanity check for docs/spec-numbers.md (phase 1). Run: python3 tools/balance_sim.py"""
import math
def exp_next(L): return round(60*L**1.6)
def p_hp(L): return 100+12*(L-1)
def p_atk(L,bow): return 10+2*(L-1)+bow
def p_def(L,armor): return 2+(L-1)+armor
def mit(d): return d/(d+100)
def bow_for(L): return 8 if L<8 else (20 if L<15 else 38)
def armor_for(L): return 4 if L<5 else (10 if L<10 else (18 if L<15 else 28))
MON={'wolf':dict(hp=lambda l:40+18*(l-1),atk=lambda l:6+2*(l-1),df=lambda l:2+l,exp=lambda l:8+5*l,lv=(1,8)),
     'kongkoi':dict(hp=lambda l:70+25*(l-1),atk=lambda l:9+2.5*(l-1),df=lambda l:3+1.5*l,exp=lambda l:14+7*l,lv=(5,12))}
CRIT=0.05; CDMG=1.5; APS=1.25
def dps(L):
    a=p_atk(L,bow_for(L))
    basic=a*APS*(1+CRIT*(CDMG-1))
    skills=a*(1.8/4 + (0.7*5*0.6)/6 + (2.4/10 if L>=7 else 0))  # pierce, spread(60% arrows hit), rain
    return basic+skills
def mob_level(L):
    if L<=6: return ('wolf',max(1,min(8,L)))
    return ('kongkoi',max(5,min(12,L)))
print('Lv  exp_next  mob      mobLv  TTK(s) kills_to_lv  min_to_lv(8s/kill)  dmg_taken/hit  hits_to_die')
tot=0
for L in range(1,15):
    m,ml=mob_level(L); M=MON[m]
    eff=M['df'](ml); ttk=M['hp'](ml)/(dps(L)*(1-mit(eff)))
    e=M['exp'](ml)*(0.3 if ml<L-5 else 1)
    kills=math.ceil(exp_next(L)/e); mins=kills*max(8,ttk+5)/60; tot+=mins
    hit=M['atk'](ml)*(1-mit(p_def(L,armor_for(L))))
    print(f"{L:2d} {exp_next(L):8d}  {m:8s} {ml:5d} {ttk:6.2f} {kills:11d} {mins:18.1f} {hit:13.1f} {p_hp(L)/hit:11.1f}")
print(f"total minutes to Lv15 (phase-1 cap) ~ {tot:.0f} ({tot/60:.1f} h)")
# boss
L=15; a=p_atk(L,38); d=dps(L)*(1-mit(30))
print(f"boss Lv15: HP 6000 / DPS {d:.0f} = {6000/d:.0f}s pure damage time")
# upgrade expected attempts
rates=[100,95,90,85,75,60,50,40,32,25]
import random
random.seed(1)
def attempts_to(target):
    tries=[];
    for _ in range(20000):
        lv=0;n=0
        while lv<target:
            n+=1
            if random.random()*100<rates[lv]: lv+=1
            elif lv>=6: lv-=1
        tries.append(n)
    return sum(tries)/len(tries)
for t in (5,7,10): print(f"avg attempts to +{t}: {attempts_to(t):.1f}")
