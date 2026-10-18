#!/usr/bin/env python3
"""Owned host lab: real C/V cmds, Goose, restricted PG, Flutter production APIs.

All credentials/images are disposable synthetic fixtures. SMTP capture, control
and network fault injection are test ports, never replacement business handlers.
Requires existing toolchains and an already prepared owned SDK/cache/source.
"""
import argparse
import base64
import contextlib
import datetime
import email
import email.policy
import email.utils
import hashlib
import http.client
import http.server
import json
import os
from pathlib import Path
import re
import secrets
import signal
import socket
import socketserver
import ssl
import subprocess
import threading
import time
import urllib.parse
import urllib.request


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def dump(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    Path(path).chmod(0o600)


def inputs(source):
    files = {}
    for parent in ['apps/mobile/lib','apps/mobile/integration','packages/image_viewer/lib','packages/auth_vault/lib','packages/auth_passkey/lib',
                   'services/api/cmd','services/api/internal','services/api/media','services/api/migrations','services/api/verifier-migrations',
                   'services/api/authlab/post-media-control','infra/postgres','packages/post-protocol-vectors','tools/post-media-joint']:
        for path in (source/parent).rglob('*'):
            if path.is_file() and path.suffix in ['.dart','.go','.py','.sql','.json','.sh','.yaml','.txt']:
                raw=path.read_bytes().replace(b'\r\n',b'\n')
                files[str(path.relative_to(source))]=hashlib.sha256(raw).hexdigest()
    for name in ['apps/mobile/pubspec.yaml','apps/mobile/pubspec.lock','packages/image_viewer/pubspec.lock','services/api/go.mod','services/api/go.sum']:
        files[name]=hashlib.sha256((source/name).read_bytes().replace(b'\r\n',b'\n')).hexdigest()
    joined='\n'.join(k+' '+files[k] for k in sorted(files))
    return {'canonicalLfSha256':hashlib.sha256(joined.encode()).hexdigest(),'fileCount':len(files),'files':dict(sorted(files.items()))}


def wait(predicate, label, seconds=40):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if predicate():
            return
        time.sleep(.1)
    raise RuntimeError('Timeout: ' + label)


class SMTP(socketserver.StreamRequestHandler):
    def handle(self):
        self.wfile.write(b'220 synthetic-local-capture\r\n')
        while True:
            line = self.rfile.readline(4096)
            if not line:
                return
            cmd = line.upper()
            if cmd.startswith(b'EHLO'):
                self.wfile.write(b'250 synthetic-local-capture\r\n')
            elif cmd.startswith(b'DATA'):
                self.wfile.write(b'354 end with dot\r\n')
                data = bytearray()
                while True:
                    item = self.rfile.readline(8192)
                    if item == b'.\r\n':
                        break
                    if not item or len(data) + len(item) > 65536:
                        return
                    data.extend(item[1:] if item.startswith(b'..') else item)
                message = email.message_from_bytes(data, policy=email.policy.default)
                recipient = email.utils.parseaddr(message['To'])[1]
                body = message.get_body(preferencelist=('plain',)) if message.is_multipart() else message
                code = re.search(r'(?<!\d)(\d{6})(?!\d)', body.get_content())
                if recipient.endswith('@hainanu.edu.cn') and code:
                    with self.server.lab.lock:
                        self.server.lab.mail[recipient] = code[1]
                self.wfile.write(b'250 captured\r\n')
            elif cmd.startswith(b'QUIT'):
                self.wfile.write(b'221 done\r\n')
                return
            else:
                self.wfile.write(b'250 ok\r\n')


class OwnedTLSConnection(http.client.HTTPSConnection):
    def connect(self):
        # Same trusted C name/port, separate owned loopback bind; verification
        # stays enabled. The proxy never forwards to a caller-supplied address.
        sock = socket.create_connection(('127.0.0.2', self.port), self.timeout)
        self.sock = self._context.wrap_socket(sock, server_hostname='127.0.0.1')


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *_):
        pass  # No paths, headers, bodies, accounts or capabilities in logs.

    def read_body(self, limit):
        out = bytearray()
        if self.headers.get('Transfer-Encoding', '').lower() == 'chunked':
            while True:
                size = int(self.rfile.readline(80).split(b';')[0], 16)
                if not size:
                    while self.rfile.readline(4096) != b'\r\n':
                        pass
                    break
                if len(out) + size > limit:
                    raise ValueError('body budget')
                out.extend(self.rfile.read(size))
                if self.rfile.read(2) != b'\r\n':
                    raise ValueError('chunk boundary')
        else:
            size = int(self.headers.get('Content-Length', '0'))
            if size < 0 or size > limit:
                raise ValueError('body budget')
            out.extend(self.rfile.read(size))
        return bytes(out)

    def disconnect(self):
        self.close_connection = True
        with contextlib.suppress(OSError):
            self.connection.shutdown(socket.SHUT_RDWR)
        self.connection.close()

    def do_GET(self):
        self.dispatch()

    def do_POST(self):
        self.dispatch()

    def do_PUT(self):
        self.dispatch()

    def dispatch(self):
        lab = self.server.lab
        if self.server.control:
            if self.command != 'POST' or self.headers.get('Authorization') != 'LabControl ' + lab.token:
                self.send_error(403)
                return
            try:
                value = json.loads(self.read_body(4096) or b'{}')
                result = lab.control(self.path, value)
                status = 200
            except Exception:
                result, status = {'error': 'owned control failed'}, 500
            raw = json.dumps(result).encode()
            self.send_response(status)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)
            return
        try:
            body = self.read_body(10 * 1024 * 1024 + 1)
            path = urllib.parse.urlsplit(self.path).path
            put = self.command == 'PUT' and path.endswith('/bytes')
            create = self.command == 'PUT' and path.startswith('/api/v1/post-commands/')
            media = path.split('/')[-2] if put else ''
            with lab.lock:
                if create:
                    lab.creates += 1
                if put:
                    lab.puts[media] = lab.puts.get(media, 0) + 1
                before = (lab.hold_query and self.command == 'GET' and path.startswith('/api/v1/post-commands/'))
                if put and media in lab.drop_before:
                    before = True
                    lab.drop_before.remove(media)
                if before:
                    lab.pre_drops += 1
            if before:
                self.disconnect()
                return
            conn = OwnedTLSConnection('127.0.0.1', lab.cport, context=lab.trust, timeout=35)
            headers = {k: v for k, v in self.headers.items() if k.lower() not in ('connection', 'transfer-encoding', 'content-length')}
            headers['Content-Length'] = str(len(body))
            headers['Connection'] = 'close'
            conn.request(self.command, self.path, body, headers)
            response = conn.getresponse()
            raw = response.read(11 * 1024 * 1024)
            with lab.lock:
                after = response.status < 300 and (create and lab.drop_create or put and media in lab.drop_after)
                if create and after:
                    lab.drop_create = False
                if put and after:
                    lab.drop_after.remove(media)
                if after:
                    lab.post_drops += 1
                hold_read = self.command == 'GET' and path.endswith('/original') and lab.hold_read
                if hold_read:
                    lab.read_waiting.set()
            if hold_read:
                lab.read_release.wait(20)
            if after:
                self.disconnect()
                return
            self.send_response_only(response.status, response.reason)
            for k, v in response.getheaders():
                if k.lower() not in ('content-length', 'connection', 'transfer-encoding'):
                    self.send_header(k, v)
            self.send_header('Content-Length', str(len(raw)))
            self.send_header('Connection', 'close')
            self.end_headers()
            self.wfile.write(raw)
            self.close_connection = True
            conn.close()
        except (OSError, ValueError, http.client.HTTPException):
            self.disconnect()


