#!/usr/bin/env python3
"""Fixed B3/B4 controller: owned read-only SQL, proxy modes and normal closure worker."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
from urllib.parse import urlsplit

ROOT=Path('/var/tmp/hnuhole-android-live-b3-b4-20261009')
PHASES=('ni-c01','ni-d01','ni-d02','ni-d03','ni-d04','ni-d05','ni-k01','ni-k02')
VARIANTS=('main','control','bad-signature','missing-package','source','restart','fresh','no-key',
    'write-failure','write-failure-read','write-unknown','write-unknown-read')


def owned():
    assert ROOT.resolve()==ROOT and not ROOT.is_symlink()
    assert (ROOT/'OWNER').read_text().strip()=='HNUHOLE_ANDROID_LIVE_DEV_V1'
    source=ROOT/'repo/tools/android-auth-b3-b4-proxy.py'
    pid=int((ROOT/'b3b4-proxy.pid').read_text())
    words=Path('/proc',str(pid),'cmdline').read_bytes().rstrip(b'\0').split(b'\0')
    assert words[0] in (b'python3',b'/usr/bin/python3') and words[1:]==[str(source).encode()]
    assert hashlib.sha256(source.read_bytes()).hexdigest()==(ROOT/'b3b4-proxy-source.sha256').read_text().strip()


def run(args,env=None):
    r=subprocess.run(args,capture_output=True,text=True,env=env,timeout=120)
    assert r.returncode==0,'Owned operation failed; no private response exported'
    return r.stdout.strip()


def sql_counts():
    project='hnuhole-device-hnuholeandroidliveb3b420261009'
    ids=run(['docker','ps','-q','--filter','label=com.docker.compose.project='+project]).split()
    assert len(ids)==3
    containers=json.loads(run(['docker','inspect',*ids]))
    material=ROOT/'services/material'
    cfg=json.loads((material/'c.json').read_text());url=urlsplit(cfg['databaseUrl'])
    assert url.hostname=='127.0.0.1' and url.password is None and url.username=='hnuhole_c_runtime' and url.path=='/hnuhole_c'
    db=next(c for c in containers if c['Config']['Labels']['com.docker.compose.service']=='community-postgres')
    assert all(m['Name'].startswith(project+'_') for m in db['Mounts'] if m['Type']=='volume')
    assert any(int(p['HostPort'])==url.port and p['HostIp']=='127.0.0.1' for p in db['NetworkSettings']['Ports']['5432/tcp'])
    env=os.environ.copy();env['PGPASSWORD']=(material/cfg['databasePasswordFile']).read_text().strip()
    query="""SELECT json_build_object(
    'gateState',gate_state,'generation',authorization_generation,
    'activeAccounts',(SELECT count(*) FROM c_auth.accounts WHERE state='ACTIVE'),
    'closedAccounts',(SELECT count(*) FROM c_auth.accounts WHERE state='CLOSED'),
    'closedSecretsRemaining',(SELECT count(*) FROM c_auth.accounts WHERE state='CLOSED' AND (username IS NOT NULL OR password_hash IS NOT NULL OR password_salt IS NOT NULL)),
    'pendingClosures',(SELECT count(*) FROM c_auth.closure_requests WHERE state='PENDING'),
    'passkeys',(SELECT count(*) FROM c_auth.passkeys),
    'recoveryCodes',(SELECT count(*) FROM c_auth.recovery_codes),
    'closedPasskeys',(SELECT count(*) FROM c_auth.passkeys p JOIN c_auth.accounts a USING(account_id) WHERE a.state='CLOSED'),
    'resetIntents',(SELECT count(*) FROM c_auth.reset_intents),
    'activeSessions',(SELECT count(*) FROM c_auth.sessions WHERE revoked_at IS NULL),
    'closedActiveSessions',(SELECT count(*) FROM c_auth.sessions s JOIN c_auth.accounts a USING(account_id) WHERE a.state='CLOSED' AND revoked_at IS NULL),
    'identityReceipts',(SELECT count(*) FROM public.identity_change_receipts),
    'closedIdentityProfiles',(SELECT count(*) FROM public.community_identities i JOIN c_auth.accounts a USING(account_id) WHERE a.state='CLOSED' AND (i.deleted_at IS NULL OR i.nickname IS NOT NULL OR i.avatar IS NOT NULL OR i.last_renamed_at IS NOT NULL)),
    'activeIdentities',(SELECT count(*) FROM public.community_identities WHERE deleted_at IS NULL))
    FROM c_auth.authorization_gate WHERE singleton_id=1;"""
    return json.loads(run(['/usr/lib/postgresql/16/bin/psql','-X','-At','-v','ON_ERROR_STOP=1',cfg['databaseUrl'],'-c',query],env))


def snapshot():
    proxy=json.loads((ROOT/'b3b4-proxy-metrics.json').read_text());assert proxy['proofsStored'] is False
    return dict(sql=sql_counts(),proxy=proxy)


def mode(value):
    assert value in ('normal','hold-two','wrong-rp-options','wrong-rp-hash')
    if value=='hold-two' and (ROOT/'b3b4-release-replies').exists():
        counts=snapshot()['proxy']
        planfile=ROOT/'b3b4-evidence/final-batch-20261010.json'
        if planfile.exists() and planfile.is_file():
            plan=json.loads(planfile.read_text())
            assert plan['restartedProxyPid']==int((ROOT/'b3b4-proxy.pid').read_text())
            assert all(counts[k]==plan['proxyBeforeRestart'][k] for k in ('heldBindingReplies','heldIdentityReplies','releasedBindingReplies','releasedIdentityReplies'))
        else:
            assert counts['heldBindingReplies']==counts['releasedBindingReplies']
            assert counts['heldIdentityReplies']==counts['releasedIdentityReplies']
        assert (ROOT/'b3b4-release-replies').read_text()=='owned-release\n'
        (ROOT/'b3b4-release-replies').unlink()
    target=ROOT/'b3b4-proxy-mode.json';temp=target.with_suffix('.tmp')
    temp.write_text(json.dumps({'mode':value})+'\n');temp.replace(target)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=('status','prepare','capture','hold-two','wrong-rp-options','wrong-rp-hash','normal','close-draft','close','close-unknown','release-replies','release-unknown-replies','assert-unknown-held','verify-draft-resume'))
    parser.add_argument('--phase',choices=PHASES)
    parser.add_argument('--variant',choices=VARIANTS,default='main')
    parser.add_argument('--resume-existing',action='store_true')
    args=parser.parse_args();owned()
    evidence=ROOT/'b3b4-evidence';evidence.mkdir(mode=0o700,exist_ok=True)
    if args.action=='status':print(json.dumps(snapshot()));return
    if args.action in ('normal','hold-two','wrong-rp-options','wrong-rp-hash'):
        mode(args.action);print('MODE: '+args.action);return
    if args.action=='verify-draft-resume':
        assert args.phase=='ni-c01' and args.variant=='main'
        baseline=json.loads((evidence/'ni-c01-main-before.json').read_text())
        state=snapshot();cycle=baseline['sql']['closedAccounts'];assert cycle==3
        assert state['sql']['closedAccounts']==cycle+1 and state['sql']['pendingClosures']==0
        assert state['proxy']['closureSubmits']==baseline['proxy']['closureSubmits']+1
        run(['python3',str(ROOT/'repo/tools/control-android-closure.py'),'verify-finalized','--cycle',str(cycle),'--work',str(ROOT)])
        print('VERIFIED: original finalized draft closure; no new clock advance or submission');return
    if args.action=='assert-unknown-held':
        baseline=json.loads((evidence/'ni-c01-control-before.json').read_text())
        state=snapshot()
        assert state['sql']['passkeys']==baseline['sql']['passkeys']+1
        assert state['proxy']['heldBindingReplies']==baseline['proxy']['heldBindingReplies']+1
        assert state['proxy']['lastBindingStatus']==204
        print('HELD: first real native binding committed, original response outstanding');return
    if args.action in ('close-draft','close','close-unknown'):
        state=snapshot()
        allowed={'close-draft':(0,3,5,8,10),'close':(1,4,6,9,11),'close-unknown':(2,5,7)}[args.action]
        cycle=state['sql']['closedAccounts']-(0 if state['sql']['pendingClosures']==1 else 1)
        assert cycle in allowed,'Only original or three bounded fresh complete cases'
        if cycle>=10:
            plan=json.loads((evidence/'discoverable-batch-20261010.json').read_text())
            assert plan['allowedClosureCycles']==[10,11] and plan['requireActualAssertionPreflight']
            host=Path('/mnt/d/zewbbyTest/Hnuhole-android-live-faults-20261005/matrix/b3b4-evidence')
            witness=json.loads((host/'ni-c01-main-device.json').read_text())
            builds=json.loads((host/'builds.json').read_text())
            required='ni-assertion-preflight-passed' if cycle==10 else 'ni-identity-assertion-preflight-passed'
            assert witness['result']=='RUNNING' and witness['phase']=='ni-c01' and witness['variant']=='main'
            assert witness['device']=='10CEAG17RY003M7' and witness.get(required) is True
            assert witness['apkSha256']==next(a['apkSha256'] for a in builds['apks'] if a['fileName']=='phone-b3b4.apk')
        elif cycle>=8:
            plan=json.loads((evidence/'final-batch-20261010.json').read_text())
            assert plan['allowedClosureCycles']==[8,9] and plan['userConfirmedUninstall']
        assert args.phase=='ni-c01'
        baseline=json.loads((evidence/('ni-c01-'+args.variant+'-before.json')).read_text())
        tool=ROOT/'repo/tools/control-android-closure.py'
        assert tool.read_bytes()==Path('/mnt/c/Users/Administrator/Documents/ChatGPT/HnuHole/tools/control-android-closure.py').read_bytes()
        if state['sql']['pendingClosures']==1:
            assert state['sql']['activeIdentities']==(3 if args.action=='close' else 0)
            assert state['proxy']['heldBindingReplies']==baseline['proxy']['heldBindingReplies']+(1 if args.action=='close-unknown' else 0)
            assert state['proxy']['heldIdentityReplies']==baseline['proxy']['heldIdentityReplies']+(1 if args.action=='close' else 0)
            for action in ('capture','advance'):
                run(['python3',str(tool),action,'--cycle',str(cycle),'--work',str(ROOT)])
        else:
            assert state['sql']['pendingClosures']==0 and state['sql']['closedAccounts']==cycle+1
            assert (ROOT/'closure-evidence'/('cycle-'+str(cycle)+'.private.json')).exists()
            run(['python3',str(tool),'verify-finalized','--cycle',str(cycle),'--work',str(ROOT)])
        after=snapshot()['sql']
        assert after['closedAccounts']==cycle+1 and after['closedPasskeys']==after['closedActiveSessions']==after['closedIdentityProfiles']==after['closedSecretsRemaining']==0
        assert after['passkeys']==state['sql']['passkeys']-(1 if state['sql']['pendingClosures']==1 and args.action!='close-draft' else 0)
        assert after['identityReceipts']==state['sql']['identityReceipts']
        print('CLOSED: immutable seven-day deadline, normal workers, V ACK and retained permanent receipts');return
    if args.action in ('release-replies','release-unknown-replies'):
        assert args.phase=='ni-c01'
        baseline=json.loads((evidence/('ni-c01-'+args.variant+'-before.json')).read_text())
        state=snapshot();assert state['sql']['closedAccounts']==baseline['sql']['closedAccounts']+(1 if args.action=='release-unknown-replies' else 2)
        assert state['sql']['activeAccounts']>=1
        target=ROOT/'b3b4-release-replies';assert not target.exists();target.write_text('owned-release\n')
        print('RELEASED: old actual HTTP responses after formal closure and fresh account');return
    assert args.phase
    stem=args.phase+'-'+args.variant
    anchor=evidence/(stem+'-before.json')
    if args.action=='prepare':
        if args.resume_existing:
            assert args.phase=='ni-c01' and args.variant=='main'
            assert anchor.is_file() and not (evidence/(stem+'.json')).exists()
            original=json.loads(anchor.read_text());current=snapshot()
            if original['sql']['closedAccounts']==5:
                assert current['sql']['closedAccounts']==6 and current['sql']['pendingClosures']==0
                assert current['sql']['passkeys']==original['sql']['passkeys']
                assert current['sql']['activeIdentities']==2
                assert current['proxy']['registrationSubmits']==original['proxy']['registrationSubmits']+2
                assert current['proxy']['closureSubmits']==original['proxy']['closureSubmits']+1
                assert current['proxy']['identitySubmits']==original['proxy']['identitySubmits']+2
                assert current['proxy']['bindingSubmits']==original['proxy']['bindingSubmits']
                assert current['proxy']['heldIdentityReplies']==original['proxy']['heldIdentityReplies']
                assert (ROOT/'closure-evidence/5-advance.json').is_file()
                print('RESUMED: original cycle5 and fresh account retained; no proof submitted or late controller started');return
            if original['sql']['closedAccounts']==3:
                assert current['sql']['closedAccounts']==4 and current['sql']['pendingClosures']==0
                assert current['sql']['passkeys']==original['sql']['passkeys'] and current['sql']['activeIdentities']==0
                assert current['proxy']['registrationSubmits']==original['proxy']['registrationSubmits']+1
                assert current['proxy']['closureSubmits']==original['proxy']['closureSubmits']+1
                assert current['proxy']['bindingSubmits']==original['proxy']['bindingSubmits']
                assert current['proxy']['identitySubmits']==original['proxy']['identitySubmits']
                assert (ROOT/'closure-evidence/3-advance.json').is_file()
                print('RESUMED: original reviewed draft closure baseline retained, registration continuation only');return
            assert original['sql']['closedAccounts']==0
            assert current['sql']['closedAccounts']==1 and current['sql']['pendingClosures']==0
            empty=(current['sql']['activeAccounts']==0 and current['sql']['passkeys']==0
                and current['proxy']['registrationSubmits']==1 and current['proxy']['bindingSubmits']==0)
            bound=(current['sql']['activeAccounts']==1 and current['sql']['passkeys']==1
                and current['sql']['activeIdentities']==2 and current['proxy']['registrationSubmits']==2
                and current['proxy']['bindingSubmits']==1 and current['proxy']['lastBindingStatus']==204)
            assert empty or bound
            assert current['proxy']['closureSubmits']==1 and current['proxy']['identitySubmits']==(2 if bound else 0)
            assert (ROOT/'closure-evidence/0-advance.json').exists()
            print('RESUMED: original immutable count anchor after confirmed draft closure; no resubmission');return
        assert not anchor.exists(),'Archive prior failed attempt explicitly'
        anchor.write_text(json.dumps(snapshot(),indent=2)+'\n');mode('normal')
        print('PREPARED: immutable owned count anchor '+stem);return
    before=json.loads(anchor.read_text());after=snapshot()
    delta={k:after['proxy'][k]-before['proxy'][k] for k in after['proxy'] if k!='proofsStored' and not k.startswith('last')}
    if args.phase=='ni-c01' and args.variant=='control':
        assert delta['bindingSubmits']==delta['closureSubmits']==1 and delta['registrationSubmits'] in (1,2)
        assert delta['heldBindingReplies']==delta['releasedBindingReplies']==1 and delta['identitySubmits']==0
        assert after['sql']['closedAccounts']==before['sql']['closedAccounts']+1
        assert after['sql']['activeAccounts']==before['sql']['activeAccounts']+delta['registrationSubmits']-1
        assert after['sql']['passkeys']==before['sql']['passkeys'] and after['sql']['closedPasskeys']==0
    elif args.phase=='ni-c01':
        discoverable=before['sql']['closedAccounts']==10
        assert delta['bindingSubmits']==(2 if discoverable else 1) and delta['closureSubmits']==2 and delta['registrationSubmits'] in ((2,3) if discoverable else (3,))
        if discoverable:assert delta['removalSubmits']==1 and after['proxy']['lastRemovalStatus']==204
        assert delta['identitySubmits']==3 and delta['heldBindingReplies']==0 and delta['heldIdentityReplies']==1
        final_batch=before['sql']['closedAccounts']>=8
        assert delta['releasedBindingReplies']==(0 if final_batch else before['proxy']['heldBindingReplies']-before['proxy']['releasedBindingReplies'])
        assert delta['releasedIdentityReplies']==(1 if final_batch else before['proxy']['heldIdentityReplies']-before['proxy']['releasedIdentityReplies']+1)
        assert delta['resetIntentSubmits']==1 and after['proxy']['lastResetStatus']==401
        assert after['sql']['closedAccounts']==before['sql']['closedAccounts']+2
        assert after['sql']['activeAccounts']==before['sql']['activeAccounts']+delta['registrationSubmits']-2
        assert after['sql']['passkeys']==before['sql']['passkeys']
        assert after['sql']['resetIntents']==before['sql']['resetIntents']
        assert after['sql']['activeIdentities']==0 and after['sql']['identityReceipts']==before['sql']['identityReceipts']+3
        assert after['sql']['closedIdentityProfiles']==0
    elif args.phase in ('ni-d02','ni-d03'):
        if args.variant=='control':assert delta['bindingSubmits']==1 and after['proxy']['lastBindingStatus']==204
        else:assert delta['bindingOptions']==1 and delta['bindingSubmits']==0 and after['sql']['passkeys']==before['sql']['passkeys']
    elif args.phase=='ni-d01':
        assert delta['modifiedRpOptions']==1 and delta['modifiedRpHash']==1
        assert delta['bindingSubmits']==1 and after['proxy']['lastBindingStatus']==422
        assert after['sql']['passkeys']==before['sql']['passkeys']-delta.get('removalSubmits',0)
    elif args.phase=='ni-d05':
        assert delta['resetIntentSubmits']==1 and after['proxy']['lastResetStatus']==401
        assert after['sql']['resetIntents']==before['sql']['resetIntents']
        if 'removalSubmits' in before['proxy']:
            assert delta['bindingSubmits']==1 and delta['removalSubmits']>=1 and after['proxy']['lastRemovalStatus']==204
            assert after['sql']['passkeys']==before['sql']['passkeys']+1-delta['removalSubmits']
            assert after['sql']['recoveryCodes']==before['sql']['recoveryCodes']
            assert after['sql']['activeSessions']==before['sql']['activeSessions']
        else:assert after['sql']['passkeys']==before['sql']['passkeys']+1
    elif args.phase=='ni-d04':
        assert delta['bindingSubmits']==delta['resetIntentSubmits']==delta['identitySubmits']==0
        assert delta['sessionReads']>=2
    elif args.phase=='ni-k01' and args.variant in ('fresh','no-key'):
        assert delta['loginSubmits']==delta['sessionReads']==delta['renewalSubmits']==0
    report=dict(result='PASS',phase=args.phase,variant=args.variant,scope='OWNED_SQL_AND_PROXY_COUNTS_ONLY',
        before=before,after=after,delta=delta,sqlReadOnly=True,proofsStored=False,actualAppAcceptancePassed=False)
    (evidence/(stem+'.json')).write_text(json.dumps(report,indent=2)+'\n')
    print('CAPTURED: independent counts '+stem)


if __name__=='__main__':main()
