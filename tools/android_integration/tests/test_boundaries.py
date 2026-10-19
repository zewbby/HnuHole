import json
import copy
import os
from pathlib import Path, PurePosixPath
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit
import urllib.request
import subprocess

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from lab import IntegrationLab, Lab
from data import Data, NoRedirect
from policy import BASE, bind_public_configuration, require, owned_tool_environment


class IntegrationBoundaries(unittest.TestCase):
    @unittest.skipUnless(os.name=='posix','actual ownership/path checks require the Linux execution host')
    def test_shared_or_missing_cache_and_python_are_refused(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            env={}
            for name in ('GOCACHE','GOMODCACHE','GOPATH'):
                directory=root/name;directory.mkdir();env[name]=str(directory)
            binary=root/'python/bin/python';binary.parent.mkdir(parents=True);binary.write_text('test interpreter metadata only')
            (root/'python/pyvenv.cfg').write_text('test metadata')
            env['PRERELEASE_IMAGE_PYTHON']=str(binary)
            owned_tool_environment(root,env)
            for name in env:
                changed=dict(env);changed[name]='/tmp/outside-task-cache-or-python'
                with self.subTest(name=name),self.assertRaises(RuntimeError):owned_tool_environment(root,changed)

    def test_public_configuration_is_bound_to_the_actual_backend(self):
        state=dict(sourceSha=BASE,integrationScope='android-integration-20261019',ports=dict(c=50001,v=50002))
        config=dict(communityOrigin='https://127.0.0.1:50001',verifierOrigin='https://127.0.0.1:50002',caPem='this backend CA')
        evidence=dict(sourceSha=BASE)
        bind_public_configuration(config,state,evidence,'this backend CA')
        for field,value in [('communityOrigin','https://127.0.0.1:50003'),('verifierOrigin','https://127.0.0.1:50004'),('caPem','other task CA'),('token','fixture-must-not-compile')]:
            changed=copy.deepcopy(config);changed[field]=value
            with self.subTest(field=field),self.assertRaises(RuntimeError):
                bind_public_configuration(changed,state,evidence,'this backend CA')
        with self.assertRaises(RuntimeError):
            bind_public_configuration(config,state,dict(sourceSha='0'*40),'this backend CA')

    def test_proof_requirements_remain_active_with_python_optimization(self):
        code="import sys;sys.path.insert(0,sys.argv[1]);from policy import require;require(False,'expected proof mismatch')"
        result=subprocess.run([sys.executable,'-O','-c',code,str(Path(__file__).resolve().parents[1])],capture_output=True,text=True)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('RuntimeError: expected proof mismatch',result.stderr)

    def test_v_stays_on_original_cluster_when_c_is_restored(self):
        lab=object.__new__(IntegrationLab)
        lab.root=PurePosixPath('/owned/new-task/lab')
        lab.state=dict(target='restore',tag='owned',pgPorts={'source':{'c':50001,'v':50002},'restore':{'c':50003}})
        v=parse_qs(urlsplit(lab.dsn('v','runtime')).query)
        c=parse_qs(urlsplit(lab.dsn('c','runtime')).query)
        self.assertEqual(v['host'],['/owned/new-task/lab/source-v/socket'])
        self.assertEqual(v['port'],['50002'])
        self.assertEqual(c['host'],['/owned/new-task/lab/restore-c/socket'])
        self.assertEqual(c['port'],['50003'])

    def test_v_sql_cannot_follow_c_restore_target(self):
        lab=object.__new__(IntegrationLab)
        with patch.object(Lab,'sql',return_value='ok') as sql:
            self.assertEqual(lab.sql('v','SELECT 1',target='restore'),'ok')
            self.assertEqual(sql.call_args.kwargs['target'],'source')

    def test_v_start_cannot_create_an_extra_restore_cluster(self):
        lab=object.__new__(IntegrationLab)
        with patch.object(Lab,'pg_start') as start:
            lab.pg_start('restore','v')
            start.assert_called_once_with('source','v')

    def test_synthetic_data_refuses_legacy_or_unmarked_lab(self):
        for state in [None,{},dict(marker='hnuhole-android-prerelease-v1')]:
            with self.subTest(state=state),self.assertRaises(RuntimeError):
                Data(SimpleNamespace(state=state))

    def test_redirect_never_creates_a_cross_origin_authenticated_request(self):
        original=urllib.request.Request('https://127.0.0.1:50001/api/v1/channels',headers={'Authorization':'Bearer synthetic-test-only'})
        with self.assertRaisesRegex(RuntimeError,'redirects are forbidden'):
            NoRedirect().redirect_request(original,None,302,'redirect',{},'https://other.invalid/')


if __name__=='__main__':unittest.main()
