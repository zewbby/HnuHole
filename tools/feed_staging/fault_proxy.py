#!/usr/bin/env python3
"""One-shot loopback TLS fault ingress for an explicitly owned development lab.

No product hook, SQL mutation, global trust change, or HTTP control endpoint.
Operator control is a private local file; bearer values are never persisted.
"""
import argparse
import base64
import contextlib
import fcntl
import hashlib
import http.client
import http.server
import json
import os
from pathlib import Path
import re
import signal
import socket
import ssl
import threading
import time
import urllib.parse
import uuid
from datetime import datetime, timezone

PURPOSE = 'hnuhole-feed-isolated-fault-v1'
MODES = {'hold_before', 'hold_response', 'commit_drop_response', 'inject_401', 'inject_503'}
HOP = {'connection','keep-alive','proxy-authenticate','proxy-authorization','te','trailer','transfer-encoding','upgrade','host','content-length'}
MAX_BODY = 12 * 1024 * 1024

def require(ok, message):
    if not ok:
        raise RuntimeError(message)

def digest(value):
    return hashlib.sha256(value.encode() if isinstance(value,str) else value).hexdigest()

def private_root(path):
    path=Path(path)
    require(os.name=='posix' and os.getuid()!=0,'non-root Linux required')
    require(path.is_absolute() and path==path.resolve() and path.is_dir() and not path.is_symlink(),'canonical existing root required')
    require(path.stat().st_uid==os.getuid() and not path.stat().st_mode&0o077,'private owned root required')
    return path

def configuration(path):
    config_path=Path(path)
    require(config_path.is_file() and not config_path.is_symlink(),'owned config file required')
    require(config_path.stat().st_uid==os.getuid() and not config_path.stat().st_mode&0o077,'private config required')
    c=json.loads(config_path.read_text())
    require(c.get('purpose')==PURPOSE,'wrong purpose')
    root=private_root(c['labRoot'])
    state=json.loads((root/'state.private.json').read_text())
    require(state.get('marker')=='hnuhole-android-prerelease-v1' and state.get('integrationScope')=='android-integration-20261019','explicit isolated integration marker required')
    candidate=state.get('candidateScope','').startswith('feed-cas-')
    shared=state.get('feedDeployment',{}).get('id')=='feed-main21-20261020' and state['feedDeployment'].get('sourceSha')==state.get('sourceSha')
    require(candidate or shared,'explicit candidate or deployed isolated main21 scope required')
    target='source' if candidate else 'restore'
    require(state['target']==target,'unexpected private database target')
    require(c['sourceSha']==state['sourceSha'],'source mismatch')
    service=json.loads((root/'material/c.json').read_text())
    require(service['environment']=='dev','development service only')
    origin=urllib.parse.urlsplit(service['publicOrigin'])
    require(origin.scheme=='https' and origin.hostname=='127.0.0.1' and origin.port==state['ports']['c'] and origin.path in ('','/') and not origin.username,'fixed loopback HTTPS upstream required')
    db=urllib.parse.urlsplit(service['databaseUrl']);query=urllib.parse.parse_qs(db.query)
    require(not db.netloc.split('@')[-1] and query.get('host')==[str(root/(target+'-c/socket'))] and query.get('port')==[str(state['pgPorts'][target]['c'])],'private isolated socket required')
    require(isinstance(c['listenPort'],int) and 1024<c['listenPort']<65536 and c['listenPort'] not in state['ports'].values(),'separate loopback port required')
    require(1<=len(c['allowedAccounts'])<=12 and all(re.fullmatch(r'(cas|fault)_[a-z_]{1,32}|feed_(front|device)_[ab]',x) for x in c['allowedAccounts']),'synthetic account allowlist required')
    def material(name):
        p=Path(service[name]);p=p if p.is_absolute() else root/'material'/p
        require(p.is_file() and p.resolve().is_relative_to(root/'material'),'owned test TLS material required')
        return str(p)
    c.update(root=root,upstreamPort=origin.port,certificate=material('publicCertificateFile'),key=material('publicKeyFile'),ca=material('caFile'))
    c['controlRoot']=private_root(root/'fault-proxy')
    return c

def target_allowed(method,path):
    return (method=='PUT' and re.fullmatch(r'/api/v1/posts/[0-9a-f-]{36}/(like|favorite)',path) is not None
            or method=='GET' and path in ('/api/v1/feed','/api/v1/me/feed-preferences')
            or method=='PUT' and path=='/api/v1/comment-commands/')

def valid_rule(rule,allowed):
    require(rule['mode'] in MODES and rule['account'] in allowed,'rule scope rejected')
    require(target_allowed(rule['method'],rule['path']),'rule path rejected')
    require(re.fullmatch('[0-9a-f]{64}',rule['sessionDigest']) is not None,'session digest required')
    require(isinstance(rule.get('holdSeconds',20),(int,float)) and 0<=rule.get('holdSeconds',20)<=90,'bounded hold required')
    if rule['path']=='/api/v1/comment-commands/':
        require(isinstance(rule.get('bodyMarker'),str) and 1<=len(rule['bodyMarker'])<=80,'exact synthetic comment marker required')
    if rule['mode'].startswith('inject_'):
        require(rule['method']=='GET','synthetic errors limited to reads')

