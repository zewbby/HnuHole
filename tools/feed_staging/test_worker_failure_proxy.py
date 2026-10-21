"""Fixture scope and real TLS forwarding tests; not worker/SQL acceptance."""
import base64
import http.client
import http.server
import json
from pathlib import Path
import ssl
import subprocess
import tempfile
import threading
import unittest

import worker_failure_proxy as fixture

TASK = '11111111-1111-4111-8111-111111111111'
POST = '22222222-2222-4222-8222-222222222222'
IDENTITY = '33333333-3333-4333-8333-333333333333'
IMAGE = b'synthetic-original-bytes'
AUTH = 'Bearer ' + base64.urlsafe_b64encode(b'b' * 32).decode().rstrip('=')
CREATE = '/api/v1/comment-commands/' + 'a' * 22
UPLOAD = '/api/v1/me/comment-tasks/' + TASK + '/attempts/1/image'


def rule():
    return dict(account='feed_device_b', sessionDigest=fixture.digest(b'b' * 32),
                postId=POST, bodyMarker='FA20WorkerB1020', imageSha256=fixture.digest(IMAGE))


def command():
    return dict(operation='CREATE', taskId=TASK, postId=POST, identityId=IDENTITY,
                rootCommentId=None, targetCommentId=None, body='FA20WorkerB1020',
                image={'mediaId': TASK, 'sha256': fixture.digest(IMAGE), 'byteLength': len(IMAGE),
                       'mimeType': 'image/png', 'width': 640, 'height': 360})


def receipt():
    return json.dumps(dict(state='ACCEPTED', operation='CREATE', taskId=TASK, attemptVersion=1)).encode()


class ScopeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.j = fixture.WorkerJournal(Path(self.temp.name))
        self.id = self.j.arm(rule(), ['feed_device_b'])['id']

    def claim(self, **changes):
        obj = dict(command(), **changes)
        return self.j.inspect('PUT', CREATE, AUTH, json.dumps(obj).encode())

    def bind(self):
        self.assertEqual(self.claim(), (self.id, False))
        self.j.accepted(self.id, 202, receipt(), 'real-request')

    def test_exact_body_account_post_and_image_only(self):
        for obj in [dict(body='another'), dict(postId=IDENTITY), dict(rootCommentId=POST, targetCommentId=IDENTITY), dict(image=None)]:
            self.assertEqual(self.claim(**obj), (None, False))
        other = 'Bearer ' + base64.urlsafe_b64encode(b'c' * 32).decode().rstrip('=')
        self.assertEqual(self.j.inspect('PUT', CREATE, other, json.dumps(command()).encode()), (None, False))
        self.assertEqual(self.j.status()['state'], 'armed')
        self.bind()

    def test_only_real202_receipt_binds(self):
        self.claim()
        self.j.accepted(self.id, 400, receipt(), 'rejected')
        self.assertEqual(self.j.status()['state'], 'create_receipt_unconfirmed')
        self.assertEqual(self.j.inspect('PUT', UPLOAD, AUTH, IMAGE), (None, False))

    def test_mismatched_or_malformed202_never_binds(self):
        self.claim()
        self.j.accepted(self.id, 202, b'{"state":"ACCEPTED","taskId":"other"}', 'malformed')
        self.assertEqual(self.j.status()['state'], 'create_receipt_unconfirmed')

    def test_transport_uncertainty_is_not_server_rejection(self):
        self.claim()
        self.j.accepted(self.id, 0, b'', None)
        self.assertEqual(self.j.status()['state'], 'create_receipt_unconfirmed')
        self.assertEqual(self.j.inspect('PUT', UPLOAD, AUTH, IMAGE), (None, False))

    def test_release_and_rearm_ignore_late_old202(self):
        old = self.id
        self.claim()
        self.j.release(old)
        self.j.accepted(old, 202, receipt(), 'late-response')
        self.assertEqual(self.j.status()['state'], 'released')
        self.id = self.j.arm(rule(), ['feed_device_b'])['id']
        self.j.accepted(old, 202, receipt(), 'still-old-response')
        self.assertEqual(self.j.status()['state'], 'armed')
        self.bind()

    def test_only_first_attempt_exact_bytes_blocked(self):
        self.bind()
        self.assertEqual(self.j.inspect('PUT', UPLOAD, AUTH, IMAGE), (None, True))
        self.assertEqual(self.j.inspect('PUT', UPLOAD, AUTH, IMAGE), (None, True))
        for method, path, body in [('GET', UPLOAD, IMAGE), ('PUT', UPLOAD.replace('/1/', '/2/'), IMAGE),
                                   ('PUT', UPLOAD.replace(TASK, IDENTITY), IMAGE), ('PUT', UPLOAD, b'changed'),
                                   ('PUT', UPLOAD + '?q=1', IMAGE)]:
            self.assertEqual(self.j.inspect(method, path, AUTH, body), (None, False))

    def test_operator_release_and_lease_expiry(self):
        self.bind()
        with self.assertRaises(RuntimeError):
            self.j.release('wrong-id')
        self.j.release(self.id)
        self.assertEqual(self.j.inspect('PUT', UPLOAD, AUTH, IMAGE), (None, False))
        self.id = self.j.arm(rule(), ['feed_device_b'])['id']
        self.bind()
        with self.j.locked():
            r = self.j.read(); r['blockExpiresMonotonic'] = 0; self.j.write(r)
        self.assertEqual(self.j.inspect('PUT', UPLOAD, AUTH, IMAGE), (None, False))
        self.assertEqual(self.j.status()['state'], 'lease_expired')

    def test_no_authentication_values_in_public_status_or_journal(self):
        self.bind()
        self.j.inspect('PUT', UPLOAD, AUTH, IMAGE)
        public = json.dumps(self.j.status()) + (Path(self.temp.name) / 'events.jsonl').read_text()
        self.assertNotIn(AUTH, public)
        self.assertNotIn(rule()['sessionDigest'], public)
        self.assertNotIn('sessionDigest', public)

    def test_no_second_active_rule_or_extra_config_fields(self):
        with self.assertRaises(RuntimeError): self.j.arm(rule(), ['feed_device_b'])
        with self.assertRaises(RuntimeError): fixture.valid_rule(dict(rule(), target='https://production'), ['feed_device_b'])
        with self.assertRaises(RuntimeError): fixture.valid_rule(rule(), ['feed_device_a'])
        with self.assertRaises(RuntimeError): fixture.strict_json(b'{"taskId":"a","taskId":"b"}')


