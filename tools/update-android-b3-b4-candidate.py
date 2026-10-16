#!/usr/bin/env python3
"""Update one reviewed owned candidate without uninstalling or clearing data."""
import argparse,hashlib,json,re,subprocess
from pathlib import Path
ROOT=Path('D:/zewbbyTest/Hnuhole-android-live-faults-20261005/matrix')
ADB=Path('D:/zewbbyTest/Hnuhole-env/android-sdk/platform-tools/adb.exe')
PHONE='10CEAG17RY003M7'
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('variant',choices=('main','acceptance'))
    p.add_argument('--fresh',action='store_true',help='Install only after confirming the owned package is absent')
    p.add_argument('--preflight',action='store_true',help='Validate without installing or changing the phone')
    args=p.parse_args()
    assert (ROOT/'OWNER').read_text().strip()=='HNUHOLE_ANDROID_MATRIX_V1'
    assert (ROOT/'driver/apps/mobile/.device-app-owner').read_text()==PHONE+'|hnuhole-android-live-matrix-20261006'
    name='phone-b3b4.apk' if args.variant=='main' else 'b3b4-acceptance.apk'
    package='org.hnuhole.hnuhole_mobile'+('' if args.variant=='main' else '.acceptance')
    evidence=ROOT/'b3b4-evidence';manifest=json.loads((evidence/'builds.json').read_text())
    candidate=next(a for a in manifest['apks'] if a['fileName']==name and a['applicationId']==package)
    apk=ROOT/name;assert hashlib.sha256(apk.read_bytes()).hexdigest()==candidate['apkSha256']
    def ad(*a,allow_absent=False):
        r=subprocess.run([str(ADB),'-s',PHONE,*a],capture_output=True,timeout=240)
        if allow_absent and r.returncode==1 and not r.stdout.strip() and not r.stderr.strip():return b''
        if r.returncode:
            (evidence/('update-'+args.variant+'.private.log')).write_bytes(r.stdout+r.stderr)
            print('UPDATE_ERROR: '+('INSTALL_USER_RESTRICTED' if b'INSTALL_FAILED_USER_RESTRICTED' in r.stdout+r.stderr else 'OTHER_OWNED_ADB_ERROR'))
        assert r.returncode==0,'Owned update failed; original data preserved';return r.stdout
    installed=ad('shell','pm','path',package,allow_absent=args.fresh).decode().strip()
    if installed:
        assert re.fullmatch(r'package:/data/app/[A-Za-z0-9_~./+=-]+/base\.apk',installed)
        before=ad('shell','sha256sum',installed.removeprefix('package:')).decode().split()[0]
    else:
        assert args.fresh,'Explicit fresh-install scope required for an absent package'
        assert ad('shell','cmd','activity','get-current-user').strip()==b'0'
        assert candidate['signingCertificateSha256']=='fd26b276cb170bf084a932d3b3919bd3aa44874395809968bdd74ddab87389dc'
        before=None
    if before==candidate['apkSha256']:print('CURRENT: reviewed candidate already installed; no reinstall');return
    prior=[]
    for path in evidence.glob('attempt-*/builds.json'):
        for a in json.loads(path.read_text())['apks']:
            if a['fileName']==name and a['applicationId']==package and a['signingCertificateSha256']==candidate['signingCertificateSha256']:prior.append(a['apkSha256'])
    assert before is None or before in prior,'Preserve an unknown installed candidate'
    operation='fresh-install' if before is None else 'update'
    if args.preflight:
        print('READY: '+operation+' '+args.variant+'; exact reviewed APK; no device mutation');return
    record=evidence/(operation+'-'+args.variant+'-'+candidate['apkSha256'][:12]+'.json');assert not record.exists()
    result=ad('install','--no-streaming','-t','-r',str(apk));assert b'Success' in result
    installed=ad('shell','pm','path',package).decode().strip()
    after=ad('shell','sha256sum',installed.removeprefix('package:')).decode().split()[0]
    assert after==candidate['apkSha256']
    record.write_text(json.dumps(dict(result='PASS',device=PHONE,applicationId=package,
        previousApkSha256=before,apkSha256=after,uninstalled=False,clearedData=False,
        freshInstall=before is None,scope='OWNED_PACKAGE_INSTALL_ONLY_NOT_DEVICE_ACCEPTANCE'),indent=2)+'\n')
    print('PASS: reviewed '+args.variant+' '+operation+' completed; no data clear or uninstall performed')
if __name__=='__main__':main()
