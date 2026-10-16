"""Admission protects existing phone/AVD data before any release operation."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SPEC=importlib.util.spec_from_file_location('release_boundary',Path(__file__).parents[1]/'run-android-release-boundary.py')
probe=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(probe)


class ReleaseAdmissionTests(unittest.TestCase):
    def fixture(self,parent):
        root=Path(parent);work=root/'b6-20261013';work.mkdir()
        (work/'OWNER').write_text('HNUHOLE_B6_SINGLE_ANDROID_20261013_V1\n')
        value=dict(owner='HNUHOLE_B6_SINGLE_ANDROID_20261013_V1',device='emulator-5554',
                   avd='hnuhole-b6-20261013',newOwnedAVD=True,existingAVDDataCopied=False)
        (work/'emulator-owner.json').write_text(json.dumps(value))
        return root,work,value

    def test_exact_owned_new_avd_admitted(self):
        with tempfile.TemporaryDirectory() as temporary:
            root,work,value=self.fixture(temporary)
            self.assertEqual(probe.admit_work(work,root,True),value)

    def test_phone_reused_avd_or_wrong_owner_refused(self):
        for field,bad in [('owner','UNKNOWN'),('device','physical-phone'),('avd','user-avd'),
                          ('newOwnedAVD',False),('existingAVDDataCopied',True)]:
            with self.subTest(field=field),tempfile.TemporaryDirectory() as temporary:
                root,work,value=self.fixture(temporary);value[field]=bad
                (work/'emulator-owner.json').write_text(json.dumps(value))
                with self.assertRaises(AssertionError):probe.admit_work(work,root,True)

    def test_wrong_directory_owner_marker_and_mixed_historical_mode_refused(self):
        with tempfile.TemporaryDirectory() as temporary:
            root,work,_=self.fixture(temporary)
            with self.assertRaises(AssertionError):probe.admit_work(work,work,True)
            with self.assertRaises(AssertionError):probe.admit_work(work,root,True,True)
            (work/'OWNER').write_text('UNKNOWN')
            with self.assertRaises(AssertionError):probe.admit_work(work,root,True)


if __name__=='__main__':unittest.main()
