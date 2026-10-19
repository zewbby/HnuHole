#!/usr/bin/env python3
"""Validate the design-only comments contract and synthetic payload fixtures.

This does not exercise HTTP, SQL, C authorization, media decoding or notifications.
Dependencies come from packages/openapi/requirements-check.txt (including jsonschema).
"""

import argparse
from copy import deepcopy
from pathlib import Path

from jsonschema import Draft7Validator, FormatChecker
import yaml


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SPEC = ROOT / "packages/openapi/comment-api.yaml"
STATUS = "design-core-only-no-http-or-sql-implementation"
PUBLIC_ROOTS = (
    "PublicComment", "PublicAuthor", "ReplyRelation", "PublishedCommentImage",
    "CommentPage", "ReplyPage", "CommentLocation",
)
PRIVATE_FIELDS = {
    "accountId", "ownerAccountId", "identityId", "ownerIdentityId", "slot",
    "taskId", "commandId", "password", "username", "email", "bearer", "token",
    "isOriginal", "otherIdentities", "deviceId", "installationId",
}


class ContractViolation(ValueError):
    """A bounded contract error; never includes fixture content or secrets."""


class UniqueKeysLoader(yaml.SafeLoader):
    pass


def unique_mapping(loader, node, deep=False):
    result = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in result:
            raise ContractViolation("duplicate YAML key")
        result[key] = loader.construct_object(value_node, deep=deep)
    return result


UniqueKeysLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, unique_mapping
)


def read_spec(path=DEFAULT_SPEC):
    return yaml.load(Path(path).read_text(encoding="utf-8"), Loader=UniqueKeysLoader)


def require(condition, message):
    if not condition:
        raise ContractViolation(message)


def resolve(spec, value):
    while isinstance(value, dict) and "$ref" in value:
        reference = value["$ref"]
        require(reference.startswith("#/"), "external references are forbidden")
        value = spec
        try:
            for segment in reference[2:].split("/"):
                value = value[segment.replace("~1", "/").replace("~0", "~")]
        except (KeyError, TypeError) as exc:
            raise ContractViolation("unresolved local reference") from exc
    return value


