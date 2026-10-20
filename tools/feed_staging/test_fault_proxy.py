import email.message
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('fault_proxy',Path(__file__).with_name('fault_proxy.py'))
proxy=importlib.util.module_from_spec(spec);spec.loader.exec_module(proxy)

class FaultScopeTests(unittest.TestCase):
    def test_shared_marker_source_and_socket_must_agree(self):
        import os
        if os.getuid()==0:self.skipTest('configuration deliberately refuses root')
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);root.chmod(0o700);(root/'material').mkdir();(root/'fault-proxy').mkdir(mode=0o700)
            for name in ('ca','cert','key'):(root/'material'/name).write_text('unit material')
            state=dict(marker='hnuhole-android-prerelease-v1',integrationScope='android-integration-20261019',sourceSha='merged',target='restore',ports={'c':12346},pgPorts={'restore':{'c':12347}},feedDeployment={'id':'feed-main21-20261020','sourceSha':'merged'})
            service=dict(environment='dev',publicOrigin='https://127.0.0.1:12346',databaseUrl='postgres://runtime@/hnuhole_c?host='+str(root/'restore-c/socket')+'&port=12347',publicCertificateFile='cert',publicKeyFile='key',caFile='ca')
            config=root/'config.json';config.write_text(json.dumps(dict(purpose=proxy.PURPOSE,labRoot=str(root),sourceSha='merged',listenPort=12348,allowedAccounts=['feed_device_b'])));config.chmod(0o600)
            def save():
                (root/'state.private.json').write_text(json.dumps(state));(root/'material/c.json').write_text(json.dumps(service))
            save();self.assertEqual(proxy.configuration(config)['upstreamPort'],12346)
            state['feedDeployment']['sourceSha']='old';save()
            with self.assertRaises(RuntimeError):proxy.configuration(config)
            state['feedDeployment']['sourceSha']='merged';service['databaseUrl']='postgres://runtime@production/hnuhole_c';save()
            with self.assertRaises(RuntimeError):proxy.configuration(config)
    def test_configuration_rejects_production_and_unknown_roots(self):
        import os
        if os.getuid()==0:self.skipTest('configuration deliberately refuses root')
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);root.chmod(0o700);(root/'material').mkdir()
            config=root/'config.json';config.write_text(json.dumps(dict(purpose=proxy.PURPOSE,labRoot=str(root),sourceSha='test',listenPort=12345,allowedAccounts=['cas_appeal'])));config.chmod(0o600)
            (root/'state.private.json').write_text(json.dumps(dict(marker='unknown',candidateScope='feed-cas-test',sourceSha='test')))
            with self.assertRaises(RuntimeError):proxy.configuration(config)
            (root/'state.private.json').write_text(json.dumps(dict(marker='hnuhole-android-prerelease-v1',integrationScope='android-integration-20261019',candidateScope='feed-cas-test',sourceSha='test',target='source')))
            (root/'material/c.json').write_text(json.dumps(dict(environment='production')))
            with self.assertRaises(RuntimeError):proxy.configuration(config)
            (root/'material/c.json').write_text(json.dumps(dict(environment='dev',publicOrigin='https://example.org')))
            with self.assertRaises((RuntimeError,KeyError)):proxy.configuration(config)
            config.chmod(0o644)
            with self.assertRaises(RuntimeError):proxy.configuration(config)

    def test_rule_scope_and_one_shot(self):
        raw=b'x'*32
        import base64
        bearer='Bearer '+base64.urlsafe_b64encode(raw).decode().rstrip('=')
        r=dict(id='one',state='armed',mode='hold_before',account='cas_appeal',method='PUT',path='/api/v1/posts/11111111-1111-4111-8111-111111111111/like',sessionDigest=proxy.digest(raw),holdSeconds=20)
        proxy.valid_rule(r,['cas_appeal'])
        with tempfile.TemporaryDirectory() as temp:
            j=proxy.Journal(temp);j.write(r)
            self.assertIsNone(j.claim('GET',r['path'],bearer,b'{}',['cas_appeal']))
            self.assertIsNone(j.claim('PUT',r['path'],'Bearer invalid',b'{}',['cas_appeal']))
            self.assertEqual(j.claim('PUT',r['path'],bearer,b'{"liked":true}',['cas_appeal'])['id'],'one')
            self.assertIsNone(j.claim('PUT',r['path'],bearer,b'{}',['cas_appeal']))
            log=(Path(temp)/'events.jsonl').read_text();self.assertNotIn(bearer,log);self.assertNotIn(r['sessionDigest'],log)
        for method,path in [('POST',r['path']),('PUT','/api/v1/auth/sessions'),('GET','https://example.org/api/v1/feed')]:
            with self.assertRaises(RuntimeError):proxy.valid_rule(dict(r,method=method,path=path),['cas_appeal'])
        with self.assertRaises(RuntimeError):proxy.valid_rule(dict(r,mode='inject_503'),['cas_appeal'])
        with self.assertRaises(RuntimeError):proxy.valid_rule(dict(r,holdSeconds=121),['cas_appeal'])

    def test_body_framing(self):
        h=email.message.Message();h['Content-Length']='3'
        self.assertEqual(proxy.request_body(io.BytesIO(b'abc'),h),b'abc')
        h['Transfer-Encoding']='chunked'
        with self.assertRaises(RuntimeError):proxy.request_body(io.BytesIO(b'abc'),h)
        h=email.message.Message();h['Transfer-Encoding']='chunked'
        self.assertEqual(proxy.request_body(io.BytesIO(b'3\r\nabc\r\n0\r\n\r\n'),h),b'abc')
        for raw in (b'3\r\nab\r\n',b'3;bad\r\nabc\r\n0\r\n\r\n',b'0\r\nX: y\r\n\r\n'):
            with self.assertRaises(RuntimeError):proxy.request_body(io.BytesIO(raw),h)

    def test_get_and_comment_matching(self):
        import base64
        raw=b'y'*32;bearer='Bearer '+base64.urlsafe_b64encode(raw).decode().rstrip('=')
        r=dict(id='comment',state='armed',mode='commit_drop_response',account='cas_appeal',method='PUT',path='/api/v1/comment-commands/',sessionDigest=proxy.digest(raw),bodyMarker='FAControlledComment',holdSeconds=35)
        proxy.valid_rule(r,['cas_appeal'])
        with tempfile.TemporaryDirectory() as temp:
            j=proxy.Journal(temp);j.write(r)
            path='/api/v1/comment-commands/'+'a'*22
            self.assertIsNone(j.claim('PUT',path,bearer,b'{"operation":"CREATE","body":"other"}',['cas_appeal']))
            self.assertIsNotNone(j.claim('PUT',path,bearer,b'{"operation":"CREATE","body":"FAControlledComment"}',['cas_appeal']))
        for mode in ('inject_401','inject_503','hold_response'):
            proxy.valid_rule(dict(r,mode=mode,method='GET',path='/api/v1/feed'),['cas_appeal'])

if __name__=='__main__':unittest.main()
