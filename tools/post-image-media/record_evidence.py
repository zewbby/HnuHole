"""Save small, redacted test facts and verify the Linux mirror's source bytes.

Never copies logs, HTTP bodies, private keys, DSNs, accounts or capabilities.
Text hashes normalize CRLF to LF to match Git's text representation.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path


def sha(data):
    return hashlib.sha256(data).hexdigest()


def inputs(root):
    result = {}
    for folder in ("services/api", "infra/postgres", "packages/openapi", "packages/post-protocol-vectors"):
        for path in (root / folder).rglob("*"):
            if path.is_file() and path.suffix in (".go", ".sql", ".mod", ".sum", ".yaml", ".py", ".sh", ".txt", ".json"):
                # Historical validation reports are not runtime inputs.
                if path.suffix == ".json" and "post-protocol-vectors" not in str(path) and not path.name.endswith("example.json"):
                    continue
                relative = path.relative_to(root).as_posix()
                result[relative] = sha(path.read_bytes().replace(b"\r\n", b"\n"))
    return dict(sorted(result.items()))


def fingerprint(entries):
    return sha("".join(f"{name}\0{digest}\n" for name, digest in entries.items()).encode())


def read_run(path):
    records = [json.loads(line) for line in path.read_text().splitlines() if line.startswith("{")]
    packages, tests = {}, {}
    for record in records:
        action = record.get("Action")
        if action not in ("pass", "fail", "skip"):
            continue
        package = record["Package"].split("/")[-1]
        test = record.get("Test")
        item = {"result": action.upper(), "seconds": record.get("Elapsed", 0)}
        if test:
            tests[package + "/" + test] = item
        else:
            packages[package] = item
    if len(packages) != 5 or any(v["result"] != "PASS" for v in packages.values()):
        raise RuntimeError("all five test packages must have completed successfully")
    if any(v["result"] != "PASS" for v in tests.values()):
        raise RuntimeError("a selected test failed or skipped; inspect privately")
    for package, result in packages.items():
        result["topLevelTests"] = sum(name.startswith(package + "/") and name.count("/") == 1 for name in tests)
        if result["topLevelTests"] == 0:
            result["scope"] = "compiled/no tests selected in this supplemental run"
    return {"sha256": sha(path.read_bytes()), "packages": packages, "tests": tests}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--mirror", type=Path, required=True)
    parser.add_argument("--logs", type=Path, required=True)
    args = parser.parse_args()
    current, mirrored = inputs(args.repo), inputs(args.mirror)
    if current != mirrored:
        changed = sorted(k for k in current.keys() | mirrored.keys() if current.get(k) != mirrored.get(k))
        raise RuntimeError("mirror mismatch: " + ", ".join(changed))
    runs = {name: read_run(args.logs / name) for name in ("verified.jsonl", "lifecycle.jsonl")}
    tests = {}
    for run in runs.values():
        tests.update(run["tests"])
    top = {name: value for name, value in tests.items() if name.count("/") == 1}
    python_log = (args.logs / "python-test.log").read_text()
    if "Ran 4 tests" not in python_log or "\nOK\n" not in python_log:
        raise RuntimeError("Python checks incomplete")
    for name in ("vet-final.log",):
        if (args.logs / name).read_bytes():
            raise RuntimeError(name + " is not clean")
    compile_log = (args.logs / "compile-final.log").read_text()
    if "FAIL" in compile_log:
        raise RuntimeError("compilation failed")
    openapi = (args.logs / "openapi.log").read_text().splitlines()
    if len(openapi) != 6 or any("OpenAPI/contract passed" not in line for line in openapi):
        raise RuntimeError("OpenAPI checks incomplete")
    result = {
        "schemaVersion": "hnuhole-post-image-media-evidence/v1", "recordedOn": "2026-10-15", "timeZone": "Asia/Shanghai",
        "branch": "codex/post-image-media", "startingCommit": "e0c128033682923d519ea99546d72503b085a99e",
        "frontendReadOnlyCommit": "a696742f943c1cfe6a5005024dccaf40be752d8f", "viewerComponentCommit": "bd7458ad94b7f9aea377ef060acf1316a6cfc6de",
        "scopedResult": "PASS", "fullAppResult": "NOT_RUN", "productionResult": "NOT_RUN",
        "sourceFingerprint": {"canonicalLF_SHA256": fingerprint(current), "fileCount": len(current), "linuxMirrorMatched": True, "files": current},
        "testCounts": {"distinctTopLevelGoTests": len(top), "distinctGoTestsIncludingSubtests": len(tests),
                       "goResults": dict(Counter(v["result"] for v in tests.values())), "pythonTests": 4, "openapiDocuments": 6},
        "runs": runs,
        "additionalChecks": {"goVetAll": "PASS", "goCompileAllPackagesOnly": "PASS", "pythonSyntheticValidation": "PASS", "sixOpenAPIContracts": "PASS"},
        "evidenceBoundaries": {
            "realHTTP": "Fresh loopback TLS HTTP servers execute actual C handlers, synthetic account flows and real PostgreSQL byte storage; not actual cmd/deployment/mobile.",
            "realSQL": "Fresh private-socket cluster/empty C and V databases; raw Up migration SQL including 0014, actual image constraints/hash/erasure and restricted C runtime DML. Not formal Goose upgrade evidence.",
            "realFilesystem": "Task-owned synthetic fixtures, real Python child and FileAuthorizationEvidenceProvider/FileAuthorizationAnchorStore. Image payloads are SQL bytea, not fake filesystem storage.",
            "hostSubstitutes": "PostImageHTTP strictness tests use a host backend substitute only. OTP/mail/time authorities use fresh test material. No production safety/operating assertion.",
            "android": "NOT_RUN; API29+ design only; no SDK/Flutter/bin-cache, ADB or phone use.", "ios": "NOT_RUN; independent acceptance required.",
            "frontend": "No app/UI modification or merge; PostImages mapping and imageCount/empty-body/new-digest deltas handed off at fixed SHA."
        },
        "isolation": {"checkout": "E:/Hnuhole-post-image-media-20261015/repo", "linuxOwnedRoot": "/home/hnuhole/post-image-media-20261015",
                      "sdkInvoked": False, "adbInvoked": False, "deviceUsed": False, "sharedServicesModified": False,
                      "sharedDatabasesUsed": False, "sharedCachesOrSecretsUsed": False, "parallelWorkspacesWritten": False},
        "historicalFailures": [{"run": "initial focused run", "tests": ["identity delete fixture", "party relation inventory"],
                                "cause": "Last-identity deletion is forbidden and the old inventory omitted the new images table; fixture/inventory corrected and retested. Initial compilation also corrected an int/int64 local mismatch.", "currentResult": "RESOLVED"}],
        "notRun": ["formal Goose old-database upgrade", "actual C cmd image-validator assembly", "Flutter host uploader/durable image drafts/viewer wiring", "Android device/gallery/animation", "iOS device/gallery/animation", "production storage/quotas/load/backup deletion/independent security"],
        "report": "docs/design/post-image-media-contract.md", "cleanup": {"status": "PENDING_OWNED_ARTIFACT_CLEANUP"}
    }
    destination = args.repo / "docs/design/post-image-media-verification-20261015.json"
    destination.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result["testCounts"], ensure_ascii=False))
    print("Canonical LF source fingerprint: " + fingerprint(current))


if __name__ == "__main__":
    main()
