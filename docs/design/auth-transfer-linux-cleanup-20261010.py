"""One-host cleanup receipt: only the five OWNER-verified auth WSL roots."""
import importlib.util
import json
from pathlib import Path
import shlex
import subprocess

out = Path('C:/Users/Administrator/Documents/HnuHole-transfer-20261010')
spec = importlib.util.spec_from_file_location('transfer', out / 'transfer.py')
transfer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(transfer)
assets = transfer.api('/repos/zewbby/HnuHole/releases/409043077/assets?per_page=100')
for name in ('wsl-recovered-full', 'wsl-recovery-delta'):
    record = json.loads((out / (name + '-record.json')).read_text(encoding='utf-8'))
    assert json.loads((out / (name + '-restore-check.json')).read_text())['memberContentHashes'] == 'PASS'
    for part in record['parts']:
        remote = next(a for a in assets if a['name'] == part['name'])
        assert remote['state'] == 'uploaded' and remote['size'] == part['bytes']
        assert remote['digest'] == 'sha256:' + part['sha256']

names = ['hnuhole-android-live-faults-20261005', 'hnuhole-android-live-b3-b4-20261009',
         'hnuhole-android-live-batch-20261007', 'hnuhole-android-live-closure-20261007',
         'hnuhole-android-live-boundary-20261006']
code = '''from pathlib import Path
import json,shutil
names=NAMES
roots=[Path('/var/tmp')/n for n in names]
for root in roots:
 assert root.resolve()==root and not root.is_symlink()
 assert (root/'OWNER').read_text().strip()=='HNUHOLE_ANDROID_LIVE_DEV_V1'
for root in roots:
 shutil.rmtree(root)
 assert not root.exists()
print(json.dumps({'result':'PASS','removedRoots':[str(p) for p in roots]}))
'''.replace('NAMES', repr(names))
# The original Ubuntu VHD was explicitly attached bare after Docker/WSL stopped.
# Reject a different device, mounted device, or ambiguous duplicate UUID.
prefix = "test $(blkid -s UUID -o value /dev/sdd) = 93562053-0225-4b55-b9ba-aa05bf14c90f || exit 91; "
prefix += "test $(blkid -t UUID=93562053-0225-4b55-b9ba-aa05bf14c90f -o device | wc -l) = 1 || exit 92; "
command = prefix + 'mkdir -p /mnt/auth-original-cleanup; mount -o rw /dev/sdd /mnt/auth-original-cleanup || exit 93; '
command += 'chroot /mnt/auth-original-cleanup /usr/bin/python3 -c ' + shlex.quote(code)
result = subprocess.run(['wsl', '--system', '-u', 'root', '--', 'sh', '-c', command], capture_output=True)
assert result.returncode == 0, result.stderr.decode(errors='replace')
receipt = json.loads(result.stdout)
transfer.write(out / 'linux-cleanup-receipt.json', receipt)
print('REMOVED_OWNED_LINUX_ROOTS', len(receipt['removedRoots']))
