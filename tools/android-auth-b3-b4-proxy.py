#!/usr/bin/env python3
"""Owned B3/B4 HTTPS proxy. Delay actual replies; never persist proofs or bodies."""
import base64
import hashlib
import http.client
import http.server
import json
import os
from pathlib import Path
import ssl
import threading
import time
from urllib.parse import urlsplit

ROOT=Path('/var/tmp/hnuhole-android-live-b3-b4-20261009')
MODES={'normal','hold-two','wrong-rp-options','wrong-rp-hash'}


def changed_rp_hash(body):
    """Change only the RP hash within the attestation's bounded CBOR authData."""
    value=json.loads(body)
    response=value['webauthnAttestation']['response']
    raw=base64.urlsafe_b64decode(response['attestationObject']+'===' )
    assert len(raw)<=16384 and raw.count(b'\x68authData')==1
    pos=raw.index(b'\x68authData')+9
    tag=raw[pos];pos+=1
    if tag==0x58:size=raw[pos];pos+=1
    elif tag==0x59:size=int.from_bytes(raw[pos:pos+2],'big');pos+=2
    else:raise AssertionError('Unexpected bounded authData encoding')
    assert 37<=size<=8192 and pos+size<=len(raw)
    assert raw[pos:pos+32]==hashlib.sha256(b'zewbby.github.io').digest()
    changed=raw[:pos]+hashlib.sha256(b'unassociated.zewbby.github.io').digest()+raw[pos+32:]
    response['attestationObject']=base64.urlsafe_b64encode(changed).decode().rstrip('=')
    return json.dumps(value,separators=(',',':')).encode()


