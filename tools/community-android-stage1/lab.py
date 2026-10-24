#!/usr/bin/env python3
"""Owned stage1 real-cmd lab and transparent fault proxy. No device operations."""
import argparse, base64, datetime, hashlib, hmac, http.client, http.server
import json, os, secrets, signal, socket, ssl, subprocess, sys, threading, time
from pathlib import Path
OWNER='HNUHOLE_COMMUNITY_ANDROID_STAGE1_V1'
MAX_BODY=300000

def private_json(path,value):
    path.write_text(json.dumps(value,indent=2)+'\n');path.chmod(0o600)

def owned(work):
    work=Path(work)
    if not work.is_absolute() or work.is_symlink() or work.resolve()!=work:
        raise ValueError('canonical private lab required')
    if (work/'OWNER').read_text().strip()!=OWNER or work.stat().st_uid!=os.getuid():
        raise ValueError('lab ownership rejected')
    if work.stat().st_mode & 0o077:raise ValueError('private lab permissions required')
    return work

def execute(args,log,env=None):
    with log.open('ab') as out:
        subprocess.run(args,stdout=out,stderr=out,env=env,check=True)

def db_env(cfg,work):
    env={k:v for k,v in os.environ.items() if not k.startswith(('PG','AUTHLAB_','AUTHRUNTIME_'))}
    for party in ('c','v'):
        for role in ('admin','migrator','runtime','recovery'):
            p=work/'material'/('db-'+party+'-runtime.password' if role=='runtime' else 'operator/db-'+party+'-'+role+'.password')
            env[party.upper()+'_'+role.upper()+'_PASSWORD']=p.read_text().strip()
    for key,name in [('C_DATABASE_PORT','cdb'),('V_DATABASE_PORT','vdb'),('MAILPIT_SMTP_PORT','smtp'),('MAILPIT_HTTP_PORT','mail')]:
        env[key]=str(cfg['ports'][name])
    return env

def sql(work,query):
    cfg=json.loads((work/'lab.json').read_text())
    env={k:v for k,v in os.environ.items() if not k.startswith(('PG','AUTHLAB_','AUTHRUNTIME_'))};env['PGPASSWORD']=(work/'material/operator/db-c-admin.password').read_text().strip()
    dsn=f"postgres://hnuhole_c_admin@127.0.0.1:{cfg['ports']['cdb']}/hnuhole_c?sslmode=disable"
    result=subprocess.run(['psql','-X','-v','ON_ERROR_STOP=1','-At',dsn,'-c',query],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=False)
    if result.returncode:raise RuntimeError('owned SQL check failed; no SQL inputs logged')
    return result.stdout.decode().strip()

STATS_SQL="""SELECT json_build_object(
 'accounts', (SELECT count(*) FROM c_auth.accounts),
 'closed', (SELECT count(*) FROM c_auth.accounts WHERE state='CLOSED'),
 'pendingClose', (SELECT count(*) FROM c_auth.accounts WHERE state='PENDING_CLOSE'),
 'posts', (SELECT count(*) FROM c_posts.posts),
 'published', (SELECT count(*) FROM c_posts.posts WHERE visibility='PUBLISHED'),
 'deleted', (SELECT count(*) FROM c_posts.posts WHERE visibility='DELETED'),
 'attempts', (SELECT count(*) FROM c_posts.publication_attempts),
 'failed', (SELECT count(*) FROM c_posts.publication_attempts WHERE state='FAILED'),
 'bindings', (SELECT count(*) FROM c_posts.post_identity_bindings),
 'closedPayloadsRemaining', (SELECT count(*) FROM c_posts.attempt_contents x JOIN c_posts.publication_tasks t USING(task_id) JOIN c_auth.accounts a ON a.account_id=t.owner_account_id WHERE a.state='CLOSED' AND x.erased_at IS NULL AND NOT EXISTS (SELECT 1 FROM c_posts.posts p WHERE p.post_id=t.post_id AND p.visibility='PUBLISHED' AND p.published_attempt_version=x.version)),
 'closedPrivateReceiptsRemaining', (SELECT count(*) FROM c_posts.command_receipts r JOIN c_auth.accounts a ON a.account_id=r.owner_account_id WHERE a.state='CLOSED'),
 'closedCredentialsRemaining', (SELECT count(*) FROM c_auth.accounts WHERE state='CLOSED' AND (username IS NOT NULL OR password_hash IS NOT NULL)))"""

