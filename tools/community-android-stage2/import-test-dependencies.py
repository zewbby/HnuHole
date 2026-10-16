#!/usr/bin/env python3
"""Copy only public cached Maven artifacts into an owned local test repository.

No Gradle metadata database/lock, credentials, SDK, or runtime material is copied.
POMs and Gradle module metadata are kept byte-for-byte; no version is rewritten.
"""
import argparse
import hashlib
import json
import re
import shutil
import xml.etree.ElementTree as ET
from pathlib import Path

OWNER = 'HNUHOLE_COMMUNITY_ANDROID_STAGE2_V1'
N = {'m': 'http://maven.apache.org/POM/4.0.0'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', required=True, type=Path)
    parser.add_argument('--public-cache', required=True, type=Path)
    args = parser.parse_args()
    work, cache = args.work.resolve(strict=True), args.public_cache.resolve(strict=True)
    if (work / '.owner').read_text().strip() != OWNER or cache.name != 'files-2.1':
        raise ValueError('owned work and public files-only cache required')
    target = work / 'test-maven'
    if target.is_symlink():
        raise ValueError('linked Maven destination rejected')
    target.mkdir(exist_ok=True)
    todo = [('androidx.test.ext', 'junit', '1.3.0'), ('androidx.test', 'runner', '1.7.0')]
    seen, files, unavailable = set(), [], []
    while todo:
        item = todo.pop()
        if item in seen:
            continue
        seen.add(item)
        group, artifact, version = item
        if re.fullmatch(r'\[[A-Za-z0-9_.+-]+\]', version):
            version = version[1:-1]
            item = group, artifact, version
        if not all(re.fullmatch(r'[A-Za-z0-9_.+-]+', v) for v in item):
            unavailable.append(':'.join(item)); continue
        source = cache / group / artifact / version
        if not source.is_dir():
            # A higher already-cached dependency may win normal conflict
            # resolution; do not fabricate or rewrite a lower version.
            unavailable.append(':'.join(item)); continue
        dest = target / group.replace('.', '/') / artifact / version
        dest.mkdir(parents=True, exist_ok=True)
        for path in sorted(source.glob('*/*')):
            if path.suffix not in ('.pom', '.aar', '.jar', '.module'):
                continue
            # Gradle's hexadecimal cache directory may omit leading zeroes.
            if path.is_symlink() or path.parent.is_symlink() or not path.resolve().is_relative_to(cache) or not re.fullmatch(r'[0-9a-f]{1,40}', path.parent.name) or hashlib.sha1(path.read_bytes()).hexdigest() != path.parent.name.zfill(40):
                raise ValueError('cached public content hash/path mismatch: ' + str(path.relative_to(cache)))
            output = dest / path.name
            if output.exists() and output.read_bytes() != path.read_bytes():
                raise ValueError('different existing public artifact')
            shutil.copyfile(path, output)
            files.append({'path': str(output.relative_to(target)), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'bytes': path.stat().st_size})
            if path.suffix == '.pom':
                pom = ET.fromstring(path.read_bytes())
                for dep in pom.findall('./m:dependencies/m:dependency', N) + pom.findall('./m:dependencyManagement/m:dependencies/m:dependency', N) + pom.findall('./m:parent', N):
                    if dep.findtext('m:scope', default='', namespaces=N) in ('test', 'provided') or dep.findtext('m:optional', default='', namespaces=N) == 'true':
                        continue
                    values = tuple(dep.findtext('m:' + key, default='', namespaces=N) for key in ('groupId', 'artifactId', 'version'))
                    if re.fullmatch(r'\$\{[A-Za-z0-9_.-]+\}', values[2]):
                        property_value = pom.findtext('m:properties/m:' + values[2][2:-1], default=values[2], namespaces=N)
                        values = values[:2] + (property_value,)
                    todo.append(values)
            elif path.suffix == '.module':
                module = json.loads(path.read_text())
                for variant in module.get('variants', []):
                    available = variant.get('available-at', {})
                    if all(key in available for key in ('group', 'module', 'version')):
                        todo.append(tuple(available[key] for key in ('group', 'module', 'version')))
    report = {'owner': OWNER, 'sourceReadOnly': True, 'versionsRewritten': False,
              'networkUsed': False, 'bytesCopied': sum(f['bytes'] for f in files),
              'files': sorted(files, key=lambda f: f['path']), 'unavailableRequestedVersions': sorted(unavailable)}
    (work / 'public-test-dependencies.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'files': len(files), 'bytesCopied': report['bytesCopied'], 'unavailableRequestedVersions': report['unavailableRequestedVersions']}))


if __name__ == '__main__':
    main()
