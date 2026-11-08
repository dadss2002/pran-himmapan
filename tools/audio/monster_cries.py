import numpy as np, wave, json
exec(open('b.py').read().split("out=[]")[0])
def rev(y,amt=0.3,taps=((0.04,1),(0.09,0.7),(0.15,0.5),(0.23,0.35),(0.33,0.2))):
    y=np.pad(y,(0,int(SR*0.4)))
    o=y.copy()
    for d,g in taps: k=int(SR*d); o[k:]+=y[:-k]*g*amt
    return o
def vib(y,rate=7,depth=0.012):
    t=np.arange(len(y))/SR; idx=np.arange(len(y))+depth*SR/ (2*np.pi*rate)*np.sin(2*np.pi*rate*t)
    return np.interp(np.clip(idx,0,len(y)-1),np.arange(len(y)),y)
def hiss(dur=0.4,dec=5,seed=4):
    t=np.arange(int(SR*dur))/SR; n=np.random.default_rng(seed).normal(0,1,len(t))
    n=np.diff(np.concatenate([[0],n])); n=np.diff(np.concatenate([[0],n]))  # brighter
    env=(1-np.exp(-t*60))*np.exp(-t*dec); return n*env
m67=L('RPG_creature_misc_01'); m68=L('medieval-fantasy_monster-1'); m69=L('RPG_creature_misc_07'); m70=L('RPG_creature_die_01')
slime=L('RPG_creature_slime_01')
K=[]
def put(kind,th,which,y,note):
    y=y/np.max(np.abs(y))*0.9; fn=f'mon/{kind}_{which}.wav'
    w=wave.open(fn,'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((y*32767).astype(np.int16).tobytes()); w.close()
    K.append((kind,th,which,fn,note))
import os; os.makedirs('mon',exist_ok=True)
put('wolf','หมาป่า','hurt',fit(sp(m67,1.2),0.3),'67 สูงขึ้น เหมือนหมาร้องเอ๋ง')
put('wolf','หมาป่า','die',fit(sp(m70,1.1),0.7),'70 สูงขึ้นเล็กน้อย')
put('boar','หมูป่า','hurt',fit(sp(m68,0.72),0.45),'68 ต่ำลง เสียงครางหนัก')
put('boar','หมูป่า','die',fit(sp(m70,0.75),0.9),'70 ต่ำลง ตัวใหญ่')
put('deer','กวาง','hurt',fit(vib(sp(m69,1.05)),0.35),'69 สั่นเสียงแบบร้องแบ๊')
put('deer','กวาง','die',fit(vib(sp(m70,1.25),6,0.015),0.6),'70 สูงขึ้น + สั่นเสียง')
put('macaque','ลิง','hurt',fit(sp(m69,1.4),0.25),'69 สูงมาก แหลมแบบลิงร้อง')
put('macaque','ลิง','die',fit(mix([(0,sp(m67,1.35),1),(0.12,sp(m69,1.5),0.8)],0.5),0.45),'67 + 69 สูง ร้องสองจังหวะ')
put('kongkoi','กองกอย','hurt',fit(rev(sp(m68,0.9),0.35),0.6),'68 ต่ำนิด + ก้องหลอน')
put('kongkoi','กองกอย','die',fit(rev(mix([(0,sp(m70,0.85),1),(0.25,gong(110,1.4,0.5),0.5)],1.5),0.4),1.4),'70 ต่ำ + ก้องหลอน + ฆ้องต่ำ')
put('shroom','เห็ด','hurt',fit(sp(slime,1.3),0.3),'เสียงเหลวยุบ (สไลม์)')
put('shroom','เห็ด','die',fit(mix([(0,sp(slime,1.1),1),(0.05,sp(m67,1.6),0.5)],0.6),0.55),'เหลวยุบ + ร้องจิ๋ว')
put('viper','งู','hurt',fit(mix([(0,hiss(0.3,9),0.8),(0,sp(m67,0.95),0.35)],0.35),0.3),'ขู่ฟ่อสั้น')
put('viper','งู','die',fit(mix([(0,hiss(0.7,4,5),0.9),(0.05,sp(m70,0.9),0.35)],0.8),0.75),'ขู่ฟ่อยาว + ครางต่ำ')
json.dump(K,open('mon/list.json','w'),ensure_ascii=False); print(len(K))
