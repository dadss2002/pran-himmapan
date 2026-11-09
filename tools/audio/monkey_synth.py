import numpy as np, wave
from scipy.signal import lfilter
SR=44100; rng=np.random.default_rng(11)
def res(x,f,bw):
    r=np.exp(-np.pi*bw/SR); th=2*np.pi*f/SR
    return lfilter([1-r],[1,-2*r*np.cos(th),r*r],x)
def voice(f0c, dur, formants, rough=0.0, breath=0.05):
    """f0c: function t->Hz ; formants: function t->[(f,bw,g)]"""
    n=int(SR*dur); t=np.arange(n)/SR
    f0=f0c(t)*(1+0.01*rng.normal(0,1,n).cumsum()/np.sqrt(np.arange(1,n+1)))
    ph=np.cumsum(f0)/SR; src=2*(ph%1)-1
    src=src+rough*np.sign(np.sin(2*np.pi*ph*0.5))*0.3+breath*rng.normal(0,1,n)
    # formants in 4 blocks over time
    out=np.zeros(n); B=8
    for k in range(B):
        a,b=k*n//B,(k+1)*n//B; seg=src[max(0,a-400):b]
        y=sum(g*res(seg,f,bw) for f,bw,g in formants(t[(a+b)//2]))
        out[a:b]=y[-(b-a):]
    return out
def env(n,att=0.01,rel=0.08):
    t=np.arange(n)/SR; d=n/SR
    return np.clip(t/att,0,1)*np.clip((d-t)/rel,0,1)
def call(f_lo,f_hi,dur,vowel='ook',rough=0.0):
    n=int(SR*dur)
    f0=lambda t: f_lo+(f_hi-f_lo)*np.sin(np.pi*np.clip(t/dur,0,1))**0.7
    if vowel=='ook': F=lambda t:[(500,120,1.0),(900,150,0.5),(2600,300,0.15)]
    elif vowel=='eek': F=lambda t:[(700,150,0.6),(2300,250,1.0),(3200,400,0.4)]
    else: F=lambda t:[(600+400*t/dur,140,1.0),(1000+1500*t/dur,200,0.7),(2900,350,0.3)]  # oo->ee glide
    return voice(f0,dur,F,rough)*env(n)
def seq(parts,gap=0.0):
    out=[]
    for p in parts: out.append(p); out.append(np.zeros(int(SR*gap)))
    return np.concatenate(out)
def save(n,y):
    y=y/np.max(np.abs(y))*0.9
    w=wave.open(n,'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((y*32767).astype(np.int16).tobytes()); w.close()
# hurt variants
save('h1.wav',call(900,1700,0.18,'glide',0.2))                                   # short "เอี๊ยก"
save('h2.wav',seq([call(700,1000,0.08,'ook'),call(800,1200,0.08,'ook')],0.03))   # "อุ๊ก-อุ๊ก"
save('h3.wav',call(1300,2400,0.16,'eek',0.4))                                    # screech
save('h4.wav',seq([call(600,900,0.07,'ook'),call(1200,2100,0.14,'eek',0.3)],0.02)) # "อุ๊-เจี๊ยก"
save('h5.wav',seq([call(1000,1500,0.06,'eek')]*3,0.025))                          # chatter
# death variants
save('d1.wav',seq([call(1200,2200,0.2,'eek',0.4),call(1100,600,0.35,'ook',0.1)],0.03))   # screech then falling
save('d2.wav',seq([call(800,1100,0.07,'ook')]*2+[call(1500,700,0.4,'glide',0.3)],0.03))   # ook ook eeeooo
save('d3.wav',call(1600,500,0.45,'glide',0.35))                                           # long falling wail
