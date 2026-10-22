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

chat = yaml.safe_load((root / 'packages/openapi/direct-message-chat.yaml').read_text(encoding='utf-8'))
validate_spec(chat)
assert len(chat['paths']) == 6
assert chat['x-contract-status'] == 'P2_ISOLATED_IMPLEMENTATION'
assert chat['components']['schemas']['ImageIntent']['additionalProperties'] is False
assert chat['components']['schemas']['ImageIntent']['properties']['groupSize']['maximum'] == 9
assert chat['components']['schemas']['ImageIntent']['properties']['byteLength']['maximum'] == 10 * 1024 * 1024
assert {'version', 'settingsVersion', 'deletedThrough', 'unavailableUnread'} <= set(chat['components']['schemas']['Conversation']['required'])
assert all('/history' not in path and '/controls/ack' not in path for path in chat['paths'])
print('DM P2 full OpenAPI: PASS (6 paths, per-image ACK, permanent control tombstones)')
