#!/usr/bin/env python3
"""Owned loopback fixture: suppress one accepted comment attempt's image.

The product worker and its real 15-minute deadline are unchanged. This tool
never invents FAILED, touches SQL, drops the CREATE receipt, or blocks RETRY2.
"""
import argparse
import http.client
import http.server
import json
import os
from pathlib import Path
import re
import socket
import ssl
import time
import urllib.parse
import uuid

from fault_proxy import (HOP, MAX_BODY, Journal, bearer_digest, configuration,
                         digest, private_root, request_body, require)

PURPOSE = 'hnuhole-comment-worker-upload-v1'
ACTIVE = {'armed', 'create_in_flight', 'blocking_upload'}


def valid_id(value):
    try:
        return isinstance(value, str) and str(uuid.UUID(value)) == value and uuid.UUID(value).int != 0
    except (ValueError, AttributeError):
        return False


def strict_json(raw):
    def pairs(values):
        obj = {}
        for key, value in values:
            require(key not in obj, 'duplicate JSON member')
            obj[key] = value
        return obj
    return json.loads(raw, object_pairs_hook=pairs)


def valid_rule(rule, allowed):
    require(set(rule) == {'account', 'sessionDigest', 'postId', 'bodyMarker', 'imageSha256'}, 'fixed fixture fields required')
    require(rule['account'] in allowed, 'synthetic account required')
    require(isinstance(rule['sessionDigest'], str) and re.fullmatch('[0-9a-f]{64}', rule['sessionDigest']) is not None, 'session digest required')
    require(valid_id(rule['postId']), 'fixed post required')
    require(isinstance(rule['bodyMarker'], str) and re.fullmatch(r'FA20(?:10)?Worker[A-Za-z0-9_]{1,64}', rule['bodyMarker']) is not None, 'synthetic FA20 marker required')
    require(isinstance(rule['imageSha256'], str) and re.fullmatch('[0-9a-f]{64}', rule['imageSha256']) is not None, 'fixed original image digest required')


class WorkerJournal(Journal):
    def expire(self, rule):
        deadline = rule.get('blockExpiresMonotonic', rule.get('armExpiresMonotonic', 0))
        boot = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
        if rule.get('state') in ACTIVE and (rule.get('bootId') != boot or time.monotonic() >= deadline):
            rule['state'] = 'lease_expired'
            self.write(rule)
            self.event('lease_expired', rule)
        return rule

    def arm(self, rule, allowed):
        valid_rule(rule, allowed)
        with self.locked():
            require(self.expire(self.read()).get('state') not in ACTIVE, 'finish current fixture first')
            rule = dict(rule, id=uuid.uuid4().hex, state='armed',
                        bootId=Path('/proc/sys/kernel/random/boot_id').read_text().strip(),
                        armExpiresMonotonic=time.monotonic() + 600)
            self.write(rule)
            self.event('armed', rule, account=rule['account'], postId=rule['postId'], bodyMarkerSha256=digest(rule['bodyMarker']))
            return {'id': rule['id'], 'state': rule['state']}

    def status(self):
        with self.locked():
            rule = self.expire(self.read())
            return {k: v for k, v in rule.items() if k not in ('sessionDigest', 'bodyMarker', 'bootId')}

    def release(self, rule_id):
        require(isinstance(rule_id, str) and re.fullmatch('[0-9a-f]{32}', rule_id) is not None, 'exact fixture id required')
        with self.locked():
            rule = self.expire(self.read())
            require(rule.get('id') == rule_id, 'exact fixture id required')
            rule['state'] = 'released'
            self.write(rule)
            self.event('operator_release', rule)

    def inspect(self, method, path, authorization, body):
        with self.locked():
            rule = self.expire(self.read())
            if rule.get('state') not in ACTIVE or bearer_digest(authorization) != rule.get('sessionDigest'):
                return None, False
            if rule['state'] == 'blocking_upload':
                exact = '/api/v1/me/comment-tasks/' + rule['taskId'] + '/attempts/1/image'
                if method == 'PUT' and path == exact and digest(body) == rule['imageSha256']:
                    self.event('image_not_forwarded', rule, taskId=rule['taskId'], attemptVersion=1, originalSha256=digest(body))
                    return None, True
                return None, False
            if rule['state'] != 'armed' or method != 'PUT' or not re.fullmatch(r'/api/v1/comment-commands/[A-Za-z0-9_-]{22,86}', path):
                return None, False
            try:
                obj = strict_json(body)
            except (ValueError, UnicodeError, RuntimeError):
                return None, False
            if not isinstance(obj, dict) or set(obj) != {'operation', 'taskId', 'postId', 'identityId', 'rootCommentId', 'targetCommentId', 'body', 'image'}:
                return None, False
            image = obj.get('image')
            if not (obj['operation'] == 'CREATE' and obj['postId'] == rule['postId'] and obj['body'] == rule['bodyMarker']
                    and obj['rootCommentId'] is None and obj['targetCommentId'] is None
                    and valid_id(obj['taskId']) and valid_id(obj['identityId'])
                    and isinstance(image, dict) and image.get('sha256') == rule['imageSha256']):
                return None, False
            rule.update(state='create_in_flight', taskId=obj['taskId'], identityId=obj['identityId'])
            self.write(rule)
            self.event('create_forwarding', rule, taskId=rule['taskId'], postId=rule['postId'], requestBodySha256=digest(body))
            return rule['id'], False

    def accepted(self, rule_id, status, raw, request_id):
        with self.locked():
            rule = self.expire(self.read())
            if rule.get('id') != rule_id or rule.get('state') != 'create_in_flight':
                return
            try:
                obj = strict_json(raw)
            except (ValueError, UnicodeError, RuntimeError):
                obj = None
            accepted = (status == 202 and isinstance(obj, dict) and type(obj.get('attemptVersion')) is int and obj == {
                'state': 'ACCEPTED', 'operation': 'CREATE', 'taskId': rule['taskId'], 'attemptVersion': 1})
            # An incomplete response never proves that C did not commit.
            rule['state'] = 'blocking_upload' if accepted else 'create_receipt_unconfirmed'
            if accepted:
                rule['blockExpiresMonotonic'] = time.monotonic() + 1200
            self.write(rule)
            self.event('real_create_receipt' if status else 'create_receipt_unconfirmed', rule, taskId=rule['taskId'], upstreamStatus=status,
                       upstreamRequestId=request_id, responseSha256=digest(raw), accepted=accepted)


