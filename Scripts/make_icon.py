from PIL import Image, ImageDraw, ImageFilter
S=4; W=1024*S
def lerp(a,b,t): return tuple(int(a[i]+(b[i]-a[i])*t) for i in range(len(a)))
img=Image.new("RGBA",(W,W),(0,0,0,0))
# squircle body (Big Sur grid: 824 body, 100 margin)
m=100*S; body=824*S; r=186*S
mask=Image.new("L",(W,W),255)
# shadow
sh=Image.new("RGBA",(W,W),(0,0,0,0)); ImageDraw.Draw(sh).rounded_rectangle([m,m+18*S,m+body,m+body+18*S],r,fill=(0,0,0,110))

# gradient bg
bg=Image.new("RGBA",(W,W)); d=ImageDraw.Draw(bg)
top=(38,30,78); bot=(12,10,26)
for y in range(W):
    t=min(max((y-m)/body,0),1); d.line([(0,y),(W,y)],fill=lerp(top,bot,t)+(255,))
# soft glow top-left
glow=Image.new("RGBA",(W,W),(0,0,0,0)); ImageDraw.Draw(glow).ellipse([m-200*S,m-260*S,m+620*S,m+460*S],fill=(140,90,255,90))
glow=glow.filter(ImageFilter.GaussianBlur(120*S)); bg.alpha_composite(glow)
img.paste(bg,(0,0),mask)
ov=Image.new('RGBA',(W,W),(0,0,0,0)); d=ImageDraw.Draw(ov)
# inner border
img.alpha_composite(ov)
# faders
cx=[330,490,650]; knob=[600,430,520]
ty0,ty1=262,770
for x,k in zip(cx,knob):
    X=x*S
    ov=Image.new('RGBA',(W,W),(0,0,0,0)); d=ImageDraw.Draw(ov)
    d.rounded_rectangle([X-10*S,ty0*S,X+10*S,ty1*S],10*S,fill=(255,255,255,38))
    # lit part below knob
    d.rounded_rectangle([X-10*S,k*S,X+10*S,ty1*S],10*S,fill=(255,170,60,150))
    # tick marks
    for ty in range(ty0+40,ty1-20,64):
        d.line([(X-46*S,ty*S),(X-28*S,ty*S)],fill=(255,255,255,55),width=4*S)
    img.alpha_composite(ov); d=ImageDraw.Draw(img)
    # knob shadow
    ks=Image.new("RGBA",(W,W),(0,0,0,0)); ImageDraw.Draw(ks).rounded_rectangle([X-62*S,(k-26+14)*S,X+62*S,(k+26+14)*S],18*S,fill=(0,0,0,150))
    img.alpha_composite(ks.filter(ImageFilter.GaussianBlur(12*S))); d=ImageDraw.Draw(img)
    # knob gradient
    kn=Image.new("RGBA",(W,W),(0,0,0,0)); kd=ImageDraw.Draw(kn)
    for yy in range((k-26)*S,(k+26)*S):
        t=(yy-(k-26)*S)/(52*S); kd.line([(X-62*S,yy),(X+62*S,yy)],fill=lerp((255,214,120),(255,128,40),t)+(255,))
    km=Image.new("L",(W,W),0); ImageDraw.Draw(km).rounded_rectangle([X-62*S,(k-26)*S,X+62*S,(k+26)*S],18*S,fill=255)
    img.paste(kn,(0,0),km); d=ImageDraw.Draw(img)
    d.line([(X-40*S,k*S),(X+40*S,k*S)],fill=(120,50,0,200),width=5*S)
# convert badge bottom-right
bx,by,br=724*S,724*S,100*S
bsh=Image.new("RGBA",(W,W),(0,0,0,0)); ImageDraw.Draw(bsh).ellipse([bx-br,by-br+16*S,bx+br,by+br+16*S],fill=(0,0,0,140))
img.alpha_composite(bsh.filter(ImageFilter.GaussianBlur(18*S))); d=ImageDraw.Draw(img)
d.ellipse([bx-br,by-br,bx+br,by+br],fill=(255,255,255,255))
# arrows (two arcs)
ar=54*S; aw=18*S; col=(60,40,140,255)
d.arc([bx-ar,by-ar,bx+ar,by+ar],200,340,fill=col,width=aw)
d.arc([bx-ar,by-ar,bx+ar,by+ar],20,160,fill=col,width=aw)
import math
def head(angle_deg, clockwise=True):
    a=math.radians(angle_deg); px=bx+ar*math.cos(a); py=by+ar*math.sin(a)
    tx,ty=-math.sin(a),math.cos(a)  # tangent (clockwise in screen coords)
    nx,ny=math.cos(a),math.sin(a); L=40*S; Wd=30*S
    tip=(px+tx*L*0.9,py+ty*L*0.9); b1=(px+nx*Wd-tx*L*0.2,py+ny*Wd-ty*L*0.2); b2=(px-nx*Wd-tx*L*0.2,py-ny*Wd-ty*L*0.2)
    d.polygon([tip,b1,b2],fill=col)
head(340); head(160)
img=img.crop((m,m,m+body,m+body))
out=img.resize((1024,1024),Image.LANCZOS).convert("RGB").convert("RGBA")
out.save("AppIcon-1024.png")
out.save("AppIcon.icns",sizes=[(16,16),(32,32),(64,64),(128,128),(256,256),(512,512),(1024,1024)])
out.resize((64,64),Image.LANCZOS).save("small64.png")
