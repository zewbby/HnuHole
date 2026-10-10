#!/usr/bin/env python3
"""Temporarily select the installed Google provider; restore exact owned backup."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT=Path('D:/zewbbyTest/Hnuhole-android-live-faults-20261005/matrix')
ADB='D:/zewbbyTest/Hnuhole-env/android-sdk/platform-tools/adb.exe'
PHONE='10CEAG17RY003M7'
GOOGLE='com.google.android.gms/com.google.android.gms.auth.api.credentials.credman.service.PasswordAndPasskeyService'
GOOGLE_AUTOFILL='com.google.android.gms/.autofill.service.AutofillService'
KEYS=('credential_service','credential_service_primary')

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('action',choices=('enable-google','enable-google-autofill','resume-google','restore','status'))
    a=p.parse_args()
    assert ROOT.resolve()==ROOT.resolve(strict=True) and not ROOT.is_symlink()
    assert (ROOT/'OWNER').read_text().strip()=='HNUHOLE_ANDROID_MATRIX_V1'
    def adb(*args):
        r=subprocess.run([ADB,'-s',PHONE,*args],capture_output=True,text=True,
            encoding='utf-8',errors='replace',timeout=25)
        assert r.returncode==0,'Owned provider operation failed'
        return r.stdout.strip()
    def settings():return {k:adb('shell','settings','get','secure',k) for k in KEYS}
    def main_apk():
        path=adb('shell','pm','path','org.hnuhole.hnuhole_mobile')
        assert re.fullmatch(r'package:/data/app/[A-Za-z0-9_~./+=-]+/base\.apk',path)
        return adb('shell','sha256sum',path[8:]).split()[0]
    state=settings();backup=ROOT/'b3b4-evidence/v16-original-provider-settings.json'
    if a.action=='status':print(json.dumps(state));return
    manifest=json.loads((ROOT/'b3b4-evidence/builds.json').read_text())
    main_hash=next(x['apkSha256'] for x in manifest['apks'] if x['fileName']=='phone-b3b4.apk')
    installed_before=main_apk()
    if a.action=='resume-google':
        value=json.loads(backup.read_text())
        assert value['owner']=='HNUHOLE_ANDROID_MATRIX_V1' and value['device']==PHONE
        assert installed_before in (main_hash,value['mainApkSha256'])
        assert value['restored'] and state==value['originalSettings']
        services=adb('shell','cmd','package','query-services','--brief','-a','android.service.credentials.CredentialProviderService')
        assert 'com.google.android.gms/.auth.api.credentials.credman.service.PasswordAndPasskeyService' in services
        if 'originalAutofillService' in value:
            assert adb('shell','settings','get','secure','autofill_service')==value['originalAutofillService']
            services=adb('shell','cmd','package','query-services','--brief','-a','android.service.autofill.AutofillService')
            assert GOOGLE_AUTOFILL in services
        # Reuse the exact original backup. Never replace it with the temporary
        # configuration when the user explicitly resumes a disconnected run.
        value['restored']=False
        value['resumeCount']=value.get('resumeCount',0)+1
        backup.write_text(json.dumps(value,indent=2)+'\n')
        for k,v in value['temporarySettings'].items():adb('shell','settings','put','secure',k,v)
        assert settings()==value['temporarySettings']
        if 'originalAutofillService' in value:
            adb('shell','settings','put','secure','autofill_service',value['temporaryAutofillService'])
            assert adb('shell','settings','get','secure','autofill_service')==value['temporaryAutofillService']
    elif a.action=='enable-google-autofill':
        value=json.loads(backup.read_text())
        assert value['owner']=='HNUHOLE_ANDROID_MATRIX_V1' and value['device']==PHONE
        assert installed_before in (main_hash,value['mainApkSha256'])
        assert state==value['temporarySettings'] and not value['restored']
        assert 'originalAutofillService' not in value,'Retain the original autofill backup'
        original=adb('shell','settings','get','secure','autofill_service')
        assert original in ('com.vivo.cipherchain/.service.CipChainService',GOOGLE_AUTOFILL,'null')
        services=adb('shell','cmd','package','query-services','--brief','-a','android.service.autofill.AutofillService')
        assert GOOGLE_AUTOFILL in services
        value['originalAutofillService']=original
        value['temporaryAutofillService']=GOOGLE_AUTOFILL
        backup.write_text(json.dumps(value,indent=2)+'\n')
        adb('shell','settings','put','secure','autofill_service',GOOGLE_AUTOFILL)
        assert adb('shell','settings','get','secure','autofill_service')==GOOGLE_AUTOFILL
    elif a.action=='enable-google':
        assert installed_before==main_hash
        assert not backup.exists(),'Retain the original provider backup; do not overwrite'
        services=adb('shell','cmd','package','query-services','--brief','-a','android.service.credentials.CredentialProviderService')
        assert 'com.google.android.gms/.auth.api.credentials.credman.service.PasswordAndPasskeyService' in services
        value={'owner':'HNUHOLE_ANDROID_MATRIX_V1','device':PHONE,'originalSettings':state,
            'temporarySettings':{k:GOOGLE for k in KEYS},'mainApkSha256':main_hash,'restored':False,
            'accountsInspected':False,'credentialsExported':False}
        backup.write_text(json.dumps(value,indent=2)+'\n')
        for k in KEYS:adb('shell','settings','put','secure',k,GOOGLE)
        assert settings()==value['temporarySettings']
    else:
        value=json.loads(backup.read_text())
        assert value['owner']=='HNUHOLE_ANDROID_MATRIX_V1' and value['device']==PHONE
        # A fixture rebuild may advance the reviewed manifest before its main
        # APK is installed. Restoring the original settings must also work on
        # the exact original owned main APK, without requiring a reinstall.
        assert installed_before in (main_hash,value['mainApkSha256'])
        assert all(state[k] in (value['temporarySettings'][k],value['originalSettings'][k]) for k in KEYS)
        for k,v in value['originalSettings'].items():
            if v=='null':adb('shell','settings','delete','secure',k)
            else:adb('shell','settings','put','secure',k,v)
        assert settings()==value['originalSettings']
        if 'originalAutofillService' in value:
            original=value['originalAutofillService']
            assert adb('shell','settings','get','secure','autofill_service') in (original,value['temporaryAutofillService'])
            if original=='null':adb('shell','settings','delete','secure','autofill_service')
            else:adb('shell','settings','put','secure','autofill_service',original)
            assert adb('shell','settings','get','secure','autofill_service')==original
        value['restored']=True;backup.write_text(json.dumps(value,indent=2)+'\n')
    assert main_apk()==installed_before
    print('PASS: '+a.action+'; exact settings verified; main App and credentials preserved')

if __name__=='__main__':main()
