"""Generate deterministic, small test media. Requires Pillow with WebP."""
from pathlib import Path
import hashlib, json
from PIL import Image, ImageDraw
root = Path(__file__).resolve().parents[1] / "example/assets/fixtures"
root.mkdir(parents=True, exist_ok=True)
ordinary = Image.new("RGB", (640, 480), "#1e293b")
draw = ImageDraw.Draw(ordinary)
draw.rectangle((40, 40, 600, 440), outline="white", width=8)
draw.text((60, 60), "ORDINARY 640 x 480", fill="white")
ordinary.save(root / "ordinary.png")
long = Image.new("RGB", (480, 2400))
draw = ImageDraw.Draw(long)
for i in range(12):
    y = i * 200
    draw.rectangle((0, y, 480, y + 199), fill=(20 + i*12, 60, 180-i*8))
    draw.text((20, y + 25), f"BAND {i:02d} - TOP" if i == 0 else f"BAND {i:02d}", fill="white")
long.save(root / "long.png")
frames=[]
for i, color in enumerate(("red", "green", "blue")):
    f=Image.new("RGBA",(96,72),(0,0,0,0)); d=ImageDraw.Draw(f)
    d.rectangle((12+i*14,12,40+i*14,60),fill=color)
    d.rectangle((0,0,95,4),fill=(120,120,120,120))
    frames.append(f)
for loop, suffix in ((2,""),(0,"_infinite"),(1,"_once")):
    frames[0].save(root/("animation_repeat_once.gif" if loop == 1 else f"animation{suffix}.gif"),save_all=True,append_images=frames[1:],duration=[80,120,200],loop=loop,disposal=2)
    frames[0].save(root/f"animation{suffix}.webp",save_all=True,append_images=frames[1:],duration=[80,120,200],loop=loop,lossless=True,minimize_size=True)

binary=[]
for f in frames:
    b=f.copy(); ImageDraw.Draw(b).rectangle((0,0,95,4),fill=(0,0,0,0)); binary.append(b)
for loop,suffix in ((2,""),(0,"_infinite"),(1,"_once")):
    binary[0].save(root/f'animation_binary{suffix}.webp',save_all=True,append_images=binary[1:],duration=[80,120,200],loop=loop,lossless=True,minimize_size=True)
frames[0].save(root/'animation_timing.webp' ,save_all=True,append_images=frames[1:],duration=[37,53,87],loop=2,lossless=True,minimize_size=True)
# Small compressed input with too many decoded pixels: header budget rejection.
big=Image.new("RGB",(1025,8),"red");other=Image.new("RGB",(1025,8),"blue")
big.save(root/'animation_over_limit.webp',save_all=True,append_images=[other],duration=[80,120],loop=0,lossless=True)
benchmark=[]
for i in range(12):
    f=Image.new("RGB",(320,180)); pix=f.load()
    for y in range(180):
        for x in range(320):
            pix[x,y]=((x+i*7)%256,(y*2+i*11)%256,(x+y+i*13)%256)
    benchmark.append(f)
benchmark[0].save(root/'animation_benchmark.webp',save_all=True,append_images=benchmark[1:],duration=[80]*12,loop=2,lossless=True,minimize_size=True)
manifest={"generator":"Pillow", "fixtures":{}}
for path in sorted(root.iterdir()):
    if path.suffix not in (".png",".gif",".webp"): continue
    im=Image.open(path)
    durations=[]
    for frame in range(im.n_frames):
        im.seek(frame); im.load(); durations.append(im.info.get("duration",0))
    manifest["fixtures"][path.name]={"width":im.width,"height":im.height,"frames":im.n_frames,"durationsMs":durations,"rawLoop":im.info.get("loop"),"bytes":path.stat().st_size,"sha256":hashlib.sha256(path.read_bytes()).hexdigest()}
(root/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
print(json.dumps(manifest,indent=2))
