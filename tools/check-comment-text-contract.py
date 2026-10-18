#!/usr/bin/env python3
"""Validate only the live text supplement against its frozen local design DTOs.

External resolution is deliberately restricted to the one repository document;
no network request or untrusted schema retrieval is permitted.
"""
import importlib.metadata
from pathlib import Path

import yaml
from openapi_spec_validator import validate_spec

ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = ROOT / "packages/openapi"


def expand(node, current, design):
    if isinstance(node, list):
        return [expand(value, current, design) for value in node]
    if not isinstance(node, dict):
        return node
    if "$ref" in node:
        filename, fragment = node["$ref"].split("#", 1)
        if filename not in ("", "comment-api.yaml") or not fragment.startswith("/"):
            raise ValueError("Only local frozen comment references are permitted")
        source = design if filename else current
        target = source
        for name in fragment[1:].split("/"):
            target = target[name.replace("~1", "/").replace("~0", "~")]
        return expand(target, source, design)
    return {key: expand(value, current, design) for key, value in node.items()}


def main():
    assert yaml.__version__ == "6.0.1"
    assert importlib.metadata.version("openapi-spec-validator") == "0.9.0"
    design = yaml.safe_load((DIRECTORY / "comment-api.yaml").read_text(encoding="utf-8"))
    spec = yaml.safe_load((DIRECTORY / "comment-text-component.yaml").read_text(encoding="utf-8"))
    assert spec["x-contract-status"] == "IMPLEMENTED_TEXT_COMPONENT_ORDERED_MIGRATION_BLOCKED"
    assert len(spec["paths"]) == 5
    assert set(spec["components"]["schemas"]) == {"CreateCommentCommand", "RetryCommentCommand", "CommentTaskCommand", "Seal"}
    for name in ("CreateCommentCommand", "RetryCommentCommand"):
        assert spec["components"]["schemas"][name]["allOf"][1]["properties"]["image"]["enum"] == [None]
    validate_spec(expand(spec, spec, design))
    print("comment text supplement: OpenAPI passed; text-only runtime scope, ordered migration BLOCKED")


if __name__ == "__main__":
    main()
