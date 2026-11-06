"""Balance sanity check for docs/spec-numbers.md (phase 1, cap Lv10). Run: python3 tools/balance_sim.py"""
import math, random
def exp_next(L): return round(45 * L**1.8 * 1.035**L)
def p_hp(L): return 100+12*(L-1)
def p_atk(L,bow): return 10+2*(L-1)+bow
def p_def(L,armor): return 2+(L-1)+armor
def mit(d): return d/(d+100)
def bow_for(L): return 8 if L<5 else 16
def armor_for(L): return 4 if L<4 else (10 if L<8 else 18)
MON={'wolf':dict(hp=lambda l:40+18*(l-1),atk=lambda l:6+2*(l-1),df=lambda l:2+l,exp=lambda l:8+5*l),
     'kongkoi':dict(hp=lambda l:70+25*(l-1),atk=lambda l:9+2.5*(l-1),df=lambda l:3+1.5*l,exp=lambda l:14+7*l)}
CRIT=0.05; CDMG=1.5; APS=1.25
def sk(L,unlock): return 1+0.05*max(0,L-unlock)   # skill level = L-unlock+1, +5%/level
def dps(L):
    a=p_atk(L,bow_for(L))
    basic=a*APS*(1+CRIT*(CDMG-1))
    skills=a*(1.8*sk(L,1)/4 + (0.7*5*0.6*sk(L,3))/6 + (2.4*sk(L,7)/10 if L>=7 else 0))
    return basic+skills
def mob_level(L):
    return ('wolf',min(6,L)) if L<=4 else ('kongkoi',max(4,min(9,L)))
print('Lv  exp_next  mob      mobLv  TTK(s) kills  min_to_lv  hits_to_die')
tot=0
for L in range(1,10):
    m,ml=mob_level(L); M=MON[m]
    ttk=M['hp'](ml)/(dps(L)*(1-mit(M['df'](ml))))
    e=M['exp'](ml)*(0.3 if ml<L-5 else 1)
    kills=math.ceil(exp_next(L)/e); mins=kills*max(8,ttk+5)/60; tot+=mins
    hit=M['atk'](ml)*(1-mit(p_def(L,armor_for(L))))
    print(f"{L:2d} {exp_next(L):8d}  {m:8s} {ml:5d} {ttk:6.2f} {kills:5d} {mins:10.1f} {p_hp(L)/hit:11.1f}")
print(f"total minutes to Lv10 (phase-1 cap) ~ {tot:.0f}")
print('long-term curve (exp to next level):',{L:exp_next(L) for L in (10,20,30,50,70,90,98)})
d=dps(10)*(1-mit(25)); print(f"boss Lv10: HP 4000 / DPS {d:.0f} = {4000/d:.0f}s pure damage time")
rates=[100,95,90,85,75,60,50,40,32,25]; random.seed(1)
def attempts_to(t):
    s=0
    for _ in range(20000):
        lv=n=0
        while lv<t:
            n+=1
            if random.random()*100<rates[lv]: lv+=1
            elif lv>=6: lv-=1
        s+=n
    return s/20000
for t in (5,7,10): print(f"avg attempts to +{t}: {attempts_to(t):.1f}")
