"""Check the current contract and reject privacy, retry and framing regressions."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
MODULE_SPEC = importlib.util.spec_from_file_location(
    "community_text_contract", ROOT / "tools/check-community-text-contract.py"
)
CHECKER = importlib.util.module_from_spec(MODULE_SPEC)
MODULE_SPEC.loader.exec_module(CHECKER)


class CommunityTextContractTests(unittest.TestCase):
    def setUp(self):
        self.spec = CHECKER.yaml.load(
            (ROOT / "packages/openapi/post-api.yaml").read_text(encoding="utf-8"),
            Loader=CHECKER.UniqueKeysLoader,
        )
        self.text = json.loads((ROOT / "packages/post-protocol-vectors/post-command-v1.json").read_text(encoding="utf-8"))
        self.media = json.loads((ROOT / "packages/post-protocol-vectors/media-v1.json").read_text(encoding="utf-8"))

    def check(self):
        return CHECKER.check_contract(self.spec, self.text, self.media)

    def test_current_text_and_image_contract_and_shared_goldens(self):
        self.assertEqual(self.check(), (16, 9, 2))

    def test_public_account_leak_and_open_dto_are_rejected(self):
        original = copy.deepcopy(self.spec)
        for kind in ("ownerId", "open"):
            with self.subTest(kind=kind):
                self.spec = copy.deepcopy(original)
                card = self.spec["components"]["schemas"]["PublicPostCard"]
                if kind == "open":
                    card["additionalProperties"] = True
                else:
                    card["properties"]["ownerId"] = {"type": "string"}
                with self.assertRaises(AssertionError):
                    self.check()

    def test_retry_cannot_select_new_identity_or_channel(self):
        for name in ("identityId", "channelId"):
            with self.subTest(field=name):
                self.spec["components"]["schemas"]["RetryInput"]["properties"][name] = {"type": "string"}
                with self.assertRaises(AssertionError):
                    self.check()

    def test_image_count_and_private_extra_fields_are_rejected(self):
        original = copy.deepcopy(self.spec)
        for kind in ("too_many", "owner_field", "open_selection", "required_images"):
            with self.subTest(kind=kind):
                self.spec = copy.deepcopy(original)
                schemas = self.spec["components"]["schemas"]
                if kind == "too_many":
                    schemas["RetryInput"]["properties"]["images"]["maxItems"] = 10
                elif kind == "owner_field":
                    schemas["PostImageSelection"]["properties"]["ownerId"] = {"type": "string"}
                elif kind == "required_images":
                    schemas["RetryInput"]["required"].append("images")
                else:
                    schemas["PostImageSelection"]["additionalProperties"] = True
                with self.assertRaises(AssertionError):
                    self.check()

    def test_operation_authentication_and_cache_headers_are_required(self):
        original = copy.deepcopy(self.spec)
        for kind in ("auth", "cache"):
            with self.subTest(kind=kind):
                self.spec = copy.deepcopy(original)
                op = self.spec["paths"]["/api/v1/posts/{postId}"]["get"]
                if kind == "auth":
                    op["security"] = []
                else:
                    response = CHECKER.resolve(self.spec, op["responses"]["200"])
                    header = CHECKER.resolve(self.spec, response["headers"]["Cache-Control"])
                    header["required"] = False
                with self.assertRaises(AssertionError):
                    self.check()

    def test_text_golden_digest_corruption_is_rejected(self):
        self.text["cases"][0]["requestDigest"] = "0" * 64
        with self.assertRaises(AssertionError):
            self.check()

    def test_media_order_and_digest_corruption_are_rejected(self):
        original = copy.deepcopy(self.media)
        for kind in ("order", "digest"):
            with self.subTest(kind=kind):
                self.media = copy.deepcopy(original)
                if kind == "order":
                    self.media["vectors"][1]["intent"]["images"].reverse()
                else:
                    self.media["vectors"][0]["requestDigest"] = "0" * 64
                with self.assertRaises(AssertionError):
                    self.check()

    def test_duplicate_yaml_keys_and_missing_local_refs_are_rejected(self):
        with self.assertRaises(ValueError):
            CHECKER.yaml.load("a: 1\na: 2\n", Loader=CHECKER.UniqueKeysLoader)
        with self.assertRaises(KeyError):
            CHECKER.traverse(self.spec, {"$ref": "#/components/schemas/Absent"})

    def test_archived_evidence_matches_original_git_blob_bytes(self):
        archive = ROOT / "docs/archive/community-text-posting-20261008"
        manifest = json.loads((archive / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(manifest["sourceCommit"], "514a944560988e3d8d599e6f9fe9d5d99fe07f88")
        self.assertEqual(len(manifest["files"]), 19)
        self.assertEqual(len({entry["path"] for entry in manifest["files"]}), 19)
        for entry in manifest["files"]:
            with self.subTest(path=entry["path"]):
                path = (archive / entry["archivePath"]).resolve()
                self.assertTrue(path.is_relative_to((archive / "original").resolve()))
                data = path.read_bytes()
                self.assertEqual(len(data), entry["bytes"])
                self.assertEqual(hashlib.sha256(data).hexdigest(), entry["sha256"])
                git_object = b"blob " + str(len(data)).encode("ascii") + b"\0" + data
                self.assertEqual(hashlib.sha1(git_object).hexdigest(), entry["gitBlob"])


if __name__ == "__main__":
    unittest.main()
