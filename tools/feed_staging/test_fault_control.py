"""Private operator transitions, independently of upstream transport behavior."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from fault_control import control
from fault_proxy import Journal


class PrivateControlTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name);self.root.chmod(0o700)
        self.rule=self.root/'rule.json'
        self.rule.write_text(json.dumps(dict(mode='hold_before',account='feed_device_b',method='GET',path='/api/v1/feed',sessionDigest='a'*64,holdSeconds=20,bodyMarker='private marker')));self.rule.chmod(0o600)
        self.config=patch('fault_control.configuration',return_value=dict(controlRoot=self.root,allowedAccounts=['feed_device_b']))
        self.config.start();self.addCleanup(self.config.stop)

    def test_private_status_one_active_rule_and_abort(self):
        first=control(None,'arm',rule_file=self.rule)
        status=control(None,'status')
        self.assertNotIn('sessionDigest',status);self.assertNotIn('bodyMarker',status)
        with self.assertRaises(RuntimeError):control(None,'arm',rule_file=self.rule)
        with self.assertRaises(RuntimeError):control(None,'abort',rule_id='wrong')
        control(None,'abort',rule_id=first['id'])
        self.assertEqual(control(None,'status')['state'],'cancelled_before_hit')
        second=control(None,'arm',rule_file=self.rule);self.assertNotEqual(first['id'],second['id'])
        log=(self.root/'events.jsonl').read_text();self.assertNotIn('a'*64,log);self.assertNotIn('private marker',log)

    def test_release_requires_same_id_and_waiter_completion(self):
        first=control(None,'arm',rule_file=self.rule);j=Journal(self.root)
        with j.locked():
            r=j.read();r['state']='held_before_upstream';j.write(r)
        control(None,'release',rule_id=first['id'])
        self.assertTrue(control(None,'status')['release'])
        # A released rule remains active until its handler actually finishes.
        with self.assertRaises(RuntimeError):control(None,'arm',rule_file=self.rule)
        j.update(r,'aborted_before_upstream')
        with self.assertRaises(RuntimeError):control(None,'release',rule_id=first['id'])
        self.rule.chmod(0o644)
        with self.assertRaises(RuntimeError):control(None,'arm',rule_file=self.rule)


if __name__=='__main__':unittest.main()
