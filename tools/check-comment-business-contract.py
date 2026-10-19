#!/usr/bin/env python3
"""Validate the connected supplement with frozen repository-only DTO references."""
from pathlib import Path
import importlib.util
import yaml
from openapi_spec_validator import validate_spec

ROOT = Path(__file__).resolve().parents[1]
loader = importlib.util.spec_from_file_location("text_contract", ROOT / "tools/check-comment-text-contract.py")
module = importlib.util.module_from_spec(loader)
loader.loader.exec_module(module)

spec = yaml.safe_load((ROOT / "packages/openapi/comment-business-component.yaml").read_text(encoding="utf-8"))
design = yaml.safe_load((ROOT / "packages/openapi/comment-api.yaml").read_text(encoding="utf-8"))
assert spec["x-contract-status"] == "IMPLEMENTED_COMMENT_BUSINESS_DEVICE_ACCEPTANCE_SEPARATE"
assert len(spec["paths"]) == 13
assert spec["components"]["schemas"]["Seal"]["properties"]["operation"]["enum"] == ["CREATE", "RETRY", "ABANDON", "DELETE", "SET_LIKE"]
validate_spec(module.expand(spec, spec, design))
print("connected comments: OpenAPI passed; device/hardware evidence remains separate")
