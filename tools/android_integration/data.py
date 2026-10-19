"""Private synthetic integration data over real, verified HTTPS. Never compiled into APK."""
import base64
import io
import json
import os
from pathlib import Path
import secrets
import ssl
import subprocess
import time
import urllib.error
import urllib.request
import uuid

from lab import IntegrationLab, write
from policy import require,owned_tool_environment


def key(size=16):return base64.urlsafe_b64encode(secrets.token_bytes(size)).decode().rstrip('=')


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        raise RuntimeError('Integration redirects are forbidden')


class Data:
    def __init__(self, lab):
        if not lab.state or lab.state.get('integrationScope')!='android-integration-20261019':
            raise RuntimeError('explicit integration-owned backend required')
        self.lab=lab
        self.path=lab.root/'integration-data.private.json'
        self.state=json.loads(self.path.read_text()) if self.path.exists() else {}
        self.origin='https://127.0.0.1:'+str(lab.state['ports']['c'])
        context=ssl.create_default_context(cafile=str(lab.root/'material/dev-ca.pem'))
        self.client=urllib.request.build_opener(urllib.request.ProxyHandler({}),urllib.request.HTTPSHandler(context=context),NoRedirect())

    def save(self):write(self.path,self.state)

    def request(self, method, path, body=None, *, actor=None, headers=None, expected=200, raw=None):
        require(path.startswith('/api/v1/') and not path.startswith('//'),'fixed integration API path required')
        h={'Content-Type':'application/json',**(headers or {})}
        if actor:h['Authorization']='Bearer '+self.state['accounts'][actor]['sessionToken']
        data=raw if raw is not None else (None if body is None else json.dumps(body,ensure_ascii=False).encode())
        req=urllib.request.Request(self.origin+path,data=data,headers=h,method=method)
        try:
            with self.client.open(req,timeout=25) as r:
                payload=r.read();status=r.status
                require(r.url==self.origin+path,'No redirect allowed')
        except urllib.error.HTTPError as error:
            payload=error.read();status=error.code
        if status!=expected:
            write(self.lab.root/'last-http-failure.private.json',dict(method=method,path=path,status=status,body=payload.decode(errors='replace')))
            raise RuntimeError('Integration HTTPS status mismatch: '+str(status)+' expected '+str(expected))
        return json.loads(payload) if payload and raw is None else payload

    def login(self, actor):
        account=self.state['accounts'][actor]
        result=self.request('POST','/api/v1/auth/sessions',dict(username=account['username'],password=account['password'],installationId=key()),headers={'Idempotency-Key':key(32)},expected=201)
        account.update(result);self.save()

    def wait_task(self, actor, task, kind):
        deadline=time.monotonic()+30
        while time.monotonic()<deadline:
            result=self.request('GET','/api/v1/me/'+kind+'-tasks/'+task,actor=actor)
            if kind=='post':result=result['task']
            if result['state']=='PUBLISHED':return result
            if result['state']=='FAILED':raise RuntimeError('Synthetic integration task failed')
            time.sleep(.3)
        raise RuntimeError('Synthetic integration publication timed out')

    def seed(self):
        owned_tool_environment(self.lab.root.parent/'tools',os.environ)
        if not self.state:
            self.state['accounts']={name:dict(username='integration_'+name,password=secrets.token_urlsafe(18),number=str(991001+i))
                                    for i,name in enumerate(['author','reporter','reviewer','appeal'])}
            self.save()
            template=Path(__file__).with_name('seed_accounts.go')
            temporary=self.lab.api/'integration_seed_owned.go'
            require(not temporary.exists(),'temporary seed source already exists; do not overwrite')
            try:
                temporary.write_bytes(template.read_bytes())
                self.lab.run(['go','build','-mod=readonly','-o',self.lab.root/'bin/seed-accounts',temporary], 'build-synthetic-seed')
            finally:temporary.unlink(missing_ok=True)
            socket=self.lab.root/'source-c/socket'
            env=dict(self.lab.env,HNUHOLE_INTEGRATION_SEED='android-integration-20261019',HNUHOLE_INTEGRATION_DSN='postgres://prerelease_admin@/hnuhole_c?host='+str(socket)+'&port='+str(self.lab.state['pgPorts']['source']['c']))
            self.lab.run([self.lab.root/'bin/seed-accounts'],'seed-four-synthetic-accounts',env=env,input=json.dumps(list(self.state['accounts'].values())).encode())
            self.state['accountsSeeded']=True;self.save()
        if not self.state.get('accountsSeeded'):raise RuntimeError('Inspect partial account bootstrap; no blind reseed')
        for actor in self.state['accounts']:
            if 'sessionToken' not in self.state['accounts'][actor]:self.login(actor)
        for actor,nickname in [('author','集成作者'),('reporter','集成举报')]:
            account=self.state['accounts'][actor]
            if 'identityId' not in account:
                outcome=self.request('POST','/api/v1/identities',dict(nickname=nickname),actor=actor,headers={'Idempotency-Key':key()})
                account['identityId']=outcome['identityId'];self.save()
        if 'postId' not in self.state:
            channels=self.request('GET','/api/v1/channels',actor='reporter')
            # Current directory contract is a top-level channels array.
            items=channels['channels']
            accepted=self.request('PUT','/api/v1/post-commands/'+key(),dict(channelId=items[0]['id'],identityId=self.state['accounts']['reporter']['identityId'],title='集成候选验收',body='仅用于本轮新增评论治理连接与恢复。'),actor='reporter',expected=202)
            self.state.update(postId=accepted['postId'],postTaskId=accepted['taskId']);self.save()
        self.wait_task('reporter',self.state['postTaskId'],'post')
        for name,image in [('root',False),('restoreReply',True),('deviceReply',False)]:
            if name in self.state:continue
            task=str(uuid.uuid4())
            selection=None;png=None
            if image:
                from PIL import Image
                buffer=io.BytesIO();Image.new('RGB',(64,64),(30,110,190)).save(buffer,format='PNG');png=buffer.getvalue()
                import hashlib
                selection=dict(mediaId=str(uuid.uuid4()),sha256=hashlib.sha256(png).hexdigest(),mimeType='image/png',byteLength=len(png),width=64,height=64)
            target=None if name=='root' else self.state['root']['commentId']
            body=dict(operation='CREATE',taskId=task,postId=self.state['postId'],identityId=self.state['accounts']['author']['identityId'],rootCommentId=target,targetCommentId=target,body='集成 '+name+' 合成评论',image=selection)
            receipt=self.request('PUT','/api/v1/comment-commands/'+key(),body,actor='author',expected=202)
            if image:self.request('PUT','/api/v1/me/comment-tasks/'+task+'/attempts/1/image',actor='author',raw=png,headers={'Content-Type':'image/png'})
            published=self.wait_task('author',receipt['taskId'],'comment')
            self.state[name]=dict(taskId=task,commentId=published['publishedCommentId'],selection=selection);self.save()
        if not self.state.get('adminBootstrapped'):
            script=(self.lab.source/'infra/postgres/bootstrap-moderation-admin.sql').read_text().replace(":'platform_number'","'"+self.state['accounts']['reviewer']['number']+"'")
            script='\n'.join(line for line in script.splitlines() if not line.startswith('\\'))
            self.lab.sql('c',script,role='migrator')
            self.state['adminBootstrapped']=True;self.save()
        if not self.state.get('appealRoleAssigned'):
            self.request('PUT','/api/v1/moderation/roles/'+self.state['accounts']['appeal']['number'],dict(commandId=str(uuid.uuid4()),reason='本任务隔离合成复核账号',role='ADMIN'),actor='reviewer')
            self.state['appealRoleAssigned']=True;self.save()
        print('Synthetic data ready: four accounts, one post, root/two replies (one PNG), two authorized operators; no credentials exported to APK',flush=True)


if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('--source',type=Path,required=True);a=p.parse_args()
    lab=IntegrationLab(a.root,a.source)
    if lab.state.get('integrationScope')!='android-integration-20261019':raise RuntimeError('wrong lab')
    Data(lab).seed()