def walk(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def json_schema(spec, value, stack=()):
    """Expand local OAS references and translate nullable into JSON Schema.

    This contract is acyclic. Refusing cycles/external refs keeps fixture validation
    independent of network resolution and makes all reachable public fields visible.
    """
    if isinstance(value, list):
        return [json_schema(spec, child, stack) for child in value]
    if not isinstance(value, dict):
        return value
    if "$ref" in value:
        reference = value["$ref"]
        require(reference not in stack, "recursive schema is not supported")
        return json_schema(spec, resolve(spec, value), (*stack, reference))
    result = {
        key: json_schema(spec, child, stack)
        for key, child in value.items() if key != "nullable"
    }
    if value.get("nullable"):
        # OAS nullable still obeys enum: enum [null] is a null-only field.
        if result.get("enum") == [None]:
            return {"type": "null"}
        return {"anyOf": [result, {"type": "null"}]}
    return result


def validate_payload(spec, name, payload):
    """Validate one synthetic DTO, including relationship invariants."""
    schemas = spec["components"]["schemas"]
    require(name in schemas, "unknown fixture schema")
    validator = Draft7Validator(
        json_schema(spec, schemas[name]), format_checker=FormatChecker()
    )
    require(not any(validator.iter_errors(payload)), "payload violates closed DTO")
    for node in walk(payload):
        if "body" in node:
            try:
                encoded = node["body"].encode("utf-8", errors="strict")
            except (AttributeError, UnicodeError) as exc:
                raise ContractViolation("body must be valid UTF-8") from exc
            require(len(encoded) <= 65536, "body exceeds technical UTF-8 byte budget")
    if name == "PublicComment" and payload["targetCommentId"] is not None:
        require(payload["replyTo"]["commentId"] == payload["targetCommentId"],
                "reply relation must identify the exact target")
    if name in ("CommentPage", "ReplyPage"):
        rows = payload["comments"]
        require(len({row["id"] for row in rows}) == len(rows), "duplicate page comment")
        for row in rows:
            validate_payload(spec, "PublicComment", row)
            if name == "CommentPage":
                require(row["rootCommentId"] is None, "main page contains reply")
            else:
                require(row["rootCommentId"] == payload["rootCommentId"],
                        "reply page contains a different floor")
    return True


def validate_task_action(spec, command, task):
    """Check fixture action/state compatibility, not real authorization or SQL."""
    validate_payload(spec, "CommentTaskCommand", command)
    validate_payload(spec, "OwnCommentTask", task)
    require(command["operation"] in ("RETRY", "ABANDON"),
            "fixture action must target an existing task")
    require(task["state"] == "FAILED", "only FAILED tasks permit an action")
    require(command["taskId"] == task["taskId"], "action task does not match")
    require(command["expectedAttemptVersion"] == task["attemptVersion"],
            "stale attempt version")
    require(command["operation"] in task["allowedActions"],
            "action is not currently allowed")
    return True


def check_contract(spec):
    require(spec.get("openapi") == "3.0.3", "expected OpenAPI 3.0.3")
    require(spec.get("x-contract-status") == STATUS, "design-only status is missing")
    require(spec.get("x-notification-integration") == "NOT_CONNECTED",
            "notifications must remain NOT_CONNECTED")
    require(spec.get("x-media-endpoints") == "NOT_IMPLEMENTED_COMMENT_OWNED_SINGLE_IMAGE_REQUIRED",
            "protected media implementation must not be claimed")
    require(spec.get("security") == [{"bearerAuth": []}], "C Bearer required")
    for node in walk(spec):
        if "$ref" in node:
            resolve(spec, node)
    schemas = spec["components"]["schemas"]
    for node in walk(schemas):
        if node.get("type") == "object" and "properties" in node:
            require(node.get("additionalProperties") is False, "DTO must be closed")
            require(set(node.get("required", ())) <= set(node["properties"]),
                    "required field is not declared")
    for name in PUBLIC_ROOTS:
        for node in walk(json_schema(spec, schemas[name])):
            require(not PRIVATE_FIELDS.intersection(node.get("properties", {})),
                    "public DTO contains private selectors")
    create = schemas["CreateCommentCommand"]["properties"]
    require(set(create) == {"operation", "taskId", "identityId", "postId",
                           "rootCommentId", "targetCommentId", "body", "image"},
            "CREATE fields changed without an explicit contract update")
    require(create["body"].get("x-max-graphemes") == 3000 and
            create["body"].get("x-max-utf8-bytes") == 65536 and
            "maxLength" not in create["body"],
            "technical grapheme and byte budgets must not become JSON character limits")
    image_union = create["image"].get("oneOf", [])
    require("images" not in create and len(image_union) == 2 and
            image_union[0] == {"$ref": "#/components/schemas/ImageSelection"} and
            image_union[1] == {"type": "object", "nullable": True, "enum": [None]},
            "comments accept one nullable image, never an array")
    for name in ("RetryCommentCommand", "AbandonCommentCommand"):
        fields = schemas[name]["properties"]
        require(not {"identityId", "ownerIdentityId", "postId", "rootCommentId",
                     "targetCommentId"}.intersection(fields),
                "existing task binding cannot be supplied by retry/abandon")
        require(fields["expectedAttemptVersion"].get("minimum") == 1,
                "task actions require a positive expected version")
    task_variants = schemas["OwnCommentTask"]["oneOf"]
    require({resolve(spec, item)["properties"]["state"]["enum"][0]
             for item in task_variants} == {"ACCEPTED", "PUBLISHED", "FAILED", "ABANDONED"},
            "UNKNOWN/SENDING cannot be service task states")
    for variant in task_variants:
        fields = resolve(spec, variant)["properties"]
        failed = fields["state"]["enum"] == ["FAILED"]
        require(fields["allowedActions"]["enum"] ==
                ([["RETRY", "ABANDON"], ["ABANDON"]] if failed else [[]]),
                "only FAILED may expose retry/abandon actions")
    require(schemas["UnknownCommand"]["properties"]["state"]["enum"] ==
            ["UNKNOWN_NOT_OBSERVED"], "unknown must remain a command result")
    for name, state in (("RejectedReceipt", "REJECTED"),
                        ("NotAcceptedReceipt", "NOT_ACCEPTED")):
        fields = schemas[name]["properties"]
        require(fields["state"]["enum"] == [state] and
                set(fields) == {"state", "operation", "errorCode"},
                "unaccepted command must not fabricate a service task")
    for variant in schemas["CommentFailureProjection"]["oneOf"]:
        fields = resolve(spec, variant)["properties"]
        require(fields["connection"]["enum"] == ["NOT_CONNECTED"],
                "private failure adapter must remain disconnected")
    for name, top in (("CommentPage", 10), ("ReplyPage", 5)):
        order = schemas[name]["x-order-contract"]
        require(order["topCount"] == top and order["liveReorder"] is False,
                "read snapshot ordering changed")
        require(order["topOrder"] == ["likeCount:desc", "publishedAt:asc", "id:uuid-bytes-asc"]
                and order["remainderOrder"] == ["publishedAt:asc", "id:uuid-bytes-asc"],
                "rank/time/UUID order changed")
    require(schemas["ReplyPage"]["x-order-contract"]["manualExpansion"] is True,
            "hidden replies require manual expansion")
    require(schemas["Digest"].get("x-digest-definition") == "CORE_CODEC_V1_NO_HTTP_LEDGER"
            and schemas["Digest"].get("x-command-domain") == "HNUHOLE/COMMENT-COMMAND/V1",
            "independent comment codec must remain separate from the HTTP/SQL ledger")
    expected_paths = {
        "/api/v1/comment-commands/{commandId}": {"put", "get"},
        "/api/v1/comment-commands/{commandId}/seal": {"post"},
        "/api/v1/me/comment-tasks/{taskId}": {"get"},
        "/api/v1/me/comment-tasks/{taskId}/failure-projection": {"get"},
        "/api/v1/posts/{postId}/comments": {"get"},
        "/api/v1/posts/{postId}/comments/{rootCommentId}/replies": {"get"},
        "/api/v1/posts/{postId}/comments/{commentId}/location": {"get"},
        "/api/v1/comments/{commentId}/delete-commands/{commandId}": {"put"},
        "/api/v1/comments/{commentId}/like-commands/{commandId}": {"put"},
    }
    require(set(spec["paths"]) == set(expected_paths), "unexpected planned routes")
    operation_ids = set()
    for path, methods in expected_paths.items():
        item = spec["paths"][path]
        require(set(item) - {"parameters"} == methods, "unexpected planned method")
        for method in methods:
            operation = item[method]
            require(operation["security"] == [{"bearerAuth": []}], "operation needs C Bearer")
            require(operation["operationId"] not in operation_ids, "duplicate operationId")
            operation_ids.add(operation["operationId"])
            for response in operation["responses"].values():
                response = resolve(spec, response)
                for header in ("X-Request-ID", "Cache-Control"):
                    require(response["headers"][header]["required"] is True,
                            "all responses need bounded request ID and no-store")
                require(response["headers"]["Cache-Control"]["schema"]["enum"] == ["no-store"],
                        "public/private comment responses must prohibit caching")
    task_body = spec["paths"]["/api/v1/comment-commands/{commandId}"]["put"]["requestBody"]
    require(task_body["x-max-bytes"] == 262144,
            "task command envelope must contain the full technical body budget")
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", nargs="?", type=Path, default=DEFAULT_SPEC)
    args = parser.parse_args()
    spec = read_spec(args.path)
    check_contract(spec)
    from openapi_spec_validator import validate_spec
    validate_spec(deepcopy(spec))
    print("comment-api.yaml: design contract semantics and OpenAPI passed; no HTTP/SQL evidence")


if __name__ == "__main__":
    main()
