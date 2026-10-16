"""Build the additive image API and update the existing post DTO allowlists."""
from copy import deepcopy
from pathlib import Path
import yaml

ROOT = Path(__file__).resolve().parents[2]


def ref(name):
    return {"$ref": "#/components/schemas/" + name}


def obj(properties):
    return {"type": "object", "additionalProperties": False,
            "required": list(properties), "properties": properties}


def integer(low, high):
    return {"type": "integer", "minimum": low, "maximum": high}


def main():
    identifier = {"type": "string", "format": "uuid", "pattern": "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"}
    mime = {"type": "string", "enum": ["image/jpeg", "image/png", "image/gif", "image/webp"]}
    selection = obj({"mediaId": identifier, "sha256": {"type": "string", "pattern": "^[0-9a-f]{64}$"},
                     "byteLength": integer(1, 10485760), "mimeType": mime,
                     "width": integer(1, 16384), "height": integer(1, 16384)})
    selection["description"] = "Immutable ordered selection; canonical nonzero UUID, maximum 12582912 pixels. All declared values are verified against full bytes."
    source = obj({"path": {"type": "string", "pattern": "^/api/v1/posts/[0-9a-f-]{36}/images/[0-9a-f-]{36}/original$"},
                  "mimeType": mime, "byteLength": integer(1, 10485760)})
    image = obj({"mediaId": identifier, "contentVersionId": identifier, "position": integer(0, 8),
                 "width": integer(1, 16384), "height": integer(1, 16384),
                 "pixelWidth": integer(1, 16384), "pixelHeight": integer(1, 16384),
                 "frames": integer(1, 120), "animated": {"type": "boolean"}, "saveAllowed": {"type": "boolean"},
                 "thumbnail": ref("Source"), "full": ref("Source"), "original": ref("Source")})
    image["description"] = "v1 thumbnail/full/original all reference the same unchanged original. No transcoding or bandwidth-saving thumbnail claim. Pixel dimensions respect EXIF."
    item = deepcopy(selection)
    item["properties"].update({"position": integer(0, 8), "uploaded": {"type": "boolean"}})
    item["required"] += ["position", "uploaded"]
    schemas = {"Selection": selection, "Source": source, "Image": image, "UploadItem": item,
               "Group": obj({"postId": identifier, "images": {"type": "array", "maxItems": 9, "items": ref("Image")},
                             "accessValidUntil": {"type": "string", "format": "date-time", "description": "At most 60 seconds from Server-Time and no later than session expiry. Host revokes terminally on known invalidation or timeout."}}),
               "UploadState": obj({"taskId": identifier, "postId": identifier, "attemptVersion": integer(1, 2147483647),
                                   "items": {"type": "array", "maxItems": 9, "items": ref("UploadItem")}}),
               "Grant": obj({"taskId": identifier, "mediaId": identifier, "attemptVersion": integer(1, 2147483647),
                             "uploadToken": {"type": "string", "pattern": "^[A-Za-z0-9_-]{43}$", "description": "Canonical unpadded 32-byte random capability; upload only, never pass to viewer or logs."},
                             "expiresAt": {"type": "string", "format": "date-time"}}),
               "Error": obj({"error": obj({"code": {"type": "string"}, "message": {"type": "string"}}),
                             "requestId": {"type": "string"}})}
    common = {"Cache-Control": {"required": True, "schema": {"type": "string", "enum": ["no-store"]}},
              "X-Request-ID": {"required": True, "schema": {"type": "string"}}}
    success = dict(common, **{"Server-Time": {"required": True, "schema": {"type": "string", "format": "date-time"}}})
    session = dict(success, **{"Session-Expires-At": {"required": True, "schema": {"type": "string", "format": "date-time"}}})
    paths = {}
    definitions = [
        ("/api/v1/posts/{postId}/images", "get", "readPostImages", "Group"),
        ("/api/v1/posts/{postId}/images/{contentVersionId}/original", "get", "readPostOriginalImage", "binary"),
        ("/api/v1/me/post-tasks/{taskId}/attempts/{version}/images", "get", "readOwnPostImageUploads", "UploadState"),
        ("/api/v1/me/post-tasks/{taskId}/attempts/{version}/images/{mediaId}/upload-grant", "post", "issuePostImageUploadGrant", "Grant"),
        ("/api/v1/me/post-tasks/{taskId}/attempts/{version}/images/{mediaId}/bytes", "put", "uploadAcceptedPostImageBytes", None)]
    for path, method, operation, schema in definitions:
        parameters = [{"name": segment[1:-1], "in": "path", "required": True,
                       "schema": integer(1, 2147483647) if segment == "{version}" else identifier}
                      for segment in path.split("/") if segment.startswith("{")]
        code = "204" if method == "put" else "200"
        response = {"description": "Exact item stored; not a publication receipt" if schema is None else "Authorized result",
                    "headers": success if schema is None else session}
        if schema == "binary":
            response["content"] = {m: {"schema": {"type": "string", "format": "binary"}} for m in mime["enum"]}
        elif schema:
            response["content"] = {"application/json": {"schema": ref(schema)}}
        responses = {code: response}
        for status in (400, 401, 403, 404, 405, 409, 413, 415, 422, 429, 503):
            headers = deepcopy(common)
            if status == 429:
                headers["Retry-After"] = {"required": True, "schema": integer(1, 300)}
            responses[str(status)] = {"description": "Rejected; never treat timeout/error as a new publish intent", "headers": headers,
                                      "content": {"application/json": {"schema": ref("Error")}}}
        entry = {"operationId": operation, "security": [{"uploadOnly" if method == "put" else "bearerAuth": []}], "responses": responses}
        if method == "put":
            entry["requestBody"] = {"required": True, "x-max-bytes": 10485760,
                                    "content": {m: {"schema": {"type": "string", "format": "binary"}} for m in mime["enum"]}}
        paths[path] = {"parameters": parameters, method: entry}
    spec = {"openapi": "3.0.3", "info": {"title": "HnuHole protected post image API", "version": "0.1.0",
            "description": "Explicit dev-only postImages configuration. Bearer stays in host transport. Upload capabilities can only complete accepted exact bytes, survive session replacement, expire within 15 minutes and the 24-hour attempt upload deadline, and still require final C Gate/account/identity/stop-generation checks. No query parameters, cookies as auth, redirects, public storage, Range or conditional caches. Duplicate/unknown JSON fields and noncanonical path IDs are rejected. See post-image-media-contract.md for byte framing, limits and production decisions."},
            "servers": [{"url": "/"}], "paths": paths,
            "components": {"securitySchemes": {"bearerAuth": {"type": "http", "scheme": "bearer"},
                                                "uploadOnly": {"type": "http", "scheme": "Upload"}}, "schemas": schemas},
            "x-design-document": "../../docs/design/post-image-media-contract.md"}
    (ROOT / "packages/openapi/post-image-api.yaml").write_text(yaml.safe_dump(spec, allow_unicode=True, sort_keys=False), encoding="utf-8")

    # Modify only additive DTO sections, preserving the old text spec formatting.
    file = ROOT / "packages/openapi/post-api.yaml"
    data = file.read_text(encoding="utf-8")
    data = data.replace("title: Hnuhole text posting API", "title: Hnuhole posting API (optional protected images)")
    def section(name, update):
        nonlocal data
        start = data.index("    " + name + ":\n")
        end = data.find("\n    ", start + 5)
        # The next schema is four spaces followed by a non-space character.
        import re
        match = re.search(r"\n    [^ \n]", data[start + 5:])
        end = start + 5 + match.start() if match else len(data)
        data = data[:start] + update(data[start:end]) + data[end:]
    section("Body", lambda s: s.replace("minLength: 1", "minLength: 0").replace("description: Original", "description: Empty only with at least one image (or positive response imageCount). Otherwise original", 1))
    for name in ("CreatePostInput", "RetryInput"):
        section(name, lambda s: s if "\n        images:" in s else s + "\n        images:\n          type: array\n          maxItems: 9\n          items:\n            $ref: '#/components/schemas/PostImageSelection'")
    for name in ("OwnTaskContent", "PublicPost"):
        section(name, lambda s: s if "\n        imageCount:" in s else s + "\n        imageCount:\n          type: integer\n          minimum: 1\n          maximum: 9\n          description: Omitted for zero images; positive count permits an empty body.")
    section("OwnTaskDetail", lambda s: s if "imageCount:" in s else s.replace("          description: Latest", "            imageCount:\n              type: integer\n              minimum: 1\n              maximum: 9\n          description: Latest"))
    if "    PostImageSelection:\n" not in data:
        snippet = yaml.safe_dump({"PostImageSelection": selection}, sort_keys=False)
        data = data.replace("    Body:\n", "\n".join("    " + line for line in snippet.rstrip().splitlines()) + "\n    Body:\n")
    file.write_text(data, encoding="utf-8")


if __name__ == "__main__":
    main()
