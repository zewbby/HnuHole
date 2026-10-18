"""Positive and hostile fixtures for the comments design contract, not HTTP/SQL."""

from copy import deepcopy
import importlib.util
from pathlib import Path
import unittest

import yaml


MODULE_PATH = Path(__file__).resolve().parents[1] / "check-comment-contract.py"
MODULE_SPEC = importlib.util.spec_from_file_location("comment_contract", MODULE_PATH)
contract = importlib.util.module_from_spec(MODULE_SPEC)
MODULE_SPEC.loader.exec_module(contract)

TASK = "11111111-1111-1111-1111-111111111111"
IDENTITY = "22222222-2222-2222-2222-222222222222"
POST = "33333333-3333-3333-3333-333333333333"
ROOT = "44444444-4444-4444-4444-444444444444"
TARGET = "55555555-5555-5555-5555-555555555555"
COMMENT = "66666666-6666-6666-6666-666666666666"
CURSOR = "c" * 32
CONTENT = {"body": "测试评论", "image": None}
IMAGE = {
    "mediaId": COMMENT, "sha256": "a" * 64, "byteLength": 100,
    "mimeType": "image/webp", "width": 10, "height": 10,
}
AUTHOR = {"ref": "opaque-public-author", "nickname": "测试身份",
          "avatar": "default-v1", "state": "ACTIVE"}


def create(**changes):
    return {"operation": "CREATE", "taskId": TASK, "identityId": IDENTITY,
            "postId": POST, "rootCommentId": None, "targetCommentId": None,
            **deepcopy(CONTENT), **changes}


def action(operation="RETRY", **changes):
    value = {"operation": operation, "taskId": TASK, "expectedAttemptVersion": 2}
    if operation == "RETRY":
        value.update(deepcopy(CONTENT))
    return {**value, **changes}


def task(state="FAILED", **changes):
    retained = state in ("ACCEPTED", "FAILED")
    return {
        "taskId": TASK, "ownerIdentityId": IDENTITY, "postId": POST,
        "rootCommentId": None, "targetCommentId": None, "attemptVersion": 2,
        "state": state, "failureCode": "PUBLICATION_FAILED" if state == "FAILED" else None,
        "materialsAvailable": retained, "content": deepcopy(CONTENT) if retained else None,
        "allowedActions": ["RETRY", "ABANDON"] if state == "FAILED" else [],
        "publishedCommentId": COMMENT if state == "PUBLISHED" else None, **changes,
    }


def projection(state="FAILED", **changes):
    value = task(state)
    del value["content"]
    del value["publishedCommentId"]
    value.update({"entryAction": {"ACCEPTED": "HIDE_PENDING", "FAILED": "RETAIN_FAILURE",
                                  "PUBLISHED": "REMOVE", "ABANDONED": "REMOVE"}[state],
                  "connection": "NOT_CONNECTED"})
    return {**value, **changes}


def public_comment(reply=False, **changes):
    return {
        "id": COMMENT, "postId": POST, "rootCommentId": ROOT if reply else None,
        "targetCommentId": TARGET if reply else None, **deepcopy(CONTENT),
        "author": deepcopy(AUTHOR), "replyTo": {"commentId": TARGET,
                                                "author": deepcopy(AUTHOR)} if reply else None,
        "isPostAuthor": False, "publishedAt": "2026-10-18T03:00:00Z",
        "likeCount": 0, "likedByMe": False, "replyCount": 0, **changes,
    }


class CommentContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.spec = contract.read_spec()

    def assert_payload_rejected(self, name, payload):
        with self.assertRaises(contract.ContractViolation):
            contract.validate_payload(self.spec, name, payload)

    def test_design_status_and_all_local_closed_schemas(self):
        self.assertTrue(contract.check_contract(self.spec))

    def test_nullable_fields_match_actual_openapi30_validator(self):
        from openapi_schema_validator import OAS30Validator

        def expand(value):
            if isinstance(value, list):
                return [expand(child) for child in value]
            if not isinstance(value, dict):
                return value
            if "$ref" in value:
                return expand(contract.resolve(self.spec, value))
            # References have been expanded, so the optional discriminator's
            # original reference mappings are omitted in this nullable probe.
            return {key: expand(child) for key, child in value.items()
                    if key != "discriminator"}

        fixtures = [("CommentTaskCommand", create()),
                    ("CommentTaskCommand", create(body="", image=IMAGE)),
                    ("PublicComment", public_comment()),
                    ("OwnCommentTask", task()), ("OwnCommentTask", task("PUBLISHED"))]
        for name, value in fixtures:
            with self.subTest(schema=name, state=value.get("state")):
                validator = OAS30Validator(expand(self.spec["components"]["schemas"][name]))
                self.assertFalse(list(validator.iter_errors(value)))

    def test_main_reply_and_single_original_image_commands(self):
        fixtures = [create(), create(rootCommentId=ROOT, targetCommentId=TARGET),
                    create(body="", image=IMAGE), action(), action("ABANDON")]
        for value in fixtures:
            with self.subTest(operation=value["operation"], image=value.get("image") is not None):
                self.assertTrue(contract.validate_payload(self.spec, "CommentTaskCommand", value))
        contract.validate_payload(self.spec, "SetCommentLikeCommand",
                                  {"operation": "SET_LIKE", "liked": False})
        contract.validate_payload(self.spec, "DeleteCommentCommand", {"operation": "DELETE"})

    def test_rejects_empty_extra_array_and_mismatched_target_commands(self):
        cases = [
            create(body="", image=None), create(body=" \t\n", image=None),
            create(accountId=TASK), create(images=[IMAGE]), create(image=[IMAGE]),
            create(rootCommentId=ROOT), create(targetCommentId=TARGET),
            create(image={**IMAGE, "ownerIdentityId": IDENTITY}),
            create(image={**IMAGE, "mimeType": "image/apng"}),
            create(image={**IMAGE, "byteLength": 10485761}),
            create(image={**IMAGE, "width": 16385}), create(image={**IMAGE, "sha256": "A" * 64}),
        ]
        for index, value in enumerate(cases):
            with self.subTest(case=index):
                self.assert_payload_rejected("CommentTaskCommand", value)

    def test_unicode_cluster_transport_budget_is_not_json_character_count(self):
        # 3000 composed graphemes may contain 6000 Unicode code points.
        contract.validate_payload(self.spec, "CommentTaskCommand", create(body="a\u0301" * 3000))
        self.assert_payload_rejected("CommentTaskCommand", create(body="é" * 32769))
        self.assert_payload_rejected("CommentTaskCommand", create(body="\ud800"))

    def test_retry_abandon_cannot_resupply_binding_or_ignore_version(self):
        for operation in ("RETRY", "ABANDON"):
            for field, value in (("identityId", IDENTITY), ("ownerIdentityId", IDENTITY),
                                 ("postId", POST), ("rootCommentId", ROOT),
                                 ("targetCommentId", TARGET), ("expectedAttemptVersion", 0)):
                with self.subTest(operation=operation, field=field):
                    self.assert_payload_rejected("CommentTaskCommand", action(operation, **{field: value}))

    def test_command_keys_and_ids_are_canonical(self):
        contract.validate_payload(self.spec, "CommandID", "A" * 22)
        for value in ("A" * 21, "A" * 23, "A" * 21 + "B", "A" * 21 + "=", "A" * 21 + "+"):
            with self.subTest(key_length=len(value), ending=value[-1]):
                self.assert_payload_rejected("CommandID", value)
        for value in ("00000000-0000-0000-0000-000000000000", TASK.upper().replace("1", "A", 1),
                      TASK.replace("-", "")):
            with self.subTest(uuid=value):
                self.assert_payload_rejected("UUID", value)

    def test_unknown_is_command_observation_not_service_task(self):
        contract.validate_payload(self.spec, "CommentCommandResult", {"state": "UNKNOWN_NOT_OBSERVED"})
        self.assert_payload_rejected("ObservedCommandResult", {"state": "UNKNOWN_NOT_OBSERVED"})
        for state in ("UNKNOWN", "SENDING", "UNKNOWN_NOT_OBSERVED"):
            with self.subTest(state=state):
                self.assert_payload_rejected("OwnCommentTask", task(state))
        for value in ({"state": "UNKNOWN_NOT_OBSERVED", "allowedActions": ["RETRY"]},
                      {"state": "NOT_ACCEPTED"}):
            self.assert_payload_rejected("CommentCommandResult", value)

    def test_authoritative_unaccepted_receipts_do_not_fabricate_failed_task(self):
        for state, error in (("REJECTED", "TARGET_UNAVAILABLE"), ("NOT_ACCEPTED", "SEALED")):
            for operation in ("CREATE", "RETRY", "ABANDON"):
                value = {"state": state, "operation": operation, "errorCode": error}
                with self.subTest(state=state, operation=operation):
                    contract.validate_payload(self.spec, "CommentCommandResult", value)
                    contract.validate_payload(self.spec, "TaskCommandReceipt", value)
                    self.assert_payload_rejected("OwnCommentTask", value)
                    self.assert_payload_rejected("CommentCommandResult", {**value, "taskId": TASK})
                    self.assert_payload_rejected("CommentCommandResult", {**value, "allowedActions": ["RETRY"]})
        self.assert_payload_rejected("CommentCommandResult",
                                     {"state": "REJECTED", "operation": "CREATE"})

    def test_authoritative_tasks_and_failure_projection_states(self):
        for state in ("ACCEPTED", "FAILED", "PUBLISHED", "ABANDONED"):
            with self.subTest(state=state):
                contract.validate_payload(self.spec, "OwnCommentTask", task(state))
                contract.validate_payload(self.spec, "CommentFailureProjection", projection(state))
        contract.validate_payload(self.spec, "OwnCommentTask", task(allowedActions=["ABANDON"]))
        cases = [task("ACCEPTED", allowedActions=["RETRY"]), task(allowedActions=["RETRY"]),
                 task("ABANDONED", content=CONTENT), task("PUBLISHED", failureCode="FAILED"),
                 task(materialsAvailable=False), task(rootCommentId=ROOT, targetCommentId=None)]
        for index, value in enumerate(cases):
            with self.subTest(invalid_task=index):
                self.assert_payload_rejected("OwnCommentTask", value)
        for value in (projection(connection="CONNECTED"), projection(entryAction="REMOVE"),
                      projection("PUBLISHED", allowedActions=["RETRY", "ABANDON"]),
                      projection(content=CONTENT)):
            self.assert_payload_rejected("CommentFailureProjection", value)

    def test_actions_require_current_failed_allowed_matching_task_version(self):
        contract.validate_task_action(self.spec, action(), task())
        contract.validate_task_action(self.spec, action("ABANDON"), task(allowedActions=["ABANDON"]))
        cases = [
            (action(expectedAttemptVersion=1), task()), (action(taskId=POST), task()),
            (action(), task("ACCEPTED")), (action(), task("PUBLISHED")),
            (action("ABANDON"), task("ABANDONED")), (action(), task(allowedActions=["ABANDON"])),
        ]
        for index, (command, current) in enumerate(cases):
            with self.subTest(case=index), self.assertRaises(contract.ContractViolation):
                contract.validate_task_action(self.spec, command, current)

    def test_public_content_has_no_private_selectors_or_quote_blocks(self):
        contract.validate_payload(self.spec, "PublicComment", public_comment())
        contract.validate_payload(self.spec, "PublicComment", public_comment(reply=True))
        cases = [public_comment(accountId=TASK), public_comment(identityId=IDENTITY),
                 public_comment(taskId=TASK), public_comment(quote="deleted original"),
                 public_comment(author={**AUTHOR, "identityId": IDENTITY}),
                 public_comment(reply=True, replyTo={"commentId": ROOT, "author": AUTHOR}),
                 public_comment(replyTo={"commentId": TARGET, "author": AUTHOR}),
                 public_comment(body="", image=None)]
        for index, value in enumerate(cases):
            with self.subTest(case=index):
                self.assert_payload_rejected("PublicComment", value)

    def test_snapshot_page_rejects_duplicates_wrong_floor_and_mixed_main_rows(self):
        main = {"snapshotId": CURSOR, "comments": [public_comment()], "nextCursor": None, "totalCount": 1}
        reply = {"snapshotId": CURSOR, "rootCommentId": ROOT,
                 "comments": [public_comment(reply=True)], "nextCursor": None, "remainingCount": 0}
        contract.validate_payload(self.spec, "CommentPage", main)
        contract.validate_payload(self.spec, "ReplyPage", reply)
        self.assert_payload_rejected("CommentPage", {**main, "comments": [public_comment()] * 2})
        self.assert_payload_rejected("CommentPage", {**main, "comments": [public_comment(reply=True)]})
        self.assert_payload_rejected("ReplyPage", {**reply, "rootCommentId": POST})
        self.assert_payload_rejected("CommentPage", {**main, "offset": 50})

    def test_protected_media_is_metadata_only_and_single(self):
        image = {"mediaId": COMMENT, "contentVersionId": TARGET, "pixelWidth": 20,
                 "pixelHeight": 20, "mimeType": "image/gif", "saveAllowed": True}
        contract.validate_payload(self.spec, "PublishedCommentImage", image)
        for field in ("url", "path", "token", "bytes", "accountId"):
            with self.subTest(field=field):
                self.assert_payload_rejected("PublishedCommentImage", {**image, field: "private-value"})
        self.assert_payload_rejected("PublicComment", public_comment(image=[image]))

    def test_contract_guard_rejects_privacy_authorization_and_status_regressions(self):
        mutations = [
            lambda spec: spec.update({"x-contract-status": "live"}),
            lambda spec: spec.update({"x-notification-integration": "CONNECTED"}),
            lambda spec: spec["components"]["schemas"]["PublicAuthor"]["properties"].update({"accountId": {"type": "string"}}),
            lambda spec: spec["components"]["schemas"]["CreateCommentCommand"].update({"additionalProperties": True}),
            lambda spec: spec["components"]["schemas"]["RetryCommentCommand"]["properties"].update({"targetCommentId": {"type": "string"}}),
            lambda spec: spec["components"]["schemas"]["ReplyPage"]["x-order-contract"].update({"topCount": 3}),
            lambda spec: spec["components"]["schemas"]["CommentPage"]["x-order-contract"].update({"liveReorder": True}),
            lambda spec: spec["components"]["schemas"]["Digest"].update({"x-digest-definition": "IMPLEMENTED"}),
            lambda spec: spec["paths"]["/api/v1/comment-commands/{commandId}"]["get"].update({"security": []}),
            lambda spec: spec["paths"].update({"/api/v1/comments/images": {}}),
        ]
        for index, mutate in enumerate(mutations):
            with self.subTest(mutation=index):
                spec = deepcopy(self.spec)
                mutate(spec)
                with self.assertRaises(contract.ContractViolation):
                    contract.check_contract(spec)

    def test_duplicate_yaml_keys_are_rejected(self):
        with self.assertRaises(contract.ContractViolation):
            yaml.load("state: FAILED\nstate: PUBLISHED\n", Loader=contract.UniqueKeysLoader)


if __name__ == "__main__":
    unittest.main()