class Lab:
    def __init__(self, root):
        self.root = root
        self.source = root/'source'
        self.source_before = inputs(self.source)
        self.run = root/('run-' + secrets.token_hex(4))
        self.run.mkdir(mode=0o700)
        self.logs = root/'logs'/self.run.name
        self.logs.mkdir(mode=0o700)
        dump(root/'logs/latest-run.json', {'run':str(self.run),'logs':str(self.logs)})
        self.lock = threading.Lock()
        self.mail, self.puts = {}, {}
        self.drop_before, self.drop_after = set(), set()
        self.hold_query = self.drop_create = self.hold_read = False
        self.read_waiting, self.read_release = threading.Event(), threading.Event()
        self.creates = self.pre_drops = self.post_drops = 0
        self.token = secrets.token_urlsafe(32)
        self.processes, self.servers = [], []
        self.results = {}
        self.started_pg = False
        self.env = {k: v for k, v in os.environ.items() if not k.startswith(('PG', 'AUTHLAB_', 'AUTHRUNTIME_', 'F4_'))}
        self.env.update(HOME=str(root/'home'), TMPDIR=str(root/'tmp'), GOTMPDIR=str(root/'tmp'),
                        GOCACHE=str(root/'go-build'), GOMODCACHE=str(root/'go-mod'), GOPATH=str(root/'go-path'),
                        GOTOOLCHAIN='local', GOFLAGS='-mod=readonly', GOWORK='off',
                        PUB_CACHE=str(root/'pub'), PUB_HOSTED_URL='https://pub.dev',
                        FLUTTER_ROOT=str(root/'flutter'), GRADLE_USER_HOME=str(root/'gradle'),
                        XDG_CACHE_HOME=str(root/'xdg-cache'), XDG_CONFIG_HOME=str(root/'xdg-config'), XDG_DATA_HOME=str(root/'xdg-data'),
                        FLUTTER_STORAGE_BASE_URL='https://storage.googleapis.com', CI='true',
                        FLUTTER_SUPPRESS_ANALYTICS='true', DART_SUPPRESS_ANALYTICS='true',
                        PYTHONDONTWRITEBYTECODE='1', PIP_CACHE_DIR=str(root/'pip-cache'),
                        PATH=str(root/'flutter/bin')+':/usr/lib/go-1.22/bin:/usr/lib/postgresql/16/bin:/mnt/e/Hnuhole-env/linux/bin:/usr/bin:/bin')
        library = root/'sqlite'
        library.mkdir(exist_ok=True,mode=0o700)
        link = library/'libsqlite3.so'
        if not link.exists(): link.symlink_to('/usr/lib/x86_64-linux-gnu/libsqlite3.so.0')
        if link.resolve() != Path('/usr/lib/x86_64-linux-gnu/libsqlite3.so.0').resolve():
            raise RuntimeError('Unexpected host SQLite library')
        self.env['LD_LIBRARY_PATH'] = str(library)

    def cmd(self, args, name, cwd=None, timeout=240, input=None, env=None):
        started=datetime.datetime.now(datetime.timezone.utc)
        path = self.logs/(name+'.log')
        with path.open('wb') as stream:
            result = subprocess.run([str(a) for a in args], input=input, cwd=cwd or self.source/'services/api',
                                    env=env or self.env, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
        self.results[name] = {'exitCode': result.returncode, 'log': str(path), 'sha256': sha(path),
                             'command':[str(a) for a in args],'cwd':str(cwd or self.source/'services/api'),
                             'startedAtUtc':started.isoformat(),'endedAtUtc':datetime.datetime.now(datetime.timezone.utc).isoformat()}
        if result.returncode:
            raise RuntimeError(name+' failed; private log '+str(path))
        print(name+' PASS', flush=True)

    def sql(self, query, db='hnuhole_c', role='joint_admin'):
        cmd = ['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-h', str(self.run/'socket'), '-p', str(self.pgport), '-U', role, '-d', db]
        result = subprocess.run(cmd, input=query.encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=self.env, timeout=15)
        if result.returncode:
            (self.logs/'sql-error.private').write_bytes(result.stderr)
            raise RuntimeError('owned SQL assertion/setup failed')
        return result.stdout.decode().strip()

    def spawn(self, args, name):
        stream = (self.logs/(name+'.private.log')).open('wb')
        p = subprocess.Popen([str(a) for a in args], env=self.env, stdout=stream, stderr=subprocess.STDOUT)
        self.processes.append((p, stream, name))
        return p

    def setup(self):
        api = self.source/'services/api'
        flutter = self.root/'flutter/bin/flutter'
        self.cmd([flutter, 'pub', 'get', '--offline', '--enforce-lockfile'], 'joint-pub', cwd=self.source/'apps/mobile')
        if not (self.root/'python/bin/python').exists():
            self.cmd(['python3', '-m', 'venv', str(self.root/'python')], 'joint-python-venv')
            self.cmd([self.root/'python/bin/python', '-m', 'pip', 'install', '--disable-pip-version-check', '--only-binary=:all:', '-r', api/'media/requirements.txt'], 'joint-python-dependency')
        self.cmd([self.root/'python/bin/python', api/'media/test_validator.py', '--fixtures', self.root/'fixtures'], 'joint-fixtures')
        (self.root/'fixtures/oriented-jpeg.bin').write_bytes(base64.b64decode((self.source/'apps/mobile/test/fixtures/oriented-jpeg.b64').read_bytes()))
        for binary, target in [('authdev', './cmd/authdev'), ('community', './cmd/api'), ('verifier', './cmd/verifier'), ('media-control','./authlab/post-media-control')]:
            self.cmd(['go', 'build', '-o', self.root/'bin'/binary, target], 'joint-build-'+binary)
        ports = []
        with contextlib.ExitStack() as stack:
            for _ in range(7):
                s = stack.enter_context(socket.socket()); s.bind(('127.0.0.1', 0)); ports.append(s.getsockname()[1])
        self.cport, self.vport, self.ci, self.vi, smtp, control, self.pgport = ports
        self.material = self.run/'material'
        self.run.joinpath('socket').mkdir(mode=0o700)
        dsn = lambda party, role: 'postgres://hnuhole_'+party+'_'+role+'@/hnuhole_'+party+'?'+urllib.parse.urlencode({'host':str(self.run/'socket'),'port':self.pgport,'sslmode':'disable','application_name':'hnuhole_joint_'+self.run.name})
        self.cmd([self.root/'bin/authdev', 'init', '-dir', self.material, '-community-port', self.cport, '-verifier-port', self.vport,
                  '-community-internal-port', self.ci, '-verifier-internal-port', self.vi, '-smtp-port', smtp,
                  '-community-dsn', dsn('c','runtime'), '-verifier-dsn', dsn('v','runtime'),
                  '-recovery-dsn', dsn('c','recovery'), '-verifier-recovery-dsn', dsn('v','recovery')], 'joint-private-material')
        self.cmd(['initdb','-D',self.run/'pg','-U','joint_admin','-A','trust','--no-locale','-E','UTF8'], 'joint-initdb')
        options = "-p %d -c listen_addresses='' -c unix_socket_directories='%s' -c unix_socket_permissions=0700 -c shared_memory_type=mmap -c dynamic_shared_memory_type=mmap -c shared_buffers=16MB -c max_connections=40 -c log_statement=none -c log_min_messages=panic -c log_min_error_statement=panic -c log_error_verbosity=terse -c log_parameter_max_length=0 -c log_parameter_max_length_on_error=0 -c log_min_duration_statement=-1 -c log_min_duration_sample=-1 -c log_transaction_sample_rate=0 -c log_duration=off" % (self.pgport,self.run/'socket')
        self.cmd(['pg_ctl','-D',self.run/'pg','-l',self.run/'postgres.private.log','-w','start','-o',options], 'joint-start-pg')
        self.started_pg = True
        for party in ['c','v']:
            statement = "CREATE ROLE hnuhole_%s_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;" % party
            for role in ['runtime','migrator','recovery']:
                name = 'db-'+party+'-'+role+'.password'
                password = (self.material/(name if role=='runtime' else 'operator/'+name)).read_text()
                assert re.fullmatch('[0-9a-f]{64}',password)
                statement += "CREATE ROLE hnuhole_%s_%s LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD '%s';" % (party,role,password)
            statement += 'GRANT hnuhole_%s_owner TO hnuhole_%s_migrator; CREATE DATABASE hnuhole_%s OWNER hnuhole_%s_owner;' % (party,party,party,party)
            statement += 'REVOKE ALL ON DATABASE hnuhole_%s FROM PUBLIC; GRANT CONNECT ON DATABASE hnuhole_%s TO hnuhole_%s_runtime,hnuhole_%s_migrator,hnuhole_%s_recovery;' % ((party,)*5)
            self.sql(statement, db='postgres')
            self.sql('REVOKE ALL ON SCHEMA public FROM PUBLIC;', db='hnuhole_'+party)
        self.sql('CREATE ROLE hnuhole_business NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;',db='postgres')
        for party in ['c','v']:
            migrator = dsn(party,'migrator')+'&options='+urllib.parse.quote('-c role=hnuhole_'+party+'_owner')
            directory = 'migrations' if party=='c' else 'verifier-migrations'
            if party=='c':
                self.cmd(['goose','-dir',directory,'postgres',migrator,'up-to','13'],'joint-goose-c-to13')
                before = self.sql('SELECT json_agg(x ORDER BY id) FROM public.channels x;')
            self.cmd(['goose','-dir',directory,'postgres',migrator,'up'],'joint-goose-'+party+'-up')
            self.cmd(['goose','-dir',directory,'postgres',migrator,'up'],'joint-goose-'+party+'-noop')
            if party=='c':
                assert before == self.sql('SELECT json_agg(x ORDER BY id) FROM public.channels x;')
                assert self.sql('SELECT max(version_id) FROM goose_db_version WHERE is_applied;')=='14'
            grant = (self.source/'infra/postgres'/('grant-community.sql' if party=='c' else 'grant-verifier.sql')).read_text()
            self.sql('SET ROLE hnuhole_'+party+'_owner;\n'+grant,db='hnuhole_'+party)
        self.sql('SET ROLE hnuhole_c_owner;\n'+(self.source/'infra/postgres/grant-post-images.sql').read_text())
        self.validator = self.run/'validate_image.py'
        self.validator.write_bytes((api/'media/validate_image.py').read_bytes()); self.validator.chmod(0o600)
        self.validator_bytes = self.validator.read_bytes()
        cpath = self.material/'c.json'; c = json.loads(cpath.read_text())
        c['publicListen'] = '127.0.0.2:'+str(self.cport)
        c['postImages'] = {'pythonFile':str(self.root/'python/bin/python'),'validatorFile':str(self.validator),'validatorSHA256':sha(self.validator)}
        dump(cpath,c)
        self.trust = ssl.create_default_context(cafile=str(self.material/'dev-ca.pem'))
        tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); tls.load_cert_chain(self.material/'c-public.pem',self.material/'c-public.key')
        for port, is_control in [(self.cport,False),(control,True)]:
            server = http.server.ThreadingHTTPServer(('127.0.0.1',port), Handler)
            server.daemon_threads=True; server.lab=self; server.control=is_control
            server.socket=tls.wrap_socket(server.socket,server_side=True); self.servers.append(server)
            threading.Thread(target=server.serve_forever,daemon=True).start()
        server=socketserver.ThreadingTCPServer(('127.0.0.1',smtp),SMTP);server.daemon_threads=True;server.lab=self;self.servers.append(server)
        threading.Thread(target=server.serve_forever,daemon=True).start()
        for party in ['c','v']:
            self.cmd([self.root/'bin/authdev','recover','-operator',self.material/'operator'/('operator.json' if party=='c' else 'v-operator.json')],'joint-recover-'+party)
            self.spawn([self.root/'bin/authdev','watch','-operator',self.material/'operator'/('operator.json' if party=='c' else 'v-operator.json')],'watch-'+party)
        self.spawn([self.root/'bin/community','-config',self.material/'c.json'],'community')
        self.spawn([self.root/'bin/verifier','-config',self.material/'v.json'],'verifier')
        def ready():
            try:
                for port in [self.cport,self.vport]:
                    with urllib.request.urlopen('https://127.0.0.1:'+str(port)+'/health/ready',context=self.trust,timeout=2) as r:
                        if r.status!=200:return False
                return True
            except OSError:return False
        wait(ready,'owned real C/V readiness')
        print('joint-real-C-V-ready PASS',flush=True)
        client=self.run/'client';client.mkdir(mode=0o700)
        self.config = self.run/'client-config.json'
        dump(self.config,{'communityOrigin':'https://127.0.0.1:'+str(self.cport),'verifierOrigin':'https://127.0.0.1:'+str(self.vport),
                          'controlOrigin':'https://127.0.0.1:'+str(control),'controlToken':self.token,'caPath':str(self.material/'dev-ca.pem'),
                          'runDir':str(client),'fixtures':str(self.root/'fixtures')})
        self.results['actual-processes']={'result':'PASS','communityPid':self.processes[-2][0].pid,'verifierPid':self.processes[-1][0].pid,
                                          'schemaC':14,'schemaV':4,'freshPrivateCluster':True,'runtimeOwnerOrRecovery':False}

    def control(self, path, data):
        if path=='/otp':
            with self.lock: code=self.mail.get(data['email'])
            return {'code':code}
        if path=='/fault':
            with self.lock:
                self.hold_query=data.get('holdQuery',self.hold_query)
                self.drop_create=data.get('dropCreate',self.drop_create)
                self.drop_before.update(data.get('dropBefore',[]));self.drop_after.update(data.get('dropAfter',[]))
            return {'ok':True}
        if path=='/stats':
            with self.lock:return {'creates':self.creates,'puts':self.puts,'preDrops':self.pre_drops,'postDrops':self.post_drops,'readWaiting':self.read_waiting.is_set()}
        if path=='/validator':
            self.validator.write_bytes(self.validator_bytes+(b'\n# owned drift negative\n' if data['tamper'] else b''))
            return {'ok':True}
        if path in ['/freeze','/recover']:
            self.cmd([self.root/'bin/authdev',path[1:],'-operator',self.material/'operator/operator.json'],'joint-control-'+path[1:])
            return {'ok':True}
        if path=='/read-hold':
            self.hold_read=data['hold']
            if self.hold_read:self.read_waiting.clear();self.read_release.clear()
            else:self.read_release.set()
            return {'ok':True}
        task=data.get('taskId','')
        if not re.fullmatch('[a-f0-9-]{36}',task):raise ValueError('owned task required')
        if path=='/snapshot':
            raw=self.sql("SELECT json_build_object('images',count(*),'verified',count(*) FILTER(WHERE verified_at IS NOT NULL AND payload IS NOT NULL),'erased',count(*) FILTER(WHERE erased_at IS NOT NULL),'payloads',COALESCE(json_agg(json_build_object('mediaId',media_id,'sha256',encode(sha256(payload),'hex'),'bytes',octet_length(payload),'position',position,'version',version)) FILTER(WHERE payload IS NOT NULL),'[]'::json)) FROM c_posts.images WHERE task_id='%s';"%task)
            result=json.loads(raw)
            result['states']=json.loads(self.sql("SELECT COALESCE(json_agg(json_build_object('version',version,'state',state)),'[]'::json) FROM c_posts.publication_attempts WHERE task_id='%s';"%task))
            result['public']=int(self.sql("SELECT count(*) FROM c_posts.posts p JOIN c_posts.publication_tasks t ON p.post_id=t.post_id WHERE t.task_id='%s' AND p.visibility='PUBLISHED';"%task))
            return result
        if path=='/mute':
            self.cmd([self.root/'bin/media-control','-root',self.root,'-config',self.material/'c.json','-task',task],'joint-trusted-publication-stop')
            return {'ok':True}
        raise ValueError('unknown control')

    def tests(self):
        for phase in ['write','read','edges']:
            env={**self.env,'POST_MEDIA_JOINT_CONFIG':str(self.config),'POST_MEDIA_JOINT_PHASE':phase}
            self.cmd([self.root/'flutter/bin/flutter','test','--no-pub','--reporter=expanded','integration/post_media_joint_test.dart'],
                     'joint-flutter-'+phase,cwd=self.source/'apps/mobile',env=env,timeout=240)
        combined={}
        for phase in ['write','read','edges']:
            result=json.loads((self.run/'client'/('checks-'+phase+'.json')).read_text())
            assert result and all(v is True for v in result.values())
            combined.update(result)
        summary={'result':'PASS','checks':combined,'checkCount':len(combined),'runs':self.results,'realProcesses':True,'realGoose':True,'realPostgres':True,
                 'flutterProcesses':3,'nativeVault':'HOST_FILE_SUBSTITUTE','nativePicker':'SYNTHETIC_SOURCE_SUBSTITUTE','deviceUsed':False,
                 'faults':'owned transparent TLS proxy only; original C headers/body/metadata forwarded, no business handler substitute',
                 'independentSql':True,'production':False}
        after=inputs(self.source)
        if after!=self.source_before: raise RuntimeError('Runtime inputs changed during joint run')
        summary['sourceFingerprint']=after
        summary['sourceStableDuringRun']=True
        dump(self.logs/'joint-summary.json',summary)
        print('JOINT PASS '+str(len(combined))+' checkpoints',flush=True)

    def cleanup(self):
        self.read_release.set()
        for p,stream,name in reversed(self.processes):
            if p.poll() is None:p.terminate()
        for p,stream,name in self.processes:
            try:p.wait(timeout=25)
            except subprocess.TimeoutExpired:p.kill();p.wait(timeout=5)
            stream.close()
        for server in self.servers:server.shutdown();server.server_close()
        if self.started_pg:
            self.cmd(['pg_ctl','-D',self.run/'pg','-m','fast','-w','stop'],'joint-stop-pg')
        dump(self.logs/'joint-cleanup.json',{'run':str(self.run),'allOwnedProcessesStopped':all(p.poll() is not None for p,_,_ in self.processes),'otherServicesTouched':False,
                                           'privateMaterialsRetainedForFailureAnalysis':True})


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--root',required=True);args=parser.parse_args()
    root=Path(args.root)
    if os.geteuid()==0 or root.resolve()!=root or not str(root).startswith('/home/hnuhole/post-media-joint-'):
        raise SystemExit('Canonical owned non-root lab required')
    if not (root/'.owner').read_text().startswith('post-image-integration-20261015|'):
        raise SystemExit('Owner marker required')
    os.umask(0o077)
    lab=Lab(root)
    try:lab.setup();lab.tests()
    finally:lab.cleanup()


if __name__=='__main__':main()
