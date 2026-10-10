#!/usr/bin/env python3
"""Start one exact owned B3/B4 process as a persistent user systemd service."""
import argparse
import json
from pathlib import Path
import subprocess
import time

ROOT=Path('/var/tmp/hnuhole-android-live-b3-b4-20261009')
LABELS=('community','verifier','c-watch','v-watch','proxy')


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('label',choices=LABELS);args=parser.parse_args()
    assert ROOT.resolve()==ROOT and not ROOT.is_symlink()
    assert (ROOT/'OWNER').read_text().strip()=='HNUHOLE_ANDROID_LIVE_DEV_V1'
    services=ROOT/'services';material=services/'material'
    if args.label in ('community','verifier'):
        cfg='c.json' if args.label=='community' else 'v.json'
        command=[str(services/args.label),'-config',str(material/cfg)]
    elif args.label.endswith('-watch'):
        cfg='operator.json' if args.label=='c-watch' else 'v-operator.json'
        command=[str(services/'authdev'),'watch','-operator',str(material/'operator'/cfg)]
    else:command=['python3',str(ROOT/'repo/tools/android-auth-b3-b4-proxy.py')]
    for proc in Path('/proc').iterdir():
        if not proc.name.isdecimal():continue
        try:words=(proc/'cmdline').read_bytes().rstrip(b'\0').split(b'\0')
        except OSError:continue
        assert words!=[p.encode() for p in command],'Preserve exact live process; no duplicate launch'
    unit='hnuhole-b3b4-20261009-'+args.label
    r=subprocess.run(['systemctl','--user','is-active',unit],capture_output=True,text=True,timeout=10)
    assert r.stdout.strip()!='active','Preserve live owned unit'
    subprocess.run(['systemctl','--user','reset-failed',unit],capture_output=True,timeout=10)
    r=subprocess.run(['systemd-run','--user','--unit='+unit,'--property=Type=exec',
        '--property=Restart=no','--property=StandardOutput=append:'+str(ROOT/('managed-'+args.label+'.private.log')),
        '--property=StandardError=append:'+str(ROOT/('managed-'+args.label+'.private.log')),*command],
        capture_output=True,text=True,timeout=20)
    assert r.returncode==0,'Owned persistent service launch failed; private details suppressed'
    for _ in range(40):
        r=subprocess.run(['systemctl','--user','show',unit,'--property=MainPID','--value'],capture_output=True,text=True,timeout=10)
        if r.returncode==0 and r.stdout.strip().isdecimal() and int(r.stdout)>0:
            pid=int(r.stdout);break
        time.sleep(.1)
    else:raise AssertionError('No exact owned persistent service PID')
    words=Path('/proc',str(pid),'cmdline').read_bytes().rstrip(b'\0').split(b'\0')
    assert words==[p.encode() for p in command] or (args.label=='proxy' and words[0]==b'/usr/bin/python3' and words[1:]==[command[1].encode()])
    record=dict(label=args.label,pid=pid,unit=unit,supervisedByUserSystemd=True,automaticRestart=False)
    (ROOT/('managed-'+args.label+'.json')).write_text(json.dumps(record)+'\n')
    print(pid)


if __name__=='__main__':main()
