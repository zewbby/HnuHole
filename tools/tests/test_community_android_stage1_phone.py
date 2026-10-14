import base64,hashlib,importlib.util,json,socket,struct,threading,types,unittest
from pathlib import Path
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('stage1_phone',ROOT/'tools/community-android-stage1/phone.py');phone=importlib.util.module_from_spec(spec);spec.loader.exec_module(phone)
class PhoneGuardTests(unittest.TestCase):
    def test_no_consent_rejected_before_manifest_or_adb(self):
        args=types.SimpleNamespace(confirmed_window=False,allow_isolated_install=True,auth_session_released=True,allow_owned_adb_key=True,manifest='not-accessed',device='not-accessed')
        with patch.object(phone.subprocess,'run') as call:
            with self.assertRaises(ValueError):phone.run_phone(args)
            call.assert_not_called()
    def test_release_and_install_each_required(self):
        for flags in [(True,False,True,True),(True,True,False,True),(False,False,False,False),(True,True,True,False)]:
            with self.assertRaises(ValueError):phone.consent(*flags)
    def test_owned_adb_port_and_inherited_foreign_socket_rejected(self):
        for port in [5037,0,True,'30001',65536]:
            with self.assertRaises(ValueError):phone.adb_port(port)
        self.assertEqual(phone.adb_port(30001),30001)
        with patch.dict(phone.os.environ,{'ADB_SERVER_SOCKET':'tcp:foreign:5037','ANDROID_ADB_SERVER_PORT':'5037','ANDROID_SERIAL':'foreign','ADB_VENDOR_KEYS':'foreign'},clear=False):
            env=phone.adb_environment(Path("owned-task-root"))
            for key in ['ADB_SERVER_SOCKET','ANDROID_ADB_SERVER_PORT','ANDROID_SERIAL','ADB_VENDOR_KEYS']:self.assertNotIn(key,env)
            self.assertEqual(env['USERPROFILE'],str(Path('owned-task-root/adb-home')))
            self.assertEqual(env['ANDROID_USER_HOME'],env['USERPROFILE'])
    def test_fake_or_incomplete_device_success_rejected(self):
        data={'phoneUsed':False,'actualMainCalled':False,'hostVaultSubstitutes':True,'checkpoints':{}}
        with self.assertRaises(ValueError):phone.filtered_result({'result':'true','data':data})
    def test_failure_details_and_credentials_never_exported(self):
        report=phone.filtered_result({'result':'false','failureDetails':['private-secret'],'data':{'credentials':'private-secret','sql':{'closed':0}}})
        self.assertNotIn('private-secret',json.dumps(report));self.assertEqual(report['automaticDeviceChecks'],'FAIL')
    def test_loopback_vm_only_before_socket_connect(self):
        with patch.object(phone.socket,'create_connection') as call:
            for uri in ['http://remote.example:1234/auth/','https://127.0.0.1:1234/auth/','http://user@127.0.0.1:1234/auth/','http://127.0.0.1:1234/auth/?token=private']:
                with self.assertRaises(ValueError):phone.VM(uri)
            call.assert_not_called()
    def test_masked_server_and_oversized_results_rejected(self):
        from unittest.mock import Mock
        for frame in [b'\x81\x80',b'\x81\x7f'+struct.pack('!Q',phone.LIMIT+1)]:
            vm=object.__new__(phone.VM);vm.buffer=frame;vm.socket=Mock()
            with self.assertRaises(ValueError):vm.receive()
            vm.socket.recv.assert_not_called()
    def test_vm_handshake_eof_does_not_spin(self):
        from unittest.mock import Mock
        fake=Mock();fake.recv.return_value=b''
        with patch.object(phone.socket,'create_connection',return_value=fake):
            with self.assertRaises(RuntimeError):phone.VM('http://127.0.0.1:30001/synthetic/')
    def test_stdlib_vm_protocol_roundtrip_on_synthetic_loopback(self):
        listener=socket.socket();listener.bind(('127.0.0.1',0));listener.listen(1);port=listener.getsockname()[1];errors=[];seen=[]
        def server():
            try:
                conn,_=listener.accept();buffer=b''
                while b'\r\n\r\n' not in buffer:buffer+=conn.recv(4096)
                header=buffer.split(b'\r\n\r\n')[0].decode();key=next(x.split(':',1)[1].strip() for x in header.split('\r\n') if x.lower().startswith('sec-websocket-key:'))
                accept=base64.b64encode(hashlib.sha1((key+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest()).decode()
                conn.sendall(('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: '+accept+'\r\n\r\n').encode())
                def exact(n):
                    out=b''
                    while len(out)<n:out+=conn.recv(n-len(out))
                    return out
                for _ in range(3):
                    first,second=exact(2);self.assertTrue(second&128);n=second&127
                    if n==126:n=struct.unpack('!H',exact(2))[0]
                    elif n==127:n=struct.unpack('!Q',exact(8))[0]
                    mask=exact(4);raw=exact(n);request=json.loads(bytes(v^mask[i%4] for i,v in enumerate(raw)));seen.append(request['method'])
                    if request['method']=='getVM':result={'isolates':[{'id':'isolates/1','number':'0'}]}
                    elif request['method']=='getIsolate':result={'extensionRPCs':['ext.flutter.driver'],'pauseEvent':{'kind':'Resume'}}
                    else:
                        self.assertEqual(request['params']['command'],'request_data');self.assertEqual(request['params']['timeout'],'900000')
                        result={'isError':False,'response':{'message':json.dumps({'result':'true','data':{'syntheticTransportSelfTest':True}})}}
                    reply=json.dumps({'jsonrpc':'2.0','id':request['id'],'result':result}).encode()
                    conn.sendall(bytes([0x81,len(reply)])+reply if len(reply)<126 else bytes([0x81,126])+struct.pack('!H',len(reply))+reply)
                conn.close()
            except BaseException as e:errors.append(e)
            finally:listener.close()
        thread=threading.Thread(target=server,daemon=True);thread.start();client=phone.VM(f'http://127.0.0.1:{port}/synthetic/')
        try:self.assertEqual(client.run()['result'],'true')
        finally:client.close()
        thread.join(5);self.assertFalse(thread.is_alive());self.assertEqual(errors,[]);self.assertEqual(seen,['getVM','getIsolate','ext.flutter.driver'])
if __name__=='__main__':unittest.main()
