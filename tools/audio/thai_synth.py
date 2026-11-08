import numpy as np, wave, sys
SR=44100
rng=np.random.default_rng(7)
def thai(step, base=523.25):   # Thai 7-tone equal: step in scale degrees from base (C5-ish)
    return base*2**(step/7)
def ranat(f, dur=0.55, vel=1.0, bright=1.0):
    t=np.arange(int(SR*dur))/SR
    parts=[(1.0,1.0,7.0),(3.93,0.35*bright,16.0),(9.2,0.12*bright,30.0),(2.02,0.08,10.0)]
    y=sum(a*np.exp(-d*t)*np.sin(2*np.pi*f*r*t+rng.uniform(0,6.28)) for r,a,d in parts)
    # mallet click
    n=int(SR*0.006); click=rng.normal(0,1,n)*np.linspace(1,0,n)**2*0.5*bright
    y[:n]+=click
    # wooden resonator body
    y*= (1-np.exp(-t*900))
    return y*vel
def gong(f, dur=2.2, vel=1.0):
    t=np.arange(int(SR*dur))/SR
    parts=[(1.0,1.0,1.6),(1.003,0.6,1.7),(2.0,0.25,2.5),(2.74,0.18,3.5),(4.1,0.08,6),(0.5,0.12,1.2)]
    y=sum(a*np.exp(-d*t)*np.sin(2*np.pi*f*r*t+rng.uniform(0,6.28)) for r,a,d in parts)
    n=int(SR*0.01); y[:n]+=rng.normal(0,1,n)*np.linspace(1,0,n)**3*0.25
    y*=(1-np.exp(-t*400))
    return y*vel
def mix(events, total):
    out=np.zeros(int(SR*total))
    for at,sig in events:
        i=int(SR*at); j=min(len(out),i+len(sig)); out[i:j]+=sig[:j-i]
    return out
def save(name,y):
    y=y/np.max(np.abs(y))*0.85
    # tiny room reverb
    d=int(SR*0.045); r=np.zeros_like(y); r[d:]=y[:-d]*0.25; y=y+r
    d=int(SR*0.09); r=np.zeros_like(y); r[d:]=y[:-d]*0.12; y=y+r
    y=y/np.max(np.abs(y))*0.85
    with wave.open(name,'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((y*32767).astype(np.int16).tobytes())
pent=[0,1,2,4,5]   # Thai pentatonic subset of 7-tone
def deg(k): o,i=divmod(k,5); return pent[i]+7*o
# 1 ranat level-up: fast rising run then octave double strike (kep)
ev=[(i*0.075,ranat(thai(deg(i)),0.5,0.8)) for i in range(7)]
top=thai(deg(7)); ev+= [(0.56,ranat(top,0.9,1.0)),(0.56,ranat(top/2,0.9,0.7))]
save('ranat_levelup_a.wav',mix(ev,1.6))
# 2 ranat level-up b: run up and back, softer
seq=[0,1,2,3,4,5,6,5,7]
ev=[(i*0.085,ranat(thai(deg(k)),0.5,0.75)) for i,k in enumerate(seq)]
ev+=[(len(seq)*0.085,ranat(thai(deg(9)),1.0,1.0)),(len(seq)*0.085,ranat(thai(deg(4)),1.0,0.6))]
save('ranat_levelup_b.wav',mix(ev,1.9))
# 3 ranat chest: kraw roll (tremolo alternating octave) then 3 notes up
f=thai(deg(2)); ev=[(i*0.045,ranat(f if i%2==0 else f*2,0.3,0.45+0.04*i)) for i in range(10)]
ev+=[(0.5+i*0.09,ranat(thai(deg(5+i)),0.6,0.9)) for i in range(3)]
save('ranat_chest.wav',mix(ev,1.5))
# 4 ranat coin: single high double hit
f=thai(deg(8)); save('ranat_coin.wav',mix([(0,ranat(f,0.45,1.0,1.3)),(0.07,ranat(f*2**(1/7),0.45,0.8,1.3))],0.6))
# 5 gong level-up: three gongs ascending
ev=[(i*0.28,gong(thai(deg(i*2),base=220),2.0,0.9)) for i in range(3)]
save('gong_levelup.wav',mix(ev,2.8))
# 6 gong chest: low gong + ranat sparkle
ev=[(0,gong(110,2.6,1.0)),(0.02,gong(220,2.2,0.5))]+[(0.25+i*0.06,ranat(thai(deg(5+i)),0.4,0.45)) for i in range(5)]
save('gong_chest.wav',mix(ev,2.8))
# 7 gong warp: single mid gong, slow swell feel
save('gong_warp.wav',mix([(0,gong(thai(deg(2),base=165),2.4,1.0))],2.4))
# 8 ranat hit (critical accent)
save('ranat_crit.wav',mix([(0,ranat(thai(deg(3)),0.35,1.0,1.6)),(0,ranat(thai(deg(8)),0.35,0.7,1.6))],0.45))
