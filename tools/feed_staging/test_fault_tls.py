"""Real loopback TLS tests of ingress behavior, not product SQL evidence."""
import base64
import http.client
import http.server
import json
from pathlib import Path
import socket
import ssl
import subprocess
import tempfile
import threading
import time
import unittest
from test_fault_proxy import proxy

class Upstream(http.server.BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def do_GET(self):
        self.server.reads+=1
        self.reply(200,{'ok':True})
    def do_PUT(self):
        json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        self.server.conditions=self.headers.get_all('If-Interaction-Version',[])
        self.server.writes+=1
        self.reply(200,{'postId':'11111111-1111-4111-8111-111111111111','likedByMe':True,'likeCount':1})
    def reply(self,status,value):
        body=json.dumps(value).encode();self.send_response(status);self.send_header('Content-Length',str(len(body)));self.send_header('Content-Type','application/json');self.send_header('X-Request-ID','upstream-test');self.end_headers();self.wfile.write(body)

class TLSIngressTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp=tempfile.TemporaryDirectory();cls.root=Path(cls.tmp.name)
        cls.cert=cls.root/'cert.pem';cls.key=cls.root/'key.pem'
        subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-days','1','-subj','/CN=loopback-test','-addext','subjectAltName=IP:127.0.0.1','-keyout',cls.key,'-out',cls.cert],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        cls.up=http.server.ThreadingHTTPServer(('127.0.0.1',0),Upstream);cls.up.writes=0;cls.up.reads=0
        tls=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);tls.load_cert_chain(cls.cert,cls.key);cls.up.socket=tls.wrap_socket(cls.up.socket,server_side=True)
        cls.upthread=threading.Thread(target=cls.up.serve_forever,daemon=True);cls.upthread.start()
        with socket.socket() as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
        cls.ingress=proxy.Ingress(dict(listenPort=port,controlRoot=cls.root,certificate=str(cls.cert),key=str(cls.key),ca=str(cls.cert),upstreamPort=cls.up.server_port,allowedAccounts=['cas_appeal']))
        cls.thread=threading.Thread(target=cls.ingress.serve_forever,daemon=True);cls.thread.start()
        cls.trust=ssl.create_default_context(cafile=str(cls.cert));cls.token='Bearer '+base64.urlsafe_b64encode(b'z'*32).decode().rstrip('=')
    @classmethod
    def tearDownClass(cls):
        cls.ingress.stop_event.set();cls.ingress.shutdown();cls.ingress.server_close();cls.up.shutdown();cls.up.server_close();cls.tmp.cleanup()
    def call(self,method='GET',body=None,authorization=None,timeout=2,with_headers=False):
        c=http.client.HTTPSConnection('127.0.0.1',self.ingress.server_port,context=self.trust,timeout=timeout)
        try:
            c.request(method,'/api/v1/posts/11111111-1111-4111-8111-111111111111/like' if method=='PUT' else '/api/v1/feed',body=body,headers={'Authorization':authorization or self.token,'Content-Type':'application/json'})
            r=c.getresponse();raw=r.read()
            return (r.status,json.loads(raw),dict(r.headers)) if with_headers else (r.status,json.loads(raw))
        finally:c.close()
    def arm(self,mode,method='PUT',hold=.05):
        j=self.ingress.journal
        with j.locked():j.write(dict(id=mode,state='armed',mode=mode,account='cas_appeal',method=method,path='/api/v1/posts/11111111-1111-4111-8111-111111111111/like' if method=='PUT' else '/api/v1/feed',sessionDigest=proxy.digest(b'z'*32),holdSeconds=hold))
    def test_passthrough_and_nonmatching_account(self):
        self.arm('commit_drop_response')
        self.assertEqual(self.call()[0],200)
        self.assertEqual(self.call('PUT','{"liked":true}',authorization='Bearer '+base64.urlsafe_b64encode(b'w'*32).decode().rstrip('='))[0],200)
        self.assertEqual(self.ingress.journal.read()['state'],'armed')
        with self.ingress.journal.locked():self.ingress.journal.write({})
    def test_committed_response_dropped_once_then_passthrough(self):
        self.arm('commit_drop_response');before=self.up.writes
        with self.assertRaises((http.client.RemoteDisconnected,OSError)):self.call('PUT','{"liked":true}')
        self.assertEqual(self.up.writes,before+1)
        self.assertEqual(self.ingress.journal.read()['state'],'response_dropped_after_upstream')
        self.assertEqual(self.call('PUT','{"liked":true}')[0],200)
        self.assertNotIn(self.token,(self.root/'events.jsonl').read_text())
    def test_hold_before_independent_get_then_release(self):
        self.arm('hold_before');before=self.up.writes;result=[]
        t=threading.Thread(target=lambda:result.append(self.call('PUT','{"liked":true}')),daemon=True);t.start()
        deadline=time.monotonic()+2
        while self.ingress.journal.read().get('state')!='held_before_upstream' and time.monotonic()<deadline:time.sleep(.01)
        self.assertEqual(self.up.writes,before);self.assertEqual(self.call()[0],200)
        with self.ingress.journal.locked():r=self.ingress.journal.read();r['release']=True;self.ingress.journal.write(r)
        t.join(2);self.assertEqual(result[0][0],200);self.assertEqual(self.up.writes,before+1)
    def test_injected_failure_does_not_reach_upstream(self):
        for status in (401,503):
            self.arm('inject_'+str(status),method='GET');before=(self.up.writes,self.up.reads)
            code,body,headers=self.call(with_headers=True);self.assertEqual(code,status)
            self.assertEqual(set(body),{'error','requestId'})
            self.assertEqual(set(body['error']),{'code','message'})
            self.assertEqual(body['requestId'],headers['X-Request-ID'])
            self.assertRegex(body['requestId'],r'^[A-Za-z0-9_-]{22}$')
            raw=base64.urlsafe_b64decode(body['requestId']+'==');self.assertEqual(len(raw),16)
            self.assertEqual(base64.urlsafe_b64encode(raw).decode().rstrip('='),body['requestId'])
            self.assertEqual(body['error']['code'],'SESSION_INVALID' if status==401 else 'AUTHORIZATION_UNAVAILABLE')
            self.assertLessEqual(len(body['error']['message']),256)
            self.assertNotIn('Server-Time',headers);self.assertNotIn('Session-Expires-At',headers)
            self.assertEqual(headers['Cache-Control'],'no-store')
            self.assertEqual((self.up.writes,self.up.reads),before)
            self.assertEqual(self.ingress.journal.read()['state'],'injected_not_upstream')
    def test_duplicate_condition_headers_preserved(self):
        with self.ingress.journal.locked():self.ingress.journal.write({})
        c=http.client.HTTPSConnection('127.0.0.1',self.ingress.server_port,context=self.trust,timeout=2)
        try:
            c.putrequest('PUT','/api/v1/posts/11111111-1111-4111-8111-111111111111/like')
            c.putheader('Authorization',self.token);c.putheader('Content-Length','14')
            c.putheader('If-Interaction-Version','first');c.putheader('If-Interaction-Version','second');c.endheaders(b'{"liked":true}')
            r=c.getresponse();r.read();self.assertEqual(r.status,200)
            self.assertEqual(self.up.conditions,['first','second'])
        finally:c.close()

if __name__=='__main__':unittest.main()
