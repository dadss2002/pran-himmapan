import os, math
from PIL import Image, ImageDraw, ImageFont
import pathlib
R=str(pathlib.Path(__file__).resolve().parent.parent/"docs/art/passive_icons")
OUT=R+"/32"; os.makedirs(OUT+"/notable",exist_ok=True); os.makedirs(OUT+"/small",exist_ok=True)
def pal_of(im,n=40):
    q=im.convert("RGB").quantize(colors=n,method=Image.Quantize.MEDIANCUT); return q
def down(im,size):
    """48 -> size: smooth downscale, then snap every pixel back to the source's own palette (stays pixel art)."""
    q=pal_of(im)
    sm=im.convert("RGB").resize((size,size),Image.LANCZOS)
    return sm.quantize(palette=q,dither=Image.Dither.NONE).convert("RGBA")
# 11 picked: frame kept, 48 -> 32
for f in sorted(os.listdir(R+"/picked")):
    down(Image.open(f"{R}/picked/{f}"),32).save(f"{OUT}/notable/{f}")
ARM={"n":(232,184,72),"e":(236,120,44),"s":(92,184,84),"w":(84,164,230),"c":(220,220,228)}
small={ # node -> (alternate file, arm colours)
 "n1":("nB_A","n"),"n4":("nB_D","n"),"n2":("nA_A","n"),"n3":("nB_C","n"),"n5":("nA_D","n"),
 "e1":("eA_A","e"),"e3":("eA_B","e"),"e5":("eA_C","e"),"e2":("eK_B","e"),"e4":("eB_C","e"),
 "s1":("sA_A","s"),"s3":("sA_D","s"),"s2":("sA_C","s"),"s4":("sB_B","s"),"s5":("sB_C","s"),"s6":("sB_A","s"),
 "w1":("wK_B","w"),"w5":("wK_C","w"),"w2":("wA_A","w"),"w3":("wB_B","w"),"w4":("wA_B","w"),
 "b_ne":("eK_D","ne"),"b_es":("eB_D","es"),"b_sw":("wB_D","sw"),"b_wn":("nK_B","wn"),"start":("nK_C","c")}
S=32; c=(S-1)/2
for node,(alt,arms) in small.items():
    src=Image.open(f"{R}/alternates/{alt}.png").convert("RGBA")
    inner=src.crop((6,6,42,42))                     # drop the square frame
    art=down(inner,26)
    out=Image.new("RGBA",(S,S),(0,0,0,0)); px=out.load(); ap=art.load()
    for y in range(S):
        for x in range(S):
            d=math.hypot(x-c,y-c)
            ang=math.atan2(y-c,x-c)
            col=ARM[arms[0]] if (len(arms)==1 or ang<0) else ARM[arms[1]]
            if d<=12.6: px[x,y]=ap[x-3,y-3][:3]+(255,)
            elif d<=13.6: px[x,y]=(20,18,24,255)
            elif d<=15.4: px[x,y]=col+(255,)
            elif d<=16.0: px[x,y]=(20,18,24,255)
    out.save(f"{OUT}/small/{node}.png")
print("ok", len(os.listdir(OUT+"/notable")), len(os.listdir(OUT+"/small")))
