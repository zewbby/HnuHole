"""Validate the F2 design lock, without running application or device tests.
Requires Python 3 and PyYAML. Run from any directory; source objects come from Git.
"""
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import subprocess
import sys

import yaml

ROOT = Path(__file__).resolve().parents[1]
LOCK_PATH = ROOT / "docs/design/community-flutter-f2-lock.json"


def git_blob(ref, path):
    return subprocess.check_output(["git", "show", ref + ":" + path], cwd=ROOT)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def check():
    lock = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
    ref = lock["upstreamCommit"]
    sources = lock["sourceReferences"]
    require(len({r["path"] for r in sources}) == len(sources), "Duplicate source reference")
    copied = []
    for item in sources:
        blob = git_blob(ref, item["path"])
        require(hashlib.sha256(blob).hexdigest() == item["sha256"], "Source hash mismatch: " + item["path"])
        object_id = subprocess.check_output(
            ["git", "rev-parse", ref + ":" + item["path"]], cwd=ROOT, text=True
        ).strip()
        require(object_id == item["gitBlob"], "Source object mismatch: " + item["path"])
        if item["copiedToFrontend"]:
            # Apply the same Git attributes/EOL conversion as staging. A correct
            # Windows CRLF checkout must not fail this immutable Git-blob check.
            snapshot_id = subprocess.check_output(
                ["git", "hash-object", "--path=" + item["path"], str(ROOT / item["path"])],
                cwd=ROOT, text=True
            ).strip()
            require(snapshot_id == item["gitBlob"], "Snapshot differs from pinned Git blob: " + item["path"])
            copied.append(item["path"])

    api = yaml.safe_load((ROOT / "packages/openapi/post-api.yaml").read_text(encoding="utf-8"))
    methods = {"get", "put", "post", "delete", "patch", "head", "options"}
    actual = [
        {"method": m.upper(), "path": p, "operationId": operation["operationId"]}
        for p, block in api["paths"].items()
        for m, operation in block.items()
        if m in methods
    ]
    require(actual == lock["operations"] and len(actual) == 14, "14-operation lock mismatch")
    require(str(api["info"]["version"]) == lock["openApiVersion"], "OpenAPI version drift")
    require(len({o["operationId"] for o in actual}) == 14, "Duplicate operationId")

    def refs(value):
        if isinstance(value, dict):
            if "$ref" in value:
                target = value["$ref"]
                require(target.startswith("#/"), "External ref is not in this snapshot")
                current = api
                for part in target[2:].split("/"):
                    current = current[part.replace("~1", "/").replace("~0", "~")]
            for item in value.values():
                refs(item)
        elif isinstance(value, list):
            for item in value:
                refs(item)
    refs(api)

    published_lock = yaml.safe_load(git_blob(ref, "apps/mobile/pubspec.lock"))
    for name, pin in lock["dependencies"].items():
        package = published_lock["packages"][name]
        require(package["version"] == pin["version"], "Dependency version drift: " + name)
        require(package["description"]["sha256"] == pin["sha256"], "Dependency hash drift: " + name)

    store_source = git_blob(ref, "apps/mobile/lib/src/storage/post_store.dart").decode("utf-8")
    creates = re.findall(r"'(CREATE TABLE [^']+)'", store_source)
    ddl = (ROOT / "docs/design/schemas/community-posts-local-v1.sql").read_text(encoding="utf-8")
    require(len(creates) == 3 and all(statement + ";" in ddl for statement in creates), "Schema is not pinned v1")
    with sqlite3.connect(":memory:") as db:
        db.executescript(ddl)
        tables = {row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        require(tables == {"post_meta", "post_entries", "post_command_index"}, "Unexpected design tables")

    design = (ROOT / "docs/design/community-flutter-f2-design.md").read_text(encoding="utf-8")
    required = [
        "UNKNOWN_NOT_OBSERVED", "RESULT_EXPIRED", "NOT_ACCEPTED",
        "CLOSED_RELEASE_PENDING", "RELEASED", "originalAccountId",
        "hnuhole.isolated.auth.v1|$communityBaseUri|$verifierBaseUri",
        "schemaVersion1", "NOT_RUN", "F3", "F1"
    ]
    for text in required:
        require(text in design, "Missing design boundary: " + text)
    for target in re.findall(r"\]\(([^)]+)\)", design):
        if not target.startswith(("https://", "http://", "#")):
            require(((ROOT / "docs/design") / target.split("#", 1)[0]).resolve().exists(), "Broken local design link: " + target)

    # Asset preservation is a Git comparison, not visual/platform acceptance.
    changed = subprocess.check_output(["git", "-c", "core.quotepath=false", "diff", "--name-only", lock["frontendF1Commit"]], cwd=ROOT, text=True).splitlines()
    require(not any(p.startswith("UI产品图/") for p in changed), "F1 formal assets changed")
    require(not any(p.startswith(("apps/mobile/lib/", "packages/auth_vault/")) for p in changed), "F2 unexpectedly imported business implementation")

    return {
        "result": "PASS",
        "scope": "Pinned Git snapshots, local references, dependency lock, schema design syntax and unchanged F1 assets only",
        "sourceReferences": len(sources),
        "contractSnapshots": len(copied),
        "operations": len(actual),
        "dependencies": len(lock["dependencies"]),
        "schemaTables": len(tables),
        "applicationTests": "NOT_RUN",
        "driftRuntimeTests": "NOT_RUN",
        "deviceTests": "NOT_RUN",
        "fullOpenApiValidator": "NOT_RUN"
    }


if __name__ == "__main__":
    try:
        print(json.dumps(check(), ensure_ascii=False))
    except Exception as error:
        print("FAIL: " + str(error), file=sys.stderr)
        raise SystemExit(1)
