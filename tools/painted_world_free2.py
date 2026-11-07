import sys
sys.path.insert(0,'/home/claude/pran-himmapan/tools')
import numpy as np, cv2
from PIL import Image
import os
os.chdir('/home/claude/pran-himmapan')
import painted_world as pw
raw, full, filled, cells = pw.compose()
CW,CH,ROWS,COLS=pw.CW,pw.CH,pw.ROWS,pw.COLS
R=64; LV=5
def lap_blend(a,b,m):
    # a,b HxWx3 float, m HxW weight for b (0..1)
    ga=[a];gb=[b];gm=[m]
    for i in range(LV):
        ga.append(cv2.pyrDown(ga[-1]));gb.append(cv2.pyrDown(gb[-1]));gm.append(cv2.pyrDown(gm[-1]))
    la=[ga[i]-cv2.pyrUp(ga[i+1],dstsize=(ga[i].shape[1],ga[i].shape[0])) for i in range(LV)]+[ga[LV]]
    lb=[gb[i]-cv2.pyrUp(gb[i+1],dstsize=(gb[i].shape[1],gb[i].shape[0])) for i in range(LV)]+[gb[LV]]
    out=None
    for i in range(LV,-1,-1):
        w=gm[i][...,None]
        l=la[i]*(1-w)+lb[i]*w
        out=l if out is None else cv2.pyrUp(out,dstsize=(l.shape[1],l.shape[0]))+l
    return out
def multiband(img):
    out=img.copy()
    for r in range(ROWS):
        for c in range(1,COLS):
            if not(filled[r,c-1] and filled[r,c]): continue
            x=c*CW; ys=slice(r*CH,(r+1)*CH)
            L=out[ys,x-R:x]; Rr=out[ys,x:x+R]
            a=np.concatenate([L,L[:,::-1]],1); b=np.concatenate([Rr[:,::-1],Rr],1)
            m=np.zeros(a.shape[:2],np.float32); m[:,R:]=1
            out[ys,x-R:x+R]=lap_blend(a,b,m)
    for r in range(1,ROWS):
        for c in range(COLS):
            if not(filled[r-1,c] and filled[r,c]): continue
            y=r*CH; xs=slice(c*CW,(c+1)*CW)
            T=out[y-R:y,xs]; B=out[y:y+R,xs]
            a=np.concatenate([T,T[::-1]],0); b=np.concatenate([B[::-1],B],0)
            m=np.zeros(a.shape[:2],np.float32); m[R:,:]=1
            out[y-R:y+R,xs]=lap_blend(a,b,m)
    return np.clip(out,0,255)
def dp_seam(cost):
    # minimal path top->bottom through cost (H x W), step |dx|<=1; returns x per row
    H,W=cost.shape; acc=cost.copy(); back=np.zeros((H,W),int)
    for y in range(1,H):
        for x in range(W):
            lo,hi=max(0,x-1),min(W,x+2)
            k=int(np.argmin(acc[y-1,lo:hi]))+lo
            back[y,x]=k; acc[y,x]+=acc[y-1,k]
    xs=[int(np.argmin(acc[-1]))]
    for y in range(H-1,0,-1): xs.append(back[y,xs[-1]])
    return xs[::-1]
def cut_patch(world, A, B, at, bands):
    """bands: top (y0,y1), bottom (y0,y1), left (x0,x1), right (x0,x1) inside the window; B wins inside the cut."""
    x0,y0=at
    e=cv2.GaussianBlur(np.abs(A-B).sum(2),(0,0),1.2)
    H,W=e.shape
    inside=np.ones((H,W),bool)
    (t0,t1),(b0,b1),(l0,l1),(r0,r1)=bands
    top=dp_seam(e[t0:t1,:].T); bot=dp_seam(e[b0:b1,:].T)
    left=dp_seam(e[:,l0:l1]); right=dp_seam(e[:,r0:r1])
    yy,xx=np.mgrid[0:H,0:W]
    inside&=yy>=np.array(top)[None,:]+t0
    inside&=yy<=np.array(bot)[None,:]+b0
    inside&=xx>=np.array(left)[:,None]+l0
    inside&=xx<=np.array(right)[:,None]+r0
    a=cv2.GaussianBlur(inside.astype(np.float32),(0,0),1.0)[...,None]
    world[y0:y0+H,x0:x0+W]=B*a+world[y0:y0+H,x0:x0+W]*(1-a)
    return inside
mb=multiband(full)
J1=np.asarray(Image.open('/tmp/m4a/J1_inpaint.png').convert('RGB')).astype(np.float32)
A=full[444:700,636:892]
# B equals the raw crop outside the old mask; use it inside the cut
w2=mb.copy()
ins=cut_patch(w2,A,J1,(636,444),((60,104),(156,206),(14,64),(176,240)))
# old way for comparison: rectangle + mirror blend
old=pw.mirror_blend(pw.tone_match(full,filled),filled)
m=np.zeros((256,256),np.float32); m[76:186,20:236]=1; m=cv2.GaussianBlur(m,(0,0),3)[...,None]
old[444:700,636:892]=J1*m+old[444:700,636:892]*(1-m)
box=(596,424,932,720)
crop=lambda a: Image.fromarray(np.clip(a,0,255).astype(np.uint8)).crop(box)
imgs=[crop(raw),crop(old),crop(w2)]
W,H=imgs[0].size
from PIL import ImageDraw
s=Image.new('RGB',(W*3+40,H+28),(18,18,18)); d=ImageDraw.Draw(s)
for i,(im,t) in enumerate(zip(imgs,['1 raw','2 sample sent (rect mask + mirror blend)','3 free: min-error cut + multiband'])):
    s.paste(im,(i*(W+20),28)); d.text((i*(W+20)+4,8),t,fill=(255,230,0))
s.resize((s.width*2,s.height*2),Image.NEAREST).save('/tmp/m4a/free2/J1_free2.png')
Image.fromarray(np.clip(mb,0,255).astype(np.uint8)).save('/tmp/m4a/free2/world_mb.png')
np.save('/tmp/m4a/free2/inside.npy',ins)
print('ok')
