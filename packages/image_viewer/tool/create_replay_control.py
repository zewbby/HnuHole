"""Add one deterministic replay control; never regenerate existing fixtures."""
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageSequence

root = Path(__file__).resolve().parents[1] / 'example/assets/fixtures'
manifest_path = root / 'manifest.json'
manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
before = {name: hashlib.sha256((root / name).read_bytes()).hexdigest()
          for name in manifest['fixtures'] if name != 'animation_replay_slow.webp'}
source = Image.open(root / 'animation.webp')
frames = [frame.convert('RGBA').copy() for frame in ImageSequence.Iterator(source)]
target = root / 'animation_replay_slow.webp'
frames[0].save(target, save_all=True, append_images=frames[1:],
               duration=[2000, 2000, 2000], loop=2, lossless=True, minimize_size=True)
decoded = Image.open(target)
durations = []
for index, expected in enumerate(frames):
    decoded.seek(index)
    assert decoded.convert('RGBA').tobytes() == expected.tobytes()
    durations.append(decoded.info.get('duration', 0))
assert decoded.n_frames == 3 and decoded.info['loop'] == 2
assert durations == [2000, 2000, 2000]
manifest['fixtures'][target.name] = dict(width=96, height=72, frames=3,
    durationsMs=durations, rawLoop=2, bytes=target.stat().st_size,
    sha256=hashlib.sha256(target.read_bytes()).hexdigest())
assert all(hashlib.sha256((root / name).read_bytes()).hexdigest() == digest
           for name, digest in before.items())
manifest_path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
print(json.dumps(dict(newControl=manifest['fixtures'][target.name],
                     allExistingFixtureBytesUnchanged=True)))
