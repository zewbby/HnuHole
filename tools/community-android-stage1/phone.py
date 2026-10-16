#!/usr/bin/env python3
"""Stage1 consent-gated phone runner; stdlib VM protocol, no shared Flutter SDK."""
import argparse,base64,hashlib,json,os,re,secrets,socket,struct,subprocess,sys,time
from pathlib import Path
from urllib.parse import urlsplit
PACKAGE='org.hnuhole.hnuhole_mobile.communityf5'
ACTIVITY='org.hnuhole.hnuhole_mobile.MainActivity'
CHECKS=['CA-A01','CA-A02','CA-A03','CA-A04','CA-A05','CA-A06','CA-A07','CA-A10']
LIMIT=131072
class VM:
    def __init__(self,uri):
        parsed=urlsplit(uri)
        if parsed.scheme!='http' or parsed.hostname!='127.0.0.1' or not parsed.port or parsed.username or parsed.query or parsed.fragment:raise ValueError('owned loopback VM required')
        self.socket=socket.create_connection(('127.0.0.1',parsed.port),timeout=20)
        self.socket.settimeout(20);self.buffer=b'';self.sequence=0
        key=base64.b64encode(secrets.token_bytes(16)).decode();path=parsed.path.rstrip('/')+'/ws'
        request=f'GET {path} HTTP/1.1\r\nHost: 127.0.0.1:{parsed.port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n'
        self.socket.sendall(request.encode())
        while b'\r\n\r\n' not in self.buffer:
            chunk=self.socket.recv(4096)
            if not chunk:raise RuntimeError('VM handshake closed; no request replay')
            self.buffer+=chunk
            if len(self.buffer)>16384:raise ValueError('VM handshake bound exceeded')
        header,self.buffer=self.buffer.split(b'\r\n\r\n',1)
        expected=base64.b64encode(hashlib.sha1((key+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest()).decode()
        fields={}
        for line in header.decode('ascii').split('\r\n')[1:]:
            k,v=line.split(':',1);fields[k.lower()]=v.strip()
        if not header.startswith(b'HTTP/1.1 101 ') or fields.get('sec-websocket-accept')!=expected:raise ValueError('VM handshake rejected')
    def exact(self,n):
        while len(self.buffer)<n:
            chunk=self.socket.recv(max(4096,n-len(self.buffer)))
            if not chunk:raise RuntimeError('VM closed before original result')
            self.buffer+=chunk
        value=self.buffer[:n];self.buffer=self.buffer[n:];return value
    def send(self,data,opcode=1):
        raw=data if isinstance(data,bytes) else json.dumps(data,separators=(',',':')).encode()
        if len(raw)>LIMIT:raise ValueError('VM send bound exceeded')
        mask=secrets.token_bytes(4);length=len(raw)
        header=bytes([0x80|opcode,0x80|length]) if length<126 else bytes([0x80|opcode,0x80|126])+struct.pack('!H',length) if length<65536 else bytes([0x80|opcode,0x80|127])+struct.pack('!Q',length)
        self.socket.sendall(header+mask+bytes(b^mask[i%4] for i,b in enumerate(raw)))
    def receive(self):
        message=b''
        while True:
            first,second=self.exact(2);opcode=first&15;length=second&127
            if second&128:raise ValueError('masked server frame rejected')
            if length==126:length=struct.unpack('!H',self.exact(2))[0]
            elif length==127:length=struct.unpack('!Q',self.exact(8))[0]
            if length>LIMIT or len(message)+length>LIMIT:raise ValueError('VM result bound exceeded')
            raw=self.exact(length)
            if opcode==8:raise RuntimeError('VM closed with unknown original test outcome')
            if opcode==9:self.send(raw,10);continue
            if opcode==10:continue
            if opcode not in (0,1):raise ValueError('text VM frames required')
            message+=raw
            if first&128:return json.loads(message.decode())
    def rpc(self,method,params=None,timeout=30):
        self.sequence+=1;key=str(self.sequence);self.socket.settimeout(timeout)
        self.send({'jsonrpc':'2.0','id':key,'method':method,'params':params or {}})
        while True:
            reply=self.receive()
            if reply.get('id')!=key:continue
            if 'error' in reply:raise RuntimeError('VM operation failed; no request replay')
            return reply['result']
    def run(self):
        end=time.monotonic()+100;isolate=None
        while time.monotonic()<end:
            vm=self.rpc('getVM');items=vm.get('isolates',[])
            if items:
                target=next((v for v in items if str(v.get('number'))=='0'),items[0])
                current=self.rpc('getIsolate',{'isolateId':target['id']})
                if current.get('pauseEvent',{}).get('kind')=='PauseStart':self.rpc('resume',{'isolateId':target['id']})
                if 'ext.flutter.driver' in current.get('extensionRPCs',[]):isolate=target['id'];break
            time.sleep(.2)
        if isolate is None:raise RuntimeError('integration extension not ready')
        result=self.rpc('ext.flutter.driver',{'isolateId':isolate,'command':'request_data','timeout':'900000'},timeout=920)
        if result.get('isError'):raise RuntimeError('integration extension failed')
        return json.loads(result['response']['message'])
    def close(self):self.socket.close()

def filtered_result(raw):
    passed=raw.get('result')=='true';data=raw.get('data') or {}
    allowed={'checkpoints','counters','sql','manualChineseImeVerified','phoneUsed','actualMainCalled','hostVaultSubstitutes','scope'}
    public={k:v for k,v in data.items() if k in allowed}
    if passed and (data.get('phoneUsed') is not True or data.get('actualMainCalled') is not True or data.get('hostVaultSubstitutes') is not False or set(data.get('checkpoints',{}))!=set(CHECKS) or not all(data['checkpoints'].values())):raise ValueError('device scope/result mismatch')
    for key in ('counters','sql'):
        if key in public and not all(isinstance(v,(int,bool)) for v in public[key].values()):raise ValueError('only boolean/count SQL evidence allowed')
    return {'automaticDeviceChecks':'PASS' if passed else 'FAIL','data':public,'task1Result':'PARTIAL_MANUAL_IME_NOT_RUN' if passed else 'FAIL','rawFailureDetailsRetained':False}

def consent(window,install,released,key):
    if not (window and install and released and key):raise ValueError('explicit device window, isolated install, own USB debugging key and auth-session release confirmation required before any ADB call')

def require_adb_key_isolation():
    # Windows ADB resolves its default key via the OS profile API. HOME and
    # USERPROFILE overrides do not prove isolation; ADB_VENDOR_KEYS adds keys.
    # No validated isolated-profile/key-directory mechanism exists here yet.
    if sys.platform == 'win32':
        raise ValueError('BLOCKED_KEY_ISOLATION: Windows ADB dedicated key isolation is unproven; environment HOME/USERPROFILE overrides and a dedicated server port are insufficient. A verified independent OS profile or verified ADB dedicated-key-directory support is required before any ADB call. New OS accounts/security configuration or shared-key exceptions require explicit changed authorization.')

def adb_environment(root):
    require_adb_key_isolation()
    # Own server port; inherited global/other-session sockets are never used.
    env={k:v for k,v in os.environ.items() if k not in
         ('ADB_SERVER_SOCKET','ANDROID_ADB_SERVER_PORT','ANDROID_SERIAL','ADB_VENDOR_KEYS','ANDROID_USER_HOME','ANDROID_SDK_HOME')}
    home=str(Path(root)/'adb-home')
    env.update(HOME=home,USERPROFILE=home,ANDROID_USER_HOME=home,ANDROID_SDK_HOME=home)
    return env

def adb_port(value):
    if type(value) is not int or not 1024 <= value <= 65535 or value == 5037:
        raise ValueError('dedicated non-default ADB server port required')
    return value

def run_phone(args):
    consent(args.confirmed_window,args.allow_isolated_install,args.auth_session_released,args.allow_owned_adb_key)
    require_adb_key_isolation()  # Before manifest access, socket binding or ADB.
    if not re.fullmatch(r'[A-Za-z0-9._:-]{1,128}',args.device or ''):raise ValueError('one explicit device ID required')
    root=Path(args.manifest).resolve().parent;manifest=json.loads(Path(args.manifest).read_text())
    if (root/'.owner').read_text().strip()!='HNUHOLE_COMMUNITY_ANDROID_STAGE1_V1' or manifest['owner']!='HNUHOLE_COMMUNITY_ANDROID_STAGE1_V1' or manifest['applicationId']!=PACKAGE:raise ValueError('owned stage1 manifest required')
    if (root/'device-started.json').exists():raise ValueError('original run already started; inspect its result/SQL before any retry')
    adb=Path(manifest['adb']);
    if hashlib.sha256(adb.read_bytes()).hexdigest()!=manifest['adbSha256']:raise ValueError('owned ADB fingerprint changed')
    for name,digest in manifest['adbFiles'].items():
        if name not in ['adb.exe','AdbWinApi.dll','AdbWinUsbApi.dll','libwinpthread-1.dll'] or hashlib.sha256((adb.parent/name).read_bytes()).hexdigest()!=digest:raise ValueError('owned ADB support file changed')
    for mode in ('acceptance','normal'):
        apk=Path(manifest['apks'][mode]['path'])
        if hashlib.sha256(apk.read_bytes()).hexdigest()!=manifest['apks'][mode]['sha256']:raise ValueError('fixed APK changed')
    server_port=adb_port(manifest['adbServerPort'])
    # Fail before ADB if this prepared server port is already in use.
    with socket.socket() as probe:probe.bind(('127.0.0.1',server_port))
    log=root/'device-private.log'
    def command(*parts,optional=False):
        done=subprocess.run([str(adb),'-P',str(server_port),'-s',args.device,*map(str,parts)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=180,env=adb_environment(root))
        with log.open('ab') as out:out.write(done.stderr)
        if done.returncode and not optional:raise RuntimeError('owned device operation failed; uncertain writes are never replayed')
        return done.stdout.decode(errors='replace').strip()
    print('Waiting for the confirmed phone to authorize this task USB debugging key (up to 90s).',flush=True)
    end=time.monotonic()+90;state=''
    while time.monotonic()<end:
        state=command('get-state',optional=True)
        if state=='device':break
        time.sleep(.5)
    if state!='device':raise ValueError('selected physical device is not authorized/ready; no App run started')
    if command('shell','getprop','ro.kernel.qemu')=='1':raise ValueError('physical Android required')
    abi=command('shell','getprop','ro.product.cpu.abilist')
    if 'arm64-v8a' not in abi:raise ValueError('prepared APK requires ARM64 Android')
    path=command('shell','pm','path',PACKAGE,optional=True)
    if path:
        match=re.fullmatch(r'package:(/data/app/[A-Za-z0-9_~./+=-]+/base.apk)',path)
        if not match:raise ValueError('unknown installed package shape')
        digest=command('shell','sha256sum',match[1]).split()[0]
        if digest not in {manifest['apks'][k]['sha256'] for k in ('acceptance','normal')}:raise ValueError('existing package is not this task candidate; do not overwrite')
    (root/'device-started.json').write_text(json.dumps({'runId':manifest['runId'],'deviceIdHash':hashlib.sha256(args.device.encode()).hexdigest(),'startedAtUnix':int(time.time()),'windowConfirmed':True,'isolatedInstallConfirmed':True,'authSessionReleasedConfirmed':True,'ownedUsbDebugKeyConfirmed':True})+'\n')
    forwarded=[];reverse=[]
    try:
        for port in manifest['deviceReversePorts']:
            current=command('reverse','--list',optional=True)
            if re.search(r'\btcp:'+str(port)+r'\b',current):raise ValueError('existing reverse-port mapping; do not replace')
            command('reverse','--no-rebind','tcp:'+str(port),'tcp:'+str(port));reverse.append(port)
        command('install','-r',manifest['apks']['acceptance']['path'])
        command('shell','am','start','-n',PACKAGE+'/'+ACTIVITY,'--ez','hnuhole-device-driver','true','--es','hnuhole-device-phase','community-stage1')
        vm=None;end=time.monotonic()+100
        while time.monotonic()<end:
            text=command('shell','run-as',PACKAGE,'cat','files/owned-device-driver-vm.json',optional=True)
            try:
                value=json.loads(text);pid=command('shell','pidof',PACKAGE)
                if pid.isdecimal() and value.get('pid')==int(pid):vm=value['uri'];break
            except (ValueError,KeyError):pass
            time.sleep(.3)
        if vm is None:raise RuntimeError('own VM witness unavailable; do not restart unknown run')
        parsed=urlsplit(vm)
        if parsed.scheme!='http' or parsed.hostname!='127.0.0.1' or not parsed.port or parsed.username or parsed.query or parsed.fragment:raise ValueError('loopback VM witness rejected')
        forward=command('forward','tcp:0','tcp:'+str(parsed.port));
        if not forward.isdecimal():raise ValueError('allocated forward port unavailable')
        forwarded.append(int(forward));uri=f'http://127.0.0.1:{forward}'+parsed.path
        client=VM(uri)
        try:report=filtered_result(client.run())
        finally:client.close()
        report.update(runId=manifest['runId'],apkSha256=manifest['apks']['acceptance']['sha256'],sourceFingerprint=manifest['sourceFingerprint'],physicalDevice=True)
        (root/'device-result.json').write_text(json.dumps(report,indent=2)+'\n')
        if report['automaticDeviceChecks']!='PASS':raise RuntimeError('device assertions failed; preserve original state for diagnosis')
        if args.launch_manual:
            command('install','-r',manifest['apks']['normal']['path'])
            command('shell','am','start','-n',PACKAGE+'/'+ACTIVITY)
        print('Automated stage1 completed; actual manual Chinese keyboard check remains. No credentials or VM URI exported.')
    finally:
        for port in forwarded:command('forward','--remove','tcp:'+str(port),optional=True)
        # Keep this run's endpoint reverses while its isolated normal App is used.
        # Only mappings created by this run may be removed after the agreed window.
        (root/'own-device-mappings.json').write_text(json.dumps({'reversePortsCreatedByThisRun':reverse,'forwardPortsRemoved':forwarded,'package':PACKAGE})+'\n')

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--manifest',required=True);p.add_argument('--device')
    p.add_argument('--confirmed-window',action='store_true');p.add_argument('--allow-isolated-install',action='store_true');p.add_argument('--auth-session-released',action='store_true');p.add_argument('--allow-owned-adb-key',action='store_true');p.add_argument('--launch-manual',action='store_true');p.add_argument('--plan-only',action='store_true')
    args=p.parse_args()
    if args.plan_only:
        print('Plan only: Windows device execution is BLOCKED_KEY_ISOLATION until a verified independent OS profile or verified dedicated-key-directory ADB is available; consent flags cannot bypass this guard. After authorized isolation and USB release: recheck hashes/ready/empty lab -> physical ARM64 -> owned mappings -> isolated APK -> VM result -> manual IME. No manifest or ADB accessed.')
    else:run_phone(args)
