import importlib.util
import json
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location('runtime_resume', Path(__file__).parents[1] / 'resume.py')
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)
REAL_SNAPSHOT_REDIS = r.snapshot_redis


class ManifestTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.root.chmod(0o700)
        self.manifest = self.root / 'current.json'
        paths = {k: str(self.root / k) for k in ['adapter', 'receipt', 'deploymentState', 'redis.conf', 'users.acl', 'c', 'v', 'cop', 'vop', 'community', 'verifier', 'authdev']}
        for p in paths.values():
            Path(p).write_text('synthetic material')
        self.d = dict(format='DEVELOPMENT-RESUME/1', source='new-source', bin=str(self.root), adapter=paths['adapter'], receipt=paths['receipt'], deploymentState=paths['deploymentState'], config=dict(c=paths['c'], v=paths['v']), operators=dict(c=paths['cop'], v=paths['vop']), snapshotRedis=dict(config=paths['redis.conf'], acl=paths['users.acl']))
        Path(paths['receipt']).write_text(json.dumps(dict(source='new-source', result='PASS_ENABLED_DAILY_DEVELOPMENT', binarySHA256={n: r.sha(paths[n]) for n in ['community', 'verifier', 'authdev']})))
        Path(paths['deploymentState']).write_text(json.dumps(dict(sourceSha='new-source', phase='PASS_ENABLED')))
        self.d['files'] = {p: r.sha(p) for p in paths.values()}
        self.save()

    def save(self):
        self.manifest.write_text(json.dumps(self.d))
        self.manifest.chmod(0o600)

    def test_approved_pin(self):
        self.assertEqual(r.load(self.manifest)['source'], 'new-source')

    def test_old_receipt_and_file_drift_refused_before_execution(self):
        for field in ['c', 'community', 'redis.conf']:
            with self.subTest(field=field):
                p = Path(self.root / field)
                original = p.read_bytes()
                p.write_text('drift')
                with self.assertRaisesRegex(r.ResumeError, 'pinned-file-drift'):
                    r.load(self.manifest)
                p.write_bytes(original)
        self.d['source'] = 'old-source'
        self.save()
        with self.assertRaisesRegex(r.ResumeError, 'source-drift'):
            r.load(self.manifest)

    def test_missing_pin_and_shared_manifest_refused(self):
        del self.d['files'][self.d['config']['c']]
        self.save()
        with self.assertRaisesRegex(r.ResumeError, 'manifest-coverage'):
            r.load(self.manifest)
        self.manifest.chmod(0o644)
        with self.assertRaisesRegex(r.ResumeError, 'private-owner-mode'):
            r.load(self.manifest)


