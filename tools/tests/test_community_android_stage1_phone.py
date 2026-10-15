import base64,hashlib,importlib.util,json,socket,struct,tempfile,threading,types,unittest
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
    def test_windows_all_consents_still_block_before_any_manifest_socket_or_command(self):
        args=types.SimpleNamespace(confirmed_window=True,allow_isolated_install=True,auth_session_released=True,allow_owned_adb_key=True,manifest='not-accessed',device='synthetic-device')
        with patch.object(phone.sys,'platform','win32'), patch.object(Path,'read_text') as read, patch.object(Path,'write_text') as write, patch.object(phone.socket,'socket') as socket_call, patch.object(phone.subprocess,'run') as command:
            with self.assertRaisesRegex(ValueError,'BLOCKED_KEY_ISOLATION'):phone.run_phone(args)
            for call in [read,write,socket_call,command]:call.assert_not_called()
    def test_windows_environment_helper_cannot_supply_unverified_isolation(self):
        with patch.object(phone.sys,'platform','win32'):
            with self.assertRaisesRegex(ValueError,'BLOCKED_KEY_ISOLATION'):phone.adb_environment(Path('synthetic-owned-root'))
    def test_existing_host_identity_exception_requires_exact_flag_and_metadata_verification(self):
        with patch.object(phone.sys,'platform','win32'), patch.object(phone,'verify_existing_host_usb_identity') as verify:
            for value in [False,None,1,'true']:
                with self.assertRaisesRegex(ValueError,'BLOCKED_KEY_ISOLATION'):phone.require_adb_key_isolation(value)
            verify.assert_not_called()
            phone.require_adb_key_isolation(True)
            verify.assert_called_once_with()
    def test_existing_host_identity_does_not_replace_other_consents(self):
        args=types.SimpleNamespace(confirmed_window=True,allow_isolated_install=True,auth_session_released=False,allow_owned_adb_key=True,allow_existing_host_usb_identity=True)
        with patch.object(phone,'verify_existing_host_usb_identity') as verify, patch.object(phone.subprocess,'run') as command:
            with self.assertRaises(ValueError):phone.run_phone(args)
            verify.assert_not_called();command.assert_not_called()
    def test_explicit_existing_identity_environment_uses_verified_os_profile(self):
        profile=Path('synthetic-profile').absolute()
        with patch.object(phone.sys,'platform','win32'), patch.object(phone,'verify_existing_host_usb_identity',return_value=profile), patch.dict(phone.os.environ,{'ADB_VENDOR_KEYS':'foreign','ADB_SERVER_SOCKET':'tcp:foreign:5037'}):
            env=phone.adb_environment(Path('owned-task'),True)
            for key in ['HOME','USERPROFILE','ANDROID_USER_HOME','ANDROID_SDK_HOME']:self.assertEqual(env[key],str(profile))
            self.assertNotIn('ADB_VENDOR_KEYS',env);self.assertNotIn('ADB_SERVER_SOCKET',env)
    def test_previous_upgrade_requires_fingerprinted_owned_finished_same_device_and_signer(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);(root/'.owner').write_text('HNUHOLE_COMMUNITY_ANDROID_STAGE1_V1');cert='a'*64;device='synthetic-device'
            old={'owner':'HNUHOLE_COMMUNITY_ANDROID_STAGE1_V1','applicationId':phone.PACKAGE,'sourceFingerprint':'fixed','runId':'prior-owned','apks':{}}
            for mode in ['acceptance','normal']:
                apk=root/(mode+'.apk');apk.write_bytes(mode.encode());old['apks'][mode]={'path':str(apk),'sha256':hashlib.sha256(apk.read_bytes()).hexdigest(),'certificateSha256':cert,'apkSignatureVerified':True}
            path=root/'manifest.json';path.write_text(json.dumps(old));proof=root/'artifact-proof.json';proof.write_text(json.dumps({'applicationId':phone.PACKAGE,'sourceFingerprint':'fixed','apks':old['apks']}))
            latch={'runId':'prior-owned','deviceIdHash':hashlib.sha256(device.encode()).hexdigest()};(root/'device-started.json').write_text(json.dumps(latch))
            result={'runId':'prior-owned','automaticDeviceChecks':'FAIL','apkSha256':old['apks']['acceptance']['sha256']};(root/'device-result.json').write_text(json.dumps(result))
            mh=hashlib.sha256(path.read_bytes()).hexdigest();ph=hashlib.sha256(proof.read_bytes()).hexdigest();current={'apks':old['apks']}
            self.assertEqual(phone.previous_candidate_hashes(path,mh,ph,current,device),{v['sha256'] for v in old['apks'].values()})
            for mutation in ['manifest-hash','proof-hash','device','signer','unknown-outcome']:
                with self.subTest(mutation=mutation), patch.object(phone.subprocess,'run') as adb:
                    selected=current if mutation!='signer' else {'apks':{'acceptance':{'certificateSha256':'b'*64,'apkSignatureVerified':True}}}
                    if mutation=='unknown-outcome':(root/'device-result.json').write_text(json.dumps({**result,'automaticDeviceChecks':'UNKNOWN'}))
                    with self.assertRaises(ValueError):phone.previous_candidate_hashes(path,'0'*64 if mutation=='manifest-hash' else mh,'0'*64 if mutation=='proof-hash' else ph,selected,'other' if mutation=='device' else device)
                    adb.assert_not_called()
            self.assertEqual(phone.previous_candidate_hashes(None,None,None,current,device),set())
    def test_failed_install_stdout_is_private_bounded_and_other_operations_never_saved(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);log=root/'install-diagnostics.private.log'
            for parts,code in [(('install','-r','candidate.apk'),0),(('shell','run-as','owned','cat','private-witness'),1),(('get-state',),1)]:
                phone.preserve_install_failure(root,parts,code,b'never-record-other-stdout')
            self.assertFalse(log.exists())
            payload=b'INSTALL_FAILED_USER_RESTRICTED\n'+b'x'*phone.INSTALL_DIAGNOSTIC_LIMIT+b'not-retained-tail'
            phone.preserve_install_failure(root,('install','-r','candidate.apk'),1,payload)
            lines=log.read_bytes();header,body=lines.split(b'\n',1)
            self.assertTrue(json.loads(header)['truncated']);self.assertEqual(body,payload[:phone.INSTALL_DIAGNOSTIC_LIMIT]+b'\n')
            self.assertNotIn(b'never-record-other-stdout',lines);self.assertNotIn(b'not-retained-tail',lines)
    def test_existing_host_identity_metadata_only_rejects_missing_or_reparse_keys(self):
        import ctypes
        from unittest.mock import Mock
        profile=str(Path('synthetic-profile').absolute())
        def profile_api(_window,_id,_token,_flags,buffer):buffer.value=profile;return 0
        shell=Mock();shell.SHGetFolderPathW.side_effect=profile_api
        for fault in [None,'adbkey','adbkey.pub','.android','missing']:
            def metadata(path):
                if fault=='missing' and path.name=='adbkey.pub':raise FileNotFoundError()
                return types.SimpleNamespace(st_file_attributes=0x400 if path.name==fault else 0,st_mode=phone.stat.S_IFREG if path.name in ['adbkey','adbkey.pub'] else phone.stat.S_IFDIR)
            with self.subTest(fault=fault), patch.object(ctypes,'WinDLL',return_value=shell,create=True), patch.object(Path,'lstat',autospec=True,side_effect=metadata), patch.object(Path,'read_bytes') as read_bytes, patch.object(Path,'read_text') as read_text:
                if fault is None:phone.verify_existing_host_usb_identity()
                else:
                    with self.assertRaises(ValueError):phone.verify_existing_host_usb_identity()
                read_bytes.assert_not_called();read_text.assert_not_called()
    def test_owned_adb_port_and_inherited_foreign_socket_rejected(self):
        for port in [5037,0,True,'30001',65536]:
            with self.assertRaises(ValueError):phone.adb_port(port)
        self.assertEqual(phone.adb_port(30001),30001)
        with patch.object(phone.sys,'platform','linux'), patch.dict(phone.os.environ,{'ADB_SERVER_SOCKET':'tcp:foreign:5037','ANDROID_ADB_SERVER_PORT':'5037','ANDROID_SERIAL':'foreign','ADB_VENDOR_KEYS':'foreign'},clear=False):
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
    def test_only_get_isolate_has_larger_metadata_bound(self):
        from unittest.mock import Mock
        vm=object.__new__(phone.VM);vm.sequence=0;vm.socket=Mock();vm.send=Mock();vm.receive=Mock(side_effect=[{'id':str(i),'result':{}} for i in range(1,5)])
        for method in ['getIsolate','getVM','resume','ext.flutter.driver']:vm.rpc(method)
        self.assertEqual([call.args[0] for call in vm.receive.call_args_list],[phone.ISOLATE_METADATA_LIMIT,phone.LIMIT,phone.LIMIT,phone.LIMIT])
    def test_isolate_metadata_real_size_allowed_but_driver_and_oversize_rejected(self):
        from unittest.mock import Mock
        body=json.dumps({'metadata':'x'*172543}).encode()
        frame=b'\x81\x7f'+struct.pack('!Q',len(body))+body
        vm=object.__new__(phone.VM);vm.buffer=frame;vm.socket=Mock()
        self.assertEqual(len(vm.receive(phone.ISOLATE_METADATA_LIMIT)['metadata']),172543)
        vm.buffer=frame
        with self.assertRaises(ValueError):vm.receive()
        vm.buffer=b'\x81\x7f'+struct.pack('!Q',phone.ISOLATE_METADATA_LIMIT+1)
        with self.assertRaises(ValueError):vm.receive(phone.ISOLATE_METADATA_LIMIT)
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
