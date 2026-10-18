"""This task's fresh RP lab. Real cmd/migrations; no clock or auth overlay."""
import argparse,base64,datetime,hashlib,hmac,http.client,http.server,importlib.util,json,os,secrets,signal,socket,ssl,subprocess,sys,threading,time
from pathlib import Path
ROOT=Path('/home/hnuhole/community-android-stage3-execution-20261015')
OWNER='HNUHOLE_COMMUNITY_ANDROID_STAGE3_EXECUTION_20261015_V1'
OUT=Path('/mnt/e/HnuHole-community-f4-20261012/stage3-execution-20261015')
REPO=Path('/mnt/e/HnuHole-community-f4-20261012/repo')
spec=importlib.util.spec_from_file_location('stage1_lab_helpers',REPO/'tools/community-android-stage1/lab.py');helpers=importlib.util.module_from_spec(spec);spec.loader.exec_module(helpers)
def root():
    assert ROOT.resolve()==ROOT and not ROOT.is_symlink() and ROOT.stat().st_uid==os.getuid()
    assert (ROOT/'.owner').read_text().strip()==OWNER and not ROOT.stat().st_mode&0o077
    return ROOT
def owned():
    work=root()/'lab'
    assert work.resolve()==work and not work.is_symlink() and work.stat().st_uid==os.getuid()
    assert (work/'OWNER').read_text().strip()==OWNER and not work.stat().st_mode&0o077
    cfg=json.loads((work/'lab.json').read_text())
    assert cfg['project'].startswith('hnuhole-community-s3-') and cfg['source']==str(ROOT/'source/services/api')
    return work,cfg
def private(path,value):helpers.private_json(path,value)
def run(args,work,env=None):helpers.execute(args,work/'commands.private.log',env)
def query(sql):
    work,cfg=owned();env=os.environ.copy();env['PGPASSWORD']=(work/'material/operator/db-c-admin.password').read_text().strip()
    dsn=f"postgres://hnuhole_c_admin@127.0.0.1:{cfg['ports']['cdb']}/hnuhole_c?sslmode=disable"
    p=subprocess.run(['psql','-X','-At','-v','ON_ERROR_STOP=1',dsn,'-c',sql],env=env,capture_output=True)
    assert p.returncode==0,'owned lab SQL observation failed; no SQL inputs printed'
    return p.stdout.decode().strip()
def stats():
    return json.loads(query("SELECT json_build_object('accounts',(SELECT count(*) FROM c_auth.accounts),'passkeys',(SELECT count(*) FROM c_auth.passkeys),'challenges',(SELECT count(*) FROM c_auth.auth_challenges),'credentialChanges',(SELECT count(*) FROM c_auth.credential_change_intents),'posts',(SELECT count(*) FROM c_posts.posts))"))
