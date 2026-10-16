#!/usr/bin/env python3
"""Explicit owned WSL lifetime guard while retaining B3/B4 test services."""
import json
import os
import argparse
from pathlib import Path
import time

root=Path('/var/tmp/hnuhole-android-live-b3-b4-20261009')
assert root.resolve()==root and not root.is_symlink()
assert (root/'OWNER').read_text().strip()=='HNUHOLE_ANDROID_LIVE_DEV_V1'
token='HNUHOLE_B3B4_ENVIRONMENT_RETAIN_V1'
owner=root/'keepalive.owner'
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--initialize-owned',action='store_true')
args=parser.parse_args()
if args.initialize_owned and not owner.exists():owner.write_text(token+'\n')
assert owner.read_text().strip()==token
record={'pid':os.getpid(),'owner':token,'stopFile':'keepalive.stop','secretsLogged':False}
(root/'keepalive.json').write_text(json.dumps(record)+'\n')
while not (root/'keepalive.stop').exists():
    assert owner.read_text().strip()==token
    time.sleep(10)
