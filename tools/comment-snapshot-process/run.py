#!/usr/bin/env python3
"""Owned native PG + Redis + two actual cmd/api processes; no external DSN.

Synthetic SQL seed is explicitly not comment-creation acceptance. All measured
reads use production HTTPS, authorization, SQL commit and Redis code paths.
Tools must already exist. Private fixtures and logs stay outside the repository.
"""
import argparse
import base64
import concurrent.futures
import copy
import datetime
import hashlib
import hmac
import http.client
import json
import math
import os
from pathlib import Path
import secrets
import shutil
import socket
import ssl
import subprocess
import threading
import time
import urllib.parse
import uuid


def measurement_ns():
    # Benchmark physical elapsed time without NTP frequency adjustment.
    return time.clock_gettime_ns(time.CLOCK_MONOTONIC_RAW)


def elapsed_clock():
    return measurement_ns()/1e9


def host_clock():
    executable=os.environ.get('COMMENT_SNAPSHOT_WINDOWS_CLOCK')
    if not executable:return None
    before=elapsed_clock()
    command="[ordered]@{utcMs=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();ticks=[Diagnostics.Stopwatch]::GetTimestamp();frequency=[Diagnostics.Stopwatch]::Frequency}|ConvertTo-Json -Compress"
    completed=subprocess.run([executable,'-NoLogo','-NoProfile','-NonInteractive','-Command',command],capture_output=True,check=True,timeout=10)
    value=json.loads(completed.stdout.decode('utf-8-sig'))
    assert value['frequency']>0 and value['ticks']>=0
    value.update(rawBefore=before,rawAfter=elapsed_clock())
    return value


def host_clock_summary(initial,final):
    if initial is None or final is None:return None
    assert initial['frequency']==final['frequency']
    duration=(final['ticks']-initial['ticks'])/final['frequency']
    # Clock reads enclose process startup; report the uncertainty explicitly.
    low=final['rawBefore']-initial['rawAfter'];high=final['rawAfter']-initial['rawBefore']
    stable=(low-1<=duration<=high+1 and abs((final['utcMs']-initial['utcMs'])/1000-duration)<=2)
    return dict(elapsedSeconds=duration,rawElapsedLowerBound=low,rawElapsedUpperBound=high,
                utcCounterDriftSeconds=(final['utcMs']-initial['utcMs'])/1000-duration,stable=stable)


