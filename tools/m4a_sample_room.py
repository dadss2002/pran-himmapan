import sys, numpy as np, cv2
sys.path.insert(0,'/home/claude/pran-himmapan/tools')
from PIL import Image, ImageDraw, ImageFilter
from painted_world_fixes import tree_mask
R=np.asarray(Image.open('/tmp/m4a/world_f.png').convert('RGB'))
G=np.asarray(Image.open('/tmp/m4a/sample/ground.png').convert('RGB')).astype(np.float32)
H,W=G.shape[:2]
def lum(a): a=a.astype(int); return 0.3*a[...,0]+0.59*a[...,1]+0.11*a[...,2]
def ellipse_mask(e):
    m=Image.new('L',R.shape[1::-1],0); ImageDraw.Draw(m).ellipse(e,fill=255); return np.asarray(m)>0
def object_mask(box):
    """non-grass, non-dirt pixels inside box (props on the clearing: ruins, rocks, mushrooms)"""
    x0,y0,x1,y1=box; a=R.astype(int); r,g,b=a[...,0],a[...,1],a[...,2]
    grass=(g>r+12)&(g>b+25)&(lum(R)>80)
    m=np.zeros(R.shape[:2],bool); m[y0:y1,x0:x1]=~grass[y0:y1,x0:x1]
    m=cv2.morphologyEx(m.astype(np.uint8),cv2.MORPH_OPEN,np.ones((2,2),np.uint8))>0
    n,lab,st,_=cv2.connectedComponentsWithStats(m.astype(np.uint8),8)
    keep=np.zeros_like(m)
    for k in range(1,n):
        if st[k,4]>=40: keep|=lab==k
    ff=(~keep).astype(np.uint8)*255; fm=np.zeros((ff.shape[0]+2,ff.shape[1]+2),np.uint8); cv2.floodFill(ff,fm,(0,0),0)
    return keep|(ff>0)
def shadow(cx,by,wd,h,a=110):
    sh=Image.new('L',(W,H),0); ImageDraw.Draw(sh).ellipse((cx-wd*0.5,by-h*0.32,cx+wd*0.5,by+6),fill=a)
    s=np.asarray(sh.filter(ImageFilter.GaussianBlur(5))).astype(np.float32)[...,None]/255
    G[:]=G*(1-s)+np.array([20,48,30],np.float32)*s
def put(mask,ox,oy,flip=False,shade=True):
    ys,xs=np.where(mask); x0,x1,y0,y1=xs.min(),xs.max(),ys.min(),ys.max()
    sub=R[y0:y1+1,x0:x1+1]; m=mask[y0:y1+1,x0:x1+1]
    if flip: sub=sub[:,::-1]; m=m[:,::-1]
    hh,ww=m.shape
    if shade: shadow(ox+ww/2,oy+hh,ww*0.9,hh*0.5)
    for yy in range(hh):
        ty=oy+yy
        if ty<0 or ty>=H: continue
        for_x=np.where(m[yy])[0]; tx=ox+for_x; ok=(tx>=0)&(tx<W)
        G[ty,tx[ok]]=sub[yy,for_x[ok]]
lib={
 'path':tree_mask(R,[(748,592,884,700),(775,680,860,732)],(815,650),694),
 'big':tree_mask(R,[(1425,185,1605,345),(1470,320,1560,372)],(1515,260),340),
 'e2':tree_mask(R,[(2800,772,2902,885),(2815,860,2878,918)],(2850,820),880),
 'round':tree_mask(R,[(750,1384,816,1438)],(783,1411)),
 'berry':tree_mask(R,[(1536,80,1593,134)],(1565,110)),
}
circle=ellipse_mask((1637,500,1816,653))
ruinA=object_mask((1784,428,1866,506))      # broken pillars (top right of circle)
ruinB=object_mask((1568,650,1640,702))      # fallen column (bottom left)
ruinC=object_mask((1800,640,1870,696))      # fallen column (bottom right)
rocks=object_mask((1660,460,1700,490))
# --- layout (sample room 704x384), back to front by bottom y ---
items=[]
def T(name,cx,by,flip=False):
    m=lib[name]; ys,xs=np.where(m); ww=xs.max()-xs.min()+1; hh=ys.max()-ys.min()+1
    items.append((by,lambda m=m,cx=cx,by=by,ww=ww,hh=hh,flip=flip: put(m,int(cx-ww/2),int(by-hh),flip)))
# back row (mostly above the top edge) to close the canopy
T('e2',20,70); T('path',120,60,True); T('big',250,55); T('path',420,50); T('e2',540,60,True); T('big',660,70)
# top-left forest
T('big',70,125); T('path',200,112,True); T('round',300,140)
# top-right forest
T('path',480,108); T('big',610,128,True); T('e2',700,112,True); T('berry',528,150)
# bottom forest wall (lower so the clearing stays open)
T('big',60,470); T('e2',170,430,True); T('path',300,450,True); T('round',215,355)
T('big',470,470,True); T('e2',600,440); T('path',700,460); T('berry',405,360)
for by,f in sorted(items,key=lambda t:t[0]):
    if by<=230: f()
# landmarks on the clearing
put(circle,368-94,200-81,shade=False)
put(ruinA,560,140,shade=False); put(ruinB,120,245,shade=False); put(ruinC,540,250,shade=False)
for by,f in sorted(items,key=lambda t:t[0]):
    if by>230: f()
Image.fromarray(np.clip(G,0,255).astype(np.uint8)).save('/tmp/m4a/sample/sample_room.png')
print('ok')
