#!/usr/bin/env python3
"""Owned Linux prerelease C/V lab. No external DSN, downloads or down migrations.

All mutable state belongs to --root, which must be new for init. PostgreSQL uses
five separate clusters (source C/V, restored C/V, schema13 upgrade C), private sockets and SCRAM.
Only evidence.json is suitable for publication; all other state is private.
"""
import argparse
import contextlib
from datetime import datetime, timezone
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
        started = datetime.now(timezone.utc).isoformat()
        with (self.root / (name + '.private.log')).open('ab') as log:
            result = subprocess.run(list(map(str, args)), cwd=cwd or self.api, env=env or self.env,
                                    input=input, stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
        if self.state is not None:
            self.state.setdefault('commands', []).append(dict(name=name, exitCode=result.returncode, startedAtUtc=started,
                                                             endedAtUtc=datetime.now(timezone.utc).isoformat()))
            self.save()
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
        return 'postgres://hnuhole_' + party + '_' + role + '@/hnuhole_' + party + '?' + urllib.parse.urlencode(params, quote_via=urllib.parse.quote)

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
            members = [m for m in tar.getmembers() if m.name.startswith('services/api/')]
            for member in members:
                if member.issym() or member.islnk() or not (self.root / 'rollback-source' / member.name).resolve().is_relative_to(self.root / 'rollback-source'):
                    raise RuntimeError('unsafe source archive')
            tar.extractall(self.root / 'rollback-source', members=members)
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
        versions = {}
        for name, command in [('go', ['go', 'version']), ('goose', ['goose', '-version']),
                              ('postgres', ['postgres', '--version']), ('mailpit', ['mailpit', 'version']),
                              ('pillow', [python, '-c', 'import PIL; print(PIL.__version__)'])]:
            versions[name] = subprocess.check_output(command, env=self.env, stderr=subprocess.STDOUT, text=True).strip()
        if 'v3.22.1' not in versions['goose'] or not versions['pillow'].endswith('12.3.0') or ' 16.' not in versions['postgres']:
            raise RuntimeError('requires Goose3.22.1, PG16 and Pillow12.3.0')
        self.state['toolVersions'] = versions
        self.state['migrationSha256'] = {str(path.relative_to(self.api)): sha(path) for directory in ('migrations', 'verifier-migrations') for path in (self.api / directory).glob('*.sql')}
        self.save()
        validator = self.root / 'validate_image.py'
        shutil.copyfile(self.api / 'media/validate_image.py', validator)
        validator.chmod(0o600)
        cpath = self.root / 'material/c.json'
        c = json.loads(cpath.read_text())
        c['postImages'] = dict(pythonFile=python, validatorFile=str(validator), validatorSHA256=sha(validator))
        c['moderation'] = True  # Existing main 0015 only; no administrator bootstrap.
        write(cpath, c)
        self.audit()
        self.sql('c', 'GRANT UPDATE(digest) ON c_posts.images TO hnuhole_c_runtime')
        try:
            try:
                self.audit()
            except RuntimeError:
                log = (self.root / 'sql-error.private.log').read_text()
                if 'operational role acquired noncontract table privilege' not in log:
                    raise
            else:
                raise RuntimeError('image audit accepted extra immutable-column UPDATE')
        finally:
            self.sql('c', 'REVOKE UPDATE(digest) ON c_posts.images FROM hnuhole_c_runtime')
        self.audit()
        self.sql('c', 'GRANT UPDATE(evidence) ON c_moderation.cases TO hnuhole_c_runtime')
        try:
            try:
                self.audit()
            except RuntimeError:
                if 'moderation column privilege mismatch' not in (self.root / 'sql-error.private.log').read_text():
                    raise
            else:
                raise RuntimeError('moderation audit accepted immutable evidence UPDATE')
        finally:
            self.sql('c', 'REVOKE UPDATE(evidence) ON c_moderation.cases FROM hnuhole_c_runtime')
        self.audit()
        self.sql('c', 'REVOKE INSERT ON c_posts.images FROM hnuhole_c_runtime')
        try:
            code = self.run([self.root / 'bin/candidate-community', '-config', cpath], 'missing-image-insert', check=False, timeout=25)
            if code == 0 or 'stage=runtime reason=failed' not in (self.root / 'missing-image-insert.private.log').read_text():
                raise RuntimeError('missing image upload permission was not rejected at runtime startup')
        finally:
            self.grants('c')
        self.audit()
        self.state['initChecks'] = ['fresh-formal-migrations-and-schema13-snapshot-upgrade',
                                    'restricted-role-matrix-rejects-immutable-image-column-update',
                                    'restricted-role-matrix-rejects-moderation-evidence-column-update',
                                    'actual-startup-rejects-missing-image-insert-permission']
        self.save()

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
        names = ['grant-community.sql', 'grant-post-images.sql', 'grant-moderation.sql'] if party == 'c' else ['grant-verifier.sql']
        for name in names:
            if name == 'grant-moderation.sql':
                # --no-privileges restore omits migration ACLs, including its
                # PUBLIC function EXECUTE revocation. Re-establish the same
                # deny baseline before applying the canonical opt-in grants.
                self.sql(party, (self.source / 'infra/prerelease/reset-moderation-grants.sql').read_text(), target=target, role='migrator')
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
        # Refresh and verify both OPEN checkpoints before either API accepts
        # traffic. No automatic recovery: a frozen/restored Gate needs review.
        if watches:
            for party in 'cv':
                self.operator('resume', party)
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
            # the explicit 0014 upload opt-in. The exact 0015 matrix is checked
            # separately below, including every column/function/sequence. No
            # shared audit or business migration file is changed.
            audit = audit.replace("SET authlab.party TO :'party';", "SET authlab.party TO '" + party + "';")
            old_insert = "'attempt_contents','command_receipts','payload_cleanup'))"
            old_columns = "a.attname NOT IN ('payload','erased_at','grant_digest','grant_expires_at')"
            if audit.count(old_insert) != 2 or audit.count(old_columns) != 1:
                raise RuntimeError('upstream privacy audit changed; review image opt-in explicitly')
            audit = audit.replace(old_insert, "'attempt_contents','command_receipts','payload_cleanup','images'))", 1)
            audit = audit.replace(old_columns, "a.attname NOT IN ('payload','erased_at','grant_digest','grant_expires_at','verified_at','display_width','display_height','frames','cycle_duration_ms','max_frame_duration_ms')")
            table_selector = "AND c.relkind IN ('r','p','v','m','f')"
            sequence_selector = "WHERE n.nspname NOT LIKE 'pg_%' AND c.relkind='S'"
            if audit.count(table_selector) != 1 or audit.count(sequence_selector) != 1:
                raise RuntimeError('upstream privacy audit selectors changed; review explicit moderation matrix')
            if party == 'c':
                audit = audit.replace(table_selector, table_selector + " AND n.nspname<>'c_moderation'")
                audit = audit.replace(sequence_selector, sequence_selector + " AND n.nspname<>'c_moderation'")
            elif self.sql(party, "SELECT to_regnamespace('c_moderation') IS NOT NULL") != 'f':
                raise RuntimeError('moderation schema must not exist in V')
            self.sql(party, audit)
            if party == 'c':
                self.sql(party, (self.source / 'infra/prerelease/moderation-role-audit.sql').read_text())
            result = self.sql(party, (self.source / 'infra/prerelease/role-audit.sql').read_text().replace('@PARTY@', party))
            if result != 'PASS':
                raise RuntimeError('restricted-role audit failed')

    def fingerprint(self):
        result = {}
        for party in 'cv':
            tables = self.sql(party, "SELECT schemaname||'.'||tablename FROM pg_tables WHERE schemaname NOT LIKE 'pg_%' AND schemaname<>'information_schema' ORDER BY 1").splitlines()
            for table in tables:
                if not re.fullmatch('[a-z_]+[.][a-z_]+', table):
                    raise RuntimeError('unexpected table identifier')
                result[party + ':' + table] = self.sql(party, "SELECT COALESCE(json_agg(x ORDER BY x::text),'[]') FROM (SELECT row_to_json(t) x FROM " + table + ' t) q')
            sequences = self.sql(party, "SELECT schemaname||'.'||sequencename FROM pg_sequences WHERE schemaname NOT LIKE 'pg_%' AND schemaname<>'information_schema' ORDER BY 1").splitlines()
            for sequence in sequences:
                if not re.fullmatch('[a-z_]+[.][a-z_]+', sequence):
                    raise RuntimeError('unexpected sequence identifier')
                result[party + ':' + sequence] = self.sql(party, 'SELECT last_value,is_called FROM ' + sequence)
        return {key: hashlib.sha256(value.encode()).hexdigest() for key, value in result.items()}

    def stop(self):
        failures = []
        if any(party in self.state['processes'] for party in 'cv'):
            try:
                self.quiesce()
            except Exception as error:
                failures.append(str(error))
        for name in list(self.state['processes']):
            try:
                self.halt([name])
            except Exception as error:
                failures.append(str(error))
        for target, parties in self.state['pgPorts'].items():
            for party in parties:
                data = self.root / (target + '-' + party) / 'data'
                if data.exists():
                    try:
                        status = self.run(['pg_ctl', '-D', data, 'status'], 'pg-stop-status', check=False)
                        if status == 0:
                            self.run(['pg_ctl', '-D', data, '-m', 'fast', '-w', 'stop'], 'pg-stop-' + target + party)
                            status = self.run(['pg_ctl', '-D', data, 'status'], 'pg-stopped-status', check=False)
                        if status != 3:
                            raise RuntimeError('could not prove owned PostgreSQL stopped')
                    except Exception as error:
                        failures.append(str(error))
        if failures:
            raise RuntimeError('owned cleanup failed: ' + '; '.join(failures))

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
                    try:
                        lock.stdin.write('ROLLBACK;\n\\q\n')
                        lock.stdin.flush()
                        lock.communicate(timeout=10)
                    except (OSError, subprocess.TimeoutExpired):
                        lock.terminate()
                        try:
                            lock.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            lock.kill()
                            lock.wait(timeout=5)

    def rehearse(self):
        evidence = dict(sourceSha=self.state['sourceSha'], rollbackSha=self.state['rollbackSha'],
                        scope='same-machine isolated development; not independent production operations',
                        result='FAIL', checks=list(self.state['initChecks']), oldSnapshot=self.state['oldSnapshot'], toolVersions=self.state['toolVersions'],
                        migrationSha256=self.state['migrationSha256'], device='NOT_RUN', ios='DEFERRED', crossDevicePasskey='DEFERRED')
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
            self.probe('moderation')
            passed('existing-main-report-and-read-notification-facts-created-over-https')
            self.quiesce()
            before_restart = {party: self.sql(party, 'SELECT authorization_generation FROM ' + party + '_auth.authorization_gate') for party in 'cv'}
            before_recoveries = {party: self.sql(party, "SELECT count(*) FROM " + party + "_auth.authorization_gate_audit WHERE event_kind='RECOVER'") for party in 'cv'}
            for party in 'cv':
                opath = self.root / 'material/operator' / ('operator.json' if party == 'c' else 'v-operator.json')
                self.run([self.root / 'bin/authdev', 'issue', '-operator', opath, '-valid-for', '1s'], 'short-evidence-' + party)
            time.sleep(2)
            # start() must resume before listeners, while watch also renews
            # immediately. The saved bearer and account facts stay unchanged.
            self.start()
            self.health()
            self.probe('restart')
            self.probe('images-restart')
            for party in 'cv':
                if self.sql(party, 'SELECT authorization_generation FROM ' + party + '_auth.authorization_gate') != before_restart[party] or self.sql(party, "SELECT count(*) FROM " + party + "_auth.authorization_gate_audit WHERE event_kind='RECOVER'") != before_recoveries[party]:
                    raise RuntimeError('ordinary restart rotated authority or invoked recovery')
            passed('offline-expired-evidence-resume-preserves-original-https-session-and-generation')
            # Test raw checkpoint mismatch before any API probe can turn it
            # into an already-frozen row. This is this lab's disposable V only.
            self.quiesce()
            self.sql('v', 'UPDATE v_auth.authorization_gate SET evidence_version=evidence_version-1', role='migrator')
            opath = self.root / 'material/operator/v-operator.json'
            if self.run([self.root / 'bin/authdev', 'resume', '-operator', opath], 'resume-mismatch-negative-v', check=False) == 0:
                raise RuntimeError('ordinary resume accepted mismatched independent checkpoint')
            passed('ordinary-resume-refuses-direct-independent-checkpoint-mismatch')
            # Explicit freeze before stopping writers avoids inventing a clean
            # gate after an interrupted anchor/SQL authorization commit.
            for party in 'cv':
                self.operator('freeze', party)
            self.start(watches=False)
            self.health(503)
            self.probe('frozen')
            passed('gate-closed-denies-protected-reads')
            for party in 'cv':
                opath = self.root / 'material/operator' / ('operator.json' if party == 'c' else 'v-operator.json')
                if self.run([self.root / 'bin/authdev', 'resume', '-operator', opath], 'resume-frozen-negative-' + party, check=False) == 0:
                    raise RuntimeError('ordinary resume reopened frozen Gate')
            passed('ordinary-resume-refuses-frozen-checkpoint-without-recovery')
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
            self.probe('moderation-restart')
            passed('restore-old-session-rejected-fresh-login-reads-original-text-and-image')
            # Failed deployment uses actual candidate startup with a wrong
            # validator fingerprint; it must fail before accepting traffic.
            self.quiesce()
            path = self.root / 'material/c.json'
            bad = json.loads(path.read_text())
            bad['postImages']['validatorSHA256'] = '0' * 64
            write(self.root / 'material/c-failed.json', bad)
            code = self.run([self.root / 'bin/candidate-community', '-config', self.root / 'material/c-failed.json'], 'failed-deployment', check=False, timeout=25)
            if code == 0 or 'stage=runtime reason=failed' not in (self.root / 'failed-deployment.private.log').read_text():
                raise RuntimeError('invalid candidate deployment unexpectedly accepted')
            passed('failed-candidate-startup-rejected')
            self.start(prefix='rollback-')
            self.health()
            self.probe('images-restart')
            self.probe('moderation-restart')
            passed('previous-main-binaries-run-on-current-restored-schema')
            self.quiesce()
            self.start()
            self.health()
            self.probe('images-restart')
            self.probe('moderation-restart')
            passed('candidate-redeploy-after-application-rollback')
            evidence['binarySha256'] = {p.name: sha(p) for p in (self.root / 'bin').iterdir()}
            evidence['result'] = 'PASS'
        finally:
            cleanup_error = None
            try:
                self.stop()
                evidence['cleanup'] = 'PASS: owned processes and all five PostgreSQL instances stopped; private material retained'
            except Exception as error:
                cleanup_error = error
                evidence['result'] = 'FAIL'
                evidence['cleanup'] = 'FAIL: could not prove every owned process stopped'
            evidence['commands'] = self.state['commands']
            evidence['privateLogSha256'] = {p.name: sha(p) for p in self.root.glob('*.private.log')}
            write(self.root / 'evidence.json', evidence)
            if cleanup_error:
                raise cleanup_error


def main():
    os.umask(0o077)
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root', type=Path, required=True)
    p.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[2])
    p.add_argument('command', choices=['init', 'start', 'resume', 'health', 'stop', 'recover', 'rehearse'])
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
        lab.halt(['watch-c', 'watch-v'])
        for party in 'cv':
            lab.operator('recover', party)
            lab.spawn('watch-' + party, [lab.root / 'bin/authdev', 'watch', '-operator', lab.root / 'material/operator' / ('operator.json' if party == 'c' else 'v-operator.json')])
    elif a.command == 'resume':
        lab.start()
    elif a.command == 'start':
        lab.start(watches=False)
    else:
        getattr(lab, a.command)()


if __name__ == '__main__':
    main()