def worker_configuration(path):
    config = configuration(path)  # Reuse all non-root/dev/marker/source/socket/TLS checks.
    require(config.get('fixturePurpose') == PURPOSE, 'explicit comment worker fixture required')
    config['controlRoot'] = private_root(config['root'] / 'worker-failure-proxy')
    return config


class WorkerIngress(http.server.ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, config):
        self.config = config
        self.journal = WorkerJournal(config['controlRoot'])
        self.upstream_context = ssl.create_default_context(cafile=config['ca'])
        super().__init__(('127.0.0.1', config['listenPort']), WorkerHandler)
        tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        tls.minimum_version = ssl.TLSVersion.TLSv1_2
        tls.load_cert_chain(config['certificate'], config['key'])
        self.socket = tls.wrap_socket(self.socket, server_side=True)


class WorkerHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *args):
        pass

    def forward(self):
        claimed = None
        try:
            self.connection.settimeout(45)
            url = urllib.parse.urlsplit(self.path)
            require(self.path.startswith('/') and not self.path.startswith('//') and not url.netloc and not url.scheme
                    and (url.path.startswith('/api/v1/') or url.path == '/health/ready'), 'public origin-form path required')
            require(len(self.headers.get_all('Authorization', [])) <= 1, 'duplicate authorization')
            body = request_body(self.rfile, self.headers)
            claimed, blocked = self.server.journal.inspect(self.command, self.path, self.headers.get('Authorization'), body)
            if blocked:
                return  # Close without forwarding bytes; no fabricated server outcome.
            conn = http.client.HTTPSConnection('127.0.0.1', self.server.config['upstreamPort'],
                                              context=self.server.upstream_context, timeout=45)
            try:
                conn.putrequest(self.command, self.path, skip_accept_encoding=True)
                for key, value in self.headers.items():
                    if key.lower() not in HOP:
                        conn.putheader(key, value)
                conn.putheader('Content-Length', str(len(body)))
                conn.putheader('Connection', 'close')
                conn.endheaders(body)
                response = conn.getresponse()
                raw = response.read(MAX_BODY + 1)
                require(len(raw) <= MAX_BODY, 'upstream body too large')
                status, headers = response.status, response.getheaders()
                if claimed:
                    self.server.journal.accepted(claimed, status, raw, response.getheader('X-Request-ID'))
            finally:
                conn.close()
            self.send_response(status)
            for key, value in headers:
                if key.lower() not in HOP and key.lower() not in ('server', 'date'):
                    self.send_header(key, value)
            self.send_header('Content-Length', str(len(raw)))
            self.send_header('Connection', 'close')
            self.end_headers()
            self.wfile.write(raw)
        except (OSError, ValueError, RuntimeError, http.client.HTTPException):
            if claimed:
                self.server.journal.accepted(claimed, 0, b'', None)
        finally:
            self.close_connection = True
            try:
                self.connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass

    do_GET = do_POST = do_PUT = do_DELETE = do_OPTIONS = forward


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True)
    parser.add_argument('command', choices=('serve', 'arm', 'status', 'release'))
    parser.add_argument('--rule-file')
    parser.add_argument('--id')
    args = parser.parse_args()
    config = worker_configuration(args.config)
    journal = WorkerJournal(config['controlRoot'])
    if args.command == 'serve':
        with WorkerIngress(config) as server:
            server.serve_forever(poll_interval=.1)
    elif args.command == 'arm':
        path = Path(args.rule_file)
        require(path.is_file() and not path.is_symlink() and path.stat().st_uid == os.getuid() and not path.stat().st_mode & 0o077, 'owned private rule required')
        print(json.dumps(journal.arm(strict_json(path.read_bytes()), config['allowedAccounts'])))
    elif args.command == 'status':
        print(json.dumps(journal.status()))
    else:
        journal.release(args.id)


if __name__ == '__main__':
    main()
