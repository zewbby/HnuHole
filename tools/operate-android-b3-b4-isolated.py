#!/usr/bin/env python3
"""Owned isolated package installs/reinstalls; main App and keys are preserved."""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import subprocess
import uuid

ROOT=Path('D:/zewbbyTest/Hnuhole-android-live-faults-20261005/matrix')
ADB=Path('D:/zewbbyTest/Hnuhole-env/android-sdk/platform-tools/adb.exe')
PHONE='10CEAG17RY003M7'
MAIN='org.hnuhole.hnuhole_mobile'
ISOLATED=MAIN+'.acceptance'
UNASSOCIATED=MAIN+'.unassociated'


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=('install-approved','restore-approved','install-bad-signature','install-unassociated',
        'capture-cipher','reinstall-fresh','reinstall-no-key','reinstall-after-no-key'))
    args=parser.parse_args()
    assert ROOT.resolve()==ROOT.resolve(strict=True) and not ROOT.is_symlink()
    assert (ROOT/'OWNER').read_text().strip()=='HNUHOLE_ANDROID_MATRIX_V1'
    assert (ROOT/'driver/apps/mobile/.device-app-owner').read_text()==PHONE+'|hnuhole-android-live-matrix-20261006'
    manifest=json.loads((ROOT/'b3b4-evidence/builds.json').read_text())
    entries={v['fileName']:v for v in manifest['apks']}
    target=UNASSOCIATED if args.action=='install-unassociated' else ISOLATED
    name='b3b4-unassociated.apk' if target==UNASSOCIATED else (
        'b3b4-bad-signature.apk' if args.action=='install-bad-signature' else 'b3b4-acceptance.apk')
    apk=ROOT/name;assert hashlib.sha256(apk.read_bytes()).hexdigest()==entries[name]['apkSha256']
    def adb(*parts,data=None,absent=False):
        r=subprocess.run([str(ADB),'-s',PHONE,*parts],input=data,capture_output=True,timeout=240)
        if absent and r.returncode==1 and not r.stdout.strip() and not r.stderr.strip():return b''
        assert r.returncode==0,'Owned isolated operation failed; no private output exported'
        return r.stdout
    def installed(package):
        value=adb('shell','pm','path',package,absent=True).decode().strip()
        if not value:return None
        found=re.fullmatch(r'package:(/data/app/[A-Za-z0-9_~./+=-]+/base\.apk)',value);assert found
        return adb('shell','sha256sum',found[1]).decode().split()[0]
    original_main=installed(MAIN)
    reviewed_main={entries['phone-b3b4.apk']['apkSha256']}
    for path in (ROOT/'b3b4-evidence').glob('attempt-*/builds.json'):
        previous=json.loads(path.read_text())
        reviewed_main.update(v['apkSha256'] for v in previous['apks']
            if v['fileName']=='phone-b3b4.apk' and v['applicationId']==MAIN
            and v['signingCertificateSha256']==entries['phone-b3b4.apk']['signingCertificateSha256'])
    assert original_main is not None and original_main in reviewed_main
    current=installed(target)
    allowed={v['apkSha256'] for v in entries.values() if v['applicationId']==target}
    reviewed_certificates={v['apkSha256']:v['signingCertificateSha256']
        for v in entries.values() if v['applicationId']==target}
    # Candidate updates may leave a previously reviewed variant installed.
    # Only exact archived hashes for this same isolated package are owned.
    for path in (ROOT/'b3b4-evidence').glob('attempt-*/builds.json'):
        previous=json.loads(path.read_text())
        allowed.update(v['apkSha256'] for v in previous['apks'] if v['applicationId']==target
            and (v['signingCertificateSha256']==entries[name]['signingCertificateSha256']
                or (target==ISOLATED and v['fileName']=='b3b4-bad-signature.apk')))
        reviewed_certificates.update({v['apkSha256']:v['signingCertificateSha256']
            for v in previous['apks'] if v['applicationId']==target})
    assert current is None or current in allowed,'Unknown installed isolated package must be preserved'
    evidence=ROOT/'b3b4-evidence';record=evidence/(args.action+'-package-manager.json')
    assert not record.exists(),'Retain original package-manager operation evidence'
    def reinstall():
        assert target==ISOLATED and installed(target) in allowed
        assert b'Success' in adb('uninstall',target)
        assert installed(target) is None
        assert b'Success' in adb('install','--no-streaming','-t',str(apk))
        assert installed(target)==entries[name]['apkSha256']
    config=json.loads((ROOT/'b3b4-acceptance-config.json').read_text())
    assert config['AUTH_MATRIX_ACCOUNT_RUN_ID']=='hnuhole-android-live-b3-b4-20261009'
    scope='hnuhole.isolated.auth.v1|'+config['AUTH_COMMUNITY_BASE_URL']+'|'+config['AUTH_VERIFIER_BASE_URL']
    digest=base64.urlsafe_b64encode(hashlib.sha256(b'HNUHOLE/MOBILE-AUTH-ENVIRONMENT/V1\0'+scope.encode()).digest()).decode().rstrip('=')
    relative='no_backup/hnuhole.auth.v1.'+digest+'.auth'
    cipher=evidence/'isolated-product-ciphertext.private.bin'
    flags={}
    def report(variant):
        value=json.loads((evidence/('ni-k01-'+variant+'-report.json')).read_text())
        assert value['phase']=='ni-k01' and value['variant']==variant and value['applicationId']==ISOLATED
        assert value['actualApp'] and value['nativeVault'];return value
    if args.action=='restore-approved':
        assert (evidence/'install-approved-package-manager.json').exists()
        assert (evidence/'install-bad-signature-package-manager.json').exists()
        assert current==entries['b3b4-bad-signature.apk']['apkSha256']
        reinstall();flags['onlyOwnedIsolatedPackageUninstalled']=True
        flags['approvedSignatureRestoredAfterNegative']=True
    elif args.action.startswith('install-'):
        if current is not None and current!=entries[name]['apkSha256']:
            if reviewed_certificates[current]==entries[name]['signingCertificateSha256']:
                # Update only an exact reviewed hash of this package and the
                # same certificate. Android verifies the signature again.
                # A certificate change still requires the isolated reinstall.
                assert b'Success' in adb('install','--no-streaming','-t','-r',str(apk))
                assert installed(target)==entries[name]['apkSha256']
                flags['ownedSameCertificatePackageUpdatedWithoutUninstall']=True
            else:
                assert target==ISOLATED and args.action in ('install-approved','install-bad-signature')
                reinstall();flags['onlyOwnedIsolatedPackageUninstalled']=True
        else:
            assert b'Success' in adb('install','--no-streaming','-t','-r',str(apk))
    elif args.action=='capture-cipher':
        assert installed(target)==entries[name]['apkSha256'] and not cipher.exists()
        source,restart=report('source'),report('restart')
        assert source['pid']!=restart['pid'] and source['actualProductSessionAndDraftPersisted'] and restart['independentProcessRestoredExactSessionAndDraft']
        adb('shell','am','force-stop',target)
        value=adb('exec-out','run-as',target,'cat',relative)
        assert 29<=len(value)<=65565 and value[0]==1
        cipher.write_bytes(value)
        flags.update(ciphertextOnlyExported=True,bytes=len(value),ciphertextSha256=hashlib.sha256(value).hexdigest(),keysExported=False)
    elif args.action=='reinstall-fresh':
        assert cipher.exists() and (evidence/'capture-cipher-package-manager.json').exists()
        reinstall();flags['actualPackageManagerReinstall']=True
    elif args.action=='reinstall-no-key':
        assert report('fresh')['freshProductGuestWithoutAutomaticAuthentication']
        value=cipher.read_bytes();assert 29<=len(value)<=65565 and value[0]==1
        reinstall()
        remote='/data/local/tmp/hnuhole-b3b4-'+uuid.uuid4().hex+'.cipher'
        try:
            adb('push',str(cipher),remote)
            assert adb('shell','sha256sum',remote).decode().split()[0]==hashlib.sha256(value).hexdigest()
            adb('shell','run-as',target,'mkdir','-p','no_backup')
            adb('shell','run-as',target,'cp',remote,relative)
        finally:adb('shell','rm','-f',remote)
        assert adb('exec-out','run-as',target,'cat',relative)==value
        flags.update(actualPackageManagerReinstall=True,oldCiphertextRestoredWithoutKeys=True,
            bytesEqualBeforeStartup=True,keysExported=False)
    else:
        assert report('no-key')['actualProductReadOverwriteAndAuthorityRejected']
        assert adb('exec-out','run-as',target,'cat',relative)==cipher.read_bytes()
        reinstall();flags['rejectedCiphertextPreservedUntilOwnedReinstall']=True
    assert installed(MAIN)==original_main,'Main package changed during isolated operation'
    result=dict(result='PASS',scope='ISOLATED_PACKAGE_MANAGER_ONLY',actualFullCaseAcceptancePassed=False,
        action=args.action,device=PHONE,applicationId=target,mainPackageApkPreserved=True,
        mainPackageUninstalled=False,mainPrivateDataTouched=False,apkSha256=installed(target),**flags)
    record.write_text(json.dumps(result,indent=2)+'\n')
    print('PASS: owned isolated operation '+args.action+'; main package preserved')


if __name__=='__main__':main()