def bearer_digest(header):
    if not header or not header.startswith('Bearer '):return None
    value=header[7:]
    if not re.fullmatch('[A-Za-z0-9_-]{43}',value):return None
    raw=base64.urlsafe_b64decode(value+'=')
    return digest(raw) if len(raw)==32 and base64.urlsafe_b64encode(raw).decode().rstrip('=')==value else None

class Journal:
    def __init__(self,root):self.root=Path(root)
    @contextlib.contextmanager
    def locked(self):
        with (self.root/'control.lock').open('a+') as lock:
            fcntl.flock(lock,fcntl.LOCK_EX)
            yield
    def read(self):
        p=self.root/'control.json'
        return json.loads(p.read_text()) if p.exists() else {}
    def write(self,value):
        tmp=self.root/('control-'+uuid.uuid4().hex+'.tmp');tmp.write_text(json.dumps(value));tmp.chmod(0o600);os.replace(tmp,self.root/'control.json')
    def event(self,event,rule,**fields):
        # Callers pass only fixed operation metadata, public test ids and hashes.
        value=dict(atUtc=datetime.now(timezone.utc).isoformat(),event=event,ruleId=rule.get('id'),**fields)
        with (self.root/'events.jsonl').open('a') as f:f.write(json.dumps(value)+'\n')
    def claim(self,method,path,authorization,body,allowed):
        with self.locked():
            r=self.read()
            if r.get('state')!='armed':return None
            valid_rule(r,allowed)
            matches=method==r['method'] and bearer_digest(authorization)==r['sessionDigest']
            if r['path']=='/api/v1/comment-commands/':
                matches=matches and re.fullmatch(r'/api/v1/comment-commands/[A-Za-z0-9_-]{22,86}',path) is not None
                try:obj=json.loads(body)
                except (ValueError,UnicodeError):return None
                if not isinstance(obj,dict):return None
                matches=matches and obj.get('operation')=='CREATE' and obj.get('body')==r['bodyMarker']
            else:matches=matches and path==r['path']
            if not matches:return None
            r['state']='hit';self.write(r);self.event('hit',r,method=method,pathTemplate=r['path'],requestBodySha256=digest(body))
            return r
    def update(self,rule,state,**fields):
        with self.locked():
            current=self.read()
            require(current.get('id')==rule['id'],'rule identity changed')
            current['state']=state;self.write(current);self.event(state,rule,**fields)
    def wait(self,rule,stop,seconds=None):
        deadline=time.monotonic()+(120 if seconds is None else seconds)
        while time.monotonic()<deadline and not stop.is_set():
            with self.locked():
                r=self.read()
                if r.get('id')!=rule['id'] or r.get('cancel'):return False
                if r.get('release'):return True
            time.sleep(.05)
        return seconds is not None and not stop.is_set()

def request_body(stream,headers):
    lengths=headers.get_all('Content-Length',[]);encodings=headers.get_all('Transfer-Encoding',[])
    require(len(lengths)<=1 and len(encodings)<=1 and not (lengths and encodings),'ambiguous body framing')
    if encodings:
        require(encodings[0].lower()=='chunked','unsupported transfer encoding')
        data=bytearray()
        while True:
            line=stream.readline(128);require(line.endswith(b'\r\n') and re.fullmatch(b'[0-9a-fA-F]+\r\n',line),'invalid chunk')
            size=int(line.strip(),16);require(len(data)+size<=MAX_BODY,'body too large')
            if size==0:
                require(stream.readline(8192)==b'\r\n','trailers not accepted');break
            part=stream.read(size);require(len(part)==size and stream.read(2)==b'\r\n','truncated chunk');data.extend(part)
        return bytes(data)
    length=int(lengths[0]) if lengths else 0;require(0<=length<=MAX_BODY,'body too large')
    body=stream.read(length);require(len(body)==length,'truncated body');return body

class Ingress(http.server.ThreadingHTTPServer):
    daemon_threads=True
    def __init__(self,c):
        self.config=c;self.journal=Journal(c['controlRoot']);self.stop_event=threading.Event()
        self.upstream_context=ssl.create_default_context(cafile=c['ca'])
        super().__init__(('127.0.0.1',c['listenPort']),Handler)
        tls=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);tls.minimum_version=ssl.TLSVersion.TLSv1_2;tls.load_cert_chain(c['certificate'],c['key']);self.socket=tls.wrap_socket(self.socket,server_side=True)

