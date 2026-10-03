#!/usr/bin/env python3
"""Pinned OpenAPI validation and the channel deadline/wrapper contract checks."""
import argparse
import importlib.metadata
from pathlib import Path

import yaml


class UniqueKeysLoader(yaml.SafeLoader):
    pass


def unique_mapping(loader, node, deep=False):
    result = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in result:
            raise ValueError(f"Duplicate YAML key: {key}")
        result[key] = loader.construct_object(value_node, deep=deep)
    return result


UniqueKeysLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, unique_mapping
)


def resolve(spec, value):
    if isinstance(value, dict) and "$ref" in value:
        ref = value["$ref"]
        if not ref.startswith("#/"):
            raise ValueError(f"Only local references are supported: {ref}")
        value = spec
        for segment in ref[2:].split("/"):
            value = value[segment.replace("~1", "/").replace("~0", "~")]
    return value


def check_refs(spec, value):
    if isinstance(value, dict):
        resolve(spec, value)
        for item in value.values():
            check_refs(spec, item)
    elif isinstance(value, list):
        for item in value:
            check_refs(spec, item)


def check_channel(spec):
    responses = spec["paths"]["/api/v1/channels"]["get"]["responses"]
    assert set(responses) == {"200", "400", "401", "403", "429", "503"}
    for status, response in responses.items():
        response = resolve(spec, response)
        headers = response["headers"]
        for name in ("X-Request-ID", "Cache-Control"):
            assert resolve(spec, headers[name])["required"] is True
        if status == "200":
            assert resolve(spec, headers["Session-Expires-At"])["required"] is True
        elif status == "429":
            assert resolve(spec, headers["Retry-After"])["required"] is True
        if status != "200":
            assert response["content"]["application/json"]["schema"]["$ref"] == "#/components/schemas/ErrorBody"
    schemas = spec["components"]["schemas"]
    assert set(schemas["Channel"]["properties"]) == {
        "id", "code", "name", "initiallyVisible", "displayOrder"
    }
    directory = schemas["ChannelListResponse"]
    assert set(directory["properties"]) == {"channels"}
    assert directory["properties"]["channels"]["minItems"] == 7
    assert directory["properties"]["channels"]["maxItems"] == 7


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--yaml-only", action="store_true", help="Structure checks only; does not establish OpenAPI validity")
    parser.add_argument("paths", nargs="*", type=Path)
    args = parser.parse_args()
    if yaml.__version__ != "6.0.1":
        raise RuntimeError("Expected PyYAML 6.0.1")
    if not args.yaml_only:
        if importlib.metadata.version("openapi-spec-validator") != "0.9.0":
            raise RuntimeError("Expected openapi-spec-validator 0.9.0")
        from openapi_spec_validator import validate_spec
    paths = args.paths or sorted(Path(__file__).parent.glob("*-api.yaml"))
    for path in paths:
        spec = yaml.load(path.read_text(), Loader=UniqueKeysLoader)
        check_refs(spec, spec)
        if "/api/v1/channels" in spec["paths"]:
            check_channel(spec)
        if "/api/v1/identities" in spec["paths"]:
            check_identity(spec)
        if not args.yaml_only:
            validate_spec(spec)
        print(f"{path.name}: {'YAML/contract structure' if args.yaml_only else 'OpenAPI/contract'} passed")


def check_identity(spec):
    paths = spec["paths"]
    assert set(paths) == {"/api/v1/identities", "/api/v1/identities/{identityId}", "/api/v1/identity-change-result"}
    assert set(paths["/api/v1/identities"]) == {"get", "post"}
    assert set(paths["/api/v1/identities/{identityId}"]) == {"parameters", "patch", "delete"}
    for path in paths.values():
        for method, operation in path.items():
            if method == "parameters":
                continue
            assert operation["security"] == [{"bearerAuth": []}]
            success = operation["responses"]["200"]
            for header in ("Session-Expires-At", "X-Request-ID", "Cache-Control"):
                assert resolve(spec, success["headers"][header])["required"] is True
    schemas = spec["components"]["schemas"]
    assert set(schemas["OwnIdentity"]["properties"]) == {"id", "nickname", "avatar", "isOriginal", "createdAt", "renameAvailableAt"}
    assert schemas["OwnIdentity"]["properties"]["avatar"]["enum"] == ["default-v1"]
    assert schemas["IdentityDirectory"]["properties"]["identities"]["maxItems"] == 3
    assert set(schemas["IdentityChange"]["properties"]) == {"state", "operation", "identityId", "errorCode"}
    assert spec["components"]["parameters"]["ChangeKey"]["schema"]["maxLength"] == 22


if __name__ == "__main__":
    main()
