#!/usr/bin/env python3
"""文字契约静态约束及摘要向量；不能代替数据库或业务handler验收。"""
import hashlib
import json
from pathlib import Path
import struct
import uuid

import yaml

ROOT = Path(__file__).resolve().parents[1]


class UniqueKeysLoader(yaml.SafeLoader):
    pass


def unique_mapping(loader, node, deep=False):
    result = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in result:
            raise ValueError(f"duplicate YAML key: {key}")
        result[key] = loader.construct_object(value_node, deep=deep)
    return result


UniqueKeysLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, unique_mapping)


def resolve(spec, node):
    if isinstance(node, dict) and "$ref" in node:
        assert node["$ref"].startswith("#/"), "only local references allowed"
        target = spec
        for part in node["$ref"][2:].split("/"):
            target = target[part.replace("~1", "/").replace("~0", "~")]
        return target
    return node


def traverse(spec, node):
    resolve(spec, node)
    if isinstance(node, dict):
        for value in node.values():
            traverse(spec, value)
    elif isinstance(node, list):
        for value in node:
            traverse(spec, value)


def frame(case):
    names = {"CREATE": 1, "RETRY": 2, "CANCEL": 3, "DELETE_POST": 4, "HIDE_TASK": 5}
    op, fields = case["operation"], case["input"]
    result = b"HNUHOLE/POST-COMMAND/V1\0" + bytes([names[op]])
    if op == "CREATE":
        result += uuid.UUID(fields["channelId"]).bytes + uuid.UUID(fields["identityId"]).bytes
    elif op == "DELETE_POST":
        result += uuid.UUID(fields["postId"]).bytes
    else:
        result += uuid.UUID(fields["taskId"]).bytes
        result += struct.pack(">Q", fields["expectedAttemptVersion"])
    if op in ("CREATE", "RETRY"):
        for name in ("title", "body"):
            encoded = fields[name].encode("utf-8", errors="strict")
            result += struct.pack(">I", len(encoded)) + encoded
    return result


def public_fields(spec, node, seen=None):
    seen = set() if seen is None else seen
    if "$ref" in node:
        key = node["$ref"]
        if key in seen:
            return set()
        seen.add(key)
        node = resolve(spec, node)
    fields = set(node.get("properties", {}))
    if node.get("type") == "object":
        assert node.get("additionalProperties") is False, "public DTO must be closed"
    for value in node.get("properties", {}).values():
        fields |= public_fields(spec, value, seen)
    for kind in ("oneOf", "allOf", "anyOf"):
        for value in node.get(kind, []):
            fields |= public_fields(spec, value, seen)
    if "items" in node:
        fields |= public_fields(spec, node["items"], seen)
    return fields