class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version='HTTP/1.1'
    def log_message(self,*args):pass
    def do_GET(self):self.forward()
    def do_POST(self):self.forward()
    def do_PUT(self):self.forward()
    def do_DELETE(self):self.forward()
    def do_OPTIONS(self):self.forward()
    def close_only(self):
        self.close_connection=True
        try:self.connection.shutdown(socket.SHUT_RDWR)
        except OSError:pass
        self.connection.close()
    def forward(self):
        rule=None;j=self.server.journal
        try:
            require(self.path.startswith('/') and not self.path.startswith('//'),'origin-form path required')
            url=urllib.parse.urlsplit(self.path);require(not url.netloc and not url.scheme and (url.path.startswith('/api/v1/') or url.path=='/health/ready'),'public path required')
            require(len(self.headers.get_all('Authorization',[]))<=1,'duplicate bearer')
            self.connection.settimeout(45)
            body=request_body(self.rfile,self.headers)
            rule=j.claim(self.command,url.path,self.headers.get('Authorization'),body,self.server.config['allowedAccounts'])
            if rule:
                j.event('condition',rule,conditionSha256=digest(self.headers.get('If-Interaction-Version','')))
                if rule['mode']=='hold_before':
                    j.update(rule,'held_before_upstream')
                    if not j.wait(rule,self.server.stop_event):j.update(rule,'aborted_before_upstream');self.close_only();return
                if rule['mode'].startswith('inject_'):
                    status=int(rule['mode'][-3:]);code='SESSION_INVALID' if status==401 else 'AUTHORIZATION_UNAVAILABLE'
                    raw=json.dumps({'error':{'code':code,'message':'Isolated test ingress response'}}).encode()
                    self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Cache-Control','no-store');self.send_header('X-Request-ID',base64.urlsafe_b64encode(os.urandom(16)).decode().rstrip('='));self.send_header('Content-Length',str(len(raw)));self.send_header('Connection','close');self.end_headers();self.wfile.write(raw);self.close_connection=True;j.update(rule,'injected_not_upstream',status=status);return
            connection=http.client.HTTPSConnection('127.0.0.1',self.server.config['upstreamPort'],context=self.server.upstream_context,timeout=45)
            try:
                if rule:j.event('forwarded_upstream',rule)
                # Preserve repeated end-to-end headers so the product's strict
                # duplicate-condition/idempotency validation still sees them.
                connection.putrequest(self.command,self.path,skip_accept_encoding=True)
                for k,v in self.headers.items():
                    if k.lower() not in HOP:connection.putheader(k,v)
                connection.putheader('Content-Length',str(len(body)))
                connection.putheader('Connection','close');connection.endheaders(body)
                response=connection.getresponse();raw=response.read(MAX_BODY+1);require(len(raw)<=MAX_BODY,'upstream body too large')
                response_headers=response.getheaders();status=response.status
            finally:connection.close()
            if rule:
                meta=dict(upstreamStatus=status,upstreamRequestId=response.getheader('X-Request-ID'),responseSha256=digest(raw),responseVersionSha256=digest(response.getheader('Interaction-Version','')))
                try:
                    obj=json.loads(raw)
                    if isinstance(obj,dict):meta['committedSummary']={k:v for k,v in obj.items() if k in ('postId','taskId','state','outcome','likeCount','favoriteCount','commentCount','likedByMe','favoritedByMe')}
                except (ValueError,UnicodeError):pass
                j.event('upstream_response_received',rule,**meta)
                if rule['mode']=='hold_response' or rule['mode']=='commit_drop_response' and status in (200,202):
                    j.update(rule,'held_response_after_upstream',upstreamStatus=status)
                    released=j.wait(rule,self.server.stop_event,seconds=rule.get('holdSeconds',20) if rule['mode']=='commit_drop_response' else None)
                    if rule['mode']=='commit_drop_response' or not released:
                        j.update(rule,'response_dropped_after_upstream',upstreamStatus=status);self.close_only();return
            self.send_response(status)
            for k,v in response_headers:
                if k.lower() not in HOP and k.lower() not in ('server','date'):self.send_header(k,v)
            self.send_header('Content-Length',str(len(raw)));self.send_header('Connection','close');self.end_headers();self.wfile.write(raw);self.close_connection=True
            if rule:j.update(rule,'response_forwarded_to_client_socket',upstreamStatus=status)
        except (OSError,ValueError,RuntimeError,http.client.HTTPException):
            if rule:
                try:j.update(rule,'transport_closed_or_rejected')
                except (OSError,RuntimeError):pass
            self.close_only()

def main():
    os.umask(0o077)
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--config',required=True);a=p.parse_args()
    c=configuration(a.config);server=Ingress(c)
    def stop(*_):
        server.stop_event.set();threading.Thread(target=server.shutdown,daemon=True).start()
    signal.signal(signal.SIGTERM,stop);signal.signal(signal.SIGINT,stop)
    with server:server.serve_forever(poll_interval=.1)

if __name__=='__main__':main()
