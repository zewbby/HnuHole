#!/usr/bin/env python3
"""Validate AC06 delivery material; does not run functional acceptance."""
import hashlib
import importlib.util
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = "services/api/authlab/final-handoff-verification.json"
PLAN = "docs/design/auth-privacy-final-handoff-plan.md"
REPORT = "docs/design/auth-privacy-final-handoff-report.md"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def matches_text(path, raw_hash, lf_hash):
    data = path.read_bytes()
    return digest(data) == raw_hash or digest(data.replace(b"\r\n", b"\n")) == lf_hash


def check_links(relative):
    path = ROOT / relative
    for target in re.findall(r"\]\(([^)]+)\)", path.read_text(encoding="utf-8")):
        if "://" not in target and not target.startswith("#"):
            assert (path.parent / target.split("#", 1)[0]).exists(), (relative, target)


def check_tables(relative):
    width = None
    for line in (ROOT / relative).read_text(encoding="utf-8").splitlines():
        if line.startswith("|"):
            columns = len(line.split("|"))
            if width is None:
                width = columns
            assert columns == width, (relative, "table column count", line)
        else:
            width = None


def main():
    spec = importlib.util.spec_from_file_location("identity_handoff", ROOT / "tools/check-identity-handoff.py")
    previous = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(previous)
    previous.main()
    ledger_path = ROOT / "docs/design/module-acceptance-ledger.json"
    ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
    current = ledger["currentAC06"]
    record = previous.read_record(EVIDENCE)
    assert current["evidence"] == EVIDENCE
    assert current["plan"] == record["plan"] == PLAN
    assert current["report"] == record["report"] == REPORT
    assert current["currentResult"] == record["currentResult"] in {"NOT_RUN", "PASS"}
    assert record["scope"] == "AC06_LOCAL_SOURCE_AND_EVIDENCE_HANDOFF_ONLY"
    previous.no_full_closure(record)
    assert record["dynamicTestsRerunForAC06"] is False
    assert record["scopedBackendAcceptancePassed"] is False
    assert record["moduleAcceptancePassed"] is False
    assert record["remoteDeliveryResult"] == "NOT_RUN"
    assert record["publication"]["committed"] is False
    assert record["publication"]["pushed"] is False
    assert record["publication"]["deployed"] is False
    previous.same_snapshot(current["sourceFingerprint"], record["sourceFingerprint"], "AC06 implementation")
    previous.same_snapshot(record["sourceFingerprint"], ledger["currentAC05"]["sourceFingerprint"],
                           "AC06 does not change accepted implementation inputs")
    assert matches_text(ledger_path, record["ledgerSha256"], record["ledgerLfSha256"]), "ledger bytes changed"
    for dependency in record["retainedEvidence"]:
        path = ROOT / dependency["path"]
        assert matches_text(path, dependency["sha256"], dependency["lfSha256"]), dependency["id"]
        retained = previous.read_record(dependency["path"])
        assert retained["currentResult"] == dependency["result"]
        assert retained["sourceFingerprint"]["sha256"] == dependency["testedSourceSha256"]
    entries = record["handoffArtifacts"]
    assert len(entries) == len({entry["path"] for entry in entries}) == record["handoffArtifactCount"]
    manifest = hashlib.sha256()
    for entry in sorted(entries, key=lambda value: value["path"]):
        assert entry["path"] not in {EVIDENCE, "docs/design/module-acceptance-ledger.json"}, "self-reference"
        path = ROOT / entry["path"]
        assert matches_text(path, entry["sha256"], entry["lfSha256"]), entry["path"]
        manifest.update(entry["path"].encode())
        manifest.update(b"\0")
        manifest.update(bytes.fromhex(entry["sha256"]))
    assert manifest.hexdigest() == record["handoffArtifactFingerprint"]
    assert PLAN in {entry["path"] for entry in entries} and REPORT in {entry["path"] for entry in entries}
    assert "tools/check-privacy-closure-handoff.py" in {entry["path"] for entry in entries}
    closure = ledger["anonymityBranchClosure"]
    assert closure["currentTask"] == "AC06"
    assert closure["localSourceHandoffClosed"] == (current["currentResult"] == "PASS")
    assert closure["sourceDeliveryClosed"] is False  # Remote publication is pending.
    assert closure["acceptanceClosed"] is False and closure["productionApproved"] is False
    gaps = {gap["id"]: gap for gap in closure["gaps"]}
    assert set(gaps) == {f"AC0{i}" for i in range(1, 7)}
    for index in range(1, 7):
        name = f"AC0{index}"
        assert gaps[name]["currentResult"] == ledger["current" + name]["currentResult"], name
        assert gaps[name]["evidence"] == ledger["current" + name]["evidence"], name
    feature = ledger["currentFeature"]
    assert feature["snapshotStatus"] == "HISTORICAL_B02_FEATURE_SNAPSHOT"
    assert feature["currentEvidence"] == ledger["currentAC05"]["evidence"]
    assert ledger["latestValidationEvidence"] == EVIDENCE
    assert ledger["latestBackendValidationEvidence"] == ledger["currentAC04"]["evidence"]
    assert ledger["latestMobileValidationEvidence"] == ledger["currentAC05"]["evidence"]
    for relative in (PLAN, REPORT):
        check_links(relative)
        check_tables(relative)
    check_tables("docs/design/auth-privacy-closure-checklist.md")
    for name in ("HANDOFF.md", "progress.md", "module-acceptance-handoff.md", "auth-privacy-machine-handoff.md",
                 "auth-privacy-closure-checklist.md", "README.md", "auth-privacy-architecture-decision.md",
                 "auth-privacy-security-review-package.md"):
        text = (ROOT / "docs/design" / name).read_text(encoding="utf-8")
        assert "auth-privacy-final-handoff-report.md" in text[:2500], name
    snapshot = previous.read_record("docs/design/auth-privacy-review-snapshot.json")
    assert snapshot["sourceCommit"] == "05dc4a4b88797f5532829c1f2953484f7ac86c90"
    assert snapshot["scope"] == "PREIMPLEMENTATION_SPECIFICATION_REVIEW_INPUT"
    assert snapshot["status"] == "PREPARED_NO_INDEPENDENT_SIGNOFF"
    assert record["cleanup"]["result"] == "PASS"
    assert not (ROOT / "infra/.cache/ac04").exists()
    assert not (ROOT / "infra/.cache/ac05").exists()
    if current["currentResult"] == "PASS":
        assert current["deliveryAcceptancePassed"] is record["deliveryAcceptancePassed"] is True
        required = {"prior-handoff", "final-handoff", "diff", "cleanup"}
        assert required <= {check["id"] for check in record["checks"]
                            if check["result"] == "PASS" and check["exitCode"] == 0}
    print(f"PASS: AC06 retained evidence, {len(entries)} handoff artifacts, ledger/source snapshots and current entrances")
    print("Scope: local delivery bookkeeping only; AC05/B02 remain BLOCKED, remote publication pending, no production approval.")


if __name__ == "__main__":
    main()