class FaultState:
    def __init__(self):
        self.lock=threading.Lock();self.armed=set();self.hold_queries=False
        self.salt=secrets.token_bytes(32);self.keys={k:set() for k in ('creates','retries','deletes')}
        self.counts={k:0 for k in ('creates','retries','deletes','commandQueries','droppedQueries','droppedReplies')}
    def observe(self,method,path,key):
        kind=None
        if method=='PUT' and path.startswith('/api/v1/post-commands/'):kind='creates'
        elif method=='POST' and path.endswith('/retry'):kind='retries'
        elif method=='POST' and path.endswith('/delete'):kind='deletes'
        with self.lock:
            if kind:
                self.counts[kind]+=1
                self.keys[kind].add(hmac.new(self.salt,key.encode(),hashlib.sha256).digest())
            query=method=='GET' and path.startswith('/api/v1/post-commands/')
            if query:self.counts['commandQueries']+=1
            drop=query and self.hold_queries
            if drop:self.counts['droppedQueries']+=1
        return kind,drop
    def after_upstream(self,kind,status):
        with self.lock:
            drop=kind in self.armed and 200<=status<300
            if drop:self.armed.remove(kind);self.counts['droppedReplies']+=1
            return drop
    def snapshot(self):
        with self.lock:return dict(self.counts,**{'unique'+k.title():len(v) for k,v in self.keys.items()},rawTokensOrProofsStored=False)

def proxy(work):
    work=owned(work);cfg=json.loads((work/'lab.json').read_text());c=json.loads((work/'material/c.json').read_text())
    tls=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    tls.load_cert_chain(work/'material'/c['publicCertificateFile'],work/'material'/c['publicKeyFile'])
    upstream_tls=ssl.create_default_context(cafile=str(work/'material/dev-ca.pem'))
    state=FaultState()
    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version='HTTP/1.1'
        def log_message(self,*args):pass
        def do_GET(self):self.forward()
        def do_POST(self):self.forward()
        def do_PUT(self):self.forward()
        def do_DELETE(self):self.forward()
        def result(self,status,value):
            data=json.dumps(value,separators=(',',':')).encode()
            self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.send_header('Cache-Control','no-store');self.send_header('Connection','close');self.end_headers();self.wfile.write(data);self.close_connection=True
        def drop(self):
            self.close_connection=True
            try:self.connection.shutdown(socket.SHUT_RDWR)
            except OSError:pass
            self.connection.close()
        def forward(self):
            try:
                length=int(self.headers.get('Content-Length','0'))
                if not 0<=length<=MAX_BODY or self.headers.get('Transfer-Encoding'):
                    self.result(413,{'error':'bounded_request_required'});return
                body=self.rfile.read(length)
                if self.path=='/__stage1/control':
                    expected='LabControl '+cfg['controlToken']
                    if self.command!='POST' or not hmac.compare_digest(self.headers.get('Authorization',''),expected):
                        self.result(403,{'error':'control_denied'});return
                    raw=json.loads(body);action=raw.get('action')
                    if set(raw)!={'action'}:raise ValueError('invalid control body')
                    if action in ('drop-create','drop-retry','drop-delete'):
                        with state.lock:state.armed.add({'drop-create':'creates','drop-retry':'retries','drop-delete':'deletes'}[action]);state.hold_queries=True
                    elif action=='release-queries':
                        with state.lock:state.hold_queries=False
                    elif action in ('pause-posts','resume-posts'):
                        (work/'publication-paused').write_text('1' if action=='pause-posts' else '0')
                    elif action=='advance-closure':
                        current=int((work/'clock-offset-ns').read_text())
                        if current!=0 or int(sql(work,"SELECT count(*) FROM c_auth.accounts WHERE state='PENDING_CLOSE'"))!=1:raise ValueError('one original pending closure required')
                        (work/'clock-offset-ns').write_text(str((7*86400+1)*10**9))
                        for party in ('c','v'):
                            operator=work/'material/operator'/('operator.json' if party=='c' else 'v-operator.json')
                            execute([str(work/'bin/authdev'),'recover','-operator',str(operator)],work/'clock-recover.private.log')
                    elif action not in ('stats','ping'):raise ValueError('unknown control')
                    self.result(200,{'counters':state.snapshot(),'sql':json.loads(sql(work,STATS_SQL))});return
                key=self.headers.get('Idempotency-Key',self.path.rsplit('/',1)[-1])
                kind,drop=state.observe(self.command,self.path,key)
                if drop:self.drop();return
                client=http.client.HTTPSConnection('127.0.0.1',cfg['ports']['c'],context=upstream_tls,timeout=25)
                headers={k:v for k,v in self.headers.items() if k.lower() not in ('host','connection','transfer-encoding','content-length')}
                headers['Connection']='close';headers['Content-Length']=str(len(body))
                try:
                    client.request(self.command,self.path,body=body,headers=headers)
                    response=client.getresponse();data=response.read(MAX_BODY+1)
                    if len(data)>MAX_BODY:raise ValueError('upstream bound exceeded')
                    if state.after_upstream(kind,response.status):self.drop();return
                    self.send_response(response.status)
                    for k,v in response.getheaders():
                        if k.lower() not in ('connection','transfer-encoding','content-length'):self.send_header(k,v)
                    self.send_header('Content-Length',str(len(data)));self.send_header('Connection','close');self.end_headers();self.wfile.write(data);self.close_connection=True
                finally:client.close()
            except (ValueError,KeyError,RuntimeError,json.JSONDecodeError):self.result(400,{'error':'owned_control_or_bound_rejected'})
            except (OSError,http.client.HTTPException):self.result(502,{'error':'owned_upstream_unavailable'})
    server=http.server.ThreadingHTTPServer(('127.0.0.1',cfg['ports']['proxy']),Handler)
    server.daemon_threads=True;server.socket=tls.wrap_socket(server.socket,server_side=True)
    server.serve_forever()

