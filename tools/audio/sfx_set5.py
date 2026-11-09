import numpy as np, wave, json
SR=44100
ns={}; exec(open('/home/claude/pran-himmapan/tools/audio/thai_synth.py').read().split('pent=[0,1,2,4,5]')[0],ns)
ranat,gong,thai=ns['ranat'],ns['gong'],ns['thai']
pent=[0,1,2,4,5]
def deg(k): o,i=divmod(k,5); return pent[i]+7*o
def L(n):
    w=wave.open(f'src/{n}.wav'); y=np.frombuffer(w.readframes(w.getnframes()),np.int16).astype(float)/32768
    e=np.abs(y); on=np.where(e>e.max()*0.06)[0][0]; y=y[max(0,on-int(SR*0.003)):]
    return y/np.max(np.abs(y))
def sp(y,r): idx=np.arange(0,len(y)-1,r); return np.interp(idx,np.arange(len(y)),y)
def mix(ev,total):
    o=np.zeros(int(SR*total))
    for at,s,g in ev:
        i=int(SR*at); j=min(len(o),i+len(s)); o[i:j]+=g*s[:j-i]
    return o
def fit(y,dur):
    y=y[:int(SR*dur)].copy()
    if len(y)<int(SR*dur): y=np.pad(y,(0,int(SR*dur)-len(y)))
    f=min(int(SR*0.08),len(y)//3); y[-f:]*=np.linspace(1,0,f)**2
    nz=np.where(np.abs(y)>1e-3)[0]; return y[:nz[-1]+1] if len(nz) else y
def twang(f0=140,dur=0.35,bright=0.5,seed=1):
    N=int(SR/f0); rng=np.random.default_rng(seed); buf=rng.uniform(-1,1,N); out=np.zeros(int(SR*dur))
    for i in range(len(out)):
        out[i]=buf[i%N]; buf[i%N]=0.996*(bright*buf[i%N]+(1-bright)*0.5*(buf[i%N]+buf[(i+1)%N]))
    t=np.arange(len(out))/SR; return out*np.exp(-t*7)
def tick(f=1800,dur=0.06):
    t=np.arange(int(SR*dur))/SR; return np.sin(2*np.pi*f*t)*np.exp(-t*90)+0.3*np.sin(2*np.pi*f*2.7*t)*np.exp(-t*140)
out=[]
def save(cat,name,y,note):
    y=y/np.max(np.abs(y))*0.9; fn=f'out/{len(out)+55:02d}.wav'
    w=wave.open(fn,'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((y*32767).astype(np.int16).tobytes()); w.close()
    out.append((cat,name,fn,note))
import os; os.makedirs('out',exist_ok=True)
C='ยิงธนู'
save(C,'ยิงธนู 1',fit(L('western-fps-2d_arrow'),0.4),'ลูกศรพุ่ง (Superpowers)')
save(C,'ยิงธนู 2',fit(twang(130,0.35,0.5),0.35),'ดีดสายธนู "ตึ๋ง" (สร้างเอง)')
save(C,'ยิงธนู 3',fit(mix([(0,twang(130,0.35,0.5),0.8),(0.02,L('Swooshes_swosh-07'),0.7)],0.4),0.4),'ตึ๋ง + วูบ')
save(C,'ยิงธนู 4',fit(mix([(0,twang(170,0.3,0.6,2),0.7),(0.015,sp(L('Swooshes_swosh-19'),1.25),0.8)],0.35),0.35),'ตึ๋งสูง + วูบเร็ว')
save(C,'ยิงธนู 5',fit(mix([(0,twang(150,0.3,0.5,3),0.6),(0.01,L('medieval-fantasy_woosh-1'),0.9)],0.35),0.35),'ตึ๋งเบา + วูบ (Superpowers)')
C='ลูกศรโดนปกติ'
save(C,'โดน 1',fit(L('SFX100_hit_01'),0.3),'ตุบสั้น (rubberduck)')
save(C,'โดน 2',fit(L('SFX100_hit_03'),0.3),'ตุบหนักขึ้น (rubberduck)')
save(C,'โดน 3',fit(L('impact_punch_medium_001'),0.3),'กระแทกกลาง (Kenney)')
save(C,'โดน 4',fit(L('RPG_wood_01'),0.25),'ปึก แบบลูกศรปักไม้ (rubberduck)')
save(C,'โดน 5',fit(mix([(0,L('impact_soft_medium_000'),1.0),(0,ranat(thai(deg(6)),0.2,0.25,0.6),1.0)],0.3),0.3),'ตุบ + ระนาดแตะเบา ๆ')
C='มอนโดน (ร้อง)'
save(C,'มอนโดน 1',fit(L('RPG_creature_hurt_01'),0.45),'ร้องเจ็บ (rubberduck)')
save(C,'มอนโดน 2',fit(L('RPG_creature_hurt_02'),0.45),'ร้องเจ็บอีกแบบ (rubberduck)')
save(C,'มอนโดน 3',fit(L('RPG_creature_misc_01'),0.3),'ร้องสั้น (rubberduck)')
save(C,'มอนโดน 4',fit(L('medieval-fantasy_monster-1'),0.35),'มอนร้อง (Superpowers)')
save(C,'มอนโดน 5',fit(sp(L('RPG_creature_misc_07'),1.15),0.32),'ร้องสั้นเสียงสูง (rubberduck)')
C='มอนตาย (ร้อง)'
save(C,'มอนตาย 1',fit(L('RPG_creature_die_01'),0.8),'ร้องตาย (rubberduck)')
save(C,'มอนตาย 2',fit(L('medieval-fantasy_monster-2'),0.4),'มอนร้องสั้น (Superpowers)')
save(C,'มอนตาย 3',fit(L('top-down-shooter_death'),0.4),'ตายแบบเกม (Superpowers)')
save(C,'มอนตาย 4',fit(sp(L('RPG_creature_misc_03'),0.9),0.6),'ร้องต่ำลากยาว (rubberduck)')
save(C,'มอนตาย 5',fit(mix([(0,L('medieval-fantasy_monster-2'),0.9),(0.18,gong(196,1.0,0.6),0.6)],1.0),0.9),'ร้อง + ฆ้องเบา ๆ ปิดท้าย')
C='เก็บของ'
save(C,'เก็บของ 1',fit(L('RPG_item_gem_01'),0.3),'ไอเทมใส (rubberduck)')
save(C,'เก็บของ 2',fit(L('RPG_item_misc_03'),0.35),'หยิบของ (rubberduck)')
save(C,'เก็บของ 3',fit(mix([(0,ranat(thai(deg(5)),0.3,0.8),1),(0.07,ranat(thai(deg(7)),0.35,0.9),1)],0.45),0.45),'ระนาด 2 เสียงขึ้น')
save(C,'เก็บของ 4',fit(mix([(0,L('handle_small_leather'),0.7),(0.05,ranat(thai(deg(7)),0.35,0.8),1)],0.45),0.45),'หยิบใส่ย่าม + ระนาด')
save(C,'เก็บของ 5',fit(mix([(0,L('SFX100_plop_01'),0.8),(0.03,ranat(thai(deg(9)),0.3,0.6,1.2),1)],0.4),0.4),'ป๊อป + ระนาดสูง')
C='ปุ่ม'
save(C,'ปุ่ม 1',fit(ranat(thai(deg(6)),0.15,1.0,0.6),0.15),'ระนาดตีเบา ๆ')
save(C,'ปุ่ม 2',fit(tick(1700),0.08),'ติ๊กไม้สั้น (สร้างเอง)')
save(C,'ปุ่ม 3',fit(L('SFX100_switch_01'),0.15),'สวิตช์ (rubberduck)')
save(C,'ปุ่ม 4',fit(L('RPG_wood_03'),0.15),'เคาะไม้ (rubberduck)')
save(C,'ปุ่ม 5',fit(mix([(0,tick(1400,0.05),0.6),(0.005,ranat(thai(deg(8)),0.15,0.5,0.4),1)],0.15),0.15),'ติ๊ก + ระนาดสูงแผ่ว')
C='เปิดกระเป๋า / เมนู'
save(C,'เปิด 1',fit(L('cloth_1'),0.4),'ผ้าสะบัด (Kenney)')
save(C,'เปิด 2',fit(L('RPG_book_01'),0.5),'เปิดสมุด (rubberduck)')
save(C,'เปิด 3',fit(L('SFX100_paper_01'),0.35),'กระดาษ (rubberduck)')
save(C,'เปิด 4',fit(mix([(0,L('cloth_3'),0.7),(0.06,ranat(thai(deg(4)),0.3,0.7),1),(0.13,ranat(thai(deg(6)),0.3,0.7),1)],0.5),0.5),'ผ้า + ระนาด 2 เสียง')
save(C,'เปิด 5',fit(mix([(0,ranat(thai(deg(3+i)),0.25,0.6),1) for i in range(1)]+[(i*0.05,ranat(thai(deg(3+i)),0.25,0.6),1) for i in range(1,4)],0.45),0.45),'ระนาดไล่ 4 เสียงเร็ว')
C='แจ้งเตือน'
save(C,'แจ้งเตือน 1',fit(mix([(0,gong(thai(deg(2),base=330),0.8,1.0),1)],0.8),0.7),'ฆ้องเล็ก 1 ลูก')
save(C,'แจ้งเตือน 2',fit(mix([(0,gong(thai(deg(2),base=330),0.7,1.0),1),(0.15,gong(thai(deg(4),base=330),0.7,1.0),1)],0.8),0.8),'ฆ้องเล็ก 2 ลูกขึ้น')
save(C,'แจ้งเตือน 3',fit(mix([(0,ranat(thai(deg(5)),0.35,0.9),1),(0.12,ranat(thai(deg(5)),0.35,0.9),1)],0.5),0.5),'ระนาดตีซ้ำ 2 ครั้ง')
save(C,'แจ้งเตือน 4',fit(L('RPG_item_gem_03'),0.35),'เสียงใสสั้น (rubberduck)')
save(C,'แจ้งเตือน 5',fit(mix([(0,ranat(thai(deg(7)),0.4,0.8),1),(0.1,gong(thai(deg(2),base=330),0.7,0.6),1)],0.7),0.7),'ระนาด + ฆ้องเล็ก')
json.dump(out,open('out/list.json','w'),ensure_ascii=False)
print(len(out))