class AdapterDependencyTest(unittest.TestCase):
    def test_missing_indirect_pin_refused_but_mutable_evidence_not_pinned(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            secret, evidence, anchor = [root / n for n in ['key', 'evidence', 'anchor']]
            for p in [secret, evidence, anchor]:
                p.write_text('synthetic')
            configs = {p: root / (p + '.json') for p in 'cv'}
            ops = {p: root / (p + '-operator.json') for p in 'cv'}
            required = {str(root / 'redis-server'), str(secret)}
            for p in 'cv':
                configs[p].write_text(json.dumps(dict(secretFile=str(secret), gate=dict(evidenceFile=str(evidence), anchorFile=str(anchor)))))
                ops[p].write_text(json.dumps(dict(communityConfig=str(configs[p]))))
                directory = root / ('redis-' + p)
                directory.mkdir()
                (directory / 'operator.json').write_text('{}')
                required.update(str(directory / n) for n in ['operator.json', 'redis.conf', 'users.acl'])
            required.update(map(str, [*configs.values(), *ops.values()]))
            d = dict(files={p: 'hash' for p in required}, config={p: str(v) for p, v in configs.items()}, operators={p: str(v) for p, v in ops.items()})
            m = SimpleNamespace(ROOT=root, REDIS=root / 'redis-server', OLD_CONFIG=configs, OLD_OP=ops)
            r.verify_adapter_inputs(d, m)
            evidence.write_text('normal evidence renewal')
            anchor.write_text('normal authority checkpoint')
            r.verify_adapter_inputs(d, m)
            del d['files'][str(root / 'redis-c/users.acl')]
            with self.assertRaisesRegex(r.ResumeError, 'adapter-input-coverage'):
                r.verify_adapter_inputs(d, m)


class SequenceTest(unittest.TestCase):
    def setUp(self):
        self.commands = [['/bin/authdev', 'watch', '-operator', 'c'], ['/bin/authdev', 'watch', '-operator', 'v'], ['/bin/community', '-config', 'c'], ['/bin/verifier', '-config', 'v']]
        self.d = dict(bin='/bin', source='new-source', config=dict(c='c', v='v'), operators=dict(c='c', v='v'), legacyCommands=[['/old/community', '-config', 'old']], apiPorts=[10001, 10002], schema=dict(c=28, v=7))
        self.m = Mock()
        self.m.expected.return_value = self.commands
        self.m.owned_redis.return_value = {'already': 'running'}
        self.m.health.return_value = {'c': True, 'v': True}
        self.m.spawn.side_effect = lambda a, label: dict(args=a, pid=len(a))
        self.point = {p: dict(schema=28 if p == 'c' else 7, gate=dict(state='OPEN', generation=1, recoverEvents=1)) for p in 'cv'}
        for target in ['pg_start', 'snapshot_redis']:
            patcher = patch.object(r, target)
            patcher.start()
            self.addCleanup(patcher.stop)
        patcher = patch.object(Path, 'iterdir', return_value=iter([]))
        patcher.start()
        self.addCleanup(patcher.stop)
        patcher = patch.object(r, 'checkpoint', return_value=self.point)
        self.cp = patcher.start()
        self.addCleanup(patcher.stop)

    def test_both_synchronous_resumes_precede_any_api(self):
        events = []
        self.m.run.side_effect = lambda a, label: events.append(a[1])
        self.m.spawn.side_effect = lambda a, label: (events.append('spawn'), dict(args=a, pid=1))[1]
        result = r.resume(self.d, '/private/current.json', self.m)
        self.assertEqual(events[:2], ['resume', 'resume'])
        self.assertNotIn('recover', events)
        self.assertEqual(result['startedServices'], 4)

    def test_second_gate_failure_starts_no_api_and_never_recovers(self):
        self.m.run.side_effect = [None, RuntimeError('V frozen')]
        with self.assertRaisesRegex(RuntimeError, 'V frozen'):
            r.resume(self.d, '/private/current.json', self.m)
        self.m.spawn.assert_not_called()
        self.assertEqual([c.args[0][1] for c in self.m.run.call_args_list], ['resume', 'resume'])

    def test_schema_drift_and_frozen_gate_stop_before_services(self):
        self.point['c']['schema'] = 27
        with self.assertRaisesRegex(r.ResumeError, 'schema-drift'):
            r.resume(self.d, '/private/current.json', self.m)
        self.m.spawn.assert_not_called()
        self.m.run.assert_not_called()
        self.cp.side_effect = r.ResumeError('gate-not-open')
        with self.assertRaisesRegex(r.ResumeError, 'gate-not-open'):
            r.resume(self.d, '/private/current.json', self.m)

    def test_already_running_is_idempotent_and_duplicate_is_rejected(self):
        entries = [SimpleNamespace(name=str(i), stat=lambda: SimpleNamespace(st_uid=os.getuid())) for i in range(4)]
        records = [dict(args=a, pid=i, binarySHA256='hash') for i, a in enumerate(self.commands)]
        self.m.proc.side_effect = lambda name: records[int(name)]
        self.m.owns_listen_port.return_value = True
        with patch.object(Path, 'iterdir', return_value=iter(entries)), patch.object(r, 'sha', return_value='hash'):
            result = r.resume(self.d, '/private/current.json', self.m)
        self.assertEqual(result['startedServices'], 0)
        self.m.spawn.assert_not_called()
        with patch.object(Path, 'iterdir', return_value=iter([entries[0], entries[0]])), patch.object(r, 'sha', return_value='hash'):
            with self.assertRaisesRegex(r.ResumeError, 'duplicate-process'):
                r.resume(self.d, '/private/current.json', self.m)

    def test_snapshot_redis_pid_reuse_refused_without_killing_it(self):
        with tempfile.TemporaryDirectory() as folder:
            pidfile = Path(folder) / 'redis.pid'
            pidfile.write_text('123')
            cfg = dict(pidfile=str(pidfile), port=12345, initialProcess=dict(pid=123, startTick='old', binarySHA256='hash'))
            self.m.proc.return_value = dict(pid=123, startTick='new', binarySHA256='hash')
            journal = Path(folder) / 'journal'
            journal.write_text(json.dumps(cfg['initialProcess']))
            with patch.object(Path, 'stat', return_value=SimpleNamespace(st_uid=os.getuid(), st_mode=0o100600)):
                with self.assertRaisesRegex(r.ResumeError, 'snapshot-redis-process-drift'):
                    REAL_SNAPSHOT_REDIS(self.m, dict(snapshotRedis=cfg), Path(folder) / 'journal')
            self.m.spawn.assert_not_called()
            self.m.stop.assert_not_called()

    def test_failed_api_quiesces_only_new_records_without_restore(self):
        self.m.health.side_effect = RuntimeError('not ready')
        with self.assertRaisesRegex(RuntimeError, 'not ready'):
            r.resume(self.d, '/private/current.json', self.m)
        records = self.m.quiesce.call_args.args[0]
        self.assertEqual([p['args'] for p in records], self.commands)
        self.m.stop.assert_not_called()


if __name__ == '__main__':
    unittest.main()