def paused_post_worker_overlay(text):
    # Accept only the two known source spellings; mixed/duplicate or changed
    # worker expressions must stop the test overlay rather than patch broadly.
    anchors=('{"posts",countTask(c.PublishAcceptedPosts)}',
             '{"posts", countTask(c.PublishAcceptedPosts)}')
    if sum(text.count(anchor) for anchor in anchors)!=1:
        raise ValueError('expected exactly one recognized post-worker overlay anchor')
    old=next(anchor for anchor in anchors if anchor in text)
    new='{"posts",countTask(func(ctx context.Context,n int)(int64,error){if stage1Paused(){return 0,nil};return c.PublishAcceptedPosts(ctx,n)})}'
    return text.replace(old,new,1)

def overlay(work,source):
    dest=work/'overlay';dest.mkdir()
    helper='''
// TEST BUILD ONLY: owner-bound clock; immutable SQL deadlines are unchanged.
func stage1Clock() time.Time {
 marker,err:=os.ReadFile("ROOT/OWNER");if err!=nil || strings.TrimSpace(string(marker))!="HNUHOLE_COMMUNITY_ANDROID_STAGE1_V1" {panic("invalid stage1 owner")}
 raw,err:=os.ReadFile("ROOT/clock-offset-ns");if err!=nil {panic("missing stage1 clock")}
 offset,err:=strconv.ParseInt(strings.TrimSpace(string(raw)),10,64);if err!=nil || offset<0 || offset>int64(8*24*time.Hour) {panic("invalid stage1 offset")}
 return time.Now().Add(time.Duration(offset))
}
'''.replace('ROOT',str(work))
    replacements={};fingerprints={}
    for name in ('internal/authprivacyruntime/server.go','cmd/authdev/main.go','internal/authprivacy/workers.go'):
        original=source/name;text=original.read_text();fingerprints[name]=hashlib.sha256(original.read_bytes()).hexdigest()
        if name.endswith('server.go'):
            assert text.count('Clock: time.Now')==1
            text=text.replace('Clock: time.Now','Clock: stage1Clock').replace('"net/http"','"net/http"\n "os"\n "strconv"')+helper
        elif name.endswith('main.go'):
            old='at := time.Now().UTC().Truncate(time.Microsecond)';assert text.count(old)==1
            text=text.replace(old,'at := stage1Clock().UTC().Truncate(time.Microsecond)').replace('"strings"','"strings"\n "strconv"')+helper
        else:
            text=paused_post_worker_overlay(text).replace('"context"','"context"\n "os"\n "strings"')+'''
// TEST BUILD ONLY: scheduler pause; resumed work calls the unchanged worker.
func stage1Paused() bool {
 marker,err:=os.ReadFile("ROOT/OWNER");if err!=nil || strings.TrimSpace(string(marker))!="HNUHOLE_COMMUNITY_ANDROID_STAGE1_V1" {panic("invalid stage1 scheduler owner")}
 raw,err:=os.ReadFile("ROOT/publication-paused");if err!=nil {panic("missing stage1 scheduler state")}
 if string(raw)!="0" && string(raw)!="1" {panic("invalid scheduler state")};return string(raw)=="1"
}
'''.replace('ROOT',str(work))
        target=dest/(name.replace('/','-'));target.write_text(text);replacements[str(original)]=str(target)
    private_json(dest/'overlay.json',{'Replace':replacements})
    private_json(dest/'scope.json',{'testBuildOnly':True,'originalSourcesSha256':fingerprints,'authenticationChecksUnchanged':True,'sqlDeadlinesUnchanged':True,'systemClocksUnchanged':True,'publicationBodyUnchanged':True,'clockMaximumDays':8,'schedulerOnlyPostJobPaused':True})