def dump(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n')
    path.chmod(0o600)


def b64(value):
    return base64.urlsafe_b64encode(value).decode().rstrip('=')


def source_digest(source):
    api=source/'services/api'
    files=sorted(p for p in api.rglob('*') if p.is_file() and p.suffix in ['.go','.lua','.mod','.sum'] and not p.name.endswith('_test.go'))
    return hashlib.sha256('\n'.join(str(p.relative_to(api))+':'+hashlib.sha256(p.read_bytes()).hexdigest() for p in files).encode()).hexdigest()


def wait(check, label, seconds=30):
    deadline = time.monotonic()+seconds
    while time.monotonic() < deadline:
        if check():
            return
        time.sleep(.1)
    raise RuntimeError('timeout: '+label)


class Redis:
    def __init__(self, port, password):
        self.port, self.password = port, password

    def call(self, *args):
        def encode(parts):
            out = b'*'+str(len(parts)).encode()+b'\r\n'
            for part in parts:
                raw = part if isinstance(part, bytes) else str(part).encode()
                out += b'$'+str(len(raw)).encode()+b'\r\n'+raw+b'\r\n'
            return out

        def read(stream):
            line = stream.readline()
            if not line:
                raise RuntimeError('Redis connection closed')
            kind, data = line[:1], line[1:-2]
            if kind == b'-':
                raise RuntimeError(data.decode())
            if kind == b':':
                return int(data)
            if kind == b'$':
                n = int(data)
                if n < 0:
                    return None
                value = stream.read(n)
                assert stream.read(2) == b'\r\n'
                return value
            if kind == b'*':
                return [read(stream) for _ in range(int(data))]
            return data
        with socket.create_connection(('127.0.0.1', self.port), timeout=3) as sock:
            stream = sock.makefile('rb')
            sock.sendall(encode(['AUTH', self.password]))
            assert read(stream) == b'OK'
            sock.sendall(encode(args))
            return read(stream)

    def info(self):
        return {k: v for line in self.call('INFO', 'memory').decode().splitlines()
                if ':' in line for k, v in [line.split(':', 1)]}


class Lab:
    def __init__(self, args):
        self.args = args
        self.root = args.root.resolve()
        assert self.root.is_dir() and self.root != Path('/')
        self.source = args.source.resolve()
        if self.root == self.source or self.source in self.root.parents or self.root.stat().st_mode & 0o077:
            raise RuntimeError('fixture root must be private and outside the source repository')
        (self.root/'bin').mkdir(exist_ok=True)
        self.api = self.source/'services/api'
        self.run = self.root/('process-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S')+'-'+secrets.token_hex(3))
        self.run.mkdir(mode=0o700)
        self.logs = self.run/'logs'; self.logs.mkdir(mode=0o700)
        self.processes = []
        self.started_pg = False
        self.results = {'result': 'RUNNING', 'syntheticSeed': True, 'productionDeployment': False}
        self.env = {k: v for k, v in os.environ.items() if not k.startswith(('PG', 'AUTHLAB_', 'AUTHRUNTIME_'))}
        archive = Path('/home/hnuhole/go/pkg/mod/cache/download')
        proxy = 'file://'+str(archive)+',off' if archive.is_dir() else 'https://proxy.golang.org,direct'
        self.env.update(PATH='/usr/lib/go-1.22/bin:/usr/lib/postgresql/16/bin:/mnt/e/Hnuhole-env/linux/bin:'+os.environ.get('PATH','/usr/bin:/bin'),
                        GOTOOLCHAIN='local', GOPATH=str(self.root/'go'), GOCACHE=str(self.root/'go-build'),
                        GOMODCACHE=str(self.root/'go/pkg/mod'), GOPROXY=os.environ.get('GOPROXY',proxy),
                        GOFLAGS='-mod=readonly', GOWORK='off',
                        LD_LIBRARY_PATH=str(args.redis.parent.parent/'lib/x86_64-linux-gnu'))
        dump(self.root/'process-latest.json', {'run': str(self.run)})

    def cmd(self, args, name, cwd=None, env=None, timeout=120):
        with (self.logs/(name+'.private.log')).open('wb') as stream:
            r = subprocess.run([str(a) for a in args], cwd=cwd or self.api, env=env or self.env,
                               stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
        if r.returncode:
            raise RuntimeError(name+' failed; inspect private log')

    def spawn(self, args, name):
        stream = (self.logs/(name+'.private.log')).open('wb')
        p = subprocess.Popen([str(a) for a in args], cwd=self.api, env=self.env, stdout=stream, stderr=subprocess.STDOUT)
        self.processes.append((p, stream, name))
        return p

    def sql(self, sql, db='hnuhole_c'):
        r = subprocess.run(['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-h', str(self.socket), '-p', str(self.pgport),
                            '-U', 'snapshot_process_admin', '-d', db], input=sql.encode(), stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, env=self.env, timeout=30)
        if r.returncode:
            (self.logs/'sql-error.private.log').write_bytes(r.stderr)
            raise RuntimeError('owned SQL setup/assertion failed')
        return r.stdout.decode().strip()

    def tls_connection(self, ip, timeout, *, tcp_nodelay=True):
        # Both processes represent one origin. B binds a second loopback IP;
        # SNI and trust verification still use the configured 127.0.0.1 origin.
        conn = http.client.HTTPSConnection('127.0.0.1', self.cport, context=self.trust, timeout=timeout)
        sock = socket.create_connection((ip, self.cport), timeout=timeout)
        # This manually selected address bypasses HTTPConnection.connect(),
        # which normally enables TCP_NODELAY before wrapping the socket.
        try:
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, int(tcp_nodelay))
            conn.sock = self.trust.wrap_socket(sock, server_hostname='127.0.0.1')
        except BaseException:
            sock.close()
            raise
        return conn

    def request(self, ip, path, token=None, nonce=None, want=200, *, tcp_nodelay=True):
        pace = getattr(self, 'request_pace_seconds', 0)
        if pace:
            time.sleep(max(0, getattr(self, 'next_request_at', 0)-time.monotonic()))
            self.next_request_at = time.monotonic()+pace
        conn = self.tls_connection(ip, 5, tcp_nodelay=tcp_nodelay)
        self.last_request_tcp_nodelay = conn.sock.getsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY)
        headers = {'Authorization': 'Bearer '+(token or self.tokens[0])}
        if nonce:
            headers['X-Comment-Snapshot-Request'] = nonce
        started = measurement_ns()
        self.last_request_start_raw_ns = started
        self.last_request_send_at = time.monotonic()
        self.last_request_clock_offsets = {'utcRawSeconds':time.time()-started/1e9,'monoRawSeconds':self.last_request_send_at-started/1e9}
        try:
            conn.request('GET', path, headers=headers)
            response = conn.getresponse(); raw = response.read()
            elapsed = (measurement_ns()-started)/1e6
            body = json.loads(raw)
            if response.status != want:
                raise RuntimeError('HTTP expected %d got %d body=%s'%(want, response.status, str(body)[:250]))
            assert response.getheader('Cache-Control') == 'no-store'
            return body, elapsed, dict(response.getheaders())
        finally:
            conn.close()

    def ready(self, ip):
        try:
            conn = self.tls_connection(ip, 1)
            conn.request('GET', '/health/ready'); response = conn.getresponse(); response.read(); conn.close()
            return response.status == 200
        except OSError:
            return False

    def setup(self):
        for name, target in [('api', './cmd/api'), ('authdev', './cmd/authdev'), ('commentsnapshotctl', './cmd/commentsnapshotctl')]:
            self.install_binary(name,target)
        ports = []
        for _ in range(7):
            with socket.socket() as s:
                s.bind(('127.0.0.1', 0)); ports.append(s.getsockname()[1])
        self.cport, vport, ci, vi, smtp, self.pgport, rp = ports
        self.socket = Path('/tmp')/('hnu-snapshot-'+secrets.token_hex(6)); self.socket.mkdir(mode=0o700)
        self.material = self.run/'material'
        dsn = lambda p, r: 'postgres://hnuhole_'+p+'_'+r+'@/hnuhole_'+p+'?'+urllib.parse.urlencode({'host': str(self.socket), 'port': self.pgport, 'sslmode': 'disable'})
        self.cmd([self.root/'bin/process-authdev', 'init', '-dir', self.material, '-community-port', self.cport, '-verifier-port', vport,
                  '-community-internal-port', ci, '-verifier-internal-port', vi, '-smtp-port', smtp,
                  '-community-dsn', dsn('c', 'runtime'), '-verifier-dsn', dsn('v', 'runtime'),
                  '-recovery-dsn', dsn('c', 'recovery'), '-verifier-recovery-dsn', dsn('v', 'recovery')], 'material')
        self.cmd(['initdb', '-D', self.run/'pg', '-U', 'snapshot_process_admin', '-A', 'trust', '--no-locale', '-E', 'UTF8'], 'initdb')
        options = "-p %d -c listen_addresses='' -c unix_socket_directories='%s' -c unix_socket_permissions=0700 -c shared_memory_type=mmap -c dynamic_shared_memory_type=mmap -c shared_buffers=32MB -c max_connections=80 -c log_statement=none -c log_min_messages=panic -c log_min_error_statement=panic -c log_error_verbosity=terse -c log_parameter_max_length=0 -c log_parameter_max_length_on_error=0 -c log_min_duration_statement=-1 -c log_min_duration_sample=-1 -c log_transaction_sample_rate=0 -c log_duration=off"%(self.pgport, self.socket)
        self.cmd(['pg_ctl', '-D', self.run/'pg', '-l', self.run/'postgres.private.log', '-w', 'start', '-o', options], 'start-pg')
        self.started_pg = True
        for p in ['c', 'v']:
            self.sql('CREATE ROLE hnuhole_%s_owner NOLOGIN;'%p, 'postgres')
            for role in ['runtime', 'migrator', 'recovery']:
                pw = (self.material/('' if role == 'runtime' else 'operator')/('db-'+p+'-'+role+'.password')).read_text()
                assert len(pw) == 64 and all(c in '0123456789abcdef' for c in pw)
                self.sql("CREATE ROLE hnuhole_%s_%s LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD '%s';"%(p, role, pw), 'postgres')
            self.sql('GRANT hnuhole_%s_owner TO hnuhole_%s_migrator;'%(p, p), 'postgres')
            self.sql('CREATE DATABASE hnuhole_%s OWNER hnuhole_%s_owner;'%(p, p), 'postgres')
            self.sql('REVOKE ALL ON DATABASE hnuhole_%s FROM PUBLIC; GRANT CONNECT ON DATABASE hnuhole_%s TO hnuhole_%s_runtime,hnuhole_%s_migrator,hnuhole_%s_recovery;'%(p,p,p,p,p), 'postgres')
            self.sql('REVOKE ALL ON SCHEMA public FROM PUBLIC;', 'hnuhole_'+p)
            env = {**self.env, 'PGPASSWORD': (self.material/'operator'/('db-'+p+'-migrator.password')).read_text()}
            self.cmd(['goose', '-dir', 'migrations' if p == 'c' else 'verifier-migrations', 'postgres', dsn(p, 'migrator')+'&options='+urllib.parse.quote('-c role=hnuhole_'+p+'_owner'), 'up'], 'migrate-'+p, env=env)
        self.sql('CREATE ROLE hnuhole_business NOLOGIN;', 'postgres')
        for p in ['c', 'v']:
            self.sql('SET ROLE hnuhole_'+p+'_owner;\n'+(self.source/'infra/postgres'/('grant-community.sql' if p == 'c' else 'grant-verifier.sql')).read_text(), 'hnuhole_'+p)
        self.sql('SET ROLE hnuhole_c_owner;\n'+(self.source/'infra/postgres/grant-comments.sql').read_text())
        self.admin_password = secrets.token_hex(32)
        self.snapshot_password = secrets.token_hex(32)
        self.redis_process = self.spawn([self.args.redis, '--bind', '127.0.0.1', '--port', rp, '--save', '', '--appendonly', 'no',
                                        '--maxmemory', '128mb', '--maxmemory-policy', 'noeviction', '--requirepass', self.admin_password,
                                        '--dir', self.run], 'redis')
        self.redis = Redis(rp, self.admin_password)
        wait(lambda: self.redis_ready(), 'owned Redis')
        dump(self.run/'fixture-owner.json',{'snapshotRedisPid':self.redis_process.pid,'kind':'comment-snapshot-owned-process-fixture'})
        self.redis.call('ACL', 'SETUSER', 'community_comment_snapshot_v2', 'on', '>'+self.snapshot_password, '~hnuhole:comment-snapshot:v2:dev:*',
                        '+get', '+set', '+setrange', '+pexpiretime', '+del', '+exists', '+pttl', '+time', '+info', '+eval', '+evalsha', '+ping', '+hello', '+client|setname')
        (self.material/'snapshot.password').write_text(self.snapshot_password); (self.material/'snapshot.password').chmod(0o600)
        (self.material/'snapshot-admin.password').write_text(self.admin_password); (self.material/'snapshot-admin.password').chmod(0o600)
        for key in ['comment-command.key', 'comment-fingerprint.key']:
            (self.material/key).write_bytes(secrets.token_bytes(32)); (self.material/key).chmod(0o600)
        self.cfg = json.loads((self.material/'c.json').read_text())
        settings = json.loads((self.source/'infra/commentsnapshot/snapshots.example.json').read_text())
        settings.update(createBackend='redis', readPostgres=True, readRedis=True)  # isolated fixture only
        settings['postgresCursorVersion'] = 2  # explicit dual-reader fixture; rollout default remains V1
        settings['redis'].update(address='127.0.0.1:'+str(rp), passwordFile='snapshot.password', namespace='hnuhole:comment-snapshot:v2:dev:', epoch=str(uuid.uuid4()))
        self.cfg['comments'] = {'commandKeyFile': 'comment-command.key', 'fingerprintKeyFile': 'comment-fingerprint.key', 'snapshots': settings}
        # Preserve authdev's existing local network limits. Measurement drivers
        # pace traffic before the timer rather than raising admission limits.
        if getattr(self.args, 'shared_admission', 'none') == 'official':
            self.setup_shared_admission()
        dump(self.material/'c.json', self.cfg)
        self.cmd([self.root/'bin/process-commentsnapshotctl', '-config', self.material/'c.json', '-initialize-new-namespace',
                  '-operator-username', 'default', '-operator-password-file', 'snapshot-admin.password'], 'initialize-snapshot')
        self.cmd([self.root/'bin/process-authdev', 'recover', '-operator', self.material/'operator/operator.json'], 'recover')
        self.spawn([self.root/'bin/process-authdev', 'watch', '-operator', self.material/'operator/operator.json'], 'watch')
        self.seed()
        self.trust = ssl.create_default_context(cafile=str(self.material/'dev-ca.pem'))
        self.a = self.start_api('a', '127.0.0.1', ci)
        self.b = self.start_api('b', '127.0.0.2', vi)
        self.results['processes'] = {'aPid': self.a.pid, 'bPid': self.b.pid, 'executable': 'services/api/cmd/api', 'independentOSProcesses': self.a.pid != self.b.pid}
        self.results['runtime'] = {'go': subprocess.check_output(['go', 'version'], env=self.env).decode().strip(),
                                   'postgres': self.sql('SELECT version();'), 'redis': self.redis.call('INFO', 'server').decode().split('redis_version:')[1].splitlines()[0],
                                   'cpus': os.cpu_count(), 'kernel': os.uname().release, 'config': settings}
        print('SETUP PASS '+str(self.run), flush=True)

    def install_binary(self,name,target):
        cached=os.environ.get('COMMENT_SNAPSHOT_BINARY_DIR')
        destination=self.root/'bin'/('process-'+name)
        if cached:
            directory=Path(cached);manifest=json.loads((directory/'binary-manifest.json').read_text())
            if manifest['sourceDigest']!=source_digest(self.source):raise RuntimeError('compiled source fingerprint mismatch')
            binary=directory/('process-'+name)
            if hashlib.sha256(binary.read_bytes()).hexdigest()!=manifest['binaries'][name]:raise RuntimeError('compiled binary hash mismatch')
            if destination.exists():
                if hashlib.sha256(destination.read_bytes()).hexdigest()!=manifest['binaries'][name]:
                    raise RuntimeError('existing fixture binary differs from frozen manifest')
                return
            shutil.copyfile(binary,destination);destination.chmod(0o700)
        else:
            self.cmd(['go','build','-o',destination,target],'build-'+name)

    def setup_shared_admission(self):
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0)); port = listener.getsockname()[1]
        password = secrets.token_hex(32)
        process = self.spawn([self.args.redis, '--bind', '127.0.0.1', '--port', port, '--save', '', '--appendonly', 'no',
                              '--maxmemory', '256mb', '--maxmemory-policy', 'noeviction', '--requirepass', password,
                              '--dir', self.run], 'official-admission-redis')
        client = Redis(port, password)
        def ready():
            try: return 'process_id:'+str(process.pid)+'\r\n' in client.call('INFO','server').decode()
            except OSError: return False
        wait(ready, 'owned official admission Redis')
        commands = ['+type','+get','+set','+pttl','+time','+zscore','+zcard','+zadd','+zremrangebyscore','+pexpire','+eval','+info','+ping','+hello','+client|setname']
        client.call('ACL','SETUSER','community_ratelimit','on','>'+password,'~hnuhole:community_dev:*',*commands)
        client.call('ACL','SETUSER','community_ratelimit_operator','on','>'+password,'~hnuhole:community_dev:*','+@all')
        for name in ['official-admission-runtime.password','official-admission-admin.password']:
            p=self.material/name;p.write_text(password);p.chmod(0o600)
        key=self.material/'official-admission.key';key.write_bytes(secrets.token_bytes(32));key.chmod(0o600)
        shared=json.loads((self.source/'infra/ratelimit/community-observe.example.json').read_text())['sharedRateLimit']
        shared['policy']['address']='127.0.0.1:'+str(port)
        shared.update(keyFile='official-admission.key',passwordFile='official-admission-runtime.password',trustedProxies=[])
        policy=copy.deepcopy(shared['policy']);policy['username']='community_ratelimit_operator'
        operator={'service':'community','databaseUrl':self.cfg['databaseUrl'].replace('hnuhole_c_runtime@','hnuhole_c_migrator@')+'&options='+urllib.parse.quote('-c role=hnuhole_c_owner'),
                  'databasePasswordFile':'operator/db-c-migrator.password','redisPasswordFile':'official-admission-admin.password',
                  'subjectKeyFile':'official-admission.key','policy':policy}
        path=self.material/'official-admission-operator.json';dump(path,operator)
        self.install_binary('ratelimitctl','./cmd/ratelimitctl')
        self.cmd([self.root/'bin/process-ratelimitctl','-config',path,'-initialize-new-namespace'],'initialize-official-admission')
        self.cfg['sharedRateLimit']=shared
        self.admission=client
        self.results['officialAdmission']={'policy':shared['policy'],'runtimeKeyScope':'hnuhole:community_dev:*','separateRedisPid':process.pid,'maxmemoryBytes':256*1024*1024}

    def redis_ready(self):
        try:
            info = self.redis.call('INFO', 'server').decode()
            return 'process_id:'+str(self.redis_process.pid)+'\r\n' in info
        except OSError:
            return False

    def start_api(self, name, ip, internal):
        cfg = copy.deepcopy(self.cfg)
        cfg['publicListen'] = ip+':'+str(self.cport)
        cfg['internalListen'] = ip+':'+str(internal)
        path = self.material/('c-'+name+'.json'); dump(path, cfg)
        p = self.spawn([self.root/'bin/process-api', '-config', path], 'api-'+name)
        wait(lambda: self.ready(ip), 'API '+name)
        return p

    def seed(self):
        self.tokens = [b64(secrets.token_bytes(32)) for _ in range(4)]
        self.accounts = [str(uuid.uuid4()) for _ in self.tokens]
        self.identity = str(uuid.uuid4()); self.post = str(uuid.uuid4()); posttask = str(uuid.uuid4())
        channel = self.sql('SELECT id FROM public.channels ORDER BY id LIMIT 1;')
        generation = self.sql('SELECT authorization_generation FROM c_auth.authorization_gate;')
        statements = ['BEGIN;', 'SET LOCAL session_replication_role=replica;']
        for i, (account, token) in enumerate(zip(self.accounts, self.tokens)):
            raw = base64.urlsafe_b64decode(token+'=')
            tokenhash = hashlib.sha256(raw).hexdigest()
            revoke = hashlib.sha256(b'HNUHOLE/SESSION-REVOKE/V1\0'+raw).digest()
            revokehash = hashlib.sha256(b'HNUHOLE/REVOKE-STORAGE/V1\0'+revoke).hexdigest()
            statements += ["INSERT INTO c_auth.accounts(account_id,platform_number,username,password_hash,password_salt,password_params_version) VALUES('%s','%06d','snapshot_user_%d',decode('%s','hex'),decode('%s','hex'),1);"%(account, 100001+i, i, secrets.token_hex(32), secrets.token_hex(16)),
                           "INSERT INTO c_auth.account_restrictions(account_id) VALUES('%s');"%account,
                           "INSERT INTO c_auth.sessions(token_digest,revoke_digest,account_id,installation_id,session_generation,created_at,last_activity_at,expires_at,authorization_generation) VALUES(decode('%s','hex'),decode('%s','hex'),'%s',decode('%s','hex'),1,now(),now(),now()+interval '30 days',%s);"%(tokenhash,revokehash,account,secrets.token_hex(16),generation)]
        account = self.accounts[0]
        statements += ["INSERT INTO public.identity_account_state VALUES('%s',1,now());"%account,
                       "INSERT INTO public.community_identities(identity_id,account_id,nickname,avatar,is_original,created_at) VALUES('%s','%s','快照压力','default-v1',true,now());"%(self.identity,account),
                       "INSERT INTO c_posts.identity_public_labels VALUES('%s','ABCDEFGHJKLM');"%self.identity,
                       "INSERT INTO c_posts.posts(post_id,owner_account_id,channel_id,visibility,published_attempt_version,published_at,publication_ordinal) VALUES('%s','%s','%s','PUBLISHED',1,now(),1);"%(self.post,account,channel),
                       "INSERT INTO c_posts.post_identity_bindings VALUES('%s','%s','%s',now());"%(account,self.post,self.identity),
                       "INSERT INTO c_posts.publication_tasks(task_id,post_id,owner_account_id,identity_id,channel_id,latest_attempt_version) VALUES('%s','%s','%s','%s','%s',1);"%(posttask,self.post,account,self.identity,channel)]
        for table, fields in [('c_posts', [('command_tag','HNUHOLE/POST-COMMAND-KEY-COMMITMENT/V1',self.cfg['posts']['commandKeyFile']), ('fingerprint_tag','HNUHOLE/POST-FINGERPRINT-KEY-COMMITMENT/V1',self.cfg['posts']['fingerprintKeyFile'])]),
                              ('c_comments', [('command_tag','HNUHOLE/COMMENT-KEY-COMMITMENT/V1','comment-command.key'), ('fingerprint_tag','HNUHOLE/COMMENT-FINGERPRINT-COMMITMENT/V1','comment-fingerprint.key')])]:
            tags = [hmac.new((self.material/key).read_bytes(), domain.encode(), hashlib.sha256).hexdigest() for _,domain,key in fields]
            statements += ["INSERT INTO %s.protocol_keys(%s) VALUES(%s);"%(table, 'singleton_id,version,command_tag,fingerprint_tag' if table=='c_posts' else 'singleton_id,command_tag,fingerprint_tag',
                            "1,"+('1,' if table=='c_posts' else '')+"decode('%s','hex'),decode('%s','hex')"%tuple(tags))]
        self.roots = [str(uuid.uuid4()) for _ in range(500)]
        for i, root in enumerate(self.roots):
            for j, comment in enumerate([root, str(uuid.uuid4()), str(uuid.uuid4())]):
                task = str(uuid.uuid4()); target = 'NULL' if j == 0 else "'%s'"%root
                statements += ["INSERT INTO c_comments.tasks(task_id,comment_id,owner_account_id,post_id,identity_id,root_comment_id,target_comment_id) VALUES('%s','%s','%s','%s','%s',%s,%s);"%(task,comment,account,self.post,self.identity,target,target),
                               "INSERT INTO c_comments.attempts(task_id,version,state,accepted_at,accepted_stop_generation,terminal_at,body) VALUES('%s',1,'PUBLISHED',now()-interval '%d seconds',0,now()-interval '%d seconds','synthetic published comment');"%(task,1500-i*3-j,1500-i*3-j)]
        statements += ['COMMIT;']
        self.sql('\n'.join(statements))
        self.sql('ANALYZE;')
        dump(self.run/'state.private.json', {'tokens': self.tokens, 'post': self.post, 'roots': self.roots})
        self.path = '/api/v1/posts/'+self.post+'/comments?limit=50'
        self.results['dataset'] = {'mainRoots': 500, 'repliesPerRoot': 2, 'mainPages': 10, 'mainLimit': 50,
                                   'requiredAccountSnapshots': 501, 'sqlSeedWithTriggersDisabledOnlyDuringOwnedSetup': True}

    def long_read(self):
        host_initial=host_clock()
        first, _, _ = self.request('127.0.0.1', self.path, token=self.tokens[3])
        cursor = first['nextCursor']; snapshot = first['snapshotId']
        raw = base64.urlsafe_b64decode(cursor+'==')
        assert len(raw) == 78 and raw[0] == 2 and raw[1] & 3 == 2
        expires = int.from_bytes(raw[38:46], 'big')
        settings = self.cfg['comments']['snapshots']['redis']
        data_key = settings['namespace']+'data:'+settings['epoch']+':'+str(uuid.UUID(bytes=raw[18:34]))
        started = elapsed_clock(); mono_started=time.monotonic(); utc_started = time.time(); records = []
        def observe():
            before = elapsed_clock(); mono=time.monotonic(); utc = time.time()
            server = self.redis.call('TIME'); ttl = self.redis.call('PTTL', data_key)
            redis_ms = int(server[0])*1000+int(server[1])//1000
            return dict(elapsedSeconds=before-started, utcUnixMilliseconds=round(utc*1000),
                        redisUnixMilliseconds=redis_ms, pttlMilliseconds=ttl,
                        utcMonotonicDriftSeconds=(utc-utc_started)-(mono-mono_started),
                        utcRawDriftSeconds=(utc-utc_started)-(before-started),
                        monotonicRawDriftSeconds=(mono-mono_started)-(before-started))
        initial = observe()
        assert initial['pttlMilliseconds'] > 1790000
        state = dict(result='RUNNING', signedExpiryUnixMilliseconds=expires,
                     initial=initial, durationTargetSeconds=self.args.duration, reads=records,
                     elapsedClock='CLOCK_MONOTONIC_RAW',hostClockInitial=host_initial)
        dump(self.run/'long-read-progress.json',state)
        try:
            while True:
                observation = observe()
                # Both API and Redis absolute expiry are observed. Monotonic
                # duration alone never decides whether a cursor is still live.
                if max(observation['utcUnixMilliseconds'],observation['redisUnixMilliseconds']) >= expires-10000:
                    break
                page, ms, _ = self.request('127.0.0.2' if len(records)%2 else '127.0.0.1', self.path+'&cursor='+urllib.parse.quote(cursor), token=self.tokens[3])
                assert page['snapshotId'] == snapshot and len(page['comments']) == 50
                after = observe()
                assert abs((expires-after['redisUnixMilliseconds'])-after['pttlMilliseconds']) < 1000
                records.append(dict(observation,status=200,latencyMs=ms,after=after))
                dump(self.run/'long-read-progress.json',state)
                time.sleep(min(30,max(.01,(expires-10000-observation['redisUnixMilliseconds'])/1000)))
            # Require the complete real-time duration as well as both clocks
            # beyond signed expiry. Never alter clocks, TTL or product errors.
            while True:
                final = observe()
                if (final['elapsedSeconds'] >= self.args.duration and
                    min(final['utcUnixMilliseconds'],final['redisUnixMilliseconds']) > expires+1000): break
                time.sleep(min(5,max(.01,self.args.duration-final['elapsedSeconds'])))
            expired, _, _ = self.request('127.0.0.2', self.path+'&cursor='+urllib.parse.quote(cursor), token=self.tokens[3], want=400)
            assert expired['error']['code'] == 'CURSOR_INVALID'
            refreshed, _, _ = self.request('127.0.0.1', self.path, token=self.tokens[3])
            assert refreshed['snapshotId'] != snapshot
            drift=max(max(abs(x['utcRawDriftSeconds']),abs(x['monotonicRawDriftSeconds'])) for x in [initial,final]+[r['after'] for r in records])
            host_final=host_clock();host_summary=host_clock_summary(host_initial,host_final)
            if host_summary is not None and (not host_summary['stable'] or host_summary['elapsedSeconds']<1800):drift=max(drift,3)
            result=dict(state,result='PASS' if drift<=2 else 'ENVIRONMENT_UNSTABLE',
                        wallSeconds=elapsed_clock()-started,hostClockFinal=host_final,hostClockSummary=host_summary, final=final, maximumClockDriftSeconds=drift,
                        expiredCode=expired['error']['code'],explicitRefreshSucceeded=True,fixedTTLSeconds=1800)
            dump(self.run/'long-read-result.json',result)
            if result['result']!='PASS': raise RuntimeError('ENVIRONMENT_UNSTABLE: UTC/monotonic/raw/host clock stability failed')
            return result
        except BaseException as error:
            state.update(result='FAIL',error=str(error),lastObservation=observe())
            dump(self.run/'long-read-failure.json',state)
            raise

    def tests(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
            long = executor.submit(self.long_read)
            compatibility = None
            if self.args.suite == 'full':
                compatibility = executor.submit(self.cmd,
                    ['python3', self.source/'tools/comment-snapshot-process/compatibility.py',
                     '--root', self.root, '--source', self.source, '--redis', self.args.redis],
                    'acceptance-30-minute-compatibility', timeout=2100)
            self.scoped_tests()
            if self.args.suite == 'full':
                directory = self.source/'tools/comment-snapshot-process'
                common = ['--root', self.root, '--source', self.source]
                for name, extra in [('exercise', ['--capacity-only']), ('faults', ['--redis', self.args.redis]),
                                    ('admission', ['--redis', self.args.redis]), ('growth', []), ('performance', []), ('rollback', [])]:
                    self.cmd(['python3', directory/(name+'.py'), *common, *extra], 'acceptance-'+name, timeout=1500)
                self.results['acceptance'] = {name: json.loads((self.run/filename).read_text())
                    for name, filename in [('capacity', 'capacity-performance.json'), ('faults', 'api-faults.json'),
                                           ('admissionIsolation', 'api-admission-isolation.json'), ('nonceGrowth', 'nonce-growth.json'),
                                           ('performance', 'performance-final.json'), ('rollback', 'api-rollback.json')]}
                assert all(v['result'] == 'PASS' for v in self.results['acceptance'].values())
            self.results['longRead'] = long.result()
            if compatibility is not None:
                compatibility.result()
                self.results['compatibility'] = json.loads((self.root/'compatibility-summary.json').read_text())
                assert self.results['compatibility']['result'] == 'PASS'

    def scoped_tests(self):
        nonce = b64(secrets.token_bytes(16))
        a, _, _ = self.request('127.0.0.1', self.path, nonce=nonce)
        b, _, _ = self.request('127.0.0.2', self.path, nonce=nonce)
        assert a['snapshotId'] == b['snapshotId']
        page, _, _ = self.request('127.0.0.2', self.path+'&cursor='+a['nextCursor'])
        assert len(page['comments']) == 50
        self.a.terminate(); self.a.wait(timeout=20)
        self.a = self.start_api('a-restart', '127.0.0.1', int(self.cfg['internalListen'].split(':')[-1]))
        page, _, _ = self.request('127.0.0.1', self.path+'&cursor='+a['nextCursor'])
        assert page['snapshotId'] == a['snapshotId']
        self.results['crossProcessAndRestart'] = 'PASS'
        print('CROSS PROCESS AND RESTART PASS', flush=True)

    def cleanup(self):
        for p, _, _ in reversed(self.processes):
            if p.poll() is None:
                p.terminate()
        for p, stream, _ in self.processes:
            try:
                p.wait(timeout=20)
            except subprocess.TimeoutExpired:
                p.kill(); p.wait(timeout=5)
            stream.close()
        if self.started_pg:
            self.cmd(['pg_ctl', '-D', self.run/'pg', '-m', 'fast', '-w', 'stop'], 'stop-pg')
        if hasattr(self, 'socket'):
            self.socket.rmdir()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--redis', type=Path, required=True)
    parser.add_argument('--duration', type=int, default=1805)
    parser.add_argument('--suite', choices=['full', 'reading'], default='full')
    parser.add_argument('--shared-admission', choices=['official','none'], default='official')
    args = parser.parse_args()
    if args.duration < 1801:
        parser.error('actual fixed-TTL acceptance requires at least 1801 seconds')
    lab = Lab(args)
    try:
        lab.setup(); lab.tests(); lab.results['result'] = 'PASS'
    except BaseException as error:
        lab.results.update(result='FAIL', error=str(error)); raise
    finally:
        dump(lab.run/'summary.json', lab.results)
        lab.cleanup()


if __name__ == '__main__':
    main()