def main():
    assert ROOT.resolve()==ROOT and not ROOT.is_symlink()
    assert (ROOT/'OWNER').read_text().strip()=='HNUHOLE_ANDROID_LIVE_DEV_V1'
    pidfile=ROOT/'b3b4-proxy.pid'
    if pidfile.exists():
        assert not Path('/proc',pidfile.read_text().strip(),'cmdline').exists(),'Preserve a live owned proxy'
    material=ROOT/'services/material'
    config=json.loads((ROOT/'device-config.json').read_text())
    service=json.loads((material/'c.json').read_text())
    origin=urlsplit(config['AUTH_COMMUNITY_BASE_URL'])
    assert origin.scheme=='https' and origin.hostname=='127.0.0.1' and origin.port>=1024
    server_tls=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    server_tls.load_cert_chain(material/service['publicCertificateFile'],material/service['publicKeyFile'])
    client_tls=ssl.create_default_context(cafile=str(material/'dev-ca.pem'))
    modefile=ROOT/'b3b4-proxy-mode.json'
    modefile.write_text('{"mode":"normal"}\n')
    release=ROOT/'b3b4-release-replies'
    metrics=ROOT/'b3b4-proxy-metrics.json'
    lock=threading.Lock()
    counts={key:0 for key in ('bindingOptions','bindingSubmits','identitySubmits','closureSubmits',
        'credentialResultQueries','identityResultQueries','resetOptions','resetIntentSubmits',
        'heldBindingReplies','heldIdentityReplies','releasedBindingReplies','releasedIdentityReplies',
        'modifiedRpOptions','modifiedRpHash','lastBindingStatus','lastResetStatus','lastIdentityStatus',
        'loginSubmits','sessionReads','renewalSubmits','registrationSubmits','removalSubmits','lastRemovalStatus')}
    counts['proofsStored']=False
    retained_config=ROOT/'b3b4-device-config.json'
    port=0
    if retained_config.exists():
        previous=json.loads(retained_config.read_text())
        endpoint=urlsplit(previous['AUTH_COMMUNITY_BASE_URL'])
        assert endpoint.scheme=='https' and endpoint.hostname=='127.0.0.1' and endpoint.port>=1024
        assert previous['AUTH_MATRIX_ACCOUNT_RUN_ID']==ROOT.name
        port=endpoint.port
        prior=json.loads(metrics.read_text())
        assert prior['proofsStored'] is False and set(prior)<=set(counts)
        assert all(type(v) is int and v>=0 for k,v in prior.items() if k!='proofsStored')
        counts.update(prior)

    def update(key=None,value=None):
        with lock:
            if key:counts[key]=counts[key]+1 if value is None else value
            temp=metrics.with_suffix('.tmp');temp.write_text(json.dumps(counts)+'\n');temp.replace(metrics)
    update()

    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version='HTTP/1.1'
        def log_message(self,*_):pass
        def do_GET(self):self.forward()
        def do_POST(self):self.forward()
        def do_DELETE(self):self.forward()

        def forward(self):
            size=int(self.headers.get('Content-Length','0'))
            if size<0 or size>32768 or self.headers.get('Transfer-Encoding'):
                self.send_error(413);return
            if not self.path.startswith('/') or self.path.startswith('//'):
                self.send_error(400);return
            body=self.rfile.read(size)
            mode=json.loads(modefile.read_text())['mode'];assert mode in MODES
            path=self.path.split('?',1)[0]
            binding=self.command=='POST' and path=='/api/v1/auth/passkeys'
            identity=self.command=='POST' and path=='/api/v1/identities'
            option=self.command=='POST' and path=='/api/v1/auth/passkey-options'
            reset=self.command=='POST' and path=='/api/v1/auth/passkey-reset-intents'
            removal=self.command=='DELETE' and path.startswith('/api/v1/auth/passkeys/')
            for condition,key in ((binding,'bindingSubmits'),(identity,'identitySubmits'),(option,'bindingOptions'),
                (reset,'resetIntentSubmits'),(removal,'removalSubmits'),(self.command=='POST' and path=='/api/v1/account-closures','closureSubmits'),
                (path=='/api/v1/auth/credential-change-result','credentialResultQueries'),
                (path=='/api/v1/identity-change-result','identityResultQueries'),
                (path=='/api/v1/auth/passkey-reset-options','resetOptions'),
                (self.command=='POST' and path=='/api/v1/auth/sessions','loginSubmits'),
                (self.command=='GET' and path=='/api/v1/auth/session','sessionReads'),
                (path=='/api/v1/auth/session-renewals','renewalSubmits'),
                (path=='/api/v1/auth/registrations','registrationSubmits')):
                if condition:update(key)
            if binding and mode=='wrong-rp-hash':
                body=changed_rp_hash(body);update('modifiedRpHash')
            excluded={'host','connection','content-length','transfer-encoding','proxy-connection'}
            headers={k:v for k,v in self.headers.items() if k.lower() not in excluded}
            upstream=http.client.HTTPSConnection(origin.hostname,origin.port,context=client_tls,timeout=25)
            try:
                upstream.request(self.command,self.path,body,headers)
                response=upstream.getresponse()
                status=response.status
                response_headers=[(k,v) for k,v in response.getheaders() if k.lower() not in excluded]
                payload=response.read(65537);assert len(payload)<=65536
                upstream.close()
                if binding:update('lastBindingStatus',status)
                if identity:update('lastIdentityStatus',status)
                if reset:update('lastResetStatus',status)
                if removal:update('lastRemovalStatus',status)
                if option and mode=='wrong-rp-options' and status==200:
                    value=json.loads(payload)
                    value['publicKey']['rp']['id']='unassociated.zewbby.github.io'
                    payload=json.dumps(value,separators=(',',':')).encode();update('modifiedRpOptions')
                if mode=='hold-two' and (binding or identity) and 200<=status<300:
                    kind='Binding' if binding else 'Identity'
                    update('held'+kind+'Replies')
                    deadline=time.monotonic()+1500
                    while not release.exists() and time.monotonic()<deadline:time.sleep(.1)
                    assert release.exists(),'Bounded reply hold expired'
                    update('released'+kind+'Replies')
                self.send_response(status)
                for key,value in response_headers:self.send_header(key,value)
                self.send_header('Content-Length',str(len(payload)))
                self.send_header('Connection','close');self.end_headers()
                self.wfile.write(payload)
            except (OSError,http.client.HTTPException,AssertionError):
                # No exception text, HTTP capability, payload or request value.
                self.close_connection=True
            finally:upstream.close()

    server=http.server.ThreadingHTTPServer(('127.0.0.1',port),Handler)
    server.daemon_threads=True
    server.socket=server_tls.wrap_socket(server.socket,server_side=True)
    config.update(AUTH_COMMUNITY_BASE_URL=f'https://127.0.0.1:{server.server_port}',
        AUTH_DEVICE_RUN_ID='hnuhole-android-live-matrix-20261006',AUTH_MATRIX_ACCOUNT_RUN_ID=ROOT.name,
        AUTH_DEV_PASSKEY_RP_ID='zewbby.github.io')
    (ROOT/'b3b4-device-config.json').write_text(json.dumps(config,indent=2)+'\n')
    (ROOT/'b3b4-proxy-source.sha256').write_text(hashlib.sha256(Path(__file__).read_bytes()).hexdigest()+'\n')
    pidfile.write_text(str(os.getpid())+'\n')
    server.serve_forever(poll_interval=.2)


if __name__=='__main__':main()