def main():
    spec = yaml.load((ROOT / "packages/openapi/post-api.yaml").read_text(encoding="utf-8"), Loader=UniqueKeysLoader)
    assert spec["x-contract-status"] == "server-implemented-mobile-integration-pending"
    assert spec["x-max-json-body-bytes"] == 262144
    traverse(spec, spec)
    operations = []
    for path in spec["paths"].values():
        for method, op in path.items():
            if method == "parameters":
                continue
            operations.append(op["operationId"])
            assert op.get("security") == [{"bearerAuth": []}]
            for status, raw_response in op["responses"].items():
                response = resolve(spec, raw_response)
                for name in ("Cache-Control", "X-Request-ID"):
                    assert resolve(spec, response["headers"][name])["required"] is True
                if status.startswith("2"):
                    for name in ("Session-Expires-At", "Server-Time"):
                        assert resolve(spec, response["headers"][name])["required"] is True
    assert len(operations) == len(set(operations)) == 14
    for path, method in (("/api/v1/post-commands/{commandId}", "put"), ("/api/v1/me/post-tasks/{taskId}/retry", "post")):
        assert spec["paths"][path][method]["requestBody"]["x-max-bytes"] == 262144
    schemas = spec["components"]["schemas"]
    forbidden = {"accountId", "ownerId", "ownerAccountId", "identityId", "slot", "slotId", "isOriginal", "createdCount", "otherIdentities", "canDelete", "canEdit", "body"}
    card = public_fields(spec, schemas["PublicPostCard"])
    assert not card.intersection(forbidden), card.intersection(forbidden)
    assert not public_fields(spec, schemas["PublicPost"]).intersection(forbidden - {"body"})
    assert schemas["UnknownCommandResult"]["properties"]["state"]["enum"] == ["UNKNOWN_NOT_OBSERVED"]
    assert schemas["SealedCommandResult"]["properties"]["state"]["enum"] == ["NOT_ACCEPTED"]
    seal_response = resolve(spec, spec["paths"]["/api/v1/post-commands/{commandId}/seal"]["post"]["responses"]["200"])
    seal_schema = resolve(spec, seal_response["content"]["application/json"]["schema"])
    assert {value["$ref"] for value in seal_schema["oneOf"]} == {value["$ref"] for value in schemas["CommandResult"]["oneOf"]} - {"#/components/schemas/UnknownCommandResult"}
    for route, schema in (("/api/v1/me/post-tasks/{taskId}/cancel", "CommittedCancelCommand"), ("/api/v1/posts/{postId}/delete", "CommittedDeleteCommand"), ("/api/v1/me/post-tasks/{taskId}/hide", "CommittedHideCommand")):
        response = resolve(spec, spec["paths"][route]["post"]["responses"]["200"])
        assert response["content"]["application/json"]["schema"] == {"$ref": "#/components/schemas/" + schema}
    assert "UNKNOWN" not in schemas["TaskState"]["enum"]
    assert "RESULT_EXPIRED" in schemas["ExpiredCommandResult"]["properties"]["state"]["enum"]
    for name, count, byte_limit in (("Title", 15, 4096), ("Body", 3000, 65536)):
        assert "maxLength" not in schemas[name], "maxLength is not grapheme counting"
        assert schemas[name]["x-max-grapheme-clusters"] == count
        assert schemas[name]["x-max-utf8-bytes"] == byte_limit
        assert schemas[name]["x-unicode-version"] == "16.0.0"
    assert set(schemas["RetryInput"]["properties"]) == {"expectedAttemptVersion", "title", "body"}
    assert not {"identityId", "channelId"}.intersection(schemas["RetryInput"]["properties"])
    assert set(schemas["OwnPostCapabilities"]["properties"]) == {"postId", "canDelete", "canEdit"}
    assert set(schemas["OwnTaskSummary"]["properties"]) >= {"canRetry", "canCancel", "canHide", "contentAvailable", "visible", "serverSortAt", "terminalAt"}
    assert {"canRetry", "canCancel", "canHide", "contentAvailable", "visible", "serverSortAt", "terminalAt"} <= set(schemas["OwnTaskSummary"]["required"])
    assert schemas["ComposerContext"]["properties"]["selectionState"]["enum"] == ["INITIAL_SETUP_REQUIRED", "DEFAULT_AVAILABLE", "SELECTION_REQUIRED"]
    assert schemas["ComposerContext"]["properties"]["defaultIdentityId"]["nullable"] is True
    vectors = json.loads((ROOT / "packages/post-protocol-vectors/post-command-v1.json").read_text(encoding="utf-8"))
    assert vectors["schemaVersion"] == "hnuhole-post-command-vectors/v1"
    assert vectors["unicodeVersion"] == "16.0.0"
    assert len({case["id"] for case in vectors["cases"]}) == len(vectors["cases"]) == 9
    assert {case["operation"] for case in vectors["cases"]} == {"CREATE", "RETRY", "CANCEL", "DELETE_POST", "HIDE_TASK"}
    for case in vectors["cases"]:
        data = frame(case)
        assert data.hex() == case["frameHex"], case["id"]
        assert hashlib.sha256(data).hexdigest() == case["requestDigest"], case["id"]
    hashes = {case["id"]: case["requestDigest"] for case in vectors["cases"]}
    assert hashes["create-composed"] != hashes["create-decomposed"]
    assert hashes["create-lf"] != hashes["create-crlf"]
    print(f"PASS: {len(operations)} protected operations; closed public DTOs; UNKNOWN/seal and retry invariants; Unicode16 metadata; {len(vectors['cases'])} framing vectors")
    print("Scope: static design checks only; no Go/Dart/SQL/HTTP/Android business acceptance")


if __name__ == "__main__":
    main()