def prepare():
    base=root();work=base/'lab';assert not work.exists() and not work.is_symlink()
    work.mkdir(mode=0o700);(work/'OWNER').write_text(OWNER);(work/'bin').mkdir(mode=0o700)
    source=base/'source/services/api';assert source.is_dir();os.chdir(source)
    for image in ('postgres:16.6-alpine','axllent/mailpit:v1.21.8'):run(['docker','image','inspect',image],work)
    project='hnuhole-community-s3-'+secrets.token_hex(5)
    for args in (['docker','ps','-aq'],['docker','volume','ls','-q'],['docker','network','ls','-q']):
        assert not subprocess.check_output(args+['--filter','label=com.docker.compose.project='+project]).strip()
    held=[];ports={}
    try:
        for name in ('cdb','vdb','smtp','mail','c','v','ci','vi','proxy'):
            s=socket.socket();s.bind(('127.0.0.1',0));held.append(s);ports[name]=s.getsockname()[1]
    finally:
        for s in held:s.close()
    cfg={'project':project,'ports':ports,'source':str(source),'compose':str(base/'source/infra/docker-compose.yml'),'controlToken':secrets.token_urlsafe(32),'runId':'community-stage3-'+secrets.token_hex(5)}
    private(work/'lab.json',cfg)
    for name,pkg in (('authdev','./cmd/authdev'),('community','./cmd/api'),('verifier','./cmd/verifier')):
        run(['go','build','-o',str(work/'bin'/name),pkg],work)
    args=[str(work/'bin/authdev'),'init','-dir',str(work/'material')]
    for flag,name in (('community-port','c'),('verifier-port','v'),('community-internal-port','ci'),('verifier-internal-port','vi'),('smtp-port','smtp')):args+=['-'+flag,str(ports[name])]
    for flag,party,role in (('community-dsn','c','runtime'),('verifier-dsn','v','runtime'),('recovery-dsn','c','recovery'),('verifier-recovery-dsn','v','recovery')):
        args+=['-'+flag,f"postgres://hnuhole_{party}_{role}@127.0.0.1:{ports[party+'db']}/hnuhole_{party}?sslmode=disable"]
    proposal=json.loads((REPO/'docs/design/community-android-stage3-review-20261015/proposal.json').read_text())
    extra=json.loads((REPO/'docs/design/community-android-stage3-review-20261015/runtime/authdev-init-extra-argv.json').read_text())
    assert proposal['rpId']=='hnuhole-community-passkey.pages.dev' and len(extra)==6
    run(args+extra,work)
    configured=json.loads((work/'material/c.json').read_text())['webAuthn']
    expected=json.loads((REPO/'docs/design/community-android-stage3-review-20261015/runtime/web-authn.config.fragment.json').read_text())['webAuthn']
    assert configured==expected,'fresh C RP configuration differs from approved proposal'
    env=helpers.db_env(cfg,work)
    run(['docker','compose','-p',project,'-f',cfg['compose'],'up','-d','--pull','never','--wait'],work,env)
    for party,migrations,grant in (('c','migrations','grant-community.sql'),('v','verifier-migrations','grant-verifier.sql')):
        dsn=f"postgres://hnuhole_{party}_migrator@127.0.0.1:{ports[party+'db']}/hnuhole_{party}?sslmode=disable&options=-c%20role%3Dhnuhole_{party}_owner"
        local=env.copy();local['PGPASSWORD']=env[party.upper()+'_MIGRATOR_PASSWORD']
        run(['goose','-dir',migrations,'postgres',dsn,'up'],work,local)
        run(['psql','-X','-v','ON_ERROR_STOP=1',dsn,'-f',str(base/'source/infra/postgres'/grant)],work,local)
    processes=[]
    def spawn(args,label):
        processes.append(helpers.spawn(work,args,label));private(work/'processes.private.json',processes)
    for label,party in (('community','c'),('verifier','v')):spawn([str(work/'bin'/label),'-config',str(work/'material'/(party+'.json'))],label)
    tls=ssl.create_default_context(cafile=str(work/'material/dev-ca.pem'))
    for name in ('c','v'):
        for attempt in range(60):
            try:
                c=http.client.HTTPSConnection('127.0.0.1',ports[name],context=tls,timeout=2);c.request('GET','/health/live');r=c.getresponse();r.read();c.close()
                if r.status==200:break
            except OSError:pass
            time.sleep(1)
        else:raise RuntimeError('owned process startup failed')
    for party in ('c','v'):
        operator=work/'material/operator'/('operator.json' if party=='c' else 'v-operator.json')
        run([str(work/'bin/authdev'),'recover','-operator',str(operator)],work)
        spawn([str(work/'bin/authdev'),'watch','-operator',str(operator)],party+'-watch')
    spawn([sys.executable,str(Path(__file__).resolve()),'proxy'],'proxy')
    ca=(work/'material/dev-ca.pem').read_bytes()
    defines={'AUTH_COMMUNITY_BASE_URL':f"https://127.0.0.1:{ports['proxy']}",'AUTH_VERIFIER_BASE_URL':f"https://127.0.0.1:{ports['v']}",'AUTH_DEV_CA_BASE64':base64.b64encode(ca).decode(),'AUTH_DEV_PASSKEY_RP_ID':proposal['rpId'],'AUTH_DEVICE_MAILPIT_URL':f"http://127.0.0.1:{ports['mail']}"}
    private(work/'normal-defines.private.json',defines)
    snapshot=stats();assert not any(snapshot.values())
    result={'result':'FRESH_HOST_LAB_READY_DEVICE_NOT_RUN','ports':ports,'project':project,'sourceCommit':'9dda242b21694af1c4c33f11784958851c805fc4','webAuthn':configured,'sql':snapshot,'clockOverlay':False,'authProtocolOverlay':False,'formalMigrationsAndGrants':True,'existingDatabasesUsed':False}
    (OUT/'lab-prepared.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
def proxy():
    work,cfg=owned();cconfig=json.loads((work/'material/c.json').read_text())
    tls=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);tls.load_cert_chain(work/'material'/cconfig['publicCertificateFile'],work/'material'/cconfig['publicKeyFile'])
    upstream=ssl.create_default_context(cafile=str(work/'material/dev-ca.pem'))
    lock=threading.Lock();state={'armed':False,'holdResults':False,'bindingOptions':0,'bindingSubmits':0,'bindingCommittedRepliesDropped':0,'resultQueries':0,'resultQueriesHeld':0,'resultQueriesOriginalAnchorMatched':0,'resultQueriesOriginalAnchorMismatched':0,'nativeResetOptions':0,'resetSubmits':0}
    keys=set();anchors=set()
    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version='HTTP/1.1'
        def log_message(self,*args):pass
        def do_GET(self):self.forward()
        def do_POST(self):self.forward()
        def do_DELETE(self):self.forward()
        def do_PUT(self):self.forward()
        def drop(self):
            self.close_connection=True
            try:self.connection.shutdown(socket.SHUT_RDWR)
            except OSError:pass
            self.connection.close()
        def result(self,status,value):
            self.send(status,json.dumps(value).encode(),[('Content-Type','application/json'),('Cache-Control','no-store')])
        def send(self,status,data,headers):
            self.send_response(status)
            for k,v in headers:
                if k.lower() not in ('connection','content-length','transfer-encoding'):self.send_header(k,v)
            self.send_header('Content-Length',str(len(data)));self.send_header('Connection','close');self.end_headers();self.wfile.write(data);self.close_connection=True
        def forward(self):
            try:
                size=int(self.headers.get('Content-Length','0'));assert 0<=size<=300000 and not self.headers.get('Transfer-Encoding')
                body=self.rfile.read(size)
                if self.path=='/__stage3/control':
                    assert self.command=='POST' and hmac.compare_digest(self.headers.get('Authorization',''),'LabControl '+cfg['controlToken'])
                    raw=json.loads(body);assert set(raw)=={'action'};action=raw['action']
                    with lock:
                        if action=='arm-binding-response-loss':assert not state['armed'] and not state['bindingCommittedRepliesDropped'];state['armed']=True
                        elif action=='release-result-queries':state['holdResults']=False
                        else:assert action=='stats'
                        result=dict(state,uniqueBindingCommandKeys=len(keys),rawTokensOrProofsStored=False)
                    self.result(200,{'counters':result,'sql':stats()});return
                binding=self.command=='POST' and self.path=='/api/v1/auth/passkeys'
                resultquery=self.command=='GET' and self.path=='/api/v1/auth/credential-change-result'
                with lock:
                    if self.command=='POST' and self.path=='/api/v1/auth/passkey-options':state['bindingOptions']+=1
                    if binding:
                        state['bindingSubmits']+=1;key=self.headers.get('Idempotency-Key','');assert key
                        keys.add(hashlib.sha256(key.encode()).digest())
                        challenge=json.loads(body)['challengeId'];assert isinstance(challenge,str)
                        anchors.add((hashlib.sha256(key.encode()).digest(),hashlib.sha256(challenge.encode()).digest()))
                    if self.command=='POST' and self.path=='/api/v1/auth/passkey-reset-options':state['nativeResetOptions']+=1
                    if self.command=='POST' and self.path=='/api/v1/auth/passkey-reset-intents':state['resetSubmits']+=1
                    hold=resultquery and state['holdResults']
                    if resultquery:
                        state['resultQueries']+=1
                        anchor=(hashlib.sha256(self.headers.get('Idempotency-Key','').encode()).digest(),hashlib.sha256(self.headers.get('Credential-Change-ID','').encode()).digest())
                        state['resultQueriesOriginalAnchorMatched' if anchor in anchors else 'resultQueriesOriginalAnchorMismatched']+=1
                    if hold:state['resultQueriesHeld']+=1
                if hold:self.drop();return
                client=http.client.HTTPSConnection('127.0.0.1',cfg['ports']['c'],context=upstream,timeout=25)
                try:
                    headers={k:v for k,v in self.headers.items() if k.lower() not in ('host','connection','content-length','transfer-encoding')}
                    headers.update({'Connection':'close','Content-Length':str(len(body))})
                    client.request(self.command,self.path,body,headers);r=client.getresponse();data=r.read(300001);assert len(data)<=300000
                    with lock:
                        drop=binding and r.status==204 and state['armed']
                        if drop:state['armed']=False;state['holdResults']=True;state['bindingCommittedRepliesDropped']+=1
                    if drop:self.drop();return
                    self.send(r.status,data,r.getheaders())
                finally:client.close()
            except (AssertionError,ValueError,KeyError):self.result(400,{'error':'owned_stage3_request_rejected'})
            except (OSError,http.client.HTTPException):self.result(502,{'error':'owned_stage3_upstream_unavailable'})
    server=http.server.ThreadingHTTPServer(('127.0.0.1',cfg['ports']['proxy']),Handler);server.daemon_threads=True;server.socket=tls.wrap_socket(server.socket,server_side=True);server.serve_forever()
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('action',choices=('prepare','proxy','stats'));args=p.parse_args()
    if args.action=='prepare':prepare()
    elif args.action=='proxy':proxy()
    else:print(json.dumps(stats()))
