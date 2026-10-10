#!/usr/bin/env python3
"""Accept fixed cases only from matching App/device/version and owned SQL evidence."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import subprocess
from datetime import datetime, timezone, timedelta

REPO=Path(__file__).resolve().parents[1]
ROOT=Path('D:/zewbbyTest/Hnuhole-android-live-faults-20261005/matrix')
LINUX='/var/tmp/hnuhole-android-live-b3-b4-20261009'
CASES=('NI-C01','NI-C02','NI-C03','NI-C04','NI-D01','NI-D02','NI-D03','NI-D04','NI-D05','NI-K01','NI-K02')

def read(path):return json.loads(path.read_text(encoding='utf-8-sig'))

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sync-handoff',action='store_true')
    parser.add_argument('--handoff-date',default=datetime.now(timezone(timedelta(hours=8))).strftime('%Y-%m-%d'))
    args=parser.parse_args()
    assert re.fullmatch(r'\d{4}-\d{2}-\d{2}',args.handoff_date)
    assert ROOT.resolve()==ROOT.resolve(strict=True) and not ROOT.is_symlink()
    assert (ROOT/'OWNER').read_text().strip()=='HNUHOLE_ANDROID_MATRIX_V1'
    evidence=ROOT/'b3b4-evidence';accepted={};stages={}
    def stage(phase,variant):
        key=phase+'-'+variant
        if key in stages:return stages[key]
        paths=[evidence/(key+suffix) for suffix in ('-report.json','-device.json','-version.json')]
        if not all(p.exists() for p in paths):return None
        app,device,version=map(read,paths)
        assert app['actualApp'] and app['nativeVault'] and not app['rawProofStored']
        assert device['result']=='PASS' and device['actualActivityAndEngine']
        assert app['pid']==device['pid'] and app['applicationId']==device['applicationId']==version['applicationId']
        assert device['apkSha256']==version['apkSha256'] and version['capturedAtLaunch']
        assert all(v['phase']==phase and v['variant']==variant for v in (app,device,version))
        code="from pathlib import Path; r=Path('"+LINUX+"'); assert (r/'OWNER').read_text().strip()=='HNUHOLE_ANDROID_LIVE_DEV_V1'; print((r/'b3b4-evidence/"+key+".json').read_text())"
        r=subprocess.run(['wsl','-d','Ubuntu-24.04','--','python3','-c',code],capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=20)
        assert r.returncode==0,'Matching independent owned SQL evidence required'
        sql=json.loads(r.stdout)
        assert sql['result']=='PASS' and sql['sqlReadOnly'] and not sql['proofsStored']
        assert sql['phase']==phase and sql['variant']==variant
        result=dict(actualApp=app,independentDevice=device,versionAtLaunch=version,independentSqlAndProxy=sql,
            fileSha256={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in paths})
        stages[key]=result;return result
    def accept(case,requirements,flags):
        values=[stage(*s) for s in requirements]
        if any(v is None for v in values):return
        for index,required in flags.items():
            assert all(values[index]['actualApp'].get(f) is True for f in required),case+' missing actual boundary'
        accepted[case]=dict(caseId=case,id=case.lower(),result='PASS',
            stageKeys=[p+'-'+v for p,v in requirements],versionScope='Each actual stage retains its own APK/source/PID; preparation does not replace device evidence.')
    accept('NI-D04',[('ni-d04','main')],{0:('actualDeviceWrongCaRejected','actualDeviceWrongHostnameRejected','normalPinnedHttpsBeforeAndAfter')})
    accept('NI-C01',[('ni-c01','main')],{0:('closedSystemCredentialActualAssertionRejected','actualNormalWorkerAndVerifierRelease','sqlDeadlineAndDeviceClockUnchanged')})
    accept('NI-C03',[('ni-c01','main')],{0:('actualIdentityDelayedReplyAfterFreshRegistration','lateOriginalResponsesAndQueriesCannotMutateNewAccount','actualNormalWorkerAndVerifierRelease')})
    accept('NI-C04',[('ni-c01','main')],{0:('sameExactEmailFreshAccountNoInheritedCredentialIdentityHistoryDraft','lateOriginalResponsesAndQueriesCannotMutateNewAccount')})
    accept('NI-C02',[('ni-c01','control')],{0:('actualFirstBindingCommittedWhileReplyHeld','originalUnknownBindingRetainedAcrossFormalClosure','lateOriginalBindingReplyAndQueryCannotMutateFreshAccount','actualNormalWorkerAndVerifierRelease')})
    accept('NI-D01',[('ni-d01','main')],{0:('clientPinnedRpRejectedWithoutNativeStart','actualNativeWrongRpAssociationRejected','actualServerWrongRpHashRejected422','originalResultQueriedWithoutProofReplay')})
    for case,phase,variant in (('NI-D02','ni-d02','bad-signature'),('NI-D03','ni-d03','missing-package')):
        accept(case,[('ni-d02','control'),(phase,variant)],{0:('approvedPackageAndCertificateActualBinding',),1:('actualProviderAssociationRejectedBeforeProofSubmission',)})
    removal=stage('ni-d05','main')
    if removal and removal['actualApp'].get('otherPasskeyRetentionRequiresSeparateActualSqlEvidence'):
        sql=read(evidence/'v15-sql-regression.json')
        assert sql['result']=='PASS' and sql['actualPostgres'] and sql['twoCredentialRemovalAndRemainingCredentialRecovery']
        assert not sql['physicalTwoKeyEnrollmentClaimed']
        for path,digest in sql['sourceFilesSha256'].items():
            assert hashlib.sha256((REPO/path).read_bytes()).hexdigest()==digest
        accept('NI-D05',[('ni-d05','main')],{0:('productRemovalAndActualSameCredentialAssertionRejected','currentSessionAndRecoveryCodeRetained','recoveryCapabilityNotConsumed')})
        accepted['NI-D05']['supportingSqlRegression']=sql
        accepted['NI-D05']['proofScope']='Actual phone removal/old assertion/session/recovery-code availability plus actual PostgreSQL two-key retention; not two native enrollments on vivo.'
    else:
        accept('NI-D05',[('ni-d05','main')],{0:('productRemovalAndActualSameCredentialAssertionRejected','otherPasskeyAndCurrentSessionRetained','recoveryCapabilityNotConsumed')})
    accept('NI-K01',[('ni-k01',v) for v in ('source','restart','fresh','no-key')],{
        0:('actualProductSessionAndDraftPersisted',),1:('independentProcessRestoredExactSessionAndDraft',),
        2:('freshProductGuestWithoutAutomaticAuthentication',),3:('actualProductReadOverwriteAndAuthorityRejected',)})
    if 'NI-K01' in accepted:
        for action,flag in (('capture-cipher','ciphertextOnlyExported'),('reinstall-fresh','actualPackageManagerReinstall'),
                ('reinstall-no-key','oldCiphertextRestoredWithoutKeys'),('reinstall-after-no-key','rejectedCiphertextPreservedUntilOwnedReinstall')):
            value=read(evidence/(action+'-package-manager.json'))
            assert value['result']=='PASS' and value[flag] and value['mainPackageApkPreserved']
        assert stages['ni-k01-source']['actualApp']['pid']!=stages['ni-k01-restart']['actualApp']['pid']
    accept('NI-K02',[('ni-k02',v) for v in ('write-failure','write-failure-read','write-unknown','write-unknown-read')],{
        0:('actualNativeKeystoreAtomicFileFault','failedAcknowledgementPublishedNoAuthority'),1:('independentProcessReadsOnlyActuallyDurableState',),
        2:('actualNativeKeystoreAtomicFileFault','failedAcknowledgementPublishedNoAuthority'),3:('independentProcessReadsOnlyActuallyDurableState',)})
    if 'NI-K02' in accepted:
        for variant in ('write-failure','write-unknown'):
            assert stages['ni-k02-'+variant]['independentDevice']['nativeFaultBoundaryWitnessed']
            assert stages['ni-k02-'+variant]['actualApp']['pid']!=stages['ni-k02-'+variant+'-read']['actualApp']['pid']
    ep=REPO/'services/api/authlab/android-matrix-verification.json';lp=REPO/'docs/design/module-acceptance-ledger.json'
    e=read(ep);ledger=read(lp);original_b1=copy.deepcopy(e['b1b2Verification'])
    b=e['b3b4Verification'];b.update(acceptedCaseCount=len(accepted),remainingPhases=[c.lower() for c in CASES if c not in accepted],
        result='PASS' if len(accepted)==11 else 'NOT_RUN',actualDeviceAcceptancePassed=len(accepted)==11,
        acceptedStageEvidence=stages,fullModuleAcceptancePassed=False,fullNonIOSAcceptancePassed=False,productionApproved=False)
    attempts=[read(p) for p in sorted(evidence.glob('attempt-*/failure.json'),
        key=lambda p:int(re.fullmatch(r'attempt-(\d+)-.+',p.parent.name)[1]))]
    b['priorActualAttempts']=attempts
    failed={}
    for attempt in attempts:
        for ids,value in attempt.get('cases',{}).items():
            for case in ids.split('/'):
                if case in CASES:failed[case]=value
    b['phases']=[accepted.get(c,dict(caseId=c,id=c.lower(),
        result='FAIL' if c in failed else 'NOT_RUN',
        reason=failed[c]['reason'] if c in failed else 'Fixed actual acceptance not yet executed completely.')) for c in CASES]
    b['failedCaseCount']=sum(p['result']=='FAIL' for p in b['phases'])
    b['notRunCaseCount']=sum(p['result']=='NOT_RUN' for p in b['phases'])
    if len(accepted)!=11 and b['failedCaseCount']:
        b['result']='FAIL'
    assert e['b1b2Verification']==original_b1
    ledger['currentNonIOS']['b3b4Verification']=copy.deepcopy(b)
    reason=f'B3/B4 accepted {len(accepted)}/11 fixed cases; {b["failedCaseCount"]} failed and {b["notRunCaseCount"]} not run. Every accepted stage retains App/device/SQL and launch version; B1/B2 eleven prior cases immutable.'
    e['currentHandoffReason']=reason;ledger['currentNonIOS']['currentHandoffReason']=reason;ledger['currentHandoffState']['reason']=reason
    for m in ledger['modules']:
        if 'currentB3B4Acceptance' in m:
            m['currentB3B4Acceptance'].update(result=b['result'],acceptedCaseIds=list(accepted),
                unexecutedChecks=[p['id'] for p in b['phases'] if p['result']=='NOT_RUN'],
                executedFailedChecks=[p['id'] for p in b['phases'] if p['result']=='FAIL'],reason=reason)
    for p,data in ((ep,e),(lp,ledger)):p.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    if args.sync_handoff:
        device_state='用户确认卸载后的旧本机状态不能续用，历史证据及可复用环境保留' if b.get('currentDeviceUpdate',{}).get('userConfirmedUninstall') else '主账号、草稿及可复用环境保留'
        remaining=('固定11项已全部取得各自范围的实际通过证据。' if len(accepted)==11 else
            '本轮11项均有执行记录；未通过项为'+ '、'.join(p['caseId'] for p in b['phases'] if p['result']=='FAIL')+'，具体缺口和后续重试前置条件见本批记录。'
            if b.get('manualActionsComplete') and b['notRunCaseCount']==0 else '剩余固定项继续执行，')
        notice=f'> **{args.handoff_date} B3＋B4 逐项结果：**固定11项当前接受{len(accepted)}项（'+('、'.join(accepted) or '无')+'）。每项保留独立App／设备／SQL和启动版本；夹具失败与原成功前置记录保留，不重放证明。'+remaining+'B1＋B2原11项PASS不改写。'+device_state+'；完整非iOS／iOS／生产未通过，HnuHole未提交／推送。见[任务单](auth-privacy-b3-b4-plan.md)及矩阵JSON的`b3b4Verification`。'
        for name in ('HANDOFF.md','progress.md','module-acceptance-handoff.md','auth-privacy-machine-handoff.md','auth-privacy-closure-checklist.md','auth-privacy-non-ios-validation-report.md'):
            p=REPO/'docs/design'/name;s=p.read_text(encoding='utf-8')
            s=re.sub(r'> \*\*\d{4}-\d{2}-\d{2} B3＋B4 逐项结果：\*\*[^\n]*\n*','',s)
            i=s.find('\n')+1;p.write_text(s[:i]+'\n'+notice+'\n\n'+s[i:],encoding='utf-8')
    print('ACCEPTED: '+str(len(accepted))+'/11; '+','.join(accepted))

if __name__=='__main__':main()
