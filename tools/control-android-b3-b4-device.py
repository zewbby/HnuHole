#!/usr/bin/env python3
"""Fixed B3/B4 owned device witnesses; no secrets, raw proofs or synthetic UV."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time

ROOT=Path('D:/zewbbyTest/Hnuhole-android-live-faults-20261005/matrix')
ADB=Path('D:/zewbbyTest/Hnuhole-env/android-sdk/platform-tools/adb.exe')
PHONE='10CEAG17RY003M7'
LINUX='/var/tmp/hnuhole-android-live-b3-b4-20261009'
PACKAGES=('org.hnuhole.hnuhole_mobile','org.hnuhole.hnuhole_mobile.acceptance',
    'org.hnuhole.hnuhole_mobile.unassociated')
PHASES=('ni-c01','ni-d01','ni-d02','ni-d03','ni-d04','ni-d05','ni-k01','ni-k02')
VARIANTS=('main','control','bad-signature','missing-package','source','restart','fresh','no-key',
    'write-failure','write-failure-read','write-unknown','write-unknown-read')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=('watch','stage'))
    parser.add_argument('--phase',required=True,choices=PHASES)
    parser.add_argument('--variant',default='main',choices=VARIANTS)
    parser.add_argument('--package',default=PACKAGES[0],choices=PACKAGES)
    parser.add_argument('--pid',type=int)
    parser.add_argument('--runner-pid',type=int)
    args=parser.parse_args()
    assert ROOT.resolve()==ROOT.resolve(strict=True) and not ROOT.is_symlink()
    assert (ROOT/'OWNER').read_text().strip()=='HNUHOLE_ANDROID_MATRIX_V1'
    assert (ROOT/'driver/apps/mobile/.device-app-owner').read_text()==PHONE+'|hnuhole-android-live-matrix-20261006'
    assert args.package==PACKAGES[0] or args.phase in ('ni-c01','ni-d02','ni-d03','ni-k01','ni-k02')
    assert args.phase!='ni-c01' or args.package==PACKAGES[0] or (args.package==PACKAGES[1] and args.variant=='control')
    assert not args.phase.startswith('ni-k') or args.package==PACKAGES[1]

    def adb(*parts,optional=False):
        for attempt in range(2):
            try:
                r=subprocess.run([str(ADB),'-s',PHONE,*parts],capture_output=True,text=True,
                    encoding='utf-8',errors='replace',timeout=25)
                break
            except subprocess.TimeoutExpired:
                # Retry only read-only witness commands. Never replay a write,
                # authentication request or installer after an uncertain result.
                assert parts[0]=='shell' and (parts[1] in ('pidof','dumpsys','sha256sum','pm')
                    or parts[1:4]==('run-as',args.package,'cat'))
                if attempt:raise
        assert optional or r.returncode==0,'Owned device operation failed; private output retained outside reports'
        return r.stdout.strip()
    def private(name):
        raw=adb('shell','run-as',args.package,'cat','files/'+name,optional=True)
        try:return json.loads(raw)
        except ValueError:return {}
    def top():
        raw=adb('shell','dumpsys','activity','activities')
        found=re.search(r'topResumedActivity=[^\n]*? ([A-Za-z0-9._]+/[A-Za-z0-9._]+)',raw)
        return found[1] if found else ''
    # Exact installed provider activities only. Google is an alternate actual
    # provider on the same phone; arbitrary account/settings activities are
    # not evidence that a native Passkey request is on screen.
    provider_activities=(
        'com.vivo.credentialmanager/.CredentialSelectorActivity',
        'com.google.android.gms/.auth.api.credentials.fido.registration.ui.RegistrationActivity',
        'com.google.android.gms/.auth.api.credentials.fido.authentication.ui.AuthenticationActivity')
    def provider():return top() in provider_activities
    current=adb('shell','pidof',args.package)
    assert current.isdecimal()
    if args.action=='stage':
        value=private('owned-device-driver-stage.json')
        assert value.get('pid')==int(current)
        native=private('owned-acceptance-passkey.json')
        ended=sum(native.get(k,0) for k in ('nativeSucceeded','nativeErrored','nativeCancelled'))
        active=native.get('nativeBegun',0)>ended
        foreground_component=top()
        foreground=foreground_component in provider_activities
        result={'phase':args.phase,'variant':args.variant,'pid':int(current),
            'stage':value.get('stage'),'actualProviderForeground':foreground,
            'nativeOperationActive':active,
            'actualProviderComponent':foreground_component if foreground else None}
        assertion_stages={'ni-preflight-assertion','ni-identity-preflight-assertion',
            'ni-closed-assertion','ni-removal-select','ni-removed-assertion'}
        if value.get('stage') in assertion_stages and foreground and active:
            label=private('owned-b3b4-ceremony-label.json')
            expected=label.get('label','')
            assert label.get('pid')==int(current) and re.fullmatch(r'HnuHole test [a-f0-9]{8}',expected)
            # Read the actual provider UI in memory. Never export the account
            # list, select a credential, or infer visibility from our request.
            import xml.etree.ElementTree as ET
            dump='/data/local/tmp/hnuhole-b3b4-target-'+current+'.xml'
            adb('shell','uiautomator','dump','--compressed',dump,optional=True)
            raw=adb('shell','cat',dump,optional=True)
            adb('shell','rm','--',dump,optional=True)
            start=raw.find('<?xml');end=raw.rfind('</hierarchy>')
            visible=False
            if start>=0 and end>=start:
                tree=ET.fromstring(raw[start:end+len('</hierarchy>')])
                visible=any(expected==re.sub(r'\s+',' ',n.get(k,'')).strip()
                    for n in tree.iter('node') for k in ('text','content-desc'))
            result.update(expectedCredentialLabel=expected,credentialLabelVisible=visible)
        print(json.dumps(result));return
    assert args.pid==int(current) and args.runner_pid
    r=subprocess.run(['pwsh','-NoProfile','-Command',
        f"$p=Get-CimInstance Win32_Process -Filter 'ProcessId = {args.runner_pid}'; $p.CommandLine"],
        capture_output=True,text=True,timeout=20)
    shared_runner='run-android-live-device.ps1' in r.stdout and 'B3B4Phases' in r.stdout
    fixed_wrapper=('run-android-b3-b4.ps1' in r.stdout
        and re.search(r'-Phase\s+'+re.escape(args.phase)+r'(?:\s|$)',r.stdout)
        and re.search(r'-Variant\s+'+re.escape(args.variant)+r'(?:\s|"\s*$|$)',r.stdout))
    assert r.returncode==0 and (shared_runner or fixed_wrapper), 'Owned fixed runner process required'
    installed=adb('shell','pm','path',args.package)
    assert re.fullmatch(r'package:/data/app/[A-Za-z0-9_~./+=-]+/base\.apk',installed)
    apk=adb('shell','sha256sum',installed.removeprefix('package:')).split()[0]
    manifest=json.loads((ROOT/'b3b4-evidence/builds.json').read_text())
    assert apk in [v['apkSha256'] for v in manifest['apks'] if v['applicationId']==args.package]
    evidence=ROOT/'b3b4-evidence';evidence.mkdir(exist_ok=True)
    target=evidence/(args.phase+'-'+args.variant+'-device.json')
    assert not target.exists(),'Retain prior actual attempts; archive explicitly before resuming'
    facts=dict(result='RUNNING',phase=args.phase,variant=args.variant,applicationId=args.package,
        device=PHONE,pid=args.pid,apkSha256=apk,actualProviderObservations=[],
        stages=[],rawProofStored=False,hostDidNotAuthenticate=True,
        watcherSourceSha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),runnerPid=args.runner_pid)
    def save():
        temp=target.with_suffix('.tmp');temp.write_text(json.dumps(facts,indent=2)+'\n');temp.replace(target)
    def control(action):
        r=subprocess.run(['wsl','-d','Ubuntu-24.04','--','python3',
            LINUX+'/repo/tools/control-android-b3-b4.py',action,'--phase',args.phase,'--variant',args.variant],capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=120)
        assert r.returncode==0,'Owned controller did not confirm its bounded transition'
        return json.loads(r.stdout) if action=='status' else None
    def ack(stage):
        record={'pid':args.pid,'phase':args.phase,'variant':args.variant,'stage':stage,'observed':True}
        if stage=='ni-b3b4-ready' and args.phase=='ni-d02' and args.variant=='control':
            # An isolated signature restore loses its fixture but not the real
            # server account. Only a retained actual successful control permits
            # normal product login instead of duplicate registration.
            for previous in evidence.glob('attempt-*/ni-d02-control-report.json'):
                prior=json.loads(previous.read_text(encoding='utf-8-sig'))
                if (prior.get('phase')=='ni-d02' and prior.get('variant')=='control'
                        and prior.get('applicationId')==PACKAGES[1]
                        and prior.get('actualApp') and prior.get('approvedPackageAndCertificateActualBinding')):
                    record['reuseAssociationControl']=True
                    facts['retainedApprovedControlPermitsProductLogin']=True
                    break
        r=subprocess.run([str(ADB),'-s',PHONE,'shell','run-as',args.package,'tee',
            'files/'+stage.replace('-','_')+'.json'],input=json.dumps(record),capture_output=True,text=True,timeout=15)
        assert r.returncode==0
        facts['stages'].append(stage);save()
    modes={'ni-hold-two':'hold-two','ni-wrong-rp-options':'wrong-rp-options',
        'ni-normal':'normal','ni-wrong-rp-hash':'wrong-rp-hash'}
    native_stages={'ni-closure-first-binding','ni-closure-second-binding','ni-closed-assertion',
        'ni-preflight-binding','ni-preflight-assertion','ni-identity-preflight-assertion',
        'ni-wrong-native-rp','ni-server-rp-hash','ni-association-create',
        'ni-removal-binding-1','ni-removal-binding-2','ni-removal-select','ni-removed-assertion','ni-unknown-binding'}
    initial=control('status')
    facts['initialCounts']=initial
    seen=set();terminal_google_seen={};save()
    try:
        limit=time.monotonic()+2400
        while time.monotonic()<limit:
            assert adb('shell','pidof',args.package)==str(args.pid),'Original actual App process ended before acceptance'
            value=private('owned-device-driver-stage.json')
            if value.get('pid')!=args.pid:time.sleep(.2);continue
            stage=value.get('stage')
            if stage in seen:time.sleep(.2);continue
            if stage=='ni-b3b4-ready':ack(stage)
            elif stage.startswith('ni-native-ended-return-'):
                state=private('owned-acceptance-passkey.json')
                ended=sum(state.get(k,0) for k in ('nativeSucceeded','nativeErrored','nativeCancelled'))
                assert state.get('pid')==args.pid and ended==state.get('nativeBegun',0)
                component=top()
                if component.startswith('com.google.android.gms/'):
                    # A Google terminal callback can precede its final UI.
                    # Keep that UI visible briefly for read-only diagnosis;
                    # never press Back while the native operation is active.
                    first=terminal_google_seen.setdefault(stage,time.monotonic())
                    if time.monotonic()-first<15:
                        time.sleep(.2);continue
                # OEM cleanup only after a terminal SDK outcome. Never dismiss
                # an active ceremony or manufacture authentication/cancellation.
                if provider() and stage not in facts.get('oemProviderDismissedAfterTerminalCallback',[]):
                    adb('shell','input','keyevent','KEYCODE_BACK')
                    facts.setdefault('oemProviderDismissedAfterTerminalCallback',[]).append(stage)
                if not top().startswith(args.package+'/'):time.sleep(.2);continue
                ack(stage)
            elif stage in ('ni-assertion-preflight-passed','ni-identity-assertion-preflight-passed'):
                state=private('owned-acceptance-passkey.json')
                assert state.get('pid')==args.pid and state.get('nativeSucceeded',0)>=2
                assert state.get('invalidResponseUserHandleAbsent',0)==0 and state.get('invalidResponseUserHandleEncoding',0)==0
                facts[stage]=True;save();ack(stage)
            elif stage in modes:control(modes[stage]);ack(stage)
            elif stage=='ni-two-replies-held':
                status=control('status')
                if status['proxy']['heldBindingReplies']!=1 or status['proxy']['heldIdentityReplies']!=1:
                    time.sleep(.2);continue
                assert status['sql']['passkeys']==2 and status['sql']['activeIdentities']==3
                facts['actualBindingAndIdentityCommittedWhileRepliesHeld']=True;ack(stage)
            elif stage=='ni-formal-close-draft':
                assert facts.get('ni-assertion-preflight-passed') or initial['sql']['closedAccounts']<10
                control('close-draft');facts['actualDraftClosureCycle']=True;ack(stage)
            elif stage=='ni-resume-formal-close-draft':
                control('verify-draft-resume');facts['originalDraftClosureIndependentlyVerifiedWithoutAdvancingClock']=True;ack(stage)
            elif stage=='ni-identity-reply-held':
                current=control('status')
                if current['proxy']['heldIdentityReplies']!=initial['proxy']['heldIdentityReplies']+1:time.sleep(.2);continue
                assert current['sql']['passkeys']==initial['sql']['passkeys']+1 and current['sql']['activeIdentities']==3
                facts['actualIdentityCommittedWhileReplyHeld']=True;ack(stage)
            elif stage=='ni-unknown-reply-held':
                control('assert-unknown-held');facts['actualFirstBindingCommittedWhileReplyHeld']=True;ack(stage)
            elif stage=='ni-formal-close':
                assert facts.get('ni-identity-assertion-preflight-passed') or initial['sql']['closedAccounts']<10
                control('close');facts['actualNormalWorkerClosure']=True;ack(stage)
            elif stage=='ni-formal-close-unknown':control('close-unknown');facts['actualUnknownBindingNormalWorkerClosure']=True;ack(stage)
            elif stage=='ni-release-old-replies':control('release-replies');ack(stage)
            elif stage=='ni-release-unknown-replies':control('release-unknown-replies');ack(stage)
            elif stage in native_stages:
                state=private('owned-acceptance-passkey.json')
                ended=sum(state.get(k,0) for k in ('nativeSucceeded','nativeErrored','nativeCancelled'))
                if state.get('nativeBegun',0)>0 and ended>=state.get('nativeBegun',0):
                    facts.setdefault('nativeAlreadyEndedBeforePrompt',[]).append(stage)
                    # Report only the SDK outcome; never invent foreground or UV.
                elif provider():
                    facts['actualProviderObservations'].append(stage)
                    component=top()
                    if component in provider_activities:
                        facts.setdefault('actualProviderComponents',{})[stage]=component
                elif stage=='ni-closure-first-binding':
                    human=private('owned-b3b4-first-uv-confirmed.json')
                    if not (human=={'pid':args.pid,'stage':stage,'humanConfirmedUV':True}
                            and state.get('pid')==args.pid and state.get('nativeSucceeded')==1):
                        time.sleep(.2);continue
                    current=control('status')
                    assert current['proxy']['bindingSubmits']==initial['proxy']['bindingSubmits']+1 and current['proxy']['lastBindingStatus']==204
                    draft_delta=0 if facts.get('originalDraftClosureIndependentlyVerifiedWithoutAdvancingClock') else 1
                    assert current['sql']['passkeys']==initial['sql']['passkeys']+1 and current['sql']['closedAccounts']==initial['sql']['closedAccounts']+draft_delta
                    facts['actualNativeResultAndServerBindingWitnessedAfterHumanUV']=True
                    facts['foregroundNotSampledForFirstBinding']=True
                elif stage=='ni-wrong-native-rp' or (stage=='ni-association-create' and args.variant!='control'):
                    if state.get('nativeErrored',0)<1:time.sleep(.2);continue
                    facts['providerReturnedNativeErrorBeforeProof']=True
                    facts['associationDiagnosisObserved']=state.get('actualAssociationRejected',0)>0
                else:time.sleep(.2);continue
                ack(stage)
            elif stage in ('ni-arm-write-failure','ni-arm-write-unknown'):
                assert args.phase=='ni-k02' and args.package==PACKAGES[1]
                fault=stage.removeprefix('ni-arm-');assert fault==args.variant
                record=json.dumps({'owner':'HNUHOLE_B3B4_NATIVE_IO_V1','mode':fault,'pid':args.pid})
                r=subprocess.run([str(ADB),'-s',PHONE,'shell','run-as',args.package,'tee',
                    'files/owned-b3b4-vault-fault.json'],input=record,capture_output=True,text=True,timeout=15)
                assert r.returncode==0;ack(stage)
            elif stage=='ni-b3b4-complete':
                life=private('owned-acceptance-lifecycle.json');assert life['pid']==args.pid
                facts['actualActivityAndEngine']=life.get('activityCreated',0)>0 and life.get('engineAttached',0)>0
                assert facts['actualActivityAndEngine']
                if args.phase=='ni-k02' and not args.variant.endswith('-read'):
                    fault=private('owned-b3b4-vault-fault-result.json')
                    assert fault=={'pid':args.pid,'mode':args.variant,'owner':'HNUHOLE_B3B4_NATIVE_IO_V1','fired':True}
                    facts['nativeFaultBoundaryWitnessed']=True
                facts['result']='PASS';ack(stage);print('PASS: fixed owned B3/B4 device witness');return
            else:time.sleep(.2);continue
            seen.add(stage)
        raise RuntimeError('Owned device witness timed out; no acceptance claimed')
    except BaseException as error:
        facts['result']='FAIL';facts['failureType']=type(error).__name__;save();raise


if __name__=='__main__':main()
