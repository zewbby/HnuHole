"""Independent binary framing vectors for the future Dart host (synthetic only)."""
import base64
import hashlib
import json
from pathlib import Path
import struct
import uuid


def text(value):
    data = value.encode("utf-8")
    return struct.pack(">I", len(data)) + data


def frame(intent):
    result = b"HNUHOLE/POST-COMMAND/V1\0"
    if intent["operation"] == "CREATE":
        result += b"\x01" + uuid.UUID(intent["channelId"]).bytes
        result += uuid.UUID(intent["identityId"]).bytes
    else:
        result += b"\x02" + uuid.UUID(intent["taskId"]).bytes
        result += struct.pack(">Q", intent["expectedAttemptVersion"])
    result += text(intent["title"]) + text(intent["body"])
    result = b"HNUHOLE/POST-MEDIA-COMMAND/V1\0" + result
    result += bytes([len(intent["images"])])
    for item in intent["images"]:
        result += uuid.UUID(item["mediaId"]).bytes + text(item["sha256"]) + text(item["mimeType"])
        result += struct.pack(">III", item["byteLength"], item["width"], item["height"])
    return result


def main():
    original = base64.b64decode("R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")
    selection = {"mediaId": "33333333-3333-4333-8333-333333333333",
                 "sha256": hashlib.sha256(original).hexdigest(), "mimeType": "image/gif",
                 "byteLength": len(original), "width": 1, "height": 1}
    create = {"operation": "CREATE", "channelId": "11111111-1111-4111-8111-111111111111",
              "identityId": "22222222-2222-4222-8222-222222222222", "title": "原图 e\u0301",
              "body": "", "images": [selection]}
    retry = {"operation": "RETRY", "taskId": "44444444-4444-4444-8444-444444444444",
             "expectedAttemptVersion": 7, "title": "原图 e\u0301", "body": "保留\r\n原文",
             "images": [selection, dict(selection, mediaId="55555555-5555-4555-8555-555555555555")]}
    result = {"schema": "hnuhole-post-media-command-v1", "syntheticOnly": True,
              "originalBase64": base64.b64encode(original).decode(), "vectors": []}
    for intent in (create, retry):
        data = frame(intent)
        result["vectors"].append({"intent": intent, "frameBase64": base64.b64encode(data).decode(),
                                  "requestDigest": hashlib.sha256(data).hexdigest()})
    root = Path(__file__).resolve().parents[2]
    (root / "packages/post-protocol-vectors/media-v1.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
