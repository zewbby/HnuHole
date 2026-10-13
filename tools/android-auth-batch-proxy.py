#!/usr/bin/env python3
"""Owned batch fault proxy: actual C replies, no request/proof logging."""
import base64
import http.client
import http.server
import hashlib
import json
import os
from pathlib import Path
import socket
import ssl
import threading
import time
from urllib.parse import urlsplit

ROOT = Path('/var/tmp/hnuhole-android-live-batch-20261007')

def main():
    assert ROOT.resolve() == ROOT and not ROOT.is_symlink()
    assert (ROOT/'OWNER').read_text().strip() == 'HNUHOLE_ANDROID_LIVE_DEV_V1'
    material = ROOT/'services/material'
    config = json.loads((ROOT/'device-config.json').read_text())
    service = json.loads((material/'c.json').read_text())
    upstream = urlsplit(config['AUTH_COMMUNITY_BASE_URL'])
    assert upstream.scheme == 'https' and upstream.hostname == '127.0.0.1'
    assert upstream.port and upstream.port >= 1024 and not upstream.username
    server_tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    server_tls.load_cert_chain(material/service['publicCertificateFile'], material/service['publicKeyFile'])
    client_tls = ssl.create_default_context(cafile=str(material/'dev-ca.pem'))
    control = ROOT/'batch-proxy-mode.json'
    metrics = ROOT/'batch-proxy-metrics.json'
    control.write_text(json.dumps({'mode':'normal'})+'\n')
    lock = threading.Lock()
    counters = {'identitySubmits':0,'bindingSubmits':0,'droppedIdentityReplies':0,
        'droppedBindingReplies':0,'heldBindings':0,'resultQueries':0,
        'rejectedOrigins':0,'lastBindingStatus':0,'proofsStored':False}
    def count(key,value=None):
        with lock:
            counters[key] = counters[key]+1 if value is None else value
            temp=metrics.with_suffix('.tmp');temp.write_text(json.dumps(counters)+'\n');temp.replace(metrics)
    count('lastBindingStatus',0)
    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version='HTTP/1.1'
        def log_message(self,*_):pass
        def do_GET(self):self.handle_request()
        def do_POST(self):self.handle_request()
        def do_DELETE(self):self.handle_request()
        def do_PUT(self):self.handle_request()
        def drop(self):
            self.close_connection=True
            try:self.connection.shutdown(socket.SHUT_RDWR)
            except OSError:pass
            self.connection.close()
        def handle_request(self):
            if not self.path.startswith('/') or self.path.startswith('//'):return self.send_error(400)
            size=int(self.headers.get('Content-Length','0'))
            if size<0 or size>32768 or self.headers.get('Transfer-Encoding'):return self.send_error(413)
            body=self.rfile.read(size)
            mode=json.loads(control.read_text())['mode']
            assert mode in {'normal','drop-identity','drop-binding','hold-binding','tamper-origin'}
            path=self.path.split('?',1)[0]
            binding=self.command=='POST' and path=='/api/v1/auth/passkeys'
            identity=self.command=='POST' and path=='/api/v1/identities'
            if binding and mode=='hold-binding':
                count('heldBindings')
                until=time.monotonic()+18
                while json.loads(control.read_text())['mode']=='hold-binding' and time.monotonic()<until:time.sleep(.05)
                if json.loads(control.read_text())['mode']=='hold-binding':return self.drop()
            if binding and mode=='tamper-origin':
                payload=json.loads(body)
                response=payload['webauthnAttestation']['response']
                raw=base64.urlsafe_b64decode(response['clientDataJSON']+'='*(-len(response['clientDataJSON'])%4))
                client=json.loads(raw);client['origin']='android:apk-key-hash:'+base64.b64encode(bytes(32)).decode()
                response['clientDataJSON']=base64.urlsafe_b64encode(json.dumps(client,separators=(',',':')).encode()).decode().rstrip('=')
                body=json.dumps(payload,separators=(',',':')).encode()
            excluded={'host','connection','content-length','transfer-encoding','proxy-connection'}
            headers={k:v for k,v in self.headers.items() if k.lower() not in excluded}
            connection=http.client.HTTPSConnection(upstream.hostname,upstream.port,context=client_tls,timeout=20)
            try:
                connection.request(self.command,self.path,body,headers)
                response=connection.getresponse();data=response.read(131073)
                assert len(data)<=131072
                if binding:
                    count('bindingSubmits');count('lastBindingStatus',response.status)
                    if mode=='tamper-origin' and response.status==422:count('rejectedOrigins')
                if identity:count('identitySubmits')
                if path in {'/api/v1/identity-change-result','/api/v1/auth/credential-change-result'}:count('resultQueries')
                if (identity and mode=='drop-identity' and response.status==200) or (binding and mode=='drop-binding' and response.status==204):
                    count('droppedIdentityReplies' if identity else 'droppedBindingReplies');return self.drop()
                self.send_response(response.status)
                for key,value in response.getheaders():
                    if key.lower() not in excluded:self.send_header(key,value)
                self.send_header('Content-Length',str(len(data)));self.send_header('Connection','close');self.end_headers()
                self.wfile.write(data);self.close_connection=True
            except (OSError,ValueError,AssertionError,http.client.HTTPException):self.drop()
            finally:connection.close()
    server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
    server.socket=server_tls.wrap_socket(server.socket,server_side=True)
    config.update(AUTH_COMMUNITY_BASE_URL=f'https://127.0.0.1:{server.server_port}',
        AUTH_DEVICE_RUN_ID='hnuhole-android-live-matrix-20261006',
        AUTH_MATRIX_ACCOUNT_RUN_ID=ROOT.name,AUTH_DEV_PASSKEY_RP_ID='zewbby.github.io')
    (ROOT/'batch-device-config.json').write_text(json.dumps(config,indent=2)+'\n')
    (ROOT/'batch-proxy.pid').write_text(str(os.getpid())+'\n')
    (ROOT/'batch-proxy-source.sha256').write_text(hashlib.sha256(Path(__file__).read_bytes()).hexdigest()+'\n')
    print('READY: owned actual C batch fault proxy; request/proof bodies never recorded',flush=True)
    server.serve_forever()

if __name__=='__main__':main()
