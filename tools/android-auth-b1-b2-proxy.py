#!/usr/bin/env python3
"""Separate owned B1/B2 passthrough. Counts only; bodies/proofs never logged."""
import hashlib
import http.client
import http.server
import json
import os
import re
from pathlib import Path
import socket
import ssl
import threading
from urllib.parse import urlsplit

ROOT = Path('/var/tmp/hnuhole-android-live-batch-20261007')


def main():
    assert ROOT.resolve() == ROOT and not ROOT.is_symlink()
    assert (ROOT / 'OWNER').read_text().strip() == 'HNUHOLE_ANDROID_LIVE_DEV_V1'
    prior_pid = ROOT / 'b1b2-proxy.pid'
    if prior_pid.exists():
        assert not Path('/proc', str(int(prior_pid.read_text())), 'cmdline').exists(), \
            'Preserve an existing process; resume only after it has exited'
    material = ROOT / 'services/material'
    config = json.loads((ROOT / 'device-config.json').read_text())
    service = json.loads((material / 'c.json').read_text())
    origin = urlsplit(config['AUTH_COMMUNITY_BASE_URL'])
    assert origin.scheme == 'https' and origin.hostname == '127.0.0.1' and origin.port >= 1024
    server_tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    server_tls.load_cert_chain(material / service['publicCertificateFile'], material / service['publicKeyFile'])
    client_tls = ssl.create_default_context(cafile=str(material / 'dev-ca.pem'))
    mode_file = ROOT / 'b1b2-proxy-mode.json'
    mode_file.write_text('{"mode":"normal"}\n')
    metrics = ROOT / 'b1b2-proxy-metrics.json'
    lock = threading.Lock()
    counts = {'bindingSubmits': 0, 'rotationSubmits': 0, 'resultQueries': 0,
              'resetOptionRequests': 0, 'resetIntentSubmits': 0,
              'droppedRotationReplies': 0, 'lastBindingStatus': 0,
              'lastResetOptionStatus': 0, 'proofsStored': False}
    retained_config = ROOT / 'b1b2-device-config.json'
    port = 0
    if retained_config.exists():
        previous = json.loads(retained_config.read_text())
        endpoint = urlsplit(previous['AUTH_COMMUNITY_BASE_URL'])
        assert endpoint.scheme == 'https' and endpoint.hostname == '127.0.0.1'
        assert endpoint.port is not None and endpoint.port >= 1024
        assert previous['AUTH_MATRIX_ACCOUNT_RUN_ID'] == ROOT.name
        port = endpoint.port
        retained_counts = json.loads(metrics.read_text())
        assert retained_counts.keys() == counts.keys() and retained_counts['proofsStored'] is False
        assert all(type(retained_counts[k]) is int and retained_counts[k] >= 0
                   for k in counts if k != 'proofsStored')
        counts = retained_counts

    def update(key, value=None):
        with lock:
            counts[key] = counts[key] + 1 if value is None else value
            temporary = metrics.with_suffix('.tmp')
            temporary.write_text(json.dumps(counts) + '\n')
            temporary.replace(metrics)

    update('lastBindingStatus', counts['lastBindingStatus'])

    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'

        def log_message(self, *_):
            pass

        def do_GET(self): self.forward()
        def do_POST(self): self.forward()
        def do_DELETE(self): self.forward()

        def forward(self):
            size = int(self.headers.get('Content-Length', '0'))
            if size < 0 or size > 32768 or self.headers.get('Transfer-Encoding'):
                return self.send_error(413)
            if not self.path.startswith('/') or self.path.startswith('//'):
                return self.send_error(400)
            body = self.rfile.read(size)
            mode = json.loads(mode_file.read_text())['mode']
            assert mode in ('normal', 'drop-rotation')
            path = self.path.split('?', 1)[0]
            excluded = {'host', 'connection', 'content-length', 'transfer-encoding', 'proxy-connection'}
            headers = {k: v for k, v in self.headers.items() if k.lower() not in excluded}
            upstream = http.client.HTTPSConnection(origin.hostname, origin.port, context=client_tls, timeout=20)
            try:
                upstream.request(self.command, self.path, body, headers)
                response = upstream.getresponse()
                data = response.read(131073)
                assert len(data) <= 131072
                if self.command == 'POST' and path == '/api/v1/auth/passkeys':
                    update('bindingSubmits'); update('lastBindingStatus', response.status)
                if path == '/api/v1/auth/credential-change-result': update('resultQueries')
                if path == '/api/v1/auth/passkey-reset-options':
                    update('resetOptionRequests'); update('lastResetOptionStatus', response.status)
                if path == '/api/v1/auth/passkey-reset-intents': update('resetIntentSubmits')
                rotation = self.command == 'POST' and re.fullmatch(
                    r'/api/v1/auth/recovery-code-rotations/[A-Za-z0-9_-]{43}/confirmations', path) is not None
                if rotation:
                    update('rotationSubmits')
                    if mode == 'drop-rotation' and response.status == 204:
                        update('droppedRotationReplies')
                        self.close_connection = True
                        try: self.connection.shutdown(socket.SHUT_RDWR)
                        except OSError: pass
                        self.connection.close()
                        return
                self.send_response(response.status)
                for k, v in response.getheaders():
                    if k.lower() not in excluded: self.send_header(k, v)
                self.send_header('Content-Length', str(len(data)))
                self.send_header('Connection', 'close')
                self.end_headers()
                self.wfile.write(data)
                self.close_connection = True
            except (OSError, ValueError, AssertionError, http.client.HTTPException):
                self.close_connection = True
                self.connection.close()
            finally:
                upstream.close()

    server = http.server.ThreadingHTTPServer(('127.0.0.1', port), Handler)
    server.socket = server_tls.wrap_socket(server.socket, server_side=True)
    config.update(AUTH_COMMUNITY_BASE_URL=f'https://127.0.0.1:{server.server_port}',
                  AUTH_DEVICE_RUN_ID='hnuhole-android-live-matrix-20261006',
                  AUTH_MATRIX_ACCOUNT_RUN_ID=ROOT.name,
                  AUTH_DEV_PASSKEY_RP_ID='zewbby.github.io')
    (ROOT / 'b1b2-device-config.json').write_text(json.dumps(config, indent=2) + '\n')
    (ROOT / 'b1b2-proxy.pid').write_text(str(os.getpid()) + '\n')
    (ROOT / 'b1b2-proxy-source.sha256').write_text(hashlib.sha256(Path(__file__).read_bytes()).hexdigest() + '\n')
    print('READY: separate B1/B2 proxy; historical batch counters/endpoints preserved', flush=True)
    server.serve_forever()


if __name__ == '__main__': main()