def process_identity(pid):
    p=Path('/proc')/str(pid)
    raw=(p/'stat').read_text();return {'pid':pid,'startTicks':raw[raw.rfind(')')+2:].split()[19]}

def spawn(work,args,label):
    stream=(work/(label+'.private.log')).open('ab')
    p=subprocess.Popen(args,stdout=stream,stderr=stream,start_new_session=True);stream.close()
    identity=process_identity(p.pid);identity.update(label=label,args=args);return identity

def prepare(work,source):
    work=Path(work);source=Path(source).resolve()
    if work.exists() or work.is_symlink():raise ValueError('new lab directory required')
    if not work.is_absolute() or work.resolve()!=work or work.parent.is_symlink():raise ValueError('canonical lab parent required')
    marker=(work.parent/'.owner').read_text().strip()
    if marker!='hnuhole-community-flutter-f4-01a11f1a-20261010|/mnt/e/HnuHole-community-f4-20261012/repo':raise ValueError('task parent rejected')
    if source!=work.parent/'source/services/api':raise ValueError('owned source mirror required')
    work.mkdir(mode=0o700);(work/'OWNER').write_text(OWNER)
    (work/'clock-offset-ns').write_text('0');(work/'publication-paused').write_text('0')
    logfile=work/'prepare.private.log';project='hnuhole-community-s1-'+secrets.token_hex(5)
    for image in ('postgres:16.6-alpine','axllent/mailpit:v1.21.8'):execute(['docker','image','inspect',image],logfile)
    for command in (['docker','ps','-aq'],['docker','volume','ls','-q'],['docker','network','ls','-q']):
        result=subprocess.check_output(command+['--filter','label=com.docker.compose.project='+project]);assert not result.strip()
    ports={};sockets=[]
    try:
        for name in ('cdb','vdb','smtp','mail','c','v','ci','vi','proxy'):
            s=socket.socket();s.bind(('127.0.0.1',0));ports[name]=s.getsockname()[1];sockets.append(s)
    finally:
        for s in sockets:s.close()
    cfg={'project':project,'ports':ports,'source':str(source),'compose':str(source.parents[1]/'infra/docker-compose.yml'),'controlToken':secrets.token_urlsafe(32),'runId':'community-stage1-'+secrets.token_hex(5)}
    private_json(work/'lab.json',cfg);overlay(work,source);(work/'bin').mkdir()
    for name,package in [('authdev','./cmd/authdev'),('community','./cmd/api'),('verifier','./cmd/verifier')]:
        execute(['go','build','-overlay',str(work/'overlay/overlay.json'),'-o',str(work/'bin'/name),package],logfile)
    args=[str(work/'bin/authdev'),'init','-dir',str(work/'material')]
    for flag,name in [('community-port','c'),('verifier-port','v'),('community-internal-port','ci'),('verifier-internal-port','vi'),('smtp-port','smtp')]:args+=['-'+flag,str(ports[name])]
    for flag,party,role in [('community-dsn','c','runtime'),('verifier-dsn','v','runtime'),('recovery-dsn','c','recovery'),('verifier-recovery-dsn','v','recovery')]:
        args+=['-'+flag,f"postgres://hnuhole_{party}_{role}@127.0.0.1:{ports[party+'db']}/hnuhole_{party}?sslmode=disable"]
    execute(args,logfile);env=db_env(cfg,work)
    compose=['docker','compose','-p',project,'-f',cfg['compose']]
    execute(compose+['up','-d','--pull','never','--wait'],logfile,env)
    for party,migrations,grant in [('c','migrations','grant-community.sql'),('v','verifier-migrations','grant-verifier.sql')]:
        dsn=f"postgres://hnuhole_{party}_migrator@127.0.0.1:{ports[party+'db']}/hnuhole_{party}?sslmode=disable&options=-c%20role%3Dhnuhole_{party}_owner"
        local=env.copy();local['PGPASSWORD']=env[party.upper()+'_MIGRATOR_PASSWORD']
        execute(['goose','-dir',migrations,'postgres',dsn,'up'],logfile,local)
        execute(['psql','-X','-v','ON_ERROR_STOP=1',dsn,'-f',str(source.parents[1]/'infra/postgres'/grant)],logfile,local)
    start(work)
    ca=(work/'material/dev-ca.pem').read_bytes()
    defines={'AUTH_COMMUNITY_BASE_URL':f"https://127.0.0.1:{ports['proxy']}",'AUTH_VERIFIER_BASE_URL':f"https://127.0.0.1:{ports['v']}",'AUTH_DEV_CA_BASE64':base64.b64encode(ca).decode(),'AUTH_DEVICE_MAILPIT_URL':f"http://127.0.0.1:{ports['mail']}",'COMMUNITY_STAGE1_CONTROL_TOKEN':cfg['controlToken'],'COMMUNITY_STAGE1_RUN_ID':cfg['runId']}
    private_json(work/'build-defines.private.json',defines)
    private_json(work/'host-config.private.json',dict(defines,hostRunDir=str(work/'host-state')))
    print(json.dumps({'result':'READY_HOST_ONLY','ports':ports,'applicationId':'org.hnuhole.hnuhole_mobile.communityf5','deviceUsed':False,'privateMaterialsRetainedForApprovedPreparation':True}))

