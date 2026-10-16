#!/usr/bin/env python3
"""Generate nine labeled synthetic originals; no user photographs or conversion."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import random

from PIL import Image, ImageDraw


def generate(output, validator):
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    if list(output.iterdir()):
        raise ValueError('New empty fixture directory required; never overwrite photos')
    spec = importlib.util.spec_from_file_location('validator', validator)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)

    def image(label, color='white', size=(640, 480)):
        result = Image.new('RGB', size, color)
        draw = ImageDraw.Draw(result)
        draw.rectangle((0, 0, size[0], 120), fill='white')
        draw.text((16, 24), label, fill='black', font_size=28)
        return result

    # Deterministic noise makes the first original span several encrypted
    # 256KiB chunks, while keeping the entire nine-image kit small.
    ordinary = Image.frombytes('RGB', (640, 480), random.Random(20261015).randbytes(640*480*3))
    ImageDraw.Draw(ordinary).rectangle((0, 0, 639, 119), fill='white')
    ImageDraw.Draw(ordinary).text((16, 24), '01 PNG / ORIGINAL', fill='black', font_size=28)
    ordinary.save(output/'01-ordinary.png')
    image('02 JPEG / ORIGINAL', 'orange').save(output/'02-photo.jpg', quality=95)
    exif = Image.Exif()
    exif[274] = 6
    image('03 EXIF 6 / ORIGINAL', 'cyan', (600, 900)).save(output/'03-exif6.jpg', quality=95, exif=exif)
    long = image('04 LONG / TOP', size=(480, 7200))
    draw = ImageDraw.Draw(long)
    for index in range(12):
        top = 160 + index*570
        draw.rectangle((0, top, 479, top+560), fill=['#d3e5f0', '#e5efd5', '#f1dada'][index % 3])
        draw.text((16, top+200), 'BAND %02d' % index, fill='black', font_size=36)
    long.save(output/'04-long.png')
    frames = [image('FRAME %d / SLOW 2s' % (n+1), color, (480, 480))
              for n, color in enumerate(['red', 'green', 'blue'])]
    frames[0].save(output/'05-loop.gif', save_all=True, append_images=frames[1:], duration=2000, loop=0)
    frames[0].save(output/'06-finite.webp', save_all=True, append_images=frames[1:], duration=2000, loop=2, lossless=True)
    frames[0].save(output/'07-loop.webp', save_all=True, append_images=frames[1:], duration=2000, loop=0, lossless=True)
    image('08 LANDSCAPE / ORIGINAL', 'yellow', (1200, 600)).save(output/'08-landscape.png')
    image('09 SQUARE / ORIGINAL', 'pink', (512, 512)).save(output/'09-square.png')
    files = []
    for path in sorted(output.iterdir()):
        data = path.read_bytes()
        metadata = module.inspect(data)
        with Image.open(path) as decoded:
            duration, loop = decoded.info.get('duration'), decoded.info.get('loop')
            if path.suffix == '.webp':
                decoded.seek(0)
                decoded.load()
                duration = decoded.info.get('duration')
        files.append({'name': path.name, **metadata, 'sha256': hashlib.sha256(data).hexdigest(),
                      'frameDurationMilliseconds': duration, 'containerLoopValue': loop})
    assert len(files) == 9
    manifest = {'schema': 'hnuhole-media-android-fixtures/v1', 'syntheticOnly': True,
                'originals': files, 'finiteWebpExpected': 'Auto-start, 2 seconds/frame, two cycles, stop blue',
                'phoneStatus': 'NOT_RUN', 'systemAlbumCaveat': 'Original-file integrity and each gallery playback are separate results'}
    (output/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    print('Nine original fixtures generated and production-validator checked')
    return manifest


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True)
    parser.add_argument('--validator', required=True)
    args = parser.parse_args()
    generate(args.output, args.validator)
