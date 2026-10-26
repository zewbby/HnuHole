#!/usr/bin/env python3
"""Regression: an acknowledged nonce remains usable after >10000 new roots."""
import argparse
import hashlib
import json
from pathlib import Path
import secrets
import uuid

from exercise import attach
from run import b64, dump


def seed_post(lab, roots):
    post=str(uuid.uuid4());task=str(uuid.uuid4())
    sql="""BEGIN;SET LOCAL session_replication_role=replica;
    INSERT INTO c_posts.posts(post_id,owner_account_id,channel_id,visibility,published_attempt_version,published_at,publication_ordinal)
      SELECT '%s',owner_account_id,channel_id,'PUBLISHED',1,now(),(SELECT max(publication_ordinal)+1 FROM c_posts.posts) FROM c_posts.posts WHERE post_id='%s';
    INSERT INTO c_posts.post_identity_bindings SELECT account_id,'%s',identity_id,now() FROM c_posts.post_identity_bindings WHERE post_id='%s';
    INSERT INTO c_posts.publication_tasks(task_id,post_id,owner_account_id,identity_id,channel_id,latest_attempt_version)
      SELECT '%s','%s',owner_account_id,identity_id,channel_id,1 FROM c_posts.publication_tasks WHERE post_id='%s';
    COMMIT;"""%(post,lab.post,post,lab.post,task,post,lab.post)
    lab.sql(sql);add_roots(lab,post,roots)
    return post


def add_roots(lab,post,count):
    lab.sql("""BEGIN;SET LOCAL session_replication_role=replica;
    CREATE TEMP TABLE growth_rows ON COMMIT DROP AS SELECT gen_random_uuid() task,gen_random_uuid() comment FROM generate_series(1,%d);
    INSERT INTO c_comments.tasks(task_id,comment_id,owner_account_id,post_id,identity_id)
      SELECT g.task,g.comment,p.owner_account_id,p.post_id,p.identity_id FROM growth_rows g CROSS JOIN c_posts.publication_tasks p WHERE p.post_id='%s';
    INSERT INTO c_comments.attempts(task_id,version,state,accepted_at,accepted_stop_generation,terminal_at,body)
      SELECT task,1,'PUBLISHED',now(),0,now(),'synthetic growth' FROM growth_rows;
    COMMIT;"""%(count,post))


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--root',type=Path,required=True);p.add_argument('--source',type=Path,required=True)
    p.add_argument('--expect-old-failure',action='store_true')
    args=p.parse_args();lab=attach(args.root,args.source);result={'result':'RUNNING'}
    try:
        post=seed_post(lab,2);nonce=b64(secrets.token_bytes(16));path='/api/v1/posts/'+post+'/comments?limit=1'
        first,_,_=lab.request('127.0.0.1',path,token=lab.tokens[2],nonce=nonce)
        add_roots(lab,post,10000)
        if args.expect_old_failure:
            failed,_,_=lab.request('127.0.0.2',path,token=lab.tokens[2],nonce=nonce,want=422)
            assert failed['error']['code']=='COMMENT_SNAPSHOT_TOO_LARGE'
            result['beforeFix']={'result':'REPRODUCED','code':failed['error']['code'],'rootsAfterGrowth':10002}
        else:
            replay,_,_=lab.request('127.0.0.2',path,token=lab.tokens[2],nonce=nonce)
            assert replay['snapshotId']==first['snapshotId'] and replay['nextCursor']==first['nextCursor']
        lab.env.update(PATH='/usr/lib/go-1.22/bin:/usr/lib/postgresql/16/bin:/mnt/e/Hnuhole-env/linux/bin:'+__import__('os').environ.get('PATH','/usr/bin:/bin'),
                       GOPATH=str(lab.root/'go'),GOCACHE=str(lab.root/'go-build'),GOMODCACHE=str(lab.root/'go/pkg/mod'),
                       GOPROXY=__import__('os').environ.get('GOPROXY','https://proxy.golang.org,direct'),GOTOOLCHAIN='local',GOFLAGS='-mod=readonly',GOWORK='off')
        lab.install_binary('api','./cmd/api')
        new=lab.start_api('nonce-final','127.0.0.7',int(lab.cfg['internalListen'].split(':')[-1]))
        replay,_,_=lab.request('127.0.0.7',path,token=lab.tokens[2],nonce=nonce)
        assert replay['snapshotId']==first['snapshotId'] and replay['nextCursor']==first['nextCursor'] and replay['comments']==first['comments']
        failure,_,_=lab.request('127.0.0.7',path,token=lab.tokens[2],nonce=b64(secrets.token_bytes(16)),want=422)
        assert failure['error']['code']=='COMMENT_SNAPSHOT_TOO_LARGE'
        page,_,_=lab.request('127.0.0.7',path+'&cursor='+first['nextCursor'],token=lab.tokens[2]);assert len(page['comments'])==1
        result.update(result='PASS',replayAfterGrowthPreservesMembershipAndCursor=True,liveTotalCount=replay['totalCount'],newNonceStillTooLarge=True,originalCursorStillReads=True,
                      finalAPIProcessPid=new.pid,apiBinarySHA256=hashlib.sha256((lab.root/'bin/process-api').read_bytes()).hexdigest())
        print('REAL CMD/API NONCE GROWTH REUSE / NEW NONCE LIMIT / ORIGINAL CURSOR PASS',flush=True)
    except BaseException as error:result.update(result='FAIL',error=str(error));raise
    finally:
        dump(lab.run/'nonce-growth.json',result)
        for child,stream,_ in reversed(lab.processes):
            if child.poll() is None:child.terminate()
            child.wait(timeout=20);stream.close()


if __name__=='__main__':main()
