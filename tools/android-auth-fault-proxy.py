#!/usr/bin/env python3
"""Owned loopback HTTPS fault injection; all business responses come from C.

No public control API, request/credential logging or external upstream override.
Modes are selected by a private host file between independent App processes.
"""
import argparse
import http.client
import http.server
import json
import os
from pathlib import Path
import socket
import ssl
import threading
from urllib.parse import urlsplit


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', required=True)
    args = parser.parse_args()
    work = Path(args.work).resolve(strict=True)
    assert (work / 'OWNER').read_text() == 'HNUHOLE_ANDROID_LIVE_DEV_V1'
    material = work / 'services/material'
    config = json.loads((work / 'device-config.json').read_text())
    upstream = urlsplit(config['AUTH_COMMUNITY_BASE_URL'])
    assert upstream.scheme == 'https' and upstream.hostname == '127.0.0.1'
    assert upstream.port and upstream.port >= 1024 and upstream.path in ('', '/')
    assert not any((upstream.username, upstream.password, upstream.query, upstream.fragment))
    service = json.loads((material / 'c.json').read_text())
    # Reuse this owned loopback development leaf; no system trust alteration.
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(material / service['publicCertificateFile'], material / service['publicKeyFile'])
    client_context = ssl.create_default_context(cafile=str(material / 'dev-ca.pem'))
    lock = threading.Lock()
    counters = {'forwardedCreates': 0, 'droppedCommittedCreates': 0,
                'blockedRevocations': 0, 'forwardedRevocations': 0, 'resultQueries': 0}
    mode_file = work / 'proxy-mode.json'
    metrics_file = work / 'proxy-metrics.json'
    mode_file.write_text(json.dumps({'mode': 'normal'}) + '\n')

    def count(name):
        with lock:
            counters[name] += 1
            temporary = metrics_file.with_suffix('.tmp')
            temporary.write_text(json.dumps(counters) + '\n')
            os.replace(temporary, metrics_file)

    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.1'

        def log_message(self, *_args):
            pass

        def close_without_response(self):
            self.close_connection = True
            try:
                self.connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            self.connection.close()

        def handle_request(self):
            if not self.path.startswith('/') or self.path.startswith('//'):
                self.send_error(400)
                return
            length = int(self.headers.get('Content-Length', '0'))
            if length < 0 or length > 32768 or self.headers.get('Transfer-Encoding'):
                self.send_error(413)
                return
            body = self.rfile.read(length)
            mode = json.loads(mode_file.read_text())['mode']
            assert mode in ('normal', 'drop-create-response', 'block-revocation')
            path = self.path.split('?', 1)[0]
            revocation = self.command == 'POST' and path == '/api/v1/auth/session-revocations'
            if mode == 'block-revocation' and revocation:
                count('blockedRevocations')
                self.close_without_response()
                return
            excluded = {'host', 'connection', 'transfer-encoding', 'content-length', 'proxy-connection'}
            headers = {k: v for k, v in self.headers.items() if k.lower() not in excluded}
            upstream_connection = http.client.HTTPSConnection(
                upstream.hostname, upstream.port, context=client_context, timeout=20)
            try:
                upstream_connection.request(self.command, self.path, body, headers)
                response = upstream_connection.getresponse()
                data = response.read(131073)
                if len(data) > 131072:
                    raise ValueError('Oversized upstream response')
                create = self.command == 'POST' and path == '/api/v1/identities'
                if create:
                    count('forwardedCreates')
                if revocation:
                    count('forwardedRevocations')
                if path == '/api/v1/identity-change-result':
                    count('resultQueries')
                if mode == 'drop-create-response' and create and response.status == 200:
                    count('droppedCommittedCreates')
                    self.close_without_response()
                    return
                self.send_response(response.status)
                for key, value in response.getheaders():
                    if key.lower() not in excluded:
                        self.send_header(key, value)
                self.send_header('Content-Length', str(len(data)))
                self.send_header('Connection', 'close')
                self.end_headers()
                self.wfile.write(data)
                self.close_connection = True
            except (OSError, ValueError, http.client.HTTPException):
                self.close_without_response()
            finally:
                upstream_connection.close()

        do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = handle_request

    port_file = work / 'proxy-port'
    port = int(port_file.read_text()) if port_file.exists() else 0
    assert port == 0 or 1024 <= port <= 65535
    server = http.server.ThreadingHTTPServer(('127.0.0.1', port), Handler)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    (work / 'proxy-port').write_text(str(server.server_port))
    config['AUTH_COMMUNITY_BASE_URL'] = f'https://127.0.0.1:{server.server_port}'
    (work / 'fault-device-config.json').write_text(json.dumps(config, indent=2) + '\n')
    metrics_file.write_text(json.dumps(counters) + '\n')
    print('READY: owned loopback HTTPS fault proxy to actual C', flush=True)
    server.serve_forever()


if __name__ == '__main__':
    main()
