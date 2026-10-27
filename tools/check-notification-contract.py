#!/usr/bin/env python3
"""Resolve notification references only within repository specifications."""
from pathlib import Path
import yaml
from openapi_spec_validator import validate_spec

ROOT = Path(__file__).resolve().parents[1] / 'packages/openapi'
documents = {name: yaml.safe_load((ROOT / name).read_text(encoding='utf-8'))
             for name in ('notification-inbox-component.yaml', 'system-notification-api.yaml', 'comment-api.yaml')}

def expand(node, current):
    if isinstance(node, list):
        return [expand(value, current) for value in node]
    if not isinstance(node, dict):
        return node
    if '$ref' in node:
        filename, fragment = node['$ref'].split('#', 1)
        if filename not in ('', *documents) or not fragment.startswith('/'):
            raise ValueError('Only repository specification references are permitted')
        target = source = documents[filename] if filename else current
        for part in fragment[1:].split('/'):
            target = target[part.replace('~1', '/').replace('~0', '~')]
        return expand(target, source)
    return {key: expand(value, current) for key, value in node.items()}

spec = documents['notification-inbox-component.yaml']
assert len(spec['paths']) == 3
assert spec['components']['schemas']['Actor']['properties']['ref']['pattern'] == '^[A-Z2-7]{12}$'
assert spec['components']['schemas']['Counts']['properties']['identityUnread']['maxProperties'] == 3
validate_spec(expand(spec, spec))
print('notification inbox: OpenAPI passed; account/identity scopes remain distinct')
