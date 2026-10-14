import importlib.util,json,os,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('community_stage1_lab',ROOT/'tools/community-android-stage1/lab.py')
lab=importlib.util.module_from_spec(spec);spec.loader.exec_module(lab)
class FaultTests(unittest.TestCase):
    def test_committed_reply_drops_exactly_once_not_failed_reply(self):
        state=lab.FaultState();state.armed.add('creates')
        self.assertFalse(state.after_upstream('creates',422))
        self.assertTrue(state.after_upstream('creates',202))
        self.assertFalse(state.after_upstream('creates',202))
        self.assertEqual(state.snapshot()['droppedReplies'],1)
    def test_original_key_count_private_and_duplicate_distinguished(self):
        state=lab.FaultState()
        for key in ['private-original-key','private-original-key','private-new-key']:
            state.observe('PUT','/api/v1/post-commands/opaque',key)
        result=state.snapshot();self.assertEqual(result['creates'],3);self.assertEqual(result['uniqueCreates'],2)
        self.assertNotIn('private-',json.dumps(result));self.assertFalse(result['rawTokensOrProofsStored'])
    def test_hold_only_original_result_get_never_replays_write(self):
        state=lab.FaultState();state.hold_queries=True
        self.assertTrue(state.observe('GET','/api/v1/post-commands/key','key')[1])
        self.assertFalse(state.observe('GET','/api/v1/me/post-tasks/task','key')[1])
        self.assertFalse(state.observe('PUT','/api/v1/post-commands/key','key')[1])
        self.assertEqual(state.snapshot()['droppedQueries'],1)
    def test_operations_counted_independently(self):
        state=lab.FaultState()
        state.observe('POST','/api/v1/me/post-tasks/task/retry','retry-key')
        state.observe('POST','/api/v1/posts/post/delete','delete-key')
        self.assertEqual(state.snapshot()['uniqueRetries'],1);self.assertEqual(state.snapshot()['uniqueDeletes'],1)
        self.assertEqual(state.snapshot()['creates'],0)
@unittest.skipUnless(os.name=='posix','POSIX private ownership and permission checks')
class OwnershipTests(unittest.TestCase):
    def test_marker_permissions_alias_and_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name);work=root/'lab';work.mkdir(mode=0o700);(work/'OWNER').write_text(lab.OWNER)
            self.assertEqual(lab.owned(work),work)
            (work/'OWNER').write_text('foreign')
            with self.assertRaises(ValueError):lab.owned(work)
            (work/'OWNER').write_text(lab.OWNER);work.chmod(0o755)
            with self.assertRaises(ValueError):lab.owned(work)
            work.chmod(0o700);link=root/'alias';link.symlink_to(work,target_is_directory=True)
            with self.assertRaises(ValueError):lab.owned(link)
            with self.assertRaises(ValueError):lab.owned(root/'x/../lab')
    def test_unknown_parent_rejected_before_writes(self):
        with tempfile.TemporaryDirectory() as name:
            root=Path(name);(root/'.owner').write_text('foreign')
            with self.assertRaises(ValueError):lab.prepare(root/'lab',root/'source/services/api')
            self.assertFalse((root/'lab').exists())
    def test_overlay_keeps_source_and_protocol_sql_unchanged(self):
        with tempfile.TemporaryDirectory() as name:
            work=Path(name)/'lab';work.mkdir();source=ROOT/'services/api'
            names=['internal/authprivacyruntime/server.go','cmd/authdev/main.go','internal/authprivacy/workers.go']
            original={n:(source/n).read_bytes() for n in names}
            lab.overlay(work,source)
            for n,raw in original.items():self.assertEqual((source/n).read_bytes(),raw)
            scope=json.loads((work/'overlay/scope.json').read_text())
            self.assertTrue(scope['authenticationChecksUnchanged']);self.assertTrue(scope['sqlDeadlinesUnchanged'])
            mapping=json.loads((work/'overlay/overlay.json').read_text())['Replace']
            self.assertEqual(len(mapping),3)
            for destination in mapping.values():
                text=Path(destination).read_text()
                self.assertNotIn("state='FAILED'",text)
                self.assertNotIn('ALTER TABLE',text)
            worker=Path(mapping[str(source/'internal/authprivacy/workers.go')]).read_text()
            self.assertIn('return c.PublishAcceptedPosts(ctx,n)',worker)
if __name__=='__main__':unittest.main()
