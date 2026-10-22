import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("configure_qq", Path(__file__).resolve().parents[1]/"configure_qq.py")
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


class QQSetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_secret_is_private_and_never_in_json(self):
        fragment, settings = setup.prepare(self.root/"private", "fixture@qq.com", "abcdefghijklmnop")
        self.assertEqual(fragment.stat().st_mode & 0o777, 0o600)
        secret = Path(settings["smtpPasswordFile"])
        self.assertEqual(secret.stat().st_mode & 0o777, 0o600)
        self.assertEqual(secret.read_text(), "abcdefghijklmnop")
        self.assertNotIn("abcdefghijklmnop", fragment.read_text())
        self.assertEqual(json.loads(fragment.read_text())["smtpMode"], "tls")
        again, other = setup.prepare(self.root/"private", "fixture@qq.com", "ponmlkjihgfedcba")
        self.assertNotEqual(again, fragment)
        self.assertEqual(secret.read_text(), "abcdefghijklmnop")

    def test_rejects_public_or_symlink_directory(self):
        public = self.root/"public"
        public.mkdir(mode=0o755)
        with self.assertRaises(ValueError):
            setup.prepare(public, "fixture@qq.com", "abcdefghijklmnop")
        link = self.root/"link"
        link.symlink_to(public, target_is_directory=True)
        with self.assertRaises(ValueError):
            setup.prepare(link, "fixture@qq.com", "abcdefghijklmnop")

    def test_updates_only_smtp_and_keeps_original_backup(self):
        config = self.root/"v.json"
        original = {"environment":"dev", "otpKeyFile":"otp.key", "mailEncryptionKeyFile":"mail.key", "trustedCommunityKeyFile":"c.pub", "publicOrigin":"https://127.0.0.1:9443", "gate":{"domain":"existing"}}
        content = json.dumps(original).encode()
        config.write_bytes(content)
        fragment, settings = setup.prepare(self.root/"private", "fixture@qq.com", "abcdefghijklmnop")
        backup = setup.apply_to_verifier(config, settings)
        self.assertEqual(backup.read_bytes(),content)
        self.assertEqual(backup.stat().st_mode & 0o777,0o600)
        updated = json.loads(config.read_text())
        for name, value in original.items():
            self.assertEqual(updated[name],value)
        self.assertEqual(updated["smtpPasswordFile"],settings["smtpPasswordFile"])
        self.assertEqual(config.stat().st_mode & 0o777,0o600)

    def test_never_modifies_community_or_production_or_symlink(self):
        for original in [{"environment":"dev","requestKeyFile":"c.key"}, {"environment":"production","otpKeyFile":"v.key","mailEncryptionKeyFile":"mail.key","trustedCommunityKeyFile":"c.pub"}]:
            config=self.root/"reject.json"
            config.write_text(json.dumps(original))
            before=config.read_bytes()
            with self.assertRaises(ValueError):
                setup.apply_to_verifier(config,{"smtpMode":"tls"})
            self.assertEqual(config.read_bytes(),before)
        link=self.root/"v-link.json"
        link.symlink_to(config)
        with self.assertRaises(ValueError):
            setup.apply_to_verifier(link,{"smtpMode":"tls"})


if __name__ == "__main__":
    unittest.main()
