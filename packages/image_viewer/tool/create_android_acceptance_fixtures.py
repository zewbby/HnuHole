"""Synthetic format/resource controls; never rewrites existing fixtures."""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw, ImageOps

root = Path(__file__).resolve().parents[1] / 'example/assets/fixtures'
old = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in root.iterdir() if not p.name.startswith('android_')}
entries = {}
def record(name, **extra):
    p = root / name
    with Image.open(p) as image:
        display = ImageOps.exif_transpose(image)
        entries[name] = dict(width=display.width, height=display.height,
            frames=getattr(image, 'n_frames', 1), bytes=p.stat().st_size,
            sha256=hashlib.sha256(p.read_bytes()).hexdigest(), **extra)

im = Image.new('RGB', (192, 128))
d = ImageDraw.Draw(im)
for rect, color in [((0,0,95,63),'red'),((96,0,191,63),'green'),((0,64,95,127),'blue'),((96,64,191,127),'yellow')]:
    d.rectangle(rect, fill=color)
for orientation in range(1,9):
    exif = im.getexif(); exif[274] = orientation
    name=f'android_exif_{orientation}.jpg'
    im.save(root/name, quality=95, subsampling=0, exif=exif)
    record(name, orientation=orientation)
for name, size in [('android_small.png',(1,1)),('android_wide.png',(2400,240)),
                   ('android_static_limit.png',(3072,4096)),('android_long_limit.png',(480,16384)),
                   ('android_pixels_over.png',(3073,4096)),('android_dimension_over.png',(1,16385))]:
    image=Image.new('RGB',size,'#2455aa')
    draw=ImageDraw.Draw(image)
    for y in range(0,size[1],256):
        draw.rectangle((0,y,size[0]-1,min(y+127,size[1]-1)),fill='#cc5533')
        if size[0]>20: draw.text((12,y+15),f'ROW {y} / {size[1]}',fill='white')
    image.save(root/name); record(name)
transparent=Image.new('RGBA',(192,128),(0,0,0,0))
ImageDraw.Draw(transparent).rectangle((20,20,170,100),fill=(255,0,0,128))
transparent.save(root/'android_transparent.png'); record('android_transparent.png')
for name, size, frames, duration in [
    ('android_animation_limit.webp',(1024,1024),16,80),
    ('android_animation_work_over.webp',(1024,1024),17,80),
    ('android_frames_limit.webp',(128,96),120,40),
    ('android_frames_over.webp',(128,96),121,40),
    ('android_duration_over.webp',(128,96),2,16000),
    ('android_gif_slow.gif',(192,128),3,1000)]:
    images=[Image.new('RGB',size,((i*73)%256,(i*131)%256,(i*193)%256)) for i in range(frames)]
    for i,image in enumerate(images):
        ImageDraw.Draw(image).text((10,10),f'FRAME {i+1} / {frames}',fill='white')
    images[0].save(root/name,save_all=True,append_images=images[1:],duration=duration,
        loop=2 if name.endswith('.gif') else 0,lossless=True)
    record(name,frameDurationMs=duration,rawLoop=2 if name.endswith('.gif') else 0)
for name,digest in old.items():
    assert hashlib.sha256((root/name).read_bytes()).hexdigest()==digest,name
(root/'android_acceptance_manifest.json').write_text(json.dumps(entries,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'fixtures':len(entries),'bytes':sum(v['bytes'] for v in entries.values()),'existingFixturesUnchanged':True}))
