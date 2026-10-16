#!/usr/bin/env python3
"""Prepare/restart the owned image-business lab; never invokes ADB or devices."""
import argparse
import base64
import contextlib
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import signal
import socketserver
import ssl
import sys
import threading
import urllib.error
import urllib.request

spec = importlib.util.spec_from_file_location('post_joint', Path(__file__).parents[1] / 'post-media-joint/run.py')
joint = importlib.util.module_from_spec(spec)
spec.loader.exec_module(joint)
OWNER = 'post-image-integration-20261015|'


def owned(root):
    root = Path(root)
    if (os.geteuid() == 0 or root.resolve() != root or root.is_symlink()
            or not str(root).startswith('/home/hnuhole/post-media-joint-android-')
            or root.stat().st_uid != os.getuid() or root.stat().st_mode & 0o077
            or not (root / '.owner').read_text().startswith(OWNER)):
        raise ValueError('Canonical private Android lab owned by this user required')
    return root


class DeviceLab(joint.Lab):
    def cmd(self, args, name, **kwargs):
        if name == 'joint-pub':
            # No Linux Flutter copy is required for the persistent native lab.
            # The separate Windows build verifies the same Dart lock and source.
            self.results[name] = {'result': 'NOT_RUN', 'reason': 'Native client built by isolated Windows runner'}
            return
        return super().cmd(args, name, **kwargs)

    def save_state(self):
        smtp = next(server.server_address[1] for server in self.servers
                    if not isinstance(server, joint.http.server.HTTPServer))
        config = json.loads(self.config.read_text())
        state = {'run': str(self.run), 'logs': str(self.logs), 'pgport': self.pgport,
                 'cport': self.cport, 'vport': self.vport, 'ci': self.ci, 'vi': self.vi,
                 'smtp': smtp, 'control': joint.urllib.parse.urlsplit(config['controlOrigin']).port,
                 'token': self.token, 'source': self.source_before, 'status': 'STOPPED',
                 'sourceDirectory': str(self.source), 'preparedResults': self.results}
        joint.dump(self.root / 'device-state.private.json', state)
        return state

    @classmethod
    def restore(cls, root):
        state = json.loads((root / 'device-state.private.json').read_text())
        lab = cls(root)
        # Base construction only created two empty, owned scratch directories.
        lab.run.rmdir()
        lab.logs.rmdir()
        run, logs = Path(state['run']), Path(state['logs'])
        if (run.parent != root or not joint.re.fullmatch('run-[a-f0-9]{8}', run.name)
                or logs != root / 'logs' / run.name or run.resolve() != run or logs.resolve() != logs):
            raise ValueError('Stored lab path escaped owner scope')
        if joint.inputs(lab.source) != state['source']:
            raise ValueError('Prepared source changed; rebuild and revalidate before device use')
        lab.run, lab.logs = run, logs
        joint.dump(root/'logs/latest-run.json', {'run': str(run), 'logs': str(logs)})
        for key in ['pgport', 'cport', 'vport', 'ci', 'vi', 'token']:
            setattr(lab, key, state[key])
        lab.material = run / 'material'
        lab.validator = run / 'validate_image.py'
        lab.validator_bytes = (lab.source/'services/api/media/validate_image.py').read_bytes()
        if lab.validator.read_bytes() != lab.validator_bytes:
            raise ValueError('Prepared validator drifted; inspect before restoring')
        lab.config = run / 'client-config.json'
        lab.trust = ssl.create_default_context(cafile=str(lab.material/'dev-ca.pem'))
        return lab

    def resume(self, recover_empty=False):
        lab, root, run = self, self.root, self.run
        state = json.loads((root / 'device-state.private.json').read_text())
        options = ("-p %d -c listen_addresses='' -c unix_socket_directories='%s' -c unix_socket_permissions=0700 "
                   "-c shared_memory_type=mmap -c dynamic_shared_memory_type=mmap -c shared_buffers=16MB -c max_connections=40 "
                   "-c log_statement=none -c log_min_messages=panic -c log_min_error_statement=panic "
                   "-c log_error_verbosity=terse -c log_parameter_max_length=0 -c log_parameter_max_length_on_error=0 "
                   "-c log_min_duration_statement=-1 -c log_min_duration_sample=-1 -c log_transaction_sample_rate=0 -c log_duration=off") % (self.pgport, run/'socket')
        self.cmd(['pg_ctl', '-D', run/'pg', '-l', run/'postgres.private.log', '-w', 'start', '-o', options], 'android-resume-pg')
        self.started_pg = True
        if recover_empty:
            counts = [int(self.sql('SELECT count(*) FROM c_auth.accounts;')),
                      int(self.sql('SELECT count(*) FROM v_auth.otp_flows;', db='hnuhole_v')),
                      int(self.sql('SELECT count(*) FROM c_posts.posts;'))]
            if any(counts):
                raise ValueError('Explicit empty-lab recovery refused: accounts/OTP/posts exist; inspect existing result and follow normal Gate recovery/login contract')
        tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        tls.load_cert_chain(lab.material/'c-public.pem', lab.material/'c-public.key')
        for port, control in [(state['cport'], False), (state['control'], True)]:
            server = joint.http.server.ThreadingHTTPServer(('127.0.0.1', port), joint.Handler)
            server.daemon_threads = True
            server.lab, server.control = lab, control
            server.socket = tls.wrap_socket(server.socket, server_side=True)
            lab.servers.append(server)
            threading.Thread(target=server.serve_forever, daemon=True).start()
        server = socketserver.ThreadingTCPServer(('127.0.0.1', state['smtp']), joint.SMTP)
        server.daemon_threads, server.lab = True, lab
        lab.servers.append(server)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        for party in ['c', 'v']:
            operator = lab.material/'operator'/('operator.json' if party == 'c' else 'v-operator.json')
            # Recovery is explicit and accepted only for the unused baseline.
            # Populated labs never silently rotate generation on restart.
            action = 'recover' if recover_empty else 'issue'
            lab.cmd([root/'bin/authdev', action, '-operator', operator], 'android-'+action+'-'+party)
            lab.spawn([root/'bin/authdev', 'watch', '-operator', operator], 'watch-'+party)
        lab.spawn([root/'bin/community', '-config', lab.material/'c.json'], 'community')
        lab.spawn([root/'bin/verifier', '-config', lab.material/'v.json'], 'verifier')

    def preflight(self, empty=False):
        def ready():
            try:
                for port in [self.cport, self.vport]:
                    with urllib.request.urlopen('https://127.0.0.1:'+str(port)+'/health/ready',
                                                context=self.trust, timeout=2) as response:
                        if response.status != 200:
                            return False
                return True
            except OSError:
                return False
        joint.wait(ready, 'real Android-lab C/V readiness')
        counts = json.loads(self.sql("SELECT json_build_object('accounts',(SELECT count(*) FROM c_auth.accounts),"
                                    "'posts',(SELECT count(*) FROM c_posts.posts),'images',(SELECT count(*) FROM c_posts.images));"))
        if empty and counts != {'accounts': 0, 'posts': 0, 'images': 0}:
            raise ValueError('Device baseline is not empty; do not reset an existing lab')
        try:
            urllib.request.urlopen('https://127.0.0.1:'+str(self.cport)+'/health/ready', timeout=2)
        except urllib.error.URLError as error:
            if not isinstance(error.reason, ssl.SSLCertVerificationError):
                raise
            untrusted_rejected = True
        else:
            raise ValueError('Private CA unexpectedly trusted by default')
        control = json.loads(self.config.read_text())['controlOrigin']
        try:
            urllib.request.urlopen(urllib.request.Request(control+'/stats', data=b'{}'),
                                   context=self.trust, timeout=2)
        except urllib.error.HTTPError as error:
            if error.code != 403:
                raise
        else:
            raise ValueError('Lab control admitted unauthenticated request')
        value = {'result': 'PASS', 'realCAndVReady': True, 'privateCaRequired': untrusted_rejected,
                 'controlRequiresPrivateToken': True, 'sql': counts, 'schemaC': 14, 'schemaV': 4,
                 'sourceStable': joint.inputs(self.source) == self.source_before,
                 'nativePicker': 'NOT_RUN', 'nativeVault': 'NOT_RUN', 'gallery': 'NOT_RUN',
                 'phoneOrAdbUsed': False, 'otherServicesTouched': False}
        joint.dump(self.logs/'android-preflight.json', value)
        return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['prepare', 'rehearse', 'serve', 'control'])
    parser.add_argument('--root', required=True)
    parser.add_argument('--output', help='Owned Windows kit private directory, for public build defines only')
    parser.add_argument('--input', help='Private JSON with action/body for the already running lab')
    parser.add_argument('--recover-empty', action='store_true', help='Explicit signed recovery; refuses nonempty accounts/OTP/posts')
    args = parser.parse_args()
    root = owned(args.root)
    os.umask(0o077)
    if args.action == 'control':
        config = json.loads((root/'device-state.private.json').read_text())
        request_data = json.loads(Path(args.input).read_text())
        context = ssl.create_default_context(cafile=str(Path(config['run'])/'material/dev-ca.pem'))
        request = urllib.request.Request('https://127.0.0.1:'+str(config['control'])+request_data['action'],
                                         data=json.dumps(request_data.get('body', {})).encode(),
                                         headers={'Authorization': 'LabControl '+config['token'], 'Content-Type': 'application/json'})
        with urllib.request.urlopen(request, context=context, timeout=40) as response:
            sys.stdout.buffer.write(response.read(65536))
        return
    with (root/'device-lab.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        lab = None
        try:
            if args.action == 'prepare':
                if (root/'device-state.private.json').exists():
                    raise ValueError('Prepared kit already exists; never reset or overwrite it')
                lab = DeviceLab(root)
                lab.setup()
                lab.preflight(empty=True)
                state = lab.save_state()
            else:
                lab = DeviceLab.restore(root)
                lab.resume(recover_empty=args.recover_empty)
                state = json.loads((root/'device-state.private.json').read_text())
                lab.preflight(empty=args.action == 'rehearse')
            if args.output:
                output = Path(args.output)
                if output.resolve() != output or output.name != 'private' or not (output.parent/'.owner').read_text().startswith('HNUHOLE_POST_MEDIA_ANDROID_V1|'):
                    raise ValueError('Owned Windows kit private directory required')
                ca = (lab.material/'dev-ca.pem').read_bytes()
                # Only public origins/CA cross to NTFS; POSIX chmod is not an
                # ACL guarantee on this mount, and no lab token/key is exported.
                (output/'build-defines.json').write_text(json.dumps({
                    'AUTH_COMMUNITY_BASE_URL': 'https://127.0.0.1:'+str(lab.cport),
                    'AUTH_VERIFIER_BASE_URL': 'https://127.0.0.1:'+str(lab.vport),
                    'AUTH_DEV_CA_BASE64': base64.b64encode(ca).decode(),
                }, indent=2)+'\n')
                for name in ['dev-ca.pem', 'c-public.pem', 'v-public.pem']:
                    (output/name).write_bytes((lab.material/name).read_bytes())
            if args.action == 'serve':
                stop = threading.Event()
                for signum in [signal.SIGINT, signal.SIGTERM]:
                    signal.signal(signum, lambda *_: stop.set())
                print('Owned lab ready; no device commands. Ctrl-C stops only its processes.', flush=True)
                while not stop.wait(1):
                    if any(process.poll() is not None for process, _, _ in lab.processes):
                        raise RuntimeError('Owned child exited; stop and inspect private logs')
            print('ANDROID LAB '+args.action.upper()+' PASS (device NOT_RUN)', flush=True)
        finally:
            if lab is not None:
                lab.cleanup()


if __name__ == '__main__':
    main()