def start(work):
    work=owned(work);cfg=json.loads((work/'lab.json').read_text())
    if (work/'processes.private.json').exists():
        for v in json.loads((work/'processes.private.json').read_text()):
            if Path('/proc',str(v['pid'])).exists():raise ValueError('existing lab processes: inspect before restart')
    items=[]
    for label,party in [('community','c'),('verifier','v')]:items.append(spawn(work,[str(work/'bin'/label),'-config',str(work/'material'/(party+'.json'))],label))
    private_json(work/'processes.private.json',items)
    context=ssl.create_default_context(cafile=str(work/'material/dev-ca.pem'))
    for name in ('c','v'):
        for attempt in range(60):
            try:
                c=http.client.HTTPSConnection('127.0.0.1',cfg['ports'][name],context=context,timeout=2);c.request('GET','/health/live');r=c.getresponse();r.read();c.close()
                if r.status==200:break
            except OSError:pass
            time.sleep(1)
        else:raise RuntimeError('owned cmd startup failed')
    for party in ('c','v'):
        operator=work/'material/operator'/('operator.json' if party=='c' else 'v-operator.json')
        execute([str(work/'bin/authdev'),'recover','-operator',str(operator)],work/'recover.private.log')
        items.append(spawn(work,[str(work/'bin/authdev'),'watch','-operator',str(operator)],party+'-watch'))
    items.append(spawn(work,[sys.executable,str(Path(__file__).resolve()),'proxy','--work',str(work)],'proxy'))
    private_json(work/'processes.private.json',items)

def stop(work):
    work=owned(work);path=work/'processes.private.json'
    if not path.exists():return
    items=json.loads(path.read_text())
    for v in items:
        try:
            now=process_identity(v['pid'])
            if now['startTicks']!=v['startTicks']:raise ValueError('PID reused: do not stop')
            cmd=(Path('/proc')/str(v['pid'])/'cmdline').read_bytes().replace(b'\0',b' ')
            if str(work).encode() not in cmd:raise ValueError('process ownership changed')
            os.kill(v['pid'],signal.SIGTERM)
        except FileNotFoundError:pass
    for _ in range(50):
        if all(not Path('/proc',str(v['pid'])).exists() for v in items):break
        time.sleep(.1)
    path.rename(work/'last-processes.private.json')
    print('Owned services stopped; same owned DB/material retained, no other service touched')

def cleanup_host(work):
    work=owned(work)
    if not work.name.startswith('stage1-host-lab'):raise ValueError('only disposable host rehearsal labs may be cleaned here')
    cfg=json.loads((work/'lab.json').read_text())
    if not cfg['project'].startswith('hnuhole-community-s1-'):raise ValueError('project ownership rejected')
    stop(work)
    env=db_env(cfg,work)
    execute(['docker','compose','-p',cfg['project'],'-f',cfg['compose'],'down','-v'],work/'cleanup.private.log',env)
    print('Owned disposable host project cleaned; phone lab, SDK, caches and other projects retained')

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('action',choices=['prepare','start','stop','proxy','cleanup-host']);p.add_argument('--work',required=True);p.add_argument('--source')
    args=p.parse_args()
    if args.action=='prepare':
        if not args.source:p.error('--source required for prepare')
        os.chdir(args.source);prepare(args.work,args.source)
    elif args.action=='proxy':proxy(args.work)
    elif args.action=='start':start(args.work)
    elif args.action=='cleanup-host':cleanup_host(args.work)
    else:stop(args.work)
