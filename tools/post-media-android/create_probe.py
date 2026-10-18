#!/usr/bin/env python3
"""Embed only this kit's synthetic originals in a separate native probe entry."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import secrets
from check_ready import owned


def generate(kit):
    kit = owned(kit)
    target = kit/'private/native-probe.dart'
    if target.exists():
        raise ValueError('Probe entry already fixed; never silently reset its namespace')
    manifest = json.loads((kit/'fixtures/manifest.json').read_text())
    if manifest.get('syntheticOnly') is not True or len(manifest['originals']) != 9:
        raise ValueError('Exactly nine synthetic originals required')
    files = []
    for item in manifest['originals']:
        name = item['name']
        path = kit/'fixtures'/name
        if Path(name).name != name or path.is_symlink() or path.resolve().parent != kit/'fixtures':
            raise ValueError('Fixture path escaped kit')
        data = path.read_bytes()
        if hashlib.sha256(data).hexdigest() != item['sha256']:
            raise ValueError('Fixture digest mismatch')
        files.append({'base64': base64.b64encode(data).decode(), 'byteLength': len(data), 'sha256': item['sha256']})
    value = {'runId': 'post-media-'+secrets.token_hex(8), 'files': files}
    text = Path(__file__).with_name('native_probe.dart.template').read_text().replace('@@OWNED_FIXTURES@@', json.dumps(value))
    target.write_text(text)
    print('Separate native probe generated; device execution NOT_RUN')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kit', required=True)
    generate(parser.parse_args().kit)
