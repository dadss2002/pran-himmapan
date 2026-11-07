#!/usr/bin/env python3
"""M4a test: LaMa clears the blob bush under the J3 path, then PixelLab bush props (assets/map/painted/props/bush_*.png,
create_image_pro job 93092a0d, 10 gen) are placed as separate sprites with a soft contact shadow and colours snapped to J3.
Outputs /tmp/m4a/bush/work/world_A.png, world_B.png and comparison sheets. In the game the bushes become a Y-sorted object layer."""
import sys, numpy as np, cv2
from PIL import Image, ImageDraw, ImageFilter
sys.path.insert(0,'/home/claude/pran-himmapan/tools')
from lama_fill import fill
W=np.asarray(Image.open('/tmp/m4a/ts/world_J3_ts2_7.png').convert('RGB')).copy()
X0,Y0=2496,0
CX,CY,RX,RY=2746,275,84,56
# 1) LaMa clear the old blob bush
win=W[Y0:Y0+512,X0:X0+512].copy()
m=Image.new('L',(512,512),0); ImageDraw.Draw(m).ellipse((CX-X0-RX,CY-Y0-RY,CX-X0+RX,CY-Y0+RY),fill=255)
mask=np.asarray(m)
cleared=W.copy(); cleared[Y0:Y0+512,X0:X0+512]=fill(win,mask)
Image.fromarray(cleared).save('/tmp/m4a/bush/work/world_cleared.png')
# palette from the J3 area (canopy greens, path) for snapping
crop=W[0:384,2496:3008].reshape(-1,3).astype(np.float32)
_,_,pal=cv2.kmeans(crop,40,None,(3,20,1.0),3,cv2.KMEANS_PP_CENTERS)
def snap(b):
    a=np.asarray(b).copy(); rgb=a[...,:3].astype(np.float32); al=a[...,3]>0
    d=((rgb[al][:,None,:]-pal[None])**2).sum(-1); rgb[al]=pal[d.argmin(1)]
    # soften: interior very dark pixels -> the tree's mid-dark teal; keep the outer 1px outline
    er=cv2.erode(al.astype(np.uint8),np.ones((3,3),np.uint8))>0
    lum=rgb.sum(-1); dark=er&(lum<150)
    rgb[dark]=rgb[dark]*0.45+np.array([22,74,80],np.float32)*0.55
    rgb[al&~er]=np.array([9,40,65],np.float32)
    a[...,:3]=rgb.astype(np.uint8); a[...,3]=np.where(al,255,0); return Image.fromarray(a)
def place(base, items):
    img=Image.fromarray(base).convert('RGBA')
    for name,cx,by in items:  # cx = centre x, by = bottom y (feet) in world
        b=snap(Image.open(f'/tmp/m4a/bush/{name}.png'))
        bb=b.getbbox(); b=b.crop(bb); w,h=b.size
        # soft contact shadow under the bush
        sh=Image.new('RGBA',img.size,(0,0,0,0)); d=ImageDraw.Draw(sh)
        d.ellipse((cx-w*0.48,by-h*0.30,cx+w*0.48,by+5),fill=(8,30,28,120))
        img=Image.alpha_composite(img,sh.filter(ImageFilter.GaussianBlur(4)))
        img.alpha_composite(b,(int(cx-w/2),int(by-h)))
    return np.asarray(img.convert('RGB'))
A=place(cleared,[('bush_3',2706,318),('bush_2',2790,326)])
B=place(cleared,[('bush_3',2748,326)])
Image.fromarray(A).save('/tmp/m4a/bush/work/world_A.png'); Image.fromarray(B).save('/tmp/m4a/bush/work/world_B.png')
# comparison sheet: zoomed area x2
box=(2600,150,2900,380)
from PIL import ImageFont
def z(arr): return Image.fromarray(arr).crop(box).resize(((box[2]-box[0])*2,(box[3]-box[1])*2),Image.NEAREST)
tiles=[('J3 ที่ผ่านแล้ว (เดิม)',W),('A: LaMa ลบ + พุ่ม PixelLab 2 พุ่ม',A),('B: LaMa ลบ + พุ่ม PixelLab 1 พุ่ม',B)]
tw,th=600,460
sheet=Image.new('RGB',(tw*3+40,th+50),(24,24,28))
try: f=ImageFont.truetype('/usr/share/fonts/opentype/tlwg/Loma-Bold.otf',22)
except Exception:
    import glob; ff=glob.glob('/usr/share/fonts/**/*Thai*.ttf',recursive=True); f=ImageFont.truetype(ff[0],22) if ff else ImageFont.load_default()
dr=ImageDraw.Draw(sheet)
for i,(t,a) in enumerate(tiles):
    sheet.paste(z(a),(10+i*(tw+10),45)); dr.text((10+i*(tw+10),8),t,fill=(240,240,240),font=f)
sheet.save('/tmp/m4a/bush/work/J3_bush_compare.png')
# wide context sheet 1x
ctx=(2496,0,3008,384)
s2=Image.new('RGB',(512*3+40,384+50),(24,24,28)); dr=ImageDraw.Draw(s2)
for i,(t,a) in enumerate(tiles):
    s2.paste(Image.fromarray(a).crop(ctx),(10+i*522,45)); dr.text((10+i*522,8),t,fill=(240,240,240),font=f)
s2.save('/tmp/m4a/bush/work/J3_bush_compare_wide.png')
