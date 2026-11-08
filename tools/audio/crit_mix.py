"""Critical-hit sound (owner pick 2026-11-08: page no. 52 = "46 ไม่เอาเสียงกระดิ่ง").
Run from the repo root: python3 tools/audio/crit_mix.py  -> docs/audio_samples/crit/crit_hit.wav
Only the final mix is written; the other variants were review candidates."""
import numpy as np, wave, sys
SR=44100
def rd(p):
    w=wave.open(p); y=np.frombuffer(w.readframes(w.getnframes()),np.int16).astype(float)/32768; return y/np.max(np.abs(y))
def raw(n): return rd(f'docs/audio_samples/crit/src_{n}.wav')
def onset(y): e=np.abs(y); on=np.where(e>e.max()*0.08)[0][0]; return y[max(0,on-int(SR*0.004)):]
pang=onset(rd('docs/audio_samples/crit/src_bang_05.wav'))
def ring(f,dur=0.7,dec=6):
    t=np.arange(int(SR*dur))/SR
    return sum(a*np.exp(-d*t)*np.sin(2*np.pi*f*r*t) for r,a,d in [(1,1,dec),(2.76,0.5,dec*1.6),(5.4,0.3,dec*2.5),(1.006,0.6,dec)])*(1-np.exp(-t*3000))
def mix(ev,total):
    o=np.zeros(int(SR*total))
    for at,s,g in ev:
        i=int(SR*at); j=min(len(o),i+len(s)); o[i:j]+=g*s[:j-i]
    return o
def echo(y,rev):
    for d,g in ((0.031,rev),(0.067,rev*0.7),(0.113,rev*0.45),(0.171,rev*0.3)):
        k=int(SR*d); r=np.zeros_like(y); r[k:]=y[:-k]*g; y=y+r
    return y
def end(y,total):
    y=y[:int(SR*total)]; f=int(SR*0.12); y[-f:]*=np.linspace(1,0,f)**2; return y
def save(n,y):
    y=y/np.max(np.abs(y))*0.9
    w=wave.open(n,'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((y*32767).astype(np.int16).tobytes()); w.close()
blade,sheet,punch=raw('blade_03'),raw('metal_sheet_03'),raw('impact_punch_heavy_000')
c32=lambda: mix([(0,blade,0.9),(0.05,sheet,0.7),(0.05,punch,0.7),(0.06,ring(1320,1.0,3.5),0.3)],1.2)
c32nb=lambda sheet_g=0.7: mix([(0,blade,0.9),(0.05,sheet,sheet_g),(0.05,punch,0.7)],1.2)
save('docs/audio_samples/crit/crit_hit.wav',end(echo(mix([(0,c32nb(),1.0),(0.05,pang,0.9)],1.2),0.22),0.7))
