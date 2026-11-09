import numpy as np, wave, json
from scipy.signal import lfilter, butter
SR=44100; rng=np.random.default_rng(21)
def res(x,f,bw):
    r=np.exp(-np.pi*bw/SR); th=2*np.pi*f/SR
    return lfilter([1-r],[1,-2*r*np.cos(th),r*r],x)
def bp(x,lo,hi): b,a=butter(2,[lo/(SR/2),min(hi/(SR/2),0.99)],'band'); return lfilter(b,a,x)
def lp(x,hi): b,a=butter(2,hi/(SR/2)); return lfilter(b,a,x)
def env(n,att=0.01,rel=0.08):
    t=np.arange(n)/SR; d=n/SR; return np.clip(t/att,0,1)*np.clip((d-t)/rel,0,1)
def voice(f0fn,dur,forms,rough=0.0,breath=0.05,jit=0.01,pulse=False):
    n=int(SR*dur); t=np.arange(n)/SR; f0=f0fn(t)*(1+jit*np.sin(2*np.pi*23*t+rng.uniform(0,6)))
    ph=np.cumsum(f0)/SR
    src=(np.where(ph%1<0.15,1.0,-0.18) if pulse else 2*(ph%1)-1)
    if rough: src=src*(1+rough*np.sin(2*np.pi*f0*0.5*t+rng.uniform(0,6)))+rough*0.4*rng.normal(0,1,n)
    src=src+breath*rng.normal(0,1,n)
    out=np.zeros(n); B=10
    for k in range(B):
        a,b=k*n//B,(k+1)*n//B; seg=src[max(0,a-500):b]
        y=sum(g*res(seg,f,bw) for f,bw,g in forms(t[(a+b)//2]/dur))
        out[a:b]=y[-(b-a):]
    return out*env(n)
def glide(a,b,shape=1.0): return lambda t: a+(b-a)*(t/ t[-1] if len(t) else 0)**shape
def lin(a,b): return lambda t: a+(b-a)*(t/max(t[-1],1e-9))
def arch(a,b): return lambda t: a+(b-a)*np.sin(np.pi*t/max(t[-1],1e-9))
def seq(parts,gap=0.03):
    o=[]
    for p in parts: o+= [p,np.zeros(int(SR*gap))]
    return np.concatenate(o)
def noise(dur,dec=8,att=0.01): n=int(SR*dur); t=np.arange(n)/SR; return rng.normal(0,1,n)*np.exp(-t*dec)*np.clip(t/att,0,1)
def rev(y,amt=0.3):
    y=np.pad(y,(0,int(SR*0.5))); o=y.copy()
    for d,g in ((0.05,1),(0.11,0.7),(0.19,0.5),(0.29,0.35),(0.41,0.2)): k=int(SR*d); o[k:]+=y[:-k]*g*amt
    return o
OO=lambda u:[(450,120,1.0),(850,150,0.5),(2500,300,0.12)]
EE=lambda u:[(350,120,0.6),(2300,250,1.0),(3100,400,0.35)]
AH=lambda u:[(750,130,1.0),(1200,160,0.7),(2600,300,0.2)]
NASAL=lambda u:[(280,80,1.0),(1100,200,0.5),(2400,300,0.2)]
EE2OO=lambda u:[(350+100*u,120,0.8),(2300-1400*u,250,1.0),(3000,400,0.25)]
EH=lambda u:[(550,120,1.0),(1800,200,0.7),(2600,300,0.25)]
def add(*xs):
    n=max(len(x) for x in xs); return sum(np.pad(x,(0,n-len(x))) for x in xs)
out=[]
def save(kind,th,which,name,y,note):
    y=y/np.max(np.abs(y))*0.9; fn=f'{kind}_{which}_{name}.wav'
    w=wave.open(fn,'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((y*32767).astype(np.int16).tobytes()); w.close()
    out.append((kind,th,which,fn,note))
# WOLF
save('wolf','หมาป่า','hurt','a',voice(lin(1100,650),0.28,EE2OO,0.1),'เอ๋ง (เสียงตก)')
save('wolf','หมาป่า','hurt','b',seq([voice(lin(1000,700),0.12,EE2OO),voice(lin(900,600),0.15,EE2OO)],0.04),'เอ๋ง-เอ๋ง')
save('wolf','หมาป่า','hurt','c',voice(lambda t:110+20*np.sin(2*np.pi*6*t),0.35,AH,0.6,0.2,pulse=True),'ขู่คำราม "แฮ่"')
save('wolf','หมาป่า','die','a',voice(lin(900,350),0.7,EE2OO,0.15),'ครางหงิง เสียงตกยาว')
save('wolf','หมาป่า','die','b',seq([voice(lin(1000,650),0.12,EE2OO),voice(lambda t:600-250*(t/max(t[-1],1e-9))+30*np.sin(2*np.pi*7*t),0.6,OO,0.1)],0.03),'เอ๋ง แล้วหอนสั้นแผ่ว')
# BOAR
save('boar','หมูป่า','hurt','a',seq([voice(lin(180,140),0.12,NASAL,0.5,pulse=True),voice(lin(170,130),0.14,NASAL,0.5,pulse=True)],0.04),'อู๊ด-อู๊ด ต่ำ')
save('boar','หมูป่า','hurt','b',voice(arch(900,1500),0.3,EH,0.7,0.2),'ร้องแหลมแบบหมู')
save('boar','หมูป่า','hurt','c',voice(lambda t:120+10*np.sin(2*np.pi*9*t),0.3,NASAL,0.8,0.25,pulse=True),'ฮึดฮัดครางต่ำ')
save('boar','หมูป่า','die','a',seq([voice(arch(1000,1600),0.3,EH,0.7,0.2),voice(lin(200,90),0.45,NASAL,0.7,0.2,pulse=True)],0.02),'ร้องแหลมแล้วครางต่ำ')
save('boar','หมูป่า','die','b',voice(lin(160,70),0.7,NASAL,0.8,0.25,pulse=True),'ครางต่ำยาวหมดแรง')
# DEER
save('deer','กวาง','hurt','a',voice(lambda t:520+40*np.sin(2*np.pi*11*t),0.35,EH,0.1),'แบ๊ะ (สั่นเสียง)')
save('deer','กวาง','hurt','b',lp(noise(0.12,25),2500)+0.6*voice(lin(450,380),0.12,AH,0.4,0.4),'เห่าสั้นแบบกวาง "ฮ่อบ"')
save('deer','กวาง','hurt','c',voice(arch(700,1000),0.25,EE2OO,0.05),'ร้องเสียงสูงสั้น')
save('deer','กวาง','die','a',voice(lambda t:(520-200*(t/max(t[-1],1e-9)))*(1+0.06*np.sin(2*np.pi*9*t)),0.7,EH,0.15),'แบ๊ะยาว เสียงตก')
save('deer','กวาง','die','b',seq([lp(noise(0.12,25),2500)+0.6*voice(lin(450,380),0.12,AH,0.4,0.4),voice(lin(600,300),0.5,EE2OO,0.1)],0.05),'เห่า แล้วครางเสียงตก')
# KONGKOI (Thai forest spirit, one-legged hopper): eerie breathy, reverb
save('kongkoi','กองกอย','hurt','a',rev(voice(lin(300,240),0.35,OO,0.2,0.6),0.4),'ครางหลอนแหบ ๆ')
save('kongkoi','กองกอย','hurt','b',rev(seq([voice(lin(900,1200),0.08,EE,0.1,0.5)]*2,0.06),0.45),'"กอย-กอย" หวีดเบา')
save('kongkoi','กองกอย','hurt','c',rev(bp(noise(0.4,6,0.05),800,3000)*0.6+voice(lin(220,180),0.4,OO,0.3,0.4),0.4),'กระซิบหลอน')
save('kongkoi','กองกอย','die','a',rev(voice(lambda t:(320-180*(t/max(t[-1],1e-9)))*(1+0.04*np.sin(2*np.pi*5*t)),1.0,OO,0.25,0.6),0.5),'โหยหวนต่ำยาว')
save('kongkoi','กองกอย','die','b',rev(seq([voice(lin(1100,800),0.15,EE,0.1,0.5),voice(lin(400,150),0.8,OO,0.3,0.6)],0.04),0.5),'หวีดแล้วโหยหวนจาง')
# SHROOM
def squish(d=0.18):
    n=noise(d,14); return lp(bp(n,200,1800),1500)
save('shroom','เห็ด','hurt','a',add(squish(),0.4*voice(arch(1300,1900),0.1,EE,0.0)),'ยุบ + เสียงแหลมจิ๋ว')
save('shroom','เห็ด','hurt','b',seq([squish(0.08),squish(0.08)],0.02),'ยุบยับ 2 ที')
save('shroom','เห็ด','hurt','c',add(bp(noise(0.25,10,0.02),1500,6000)*0.7,squish(0.1)),'พ่นสปอร์ฟู่')
save('shroom','เห็ด','die','a',seq([squish(0.12),bp(noise(0.5,5,0.02),1200,6000)*0.6],0.0),'ยุบแล้วสปอร์ฟุ้ง')
save('shroom','เห็ด','die','b',seq([voice(lin(1800,900),0.25,EE,0.05),squish(0.2)],0.01),'ร้องจิ๋วเสียงตก + ยุบ')
# VIPER
def hiss(d,dec=6,lo=3000,hi=9000): return bp(noise(d,dec,0.03),lo,hi)
save('viper','งู','hurt','a',hiss(0.3,9),'ฟ่อสั้น')
save('viper','งู','hurt','b',seq([hiss(0.1,20),hiss(0.12,18)],0.03),'ฟ่อ-ฟ่อ')
save('viper','งู','hurt','c',hiss(0.35,8,2000,7000)+0.15*lp(noise(0.35,8),300),'ขู่ฟ่อเสียงต่ำ')
save('viper','งู','die','a',hiss(0.8,3.5),'ฟ่อยาวหมดแรง')
save('viper','งู','die','b',seq([hiss(0.12,18),hiss(0.6,4,2500,8000)],0.04),'ฟ่อสั้นแล้วลากยาว')
json.dump(out,open('list.json','w'),ensure_ascii=False); print(len(out))
