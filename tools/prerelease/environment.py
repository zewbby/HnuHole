#!/usr/bin/env python3
"""Owned Linux prerelease C/V lab. No external DSN, downloads or down migrations.

All mutable state belongs to --root, which must be new for init. PostgreSQL uses
four separate clusters (source C/V and restored C/V), private sockets and SCRAM.
Only evidence.json is suitable for publication; all other state is private.
"""
import argparse
import contextlib
import hashlib
import json
import os
from pathlib import Path
import re
import selectors
import shutil
import signal
import socket
import ssl
import subprocess
import sys
import tarfile
import time
import urllib.error
import urllib.parse
import urllib.request

MARKER = 'hnuhole-android-prerelease-v1'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + '\n')
    Path(path).chmod(0o600)


def free_ports(count):
    with contextlib.ExitStack() as stack:
        sockets = [stack.enter_context(socket.socket()) for _ in range(count)]
        for sock in sockets:
            sock.bind(('127.0.0.1', 0))
        return [sock.getsockname()[1] for sock in sockets]


class Lab:
    def __init__(self, root, source):
        self.root, self.source = root, source
        self.api = source / 'services/api'
        self.env = dict(os.environ, AUTHRUNTIME_ISOLATED='1', GOTOOLCHAIN='local', GOPROXY='off')
        self.children = {}
        self.state = None
        if root.exists():
            if root.is_symlink() or root.stat().st_uid != os.getuid() or root.stat().st_mode & 0o077:
                raise RuntimeError('root must be owned, canonical and private')
            self.state = json.loads((root / 'state.private.json').read_text())
            if self.state['marker'] != MARKER or self.state['source'] != str(source):
                raise RuntimeError('ownership/source marker mismatch')

    def save(self):
        write(self.root / 'state.private.json', self.state)

    def run(self, args, name, *, env=None, input=None, cwd=None, check=True, timeout=180):
        with (self.root / (name + '.private.log')).open('ab') as log:
            result = subprocess.run(list(map(str, args)), cwd=cwd or self.api, env=env or self.env,
                                    input=input, stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
        if check and result.returncode:
            raise RuntimeError(name + ' failed (see private log)')
        return result.returncode

    def dsn(self, party, role, target=None):
        target = target or self.state['target']
        cluster = self.root / (target + '-' + party)
        params = dict(host=str(cluster / 'socket'), port=self.state['pgPorts'][target][party],
                      sslmode='disable', application_name=self.state['tag'])
        if role == 'migrator':
            params['options'] = '-c role=hnuhole_' + party + '_owner'
        return 'postgres://hnuhole_' + party + '_' + role + '@/hnuhole_' + party + '?' + urllib.parse.urlencode(params)

    def password_env(self, party, role):
        name = 'db-' + party + '-' + role + '.password'
        path = self.root / 'material' / (name if role == 'runtime' else 'operator/' + name)
        return dict(self.env, PGPASSWORD=path.read_text().strip())

    def sql(self, party, query, *, target=None, role='admin'):
        target = target or self.state['target']
        cluster = self.root / (target + '-' + party)
        if role == 'admin':
            args = ['psql', '-h', cluster / 'socket', '-p', self.state['pgPorts'][target][party],
                    '-U', 'prerelease_admin', '-d', 'hnuhole_' + party]
            env = self.env
        else:
            args, env = ['psql', self.dsn(party, role, target)], self.password_env(party, role)
        r = subprocess.run(list(map(str, args)) + ['-X', '-qAt', '-v', 'ON_ERROR_STOP=1'],
                           input=query.encode(), capture_output=True, env=env, timeout=30)
        if r.returncode:
            (self.root / 'sql-error.private.log').write_bytes(r.stderr)
            raise RuntimeError('owned SQL operation failed')
        return r.stdout.decode().strip()

    def init_cluster(self, target, party):
        cluster = self.root / (target + '-' + party)
        cluster.mkdir(mode=0o700)
        (cluster / 'socket').mkdir(mode=0o700)
        self.run(['initdb', '-D', cluster / 'data', '-U', 'prerelease_admin', '-A', 'trust',
                  '--no-locale', '-E', 'UTF8'], 'initdb-' + target + party)
        (cluster / 'data/pg_hba.conf').write_text('local all prerelease_admin trust\nlocal all all scram-sha-256\nhost all all 127.0.0.1/32 scram-sha-256\n')
        self.pg_start(target, party)
        # Bootstrap roles into this new cluster only. Passwords are never argv/logs.
        statement = 'CREATE ROLE hnuhole_' + party + '_owner NOLOGIN;\n'
        for role in ('runtime', 'migrator', 'recovery'):
            password = self.password_env(party, role)['PGPASSWORD']
            if not re.fullmatch('[0-9a-f]{64}', password):
                raise RuntimeError('unexpected password shape')
            statement += "CREATE ROLE hnuhole_%s_%s LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD '%s';\n" % (party, role, password)
        statement += ('GRANT hnuhole_{p}_owner TO hnuhole_{p}_migrator;\n'
                      'CREATE DATABASE hnuhole_{p} OWNER hnuhole_{p}_owner;\n'
                      'REVOKE ALL ON DATABASE hnuhole_{p} FROM PUBLIC;\n'
                      'GRANT CONNECT ON DATABASE hnuhole_{p} TO hnuhole_{p}_runtime,hnuhole_{p}_migrator,hnuhole_{p}_recovery;\n').format(p=party)
        if party == 'c':
            statement += 'CREATE ROLE hnuhole_business NOLOGIN;\n'
        self.run(['psql', '-X', '-v', 'ON_ERROR_STOP=1', '-h', cluster / 'socket', '-p',
                  self.state['pgPorts'][target][party], '-U', 'prerelease_admin', '-d', 'postgres'],
                 'roles-' + target + party, input=statement.encode())
        self.sql(party, 'REVOKE ALL ON SCHEMA public FROM PUBLIC;', target=target)

    def pg_start(self, target, party):
        cluster = self.root / (target + '-' + party)
        if self.run(['pg_ctl', '-D', cluster / 'data', 'status'], 'pg-status', check=False) == 0:
            return
        options = "-p %s -c listen_addresses='127.0.0.1' -c unix_socket_directories='%s' -c unix_socket_permissions=0700 -c shared_memory_type=mmap -c dynamic_shared_memory_type=mmap -c shared_buffers=16MB -c max_connections=40 -c log_statement=none -c log_min_messages=panic -c log_min_error_statement=panic -c log_error_verbosity=terse -c log_parameter_max_length=0 -c log_parameter_max_length_on_error=0" % (self.state['pgPorts'][target][party], cluster / 'socket')
        self.run(['pg_ctl', '-D', cluster / 'data', '-l', cluster / 'postgres.private.log',
                  '-w', 'start', '-o', options], 'pg-start-' + target + party)

    def build(self, source, prefix):
        for name, package in [('community', 'api'), ('verifier', 'verifier')]:
            self.run(['go', 'build', '-mod=readonly', '-o', self.root / 'bin' / (prefix + name),
                      './cmd/' + package], 'build-' + prefix + name, cwd=source / 'services/api')

    def init(self, rollback_ref):
        if self.state is not None or self.root.exists():
            raise RuntimeError('init requires a new root')
        if os.geteuid() == 0 or str(self.root).startswith('/mnt/'):
            raise RuntimeError('use non-root Linux filesystem, not a Windows mount')
        for tool in ('go', 'goose', 'initdb', 'pg_ctl', 'pg_dump', 'pg_restore', 'psql', 'mailpit', 'git'):
            if not shutil.which(tool):
                raise RuntimeError('missing prerequisite: ' + tool)
        if not re.fullmatch('[0-9a-f]{40}', rollback_ref):
            raise RuntimeError('rollback ref must be an explicit full SHA')
        sha_head = subprocess.check_output(['git', '-C', self.source, 'rev-parse', 'HEAD'], text=True).strip()
        if subprocess.check_output(['git', '-C', self.source, 'status', '--porcelain', '--untracked-files=all'], text=True).strip():
            raise RuntimeError('init requires a committed clean source checkout')
        for key in ('GOCACHE', 'GOMODCACHE', 'GOPATH'):
            path = Path(os.environ.get(key, ''))
            if not path.is_absolute() or not path.is_dir() or path.stat().st_uid != os.getuid():
                raise RuntimeError(key + ' must be an explicit owned task cache')
        self.root.mkdir(mode=0o700)
        for name in ('bin', 'probe-state', 'backup', 'rollback-source'):
            (self.root / name).mkdir(mode=0o700)
        ports = free_ports(11)
        self.state = dict(marker=MARKER, source=str(self.source), sourceSha=sha_head,
                          rollbackSha=rollback_ref, tag='hnuhole_runtime_prerelease_' + os.urandom(6).hex(),
                          ports=dict(zip(('c', 'v', 'ci', 'vi', 'smtp', 'mail'), ports[:6])),
                          pgPorts={'source': dict(zip('cv', ports[6:8])), 'restore': dict(zip('cv', ports[8:10])), 'upgrade': {'c': ports[10]}},
                          target='source', processes={})
        self.env['AUTHRUNTIME_TAG'] = self.state['tag']
        self.save()
        (self.root / 'probe-state/.runtime-tag').write_text(self.state['tag'])
        self.build(self.source, 'candidate-')
        for name in ('authdev', 'runtimeprobe'):
            self.run(['go', 'build', '-mod=readonly', '-o', self.root / 'bin' / name, './cmd/' + name], 'build-' + name)
        archive = self.root / 'rollback.tar'
        with archive.open('wb') as stream:
            subprocess.run(['git', '-C', self.source, 'archive', rollback_ref], stdout=stream, check=True)
        with tarfile.open(archive) as tar:
            for member in tar.getmembers():
                if member.issym() or member.islnk() or not (self.root / 'rollback-source' / member.name).resolve().is_relative_to(self.root / 'rollback-source'):
                    raise RuntimeError('unsafe source archive')
            tar.extractall(self.root / 'rollback-source')
        archive.unlink()
        self.build(self.root / 'rollback-source', 'rollback-')
        args = [self.root / 'bin/authdev', 'init', '-dir', self.root / 'material']
        for key, flag in [('c', 'community-port'), ('v', 'verifier-port'), ('ci', 'community-internal-port'), ('vi', 'verifier-internal-port'), ('smtp', 'smtp-port')]:
            args += ['-' + flag, self.state['ports'][key]]
        for party, flag in [('c', 'community-dsn'), ('v', 'verifier-dsn')]:
            args += ['-' + flag, self.dsn(party, 'runtime'),
                     '-recovery-dsn' if party == 'c' else '-verifier-recovery-dsn', self.dsn(party, 'recovery')]
        self.run(args, 'authdev-init')
        for party in 'cv':
            self.init_cluster('source', party)
            self.migrate(party)
        python = os.environ.get('PRERELEASE_IMAGE_PYTHON')
        if not python or not Path(python).is_file():
            raise RuntimeError('PRERELEASE_IMAGE_PYTHON must point to an independent Pillow environment')
        validator = self.root / 'validate_image.py'
        shutil.copyfile(self.api / 'media/validate_image.py', validator)
        validator.chmod(0o600)
        cpath = self.root / 'material/c.json'
        c = json.loads(cpath.read_text())
        c['postImages'] = dict(pythonFile=python, validatorFile=str(validator), validatorSHA256=sha(validator))
        write(cpath, c)
        self.audit()

    def migrate(self, party):
        directory = self.api / ('migrations' if party == 'c' else 'verifier-migrations')
        if party == 'c':
            self.run(['goose', '-dir', directory, 'postgres', self.dsn(party, 'migrator'), 'up-to', '13'], 'upgrade-c-to13', env=self.password_env(party, 'migrator'))
            before = self.sql(party, 'SELECT json_agg(x ORDER BY id) FROM public.channels x')
            snapshot = self.root / 'backup/c-schema13.dump'
            self.run(['pg_dump', '--format=custom', '--no-owner', '--no-privileges', '--file', snapshot,
                      self.dsn('c', 'migrator')], 'schema13-snapshot', env=self.password_env('c', 'migrator'))
            self.init_cluster('upgrade', 'c')
            self.run(['pg_restore', '--exit-on-error', '--no-owner', '--no-privileges', '--dbname',
                      self.dsn('c', 'migrator', 'upgrade'), snapshot], 'schema13-load-new-cluster', env=self.password_env('c', 'migrator'))
            self.run(['goose', '-dir', directory, 'postgres', self.dsn('c', 'migrator', 'upgrade'), 'up'],
                     'schema13-snapshot-upgrade', env=self.password_env('c', 'migrator'))
            self.grants('c', target='upgrade')
            if self.sql('c', 'SELECT json_agg(x ORDER BY id) FROM public.channels x', target='upgrade') != before:
                raise RuntimeError('schema13 snapshot catalog changed during restored upgrade')
            self.state['oldSnapshot'] = dict(version=13, sha256=sha(snapshot), catalogRowsPreserved=7,
                                            scope='synthetic schema13 snapshot; catalog/goose data, no historical user data')
            self.save()
        for step in ('up', 'up'):
            self.run(['goose', '-dir', directory, 'postgres', self.dsn(party, 'migrator'), step], 'goose-' + party, env=self.password_env(party, 'migrator'))
        if party == 'c' and before != self.sql(party, 'SELECT json_agg(x ORDER BY id) FROM public.channels x'):
            raise RuntimeError('13 -> latest changed existing catalog')
        self.grants(party)

    def grants(self, party, target=None):
        names = ['grant-community.sql', 'grant-post-images.sql'] if party == 'c' else ['grant-verifier.sql']
        for name in names:
            self.sql(party, (self.source / 'infra/postgres' / name).read_text(), target=target, role='migrator')

    def operator(self, command, party):
        path = self.root / 'material/operator' / ('operator.json' if party == 'c' else 'v-operator.json')
        self.run([self.root / 'bin/authdev', command, '-operator', path], command + '-' + party)

    def spawn(self, name, args):
        if name in self.state['processes']:
            raise RuntimeError('stop the owned process before starting ' + name)
        with (self.root / (name + '.private.log')).open('ab') as log:
            p = subprocess.Popen(list(map(str, args)), env=self.env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        self.children[name] = p
        token = Path('/proc/' + str(p.pid) + '/stat').read_text().split()[21]
        self.state['processes'][name] = dict(pid=p.pid, token=token)
        self.save()

    def halt(self, names=None):
        for name in list(names or self.state['processes']):
            info = self.state['processes'].get(name)
            if not info:
                continue
            proc = Path('/proc/' + str(info['pid']))
            if proc.exists():
                if proc.stat().st_uid != os.getuid() or (proc / 'stat').read_text().split()[21] != info['token']:
                    raise RuntimeError('PID ownership changed; refusing signal')
                os.kill(info['pid'], signal.SIGTERM)
                deadline = time.monotonic() + 25
                while proc.exists() and (proc / 'stat').read_text().split()[2] != 'Z':
                    if time.monotonic() > deadline:
                        raise RuntimeError('owned shutdown timed out')
                    time.sleep(.1)
            if name in self.children:
                self.children.pop(name).wait(timeout=3)
            del self.state['processes'][name]
            self.save()

    def start(self, prefix='candidate-', watches=True):
        for party in 'cv':
            self.pg_start(self.state['target'], party)
        if 'mailpit' not in self.state['processes']:
            self.spawn('mailpit', ['mailpit', '--listen', '127.0.0.1:' + str(self.state['ports']['mail']),
                                  '--smtp', '127.0.0.1:' + str(self.state['ports']['smtp']), '--database', self.root / 'mailpit.db'])
        for party, binary in [('c', 'community'), ('v', 'verifier')]:
            self.spawn(party, [self.root / 'bin' / (prefix + binary), '-config', self.root / 'material' / (party + '.json')])
            if watches:
                self.spawn('watch-' + party, [self.root / 'bin/authdev', 'watch', '-operator', self.root / 'material/operator' / ('operator.json' if party == 'c' else 'v-operator.json')])

    def health(self, want=200):
        trust = ssl.create_default_context(cafile=str(self.root / 'material/dev-ca.pem'))
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), urllib.request.HTTPSHandler(context=trust))
        for _ in range(60):
            statuses = []
            for party in 'cv':
                try:
                    with opener.open('https://127.0.0.1:' + str(self.state['ports'][party]) + '/health/ready', timeout=2) as r:
                        statuses.append(r.status)
                except urllib.error.HTTPError as e:
                    statuses.append(e.code)
                except OSError:
                    statuses.append(0)
            if statuses == [want, want]:
                return
            time.sleep(.25)
        raise RuntimeError('C/V readiness did not reach expected status ' + str(want))

    def probe(self, phase):
        ports = self.state['ports']
        env = self.password_env('c', 'runtime')
        tcp_dsn = 'postgres://hnuhole_c_runtime@127.0.0.1:' + str(self.state['pgPorts'][self.state['target']]['c']) + '/hnuhole_c?sslmode=disable&application_name=' + self.state['tag']
        env.update(AUTHRUNTIME_TAG=self.state['tag'], AUTHRUNTIME_C_DSN=tcp_dsn)
        self.run([self.root / 'bin/runtimeprobe', '-phase', phase, '-community', 'https://127.0.0.1:' + str(ports['c']),
                  '-verifier', 'https://127.0.0.1:' + str(ports['v']), '-mailpit', 'http://127.0.0.1:' + str(ports['mail']),
                  '-ca', self.root / 'material/dev-ca.pem', '-state', self.root / 'probe-state/session.json'], 'probe-' + phase, env=env)

    def audit(self):
        # Startup validates the complete runtime permission contract as well.
        for party in 'cv':
            audit = (self.api / 'authlab/privacy-role-audit.sql').read_text()
            # Preserve the existing role/table/sequence matrix, extending only
            # the explicit 0014 upload opt-in. No shared audit file is changed.
            audit = audit.replace("SET authlab.party TO :'party';", "SET authlab.party TO '" + party + "';")
            old_insert = "'attempt_contents','command_receipts','payload_cleanup'))"
            old_columns = "a.attname NOT IN ('payload','erased_at','grant_digest','grant_expires_at')"
            if audit.count(old_insert) != 1 or audit.count(old_columns) != 1:
                raise RuntimeError('upstream privacy audit changed; review image opt-in explicitly')
            audit = audit.replace(old_insert, "'attempt_contents','command_receipts','payload_cleanup','images'))")
            audit = audit.replace(old_columns, "a.attname NOT IN ('payload','erased_at','grant_digest','grant_expires_at','verified_at','display_width','display_height','frames','cycle_duration_ms','max_frame_duration_ms')")
            self.sql(party, audit)
            result = self.sql(party, (self.source / 'infra/prerelease/role-audit.sql').read_text().replace('@PARTY@', party))
            if result != 'PASS':
                raise RuntimeError('restricted-role audit failed')

    def fingerprint(self):
        result = {}
        for party in 'cv':
            tables = self.sql(party, "SELECT schemaname||'.'||tablename FROM pg_tables WHERE schemaname IN ('public','c_auth','c_posts','v_auth') ORDER BY 1").splitlines()
            for table in tables:
                if not re.fullmatch('[a-z_]+[.][a-z_]+', table):
                    raise RuntimeError('unexpected table identifier')
                result[party + ':' + table] = self.sql(party, "SELECT COALESCE(json_agg(x ORDER BY x::text),'[]') FROM (SELECT row_to_json(t) x FROM " + table + ' t) q')
        return {key: hashlib.sha256(value.encode()).hexdigest() for key, value in result.items()}

    def stop(self):
        self.halt()
        for target, parties in self.state['pgPorts'].items():
            for party in parties:
                data = self.root / (target + '-' + party) / 'data'
                if data.exists():
                    if self.run(['pg_ctl', '-D', data, 'status'], 'pg-stop-status', check=False) == 0:
                        self.run(['pg_ctl', '-D', data, '-m', 'fast', '-w', 'stop'], 'pg-stop-' + target + party)

    def quiesce(self):
        # Stop between Gate commits, as in the existing actual-runtime runner.
        locks = []
        try:
            for party in 'cv':
                lock = subprocess.Popen(['psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', self.dsn(party, 'migrator')],
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                        text=True, env=self.password_env(party, 'migrator'))
                locks.append(lock)
                lock.stdin.write('BEGIN; SELECT singleton_id FROM ' + party + '_auth.authorization_gate FOR UPDATE;\n')
                lock.stdin.flush()
                with selectors.DefaultSelector() as selector:
                    selector.register(lock.stdout, selectors.EVENT_READ)
                    if not selector.select(15) or lock.stdout.readline().strip() != '1':
                        raise RuntimeError('Gate quiescence timed out')
            self.halt(['c', 'v', 'watch-c', 'watch-v'])
        finally:
            for lock in locks:
                if lock.poll() is None:
                    lock.stdin.write('ROLLBACK;\n\\q\n')
                    lock.stdin.flush()
                    lock.communicate(timeout=10)

    def rehearse(self):
        evidence = dict(sourceSha=self.state['sourceSha'], rollbackSha=self.state['rollbackSha'],
                        scope='same-machine isolated development; not independent production operations',
                        result='FAIL', checks=[], oldSnapshot=self.state['oldSnapshot'], device='NOT_RUN', ios='DEFERRED', crossDevicePasskey='DEFERRED')
        def passed(name):
            evidence['checks'].append(name)
            write(self.root / 'evidence.json', evidence)
            print(name + ' PASS', flush=True)
        try:
            self.start(watches=False)
            self.health(503)
            passed('new-instance-startup-remains-frozen')
            for party in 'cv':
                self.operator('recover', party)
            self.health()
            self.probe('lifecycle')
            self.probe('identities')
            self.probe('posts')
            self.probe('images')
            passed('actual-https-registration-login-catalog-text-image-and-denials')
            # Explicit freeze before stopping writers avoids inventing a clean
            # gate after an interrupted anchor/SQL authorization commit.
            for party in 'cv':
                self.operator('freeze', party)
            self.health(503)
            self.probe('frozen')
            passed('gate-closed-denies-protected-reads')
            self.halt(['c', 'v'])
            before = self.fingerprint()
            evidence['backupSha256'] = {}
            for party in 'cv':
                self.run(['pg_dump', '--format=custom', '--no-owner', '--no-privileges', '--file', self.root / 'backup' / (party + '.dump'), self.dsn(party, 'migrator')], 'backup-' + party, env=self.password_env(party, 'migrator'))
                evidence['backupSha256'][party] = sha(self.root / 'backup' / (party + '.dump'))
                self.init_cluster('restore', party)
                self.run(['pg_restore', '--exit-on-error', '--no-owner', '--no-privileges', '--dbname', self.dsn(party, 'migrator', 'restore'), self.root / 'backup' / (party + '.dump')], 'restore-' + party, env=self.password_env(party, 'migrator'))
            self.state['target'] = 'restore'
            self.save()
            for party in 'cv':
                self.grants(party)
                path = self.root / 'material' / (party + '.json')
                config = json.loads(path.read_text())
                config['databaseUrl'] = self.dsn(party, 'runtime')
                write(path, config)
                opath = self.root / 'material/operator' / ('operator.json' if party == 'c' else 'v-operator.json')
                op = json.loads(opath.read_text())
                op['recoveryDatabaseUrl'] = self.dsn(party, 'recovery')
                write(opath, op)
            self.audit()
            if before != self.fingerprint():
                raise RuntimeError('restored schema/data fingerprint mismatch')
            evidence['restoredFingerprints'] = before
            passed('backup-restored-to-two-new-instances-data-and-permissions-match')
            for party in 'cv':
                self.operator('recover', party)
            self.start()
            self.health()
            self.probe('recovered')
            self.probe('images-restart')
            passed('restore-old-session-rejected-fresh-login-reads-original-text-and-image')
            # Failed deployment uses actual candidate startup with a wrong
            # validator fingerprint; it must fail before accepting traffic.
            self.quiesce()
            path = self.root / 'material/c.json'
            bad = json.loads(path.read_text())
            bad['postImages']['validatorSHA256'] = '0' * 64
            write(self.root / 'material/c-failed.json', bad)
            code = self.run([self.root / 'bin/candidate-community', '-config', self.root / 'material/c-failed.json'], 'failed-deployment', check=False, timeout=25)
            if code == 0:
                raise RuntimeError('invalid candidate deployment unexpectedly accepted')
            passed('failed-candidate-startup-rejected')
            self.start(prefix='rollback-')
            self.health()
            self.probe('images-restart')
            passed('previous-main-binaries-run-on-current-restored-schema')
            self.quiesce()
            self.start()
            self.health()
            self.probe('images-restart')
            passed('candidate-redeploy-after-application-rollback')
            evidence['binarySha256'] = {p.name: sha(p) for p in (self.root / 'bin').iterdir()}
            evidence['result'] = 'PASS'
        finally:
            self.stop()
            write(self.root / 'evidence.json', evidence)


def main():
    os.umask(0o077)
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root', type=Path, required=True)
    p.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[2])
    p.add_argument('command', choices=['init', 'start', 'health', 'stop', 'recover', 'rehearse'])
    p.add_argument('--rollback-sha')
    a = p.parse_args()
    if not a.root.is_absolute() or a.root != a.root.resolve() or not re.fullmatch(r'[A-Za-z0-9_/.-]+', str(a.root)):
        p.error('root must be an absolute canonical Linux path without spaces')
    lab = Lab(a.root, a.source.resolve())
    if a.command == 'init':
        try:
            lab.init(a.rollback_sha or '')
        except Exception:
            if lab.state:
                lab.stop()
            raise
    elif lab.state is None:
        p.error('initialize a new owned root first')
    elif a.command == 'recover':
        for party in 'cv':
            lab.operator('recover', party)
    else:
        getattr(lab, a.command)()


if __name__ == '__main__':
    main()
