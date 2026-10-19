#!/usr/bin/env python3
"""Only the new nonempty C comment/moderation restore and pre-0018 compatibility delta."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile
import uuid

from lab import IntegrationLab, write, sha
from data import Data
from policy import require,owned_tool_environment


def old_contract_diagnosis(lab, old):
    old_checker=old/'services/api/internal/authprivacy/community_comments_schema.go'
    new_checker=lab.api/'internal/authprivacy/community_comments_schema.go'
    require('"tasks": {"owner_visible", "abandoned_at", "deleted_at"}' in old_checker.read_text(),'old exact checker changed')
    require('"tasks": {"owner_visible", "abandoned_at", "deleted_at", "moderation_hidden"}' in new_checker.read_text(),'new exact checker changed')
    require(lab.sql('c','SELECT current_database(),current_user',role='runtime')=='hnuhole_c|hnuhole_c_runtime','actual restored runtime role required')
    query="SELECT attname FROM pg_attribute WHERE attrelid='c_comments.tasks'::regclass AND attnum>0 AND NOT attisdropped AND NOT(attname=ANY(ARRAY[%s])) AND has_column_privilege(current_user,attrelid,attname,'UPDATE') ORDER BY attname"
    old_result=lab.sql('c',query%"'owner_visible','abandoned_at','deleted_at'",role='runtime')
    new_result=lab.sql('c',query%"'owner_visible','abandoned_at','deleted_at','moderation_hidden'",role='runtime')
    require(old_result=='moderation_hidden' and new_result=='','specific old authorization incompatibility not established')
    return dict(result='PASS_EXACT_CONTRACT_DIAGNOSIS',oldCheckerSha256=sha(old_checker),newCheckerSha256=sha(new_checker),database='hnuhole_c',role='hnuhole_c_runtime',target='restore-c',oldDisallowedUpdateColumns=[old_result],newDisallowedUpdateColumns=[],scope='Exact read-only old/new UPDATE predicate plus old startup rejection; no permission weakening')


def run(lab):
    owned_tool_environment(lab.root.parent/'tools',lab.env)
    d=Data(lab)
    if 'restoreRequest' in d.state:raise RuntimeError('Inspect existing restore state; no blind repeat')
    evidence=dict(result='FAIL',sourceSha=lab.state['sourceSha'],scope='New nonempty C comments/0018 governance data and rollback compatibility only; V restore and prior full rehearsal inherited',checks=[],device='NOT_RUN')
    path=lab.root/'integration-restore-evidence.json'
    def passed(name):
        evidence['checks'].append(name);write(path,evidence);print(name+' PASS',flush=True)
    request=str(uuid.uuid4());d.state['restoreRequest']=request;d.save()
    reportPath='/api/v1/reports/'+request
    fence=d.request('GET',reportPath,actor='reporter')
    reported=d.request('PUT',reportPath,dict(postId=d.state['postId'],commentId=d.state['restoreReply']['commentId'],identityId=d.state['accounts']['reporter']['identityId'],reason='OTHER',description='新增恢复兼容合成材料',images=[],retryToken=fence['retryToken']),actor='reporter')
    case=reported['report']['caseId'];d.state['restoreCaseId']=case;d.save()
    d.request('POST','/api/v1/moderation/cases/'+case+'/decision',dict(commandId=str(uuid.uuid4()),expectedVersion=1,action='MUTE',days=3,reason='隔离恢复样本，非真实用户处罚'),actor='reviewer')
    sanction=lab.sql('c',"SELECT sanction_id::text FROM c_moderation.sanctions WHERE case_id='"+case+"'::uuid")
    appeal=d.request('PUT','/api/v1/sanctions/'+sanction+'/appeals/'+str(uuid.uuid4()),dict(description='隔离恢复申诉材料',images=[]),actor='author')
    d.state.update(restoreSanctionId=sanction,restoreAppealId=appeal['id']);d.save()
    notice=d.request('GET','/api/v1/system-notifications?identityId='+d.state['accounts']['reporter']['identityId'],actor='reporter')['items'][0]
    read=d.request('POST','/api/v1/system-notifications/'+notice['id']+'/read?identityId='+d.state['accounts']['reporter']['identityId'],{},actor='reporter')
    d.state['restoreReadNotice']=read;d.save()
    counts=json.loads(lab.sql('c',"SELECT json_build_object('comments',(SELECT count(*) FROM c_comments.tasks),'commentImages',(SELECT count(*) FROM c_comments.images),'reports',(SELECT count(*) FROM c_moderation.reports),'sanctions',(SELECT count(*) FROM c_moderation.sanctions),'appeals',(SELECT count(*) FROM c_moderation.appeals),'roles',(SELECT count(*) FROM c_moderation.roles),'audit',(SELECT count(*) FROM c_moderation.audit))"))
    require(all(v>0 for v in counts.values()),'nonempty new restore facts required');evidence['nonemptyCounts']=counts
    passed('nonempty-comment-image-report-sanction-appeal-role-audit-read-notification-facts')
    lab.halt(['watch-c']);lab.operator('freeze','c')
    d.request('GET','/api/v1/posts/'+d.state['postId']+'/comments/'+d.state['root']['commentId'],actor='reporter',expected=503)
    lab.halt(['c'])
    before={k:v for k,v in lab.fingerprint().items() if k.startswith('c:')}
    dump=lab.root/'backup/c-integration-schema18.dump'
    lab.run(['pg_dump','--format=custom','--no-owner','--no-privileges','--file',dump,lab.dsn('c','migrator')],'new-comment-facts-backup',env=lab.password_env('c','migrator'))
    lab.init_cluster('restore','c')
    lab.run(['pg_restore','--exit-on-error','--no-owner','--no-privileges','--dbname',lab.dsn('c','migrator','restore'),dump],'new-comment-facts-restore',env=lab.password_env('c','migrator'))
    lab.state['target']='restore';lab.save();lab.grants('c');lab.audit()
    require(before=={k:v for k,v in lab.fingerprint().items() if k.startswith('c:')},'new C restored facts mismatch')
    evidence.update(backupSha256=sha(dump),cRestoredFingerprints=before,restoredCEntries=len(before))
    passed('new-C-instance-complete-data-sequences-and-canonical-comment-moderation-permissions-match')
    configPath=lab.root/'material/c.json';config=json.loads(configPath.read_text());config['databaseUrl']=lab.dsn('c','runtime');write(configPath,config)
    opath=lab.root/'material/operator/operator.json';op=json.loads(opath.read_text());op['recoveryDatabaseUrl']=lab.dsn('c','recovery');write(opath,op)
    # An older backend cannot be accepted simply because its binary can start:
    # 0018 changes the visibility semantics and required authorization contract.
    previous='2da7cdf9d4311e8017108e56656c74d379d4a01b'
    old=lab.root/'pre0018-source';old.mkdir(mode=0o700)
    archive=lab.root/'pre0018.tar'
    with archive.open('wb') as stream:subprocess.run(['git','-C',lab.source,'archive',previous,'services/api'],stdout=stream,check=True)
    with tarfile.open(archive) as tar:tar.extractall(old,filter='data')
    archive.unlink()
    lab.run(['go','build','-mod=readonly','-o',lab.root/'bin/pre0018-community','./cmd/api'],'build-pre0018-compatibility',cwd=old/'services/api')
    status=lab.run([lab.root/'bin/pre0018-community','-config',configPath],'pre0018-backend-compatibility',check=False,timeout=20)
    if status==0:raise RuntimeError('Old backend unexpectedly stayed up; inspect visibility before allowing rollback')
    log=(lab.root/'pre0018-backend-compatibility.private.log').read_text()
    if 'stage=runtime reason=failed' not in log:raise RuntimeError('Pre0018 did not reach its runtime checks')
    evidence['compatibilityCause']=old_contract_diagnosis(lab,old)
    evidence['pre0018BackendRollback']='REJECTED_INCOMPATIBLE: exact old comment UPDATE checker rejects moderation_hidden; no Down'
    passed('pre0018-backend-rollback-rejected-on-new-authorization-contract')
    lab.spawn('c',[lab.root/'bin/candidate-community','-config',configPath])
    lab.operator('recover','c');lab.spawn('watch-c',[lab.root/'bin/authdev','watch','-operator',opath]);lab.health()
    # Restored C recovery invalidates old sessions; re-authenticate normally.
    d.request('GET','/api/v1/channels',actor='reporter',expected=401)
    for actor in d.state['accounts']:d.login(actor)
    restored=d.request('GET',reportPath,actor='reporter')
    require(restored['report']['caseId']==case,'original report case mismatch')
    oldRead=d.request('GET','/api/v1/system-notifications/'+read['id']+'?identityId='+d.state['accounts']['reporter']['identityId'],actor='reporter')
    require(oldRead['readAt']==read['readAt'],'original notification read state mismatch')
    d.request('GET','/api/v1/posts/'+d.state['postId']+'/comments/'+d.state['restoreReply']['commentId'],actor='reporter',expected=404)
    d.request('POST','/api/v1/moderation/appeals/'+appeal['id']+'/decision',dict(commandId=str(uuid.uuid4()),expectedVersion=1,accept=True,reason='另一合成管理员核对恢复后的原申诉'),actor='appeal')
    row=d.request('GET','/api/v1/posts/'+d.state['postId']+'/comments/'+d.state['restoreReply']['commentId'],actor='reporter')
    image=row['image'];imagePath='/api/v1/posts/'+d.state['postId']+'/comments/'+d.state['restoreReply']['commentId']+'/images/'+image['contentVersionId']+'/original'
    raw=d.request('GET',imagePath,actor='reporter',raw=b'')
    require(hashlib.sha256(raw).hexdigest()==d.state['restoreReply']['selection']['sha256'],'original comment PNG mismatch')
    passed('restored-old-session-denied-fresh-login-original-report-read-state-appeal-and-image-visibility-preserved')
    evidence.update(result='PASS_SCOPED_NEW_COMMENT_MODERATION_RESTORE',migrationSha256=lab.state['migrationSha256'],binarySha256={p.name:sha(p) for p in (lab.root/'bin').iterdir() if p.is_file()},databaseDownRun=False,serviceRemainsAvailableForCandidate=True)
    write(path,evidence)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('--source',type=Path,required=True);a=p.parse_args()
    lab=IntegrationLab(a.root,a.source)
    if lab.state.get('integrationScope')!='android-integration-20261019':raise RuntimeError('wrong lab')
    run(lab)
