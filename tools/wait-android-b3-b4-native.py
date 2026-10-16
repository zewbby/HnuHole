#!/usr/bin/env python3
"""Wait read-only for a live owned SDK request and its actual provider window."""
import argparse,json,subprocess,time
from pathlib import Path

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--phase',required=True,choices=('ni-c01','ni-d01','ni-d02','ni-d03','ni-d05'))
    p.add_argument('--variant',required=True,choices=('main','control','bad-signature','missing-package'))
    p.add_argument('--stage',required=True,choices=('ni-unknown-binding','ni-closed-assertion','ni-association-create','ni-wrong-native-rp','ni-server-rp-hash','ni-removal-binding-1','ni-removal-binding-2','ni-removal-select','ni-removed-assertion','ni-closure-first-binding','ni-preflight-binding','ni-preflight-assertion','ni-identity-preflight-assertion'))
    a=p.parse_args();repo=Path(__file__).resolve().parents[1]
    valid={'ni-c01':('main','control'),'ni-d01':('main',),'ni-d02':('control','bad-signature'),
        'ni-d03':('missing-package',),'ni-d05':('main',)}
    assert a.variant in valid[a.phase]
    package='org.hnuhole.hnuhole_mobile'+('.unassociated' if a.variant=='missing-package' else
        '.acceptance' if a.variant in ('control','bad-signature') else '')
    end=time.monotonic()+180
    while time.monotonic()<end:
        r=subprocess.run(['python',str(repo/'tools/control-android-b3-b4-device.py'),'stage','--phase',a.phase,'--variant',a.variant,'--package',package],capture_output=True,text=True,timeout=30)
        if r.returncode==0:
            v=json.loads(r.stdout)
            if v['stage']==a.stage and v['actualProviderForeground'] and v['nativeOperationActive']:
                if a.stage in ('ni-preflight-assertion','ni-identity-preflight-assertion',
                    'ni-closed-assertion','ni-removal-select','ni-removed-assertion') and not v.get('credentialLabelVisible'):
                    print('LABEL_NOT_VISIBLE: actual provider has no identifiable target; do not ask user to guess',flush=True);return
                print('READY: '+json.dumps(v),flush=True);return
        time.sleep(.25)
    print('NOT_READY: no live owned native request witnessed; do not prompt UV',flush=True)

if __name__=='__main__':main()
