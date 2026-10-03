#!/usr/bin/env python3
"""Check B02 handoff paths and exact source snapshot, not application behavior."""
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def source_snapshot(config):
    output = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", *config["roots"]],
        cwd=ROOT,
    )
    paths = sorted(set(value.decode() for value in output.split(b"\0") if value))
    selected = []
    for relative in paths:
        path = ROOT / relative
        if not path.is_file() or path.name.endswith("verification.json") or "verification-report" in path.name:
            continue
        if path.suffix in config["includedSuffixes"] or path.name in config["includedAdditionalNames"]:
            selected.append(relative)
    result = hashlib.sha256()
    for relative in selected:
        result.update(relative.encode())
        result.update(b"\0")
        result.update(hashlib.sha256((ROOT / relative).read_bytes()).digest())
    return {"sha256": result.hexdigest(), "presentFileCount": len(selected)}


def main():
    ledger = json.loads((ROOT / "docs/design/module-acceptance-ledger.json").read_text())
    evidence_path = ROOT / "services/api/authlab/identity-management-verification.json"
    evidence = json.loads(evidence_path.read_text())
    modules = ledger["modules"]
    assert len(modules) == ledger["moduleCount"] == len({m["id"] for m in modules})
    identity = next(m for m in modules if m["id"] == "B02")
    assert identity["implementationState"] == "FOUNDATION_IMPLEMENTED_BUSINESS_INTEGRATION_PENDING"
    assert identity["currentResult"] == "NOT_RUN"
    assert identity["executedEvidenceIsModulePass"] is False
    for name in ("sourcePaths", "testPaths"):
        for relative in identity[name]:
            assert (ROOT / relative).is_file(), relative
            content = (ROOT / relative).read_text()
            assert "\r" not in content, relative
            assert all(line == line.rstrip(" \t") for line in content.splitlines()), relative
    for name in ("taskPlan", "evidence", "report"):
        assert (ROOT / identity[name]).is_file(), name
    for doc in ("HANDOFF.md", "progress.md", "module-acceptance-handoff.md", "identity-management-validation-report.md"):
        path = ROOT / "docs/design" / doc
        targets = re.findall(r"\]\(([^)]+)\)", path.read_text())
        # Historical UI image references are not B02 artifacts and may live
        # outside this checkout. Check all links in this new report, and only
        # this slice's five handoff links in the inherited documents.
        if doc != "identity-management-validation-report.md":
            expected = {"identity-management-plan.md", "identity-management-validation-report.md",
                        "../../services/api/authlab/identity-management-verification.json",
                        "module-acceptance-handoff.md", "module-acceptance-ledger.json"}
            assert expected <= set(targets), doc
            targets = [target for target in targets if target in expected]
        for target in targets:
            if "://" in target or target.startswith("#"):
                continue
            target = target.split("#", 1)[0]
            assert (path.parent / target).exists(), (doc, target)
    actual = source_snapshot(ledger["sourceFingerprint"])
    assert actual["sha256"] == ledger["sourceFingerprint"]["sha256"] == evidence["sourceFingerprint"]["sha256"] == identity["testedWorkingTreeSourceFingerprint"]
    assert actual["presentFileCount"] == ledger["sourceFingerprint"]["presentFileCount"]
    assert evidence["sqlTestsExecuted"] is False and evidence["flutterTestsExecuted"] is False
    assert evidence["moduleAcceptancePassed"] is False
    print(f"PASS: stable module IDs, B02 paths/status, document links and source fingerprint ({actual['presentFileCount']} files)")
    print("Scope: bookkeeping only; no compilation, SQL, Flutter or device acceptance.")


if __name__ == "__main__":
    main()
