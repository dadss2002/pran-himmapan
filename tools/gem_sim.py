"""Gem + MP balance sim at Lv10 (docs/gems.md). Run: python3 tools/gem_sim.py"""
# Gem + MP sim at Lv10
def mit(d): return d/(d+100)
L=10
MP_MAX=50+5*(L-1); REGEN=6.0
def atk(bow,up,atkpct): return (10+2*(L-1)+bow*(1+0.06*min(up,6)+0.10*max(0,up-6)))*(1+atkpct)
def critf(c,cd): return 1+min(1,0.05+c)*(0.5+cd)
# skills: name, unlock, mult, cd, mp
SK=[('pierce',1,1.8,4,8),('spread',3,0.7*5*0.6,6,12),('rain',7,2.4,10,18),('fire',10,2.6,6,14)]
GEM={'none':(1.0,1.0),'split':(3*0.6,1.4),'more':(1.35,1.5),'crit':(1.0,1.2),'elem':(1.1,1.3)}
def run(gems,bow,up,atkpct,c,cd,aspd,regen=REGEN):
    A=atk(bow,up,atkpct); cf=critf(c,cd)
    basic=A*1.25*(1+aspd)*cf
    opts=[]
    for (n,u,m,cdn,mp) in SK:
        sl=L-u+1; dm=m*(1+0.05*(sl-1)); cdv=cdn*(1-0.01*(sl-1)); cost=mp
        for g in gems.get(n,[]):
            dm*=GEM[g][0]; cost*=GEM[g][1]
            if g=='crit': dm*= (1+min(1,0.05+c+0.15)*(0.5+cd))/cf
        opts.append((A*dm*cf, cdv, cost))
    budget=regen; dps=basic
    for d,cdv,cost in sorted(opts,key=lambda o:-o[0]/o[2]):
        rate=min(1/cdv, budget/cost); dps+=d*rate; budget-=rate*cost
    return dps
cases={
 'ปกติ ไม่มีเจม':run({},26,3,0.05,0.03,0,0),
 'ปกติ + เจม 1 เม็ดต่อสกิล':run({'pierce':['split'],'spread':['crit'],'rain':['elem'],'fire':['more']},26,3,0.05,0.03,0,0),
 'สุดทาง ไม่มีเจม':run({},26,10,0.24,0.15,0.6,0.30),
 'สุดทาง + เจม 2 เม็ด (ศรทะลวง Lv10)':run({'pierce':['split','more'],'spread':['crit'],'rain':['elem'],'fire':['more']},26,10,0.24,0.15,0.6,0.30),
 'สุดทาง + เจม 2 เม็ด ถ้าไม่มี MP คุม':run({'pierce':['split','more'],'spread':['crit'],'rain':['elem'],'fire':['more']},26,10,0.24,0.15,0.6,0.30,regen=999),
}
b=list(cases.values())[0]
for k,v in cases.items(): print(f"{k:40s} DPS {v:5.0f} x{v/b:.2f}  บอส {4000/(v*(1-mit(25))):5.1f}s")
def gexp(g): return round(150*g**1.7)
tot=0; total_char=sum(round(45*l**1.8*1.035**l) for l in range(1,10))
lv=1
while lv<20 and tot+gexp(lv)<=total_char: tot+=gexp(lv); lv+=1
print('char EXP Lv1->10 =',total_char,'-> gem socketed from start reaches Lv',lv, '| gem exp to next at 1,5,10,19:',[gexp(g) for g in (1,5,10,19)])