class Upstream(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args): pass

    def do_PUT(self):
        self.rfile.read(int(self.headers['Content-Length']))
        self.server.calls.append(self.path)
        raw = receipt() if self.path == CREATE else b'{}'
        self.send_response(202 if self.path == CREATE else 204)
        self.send_header('Content-Length', str(len(raw)))
        self.send_header('X-Request-ID', 'real-upstream-test')
        self.end_headers(); self.wfile.write(raw)


class TLSForwardTests(unittest.TestCase):
    def test_real_create202_forwarded_and_only_bound_upload_suppressed(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); cert = root / 'cert.pem'; key = root / 'key.pem'
            subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
                            '-subj', '/CN=fixture-test', '-addext', 'subjectAltName=IP:127.0.0.1',
                            '-keyout', str(key), '-out', str(cert)], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            upstream = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Upstream); upstream.calls = []
            tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); tls.load_cert_chain(cert, key)
            upstream.socket = tls.wrap_socket(upstream.socket, server_side=True)
            ingress = fixture.WorkerIngress(dict(listenPort=0, controlRoot=root, ca=str(cert),
                                                certificate=str(cert), key=str(key), upstreamPort=upstream.server_port))
            threads = [threading.Thread(target=s.serve_forever, daemon=True) for s in (upstream, ingress)]
            for thread in threads: thread.start()
            trust = ssl.create_default_context(cafile=str(cert))
            def call(path, body):
                connection = http.client.HTTPSConnection('127.0.0.1', ingress.server_port, context=trust, timeout=3)
                try:
                    connection.request('PUT', path, body=body, headers={'Authorization': AUTH})
                    response = connection.getresponse(); return response.status, response.read()
                finally: connection.close()
            try:
                ingress.journal.arm(rule(), ['feed_device_b'])
                self.assertEqual(call(CREATE, json.dumps(command()).encode()), (202, receipt()))
                with self.assertRaises((http.client.RemoteDisconnected, OSError)): call(UPLOAD, IMAGE)
                self.assertEqual(upstream.calls, [CREATE])
                self.assertEqual(call(UPLOAD.replace('/1/', '/2/'), IMAGE)[0], 204)
                rule_id = ingress.journal.status()['id']; ingress.journal.release(rule_id)
                self.assertEqual(call(UPLOAD, IMAGE)[0], 204)
                wrong = ssl.create_default_context()
                connection = http.client.HTTPSConnection('127.0.0.1', ingress.server_port, context=wrong, timeout=2)
                try:
                    with self.assertRaises(ssl.SSLCertVerificationError): connection.request('GET', '/health/ready')
                finally: connection.close()
            finally:
                for server in (ingress, upstream): server.shutdown(); server.server_close()


if __name__ == '__main__': unittest.main()
