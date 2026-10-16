"""Create visibly distinct, synthetic replay controls without rewriting originals."""
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageSequence

root = Path(__file__).resolve().parents[1] / 'example/assets/fixtures'
manifest_path = root / 'manifest.json'
manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
names = {'replay_identity_slow.webp', 'replay_identity_fast.webp'}
before = {name: hashlib.sha256((root / name).read_bytes()).hexdigest()
          for name in manifest['fixtures'] if name not in names}
font = ImageFont.load_default(size=18)
for name, label, durations, loop in (
    ('replay_identity_slow.webp', 'SLOW 2s', [2000, 2000, 2000], 2),
    ('replay_identity_fast.webp', 'FAST', [80, 120, 200], 0),
):
    frames = []
    for index, color in enumerate(('red', 'green', 'blue')):
        image = Image.new('RGBA', (192, 144), color)
        draw = ImageDraw.Draw(image)
        draw.rectangle((0, 0, 191, 82), fill='black')
        draw.text((10, 6), label, font=font, fill='white')
        draw.text((10, 31), f'FRAME {index + 1}/3', font=font, fill='white')
        draw.text((10, 56), f'LOOP {loop}', font=font, fill='white')
        frames.append(image)
    target = root / name
    frames[0].save(target, save_all=True, append_images=frames[1:], duration=durations,
                   loop=loop, lossless=True, minimize_size=True)
    decoded = Image.open(target)
    actual_durations = []
    for index, expected in enumerate(frames):
        decoded.seek(index)
        assert decoded.convert('RGBA').tobytes() == expected.tobytes()
        actual_durations.append(decoded.info['duration'])
    assert actual_durations == durations and decoded.info['loop'] == loop and decoded.n_frames == 3
    manifest['fixtures'][name] = dict(width=192, height=144, frames=3,
        durationsMs=durations, rawLoop=loop, bytes=target.stat().st_size,
        sha256=hashlib.sha256(target.read_bytes()).hexdigest())
assert all(hashlib.sha256((root / name).read_bytes()).hexdigest() == digest for name, digest in before.items())
manifest_path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
print(json.dumps(dict(controls={name: manifest['fixtures'][name] for name in sorted(names)},
                     allExistingFixtureBytesUnchanged=True)))
