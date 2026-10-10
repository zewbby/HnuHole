#!/usr/bin/env python3
"""Reveal the exact synthetic credential label without selecting or authenticating."""
import argparse,json,re,subprocess,time
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT=Path('D:/zewbbyTest/Hnuhole-android-live-faults-20261005/matrix')
ADB=Path('D:/zewbbyTest/Hnuhole-env/android-sdk/platform-tools/adb.exe')
PHONE='10CEAG17RY003M7'
PACKAGE='org.hnuhole.hnuhole_mobile'
STAGES=('ni-removal-select','ni-removed-assertion','ni-preflight-assertion',
    'ni-identity-preflight-assertion','ni-closed-assertion')

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--stage',required=True,choices=STAGES)
    p.add_argument('--select-target',action='store_true',help='Select only the unique visible synthetic label; never perform UV')
    a=p.parse_args()
    assert (ROOT/'OWNER').read_text().strip()=='HNUHOLE_ANDROID_MATRIX_V1'
    def ad(*args):
        r=subprocess.run([str(ADB),'-s',PHONE,*args],capture_output=True,
            encoding='utf-8',errors='replace',timeout=15)
        return r.stdout if r.returncode==0 else ''
    def private(name):
        try:return json.loads(ad('shell','run-as',PACKAGE,'cat','files/'+name))
        except ValueError:return {}
    def active(pid):
        stage=private('owned-device-driver-stage.json')
        native=private('owned-acceptance-passkey.json')
        ended=sum(native.get(k,0) for k in ('nativeSucceeded','nativeErrored','nativeCancelled'))
        return stage.get('pid')==native.get('pid')==pid and stage.get('stage')==a.stage and native.get('nativeBegun',0)>ended
    deadline=time.monotonic()+480
    creation_notified=set()
    while time.monotonic()<deadline:
        pid=ad('shell','pidof',PACKAGE).strip()
        if pid.isdecimal():
            stage=private('owned-device-driver-stage.json')
            native=private('owned-acceptance-passkey.json')
            ended=sum(native.get(k,0) for k in ('nativeSucceeded','nativeErrored','nativeCancelled'))
            current_stage=stage.get('stage','')
            ceremony=(int(pid),current_stage)
            if stage.get('pid')==native.get('pid')==int(pid) and current_stage in ('ni-removal-binding-1','ni-preflight-binding','ni-closure-first-binding') and native.get('nativeBegun',0)>ended and ceremony not in creation_notified:
                top=ad('shell','dumpsys','activity','activities')
                if re.search(r'topResumedActivity=[^\n]*com\.vivo\.credentialmanager/\.CredentialSelectorActivity',top):
                    creation_notified.add(ceremony)
                    print('CREATION_READY: '+json.dumps(dict(pid=int(pid),stage=current_stage,actualProviderForeground=True)),flush=True)
        if not pid.isdecimal() or not active(int(pid)):
            time.sleep(.25);continue
        label=private('owned-b3b4-ceremony-label.json')
        expected=label.get('label','')
        assert label.get('pid')==int(pid) and re.fullmatch(r'HnuHole test [a-f0-9]{8}',expected)
        observed_provider=False
        for scroll in range(9):
            if not active(int(pid)):break
            dump='/data/local/tmp/hnuhole-b3b4-target-'+pid+'.xml'
            ad('shell','uiautomator','dump','--compressed',dump)
            raw=ad('shell','cat',dump)
            ad('shell','rm','--',dump)
            start=raw.find('<?xml');end=raw.rfind('</hierarchy>')
            if start<0 or end<start:break
            tree=ET.fromstring(raw[start:end+len('</hierarchy>')])
            foreground=ad('shell','dumpsys','activity','activities')
            if not re.search(r'topResumedActivity=[^\n]*com\.vivo\.credentialmanager/\.CredentialSelectorActivity',foreground):break
            # Remote provider views may retain their own package. The actual
            # foreground CredentialSelectorActivity, PID and live request bind
            # the whole hierarchy to this ceremony; do not silently miss them.
            provider=list(tree.iter('node'))
            observed_provider=True
            targets=[n for n in provider if any(expected==re.sub(r'\s+',' ',n.get(k,'')).strip()
                for k in ('text','content-desc'))]
            bounds=[]
            for target in targets:
                match=re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]',target.get('bounds',''))
                if match:
                    x1,y1,x2,y2=map(int,match.groups())
                    if x2>x1 and y2>y1:bounds.append((x1,y1,x2,y2))
            # The label can be exposed through text and accessibility at the
            # same geometry. Distinct geometries with the same label are
            # ambiguous and must never be treated as a unique target.
            bounds=list(dict.fromkeys(bounds))
            if len(bounds)>1:
                print('AMBIGUOUS: multiple visible targets have the same label; do not select',flush=True);return
            if len(bounds)==1 and active(int(pid)):
                installed=ad('shell','pm','path',PACKAGE).strip()
                assert re.fullmatch(r'package:/data/app/[A-Za-z0-9_~./+=-]+/base\.apk',installed)
                sha=ad('shell','sha256sum',installed.removeprefix('package:')).split()[0]
                record=dict(pid=int(pid),stage=a.stage,expectedCredentialLabel=expected,
                    credentialLabelVisible=True,scrollCount=scroll,apkSha256=sha,
                    targetBounds=list(bounds[0]),selectedCredential=False,authenticated=False,rawAccountListStored=False)
                path=ROOT/'b3b4-evidence'/('target-'+str(pid)+'-'+a.stage+'.json')
                assert not path.exists();path.write_text(json.dumps(record,indent=2)+'\n')
                if a.select_target:
                    # Select immediately from this fresh verified hierarchy,
                    # while the same PID/request/provider remains active. Host
                    # round trips must not consume the native 60-second window.
                    assert active(int(pid))
                    current=ad('shell','dumpsys','activity','activities')
                    assert re.search(r'topResumedActivity=[^\n]*com\.vivo\.credentialmanager/\.CredentialSelectorActivity',current)
                    x1,y1,x2,y2=bounds[0]
                    ad('shell','input','tap',str((x1+x2)//2),str((y1+y2)//2))
                    record.update(selectedCredential=True,authenticated=False,hostDidNotPerformBiometric=True)
                    path.write_text(json.dumps(record,indent=2)+'\n')
                print('READY: '+json.dumps(record),flush=True);return
            if scroll==8:break
            scrollers=[n for n in provider if n.get('scrollable')=='true']
            if not scrollers:break
            node=max(scrollers,key=lambda n:len(list(n.iter())))
            match=re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]',node.get('bounds',''))
            if not match:break
            x1,y1,x2,y2=map(int,match.groups())
            assert x2>x1 and y2-y1>100
            if not active(int(pid)):break
            # Navigate only inside the observed provider's actual scrollable
            # list. No tap, account selection, cancellation or UV is performed.
            ad('shell','input','swipe',str((x1+x2)//2),str(y2-(y2-y1)//5),
                str((x1+x2)//2),str(y1+(y2-y1)//5),'250')
        if observed_provider:
            print('NOT_READY: target not found within bounded provider navigation; do not guess',flush=True);return
        time.sleep(.25)
    print('NOT_READY: identifiable live target not revealed; do not ask user to guess',flush=True)

if __name__=='__main__':main()
