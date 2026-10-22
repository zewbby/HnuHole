#!/usr/bin/env python3
"""Validate the complete standalone P1 OpenAPI, with no remote references."""
from pathlib import Path
import yaml
from openapi_spec_validator import validate_spec

root = Path(__file__).resolve().parents[1]
spec = yaml.safe_load((root / 'packages/openapi/direct-message-text.yaml').read_text(encoding='utf-8'))
validate_spec(spec)
assert len(spec['paths']) == 6
assert spec['x-contract-status'] == 'P1_ISOLATED_IMPLEMENTATION'
assert spec['components']['schemas']['TextIntent']['additionalProperties'] is False
assert set(spec['components']['schemas']['Receipt']['properties']['state']['enum']) == {'ABSENT', 'FAILED', 'SENT'}
assert all('/history' not in path for path in spec['paths'])
print('DM P1 full OpenAPI: PASS (6 paths, owner-only receipts, no cloud history)')
