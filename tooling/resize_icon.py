from PIL import Image
import sys
import os

SRC = os.path.join('assets', 'app_icon.png')
DST = SRC

if not os.path.exists(SRC):
    print('Source icon not found:', SRC)
    sys.exit(1)

im = Image.open(SRC).convert('RGBA')
w, h = im.size
print('Original size:', w, h)

# sample background from corners
pad = max(8, int(min(w,h) * 0.06))
regions = [
    (0, 0, pad, pad),
    (w-pad, 0, w, pad),
    (0, h-pad, pad, h),
    (w-pad, h-pad, w, h),
]

def avg_color(box):
    x0,y0,x1,y1 = box
    r=g=b=a=0
    cnt = 0
    pix = im.load()
    for yy in range(max(0,y0), min(h,y1)):
        for xx in range(max(0,x0), min(w,x1)):
            pr,pg,pb,pa = pix[xx,yy]
            r += pr; g += pg; b += pb; a += pa
            cnt += 1
    if cnt == 0:
        return (255,255,255,255)
    return (r//cnt, g//cnt, b//cnt, a//cnt)

bg_colors = [avg_color(r) for r in regions]
bg = tuple(sum(c[i] for c in bg_colors)//len(bg_colors) for i in range(3))
print('Estimated background RGB:', bg)

# find bounding box of pixels that differ from background
threshold = 35
pix = im.load()
xmin, ymin = w, h
xmax, ymax = 0, 0
for yy in range(h):
    for xx in range(w):
        r,g,b,a = pix[xx,yy]
        if a == 0:
            continue
        dist = ((r-bg[0])**2 + (g-bg[1])**2 + (b-bg[2])**2) ** 0.5
        if dist > threshold:
            if xx < xmin: xmin = xx
            if yy < ymin: ymin = yy
            if xx > xmax: xmax = xx
            if yy > ymax: ymax = yy

if xmax == 0 and ymax == 0:
    print('No distinct foreground found — aborting')
    sys.exit(1)

# expand bbox slightly (tighter crop)
pad_expand = 0
xmin = max(0, xmin - pad_expand)
ymin = max(0, ymin - pad_expand)
xmax = min(w - 1, xmax + pad_expand)
ymax = min(h - 1, ymax + pad_expand)
print('Crop box:', xmin, ymin, xmax, ymax)

crop = im.crop((xmin, ymin, xmax+1, ymax+1))
Cw, Ch = crop.size

# target final canvas size: keep original square size
S = max(w, h)
# aim to occupy 99% of canvas
target_ratio = 0.99
scale = (S * target_ratio) / max(Cw, Ch)
new_w = max(1, int(Cw * scale))
new_h = max(1, int(Ch * scale))
print('Resizing crop from', (Cw,Ch), 'to', (new_w,new_h))
scale_crop = crop.resize((new_w, new_h), Image.LANCZOS)

# build final canvas with transparent background
canvas = Image.new('RGBA', (S, S), (0,0,0,0))
canvas.paste(scale_crop, ((S-new_w)//2, (S-new_h)//2), scale_crop)

# save (overwrite)
canvas.save(DST)
print('Saved scaled icon to', DST)
