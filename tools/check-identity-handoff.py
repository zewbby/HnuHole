#!/usr/bin/env python3
"""Check current AC handoff and historical B02 evidence, not app behavior."""
import hashlib
import json
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def source_snapshot(config, normalize_checkout=False):
    # These names include repository-root dependency/checkout controls which
    # are outside the service/infra roots. Keep the path selection identical
    # to the current evidence manifest, including non-ignored untracked files.
    pathspecs = list(dict.fromkeys([*config["roots"], *config["includedAdditionalNames"]]))
    output = subprocess.check_output(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", *pathspecs],
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
        data = (ROOT / relative).read_bytes()
        # Git text checkout can use CRLF while committed blobs use LF. The
        # protocol fixture has an exact byte hash and must never use this
        # equivalence fallback; its eol=lf attribute is mandatory.
        if (normalize_checkout and relative != "packages/auth-protocol-vectors/v1.json"
                and path.suffix not in (".png", ".jpg", ".jpeg", ".jar")):
            data = data.replace(b"\r\n", b"\n")
        result.update(hashlib.sha256(data).digest())
    return {"sha256": result.hexdigest(), "presentFileCount": len(selected)}


def read_record(relative):
    path = ROOT / relative
    assert path.is_file(), relative
    return json.loads(path.read_text(encoding="utf-8"))


def same_snapshot(first, second, scope):
    for field in ("sha256", "presentFileCount"):
        assert first[field] == second[field], (scope, field, first[field], second[field])


def no_full_closure(value):
    # A bounded backend PASS must never silently approve anonymity closure or
    # production. Historical records keep their own results and proof scope.
    if isinstance(value, dict):
        for name, item in value.items():
            if name in ("fullAnonymityClosurePassed", "productionApproved"):
                assert item is False, name
            no_full_closure(item)
    elif isinstance(value, list):
        for item in value:
            no_full_closure(item)


def scoped_record(name, record, result_definitions):
    assert record["currentResult"] in result_definitions, name
    assert record["fullAnonymityClosurePassed"] is False, name
    assert record.get("productionApproved", False) is False, name
    assert type(record["scopedBackendAcceptancePassed"]) is bool, name
    assert record["scopedBackendAcceptancePassed"] == (record["currentResult"] == "PASS"), name
    for field in ("plan", "report"):
        if field in record:
            assert (ROOT / record[field]).is_file(), (name, field)
    if "evidence" not in record:
        assert record["currentResult"] != "PASS", (name, "PASS without evidence")
        return None
    evidence = read_record(record["evidence"])
    same_snapshot(record["sourceFingerprint"], evidence["sourceFingerprint"], name)
    assert evidence["currentResult"] == record["currentResult"], name
    assert evidence["fullAnonymityClosurePassed"] is False, name
    assert evidence["productionApproved"] is False, name
    if "moduleAcceptancePassed" in evidence:
        assert evidence["moduleAcceptancePassed"] is False, name
    no_full_closure(evidence)
    if record["scopedBackendAcceptancePassed"]:
        for check_id in ("R01", "R02", "R03"):
            assert any(check["id"] == check_id and check["result"] == "PASS"
                       and check.get("exitCode") == 0 for check in evidence["checks"]), (name, check_id)
    return evidence


def main():
    ledger = read_record("docs/design/module-acceptance-ledger.json")
    modules = ledger["modules"]
    assert len(modules) == ledger["moduleCount"] == len({m["id"] for m in modules})
    module_ids = {module["id"] for module in modules}
    for module in modules:
        assert module["currentResult"] in ledger["resultDefinitions"], module["id"]
        assert set(module.get("relatedModules", [])) <= module_ids, module["id"]
    no_full_closure(ledger)
    identity = next(m for m in modules if m["id"] == "B02")
    evidence = read_record(identity["evidence"])
    assert identity["implementationState"] == "FOUNDATION_IMPLEMENTED_BUSINESS_INTEGRATION_PENDING"
    assert identity["currentResult"] == "BLOCKED"
    assert evidence["moduleAcceptancePassed"] is False
    assert identity["executedEvidenceIsModulePass"] == evidence["moduleAcceptancePassed"]
    for name in ("sourcePaths", "testPaths"):
        for relative in identity[name]:
            assert (ROOT / relative).is_file(), relative
            content = (ROOT / relative).read_text(encoding="utf-8")
            assert "\r" not in content, relative
            assert all(line == line.rstrip(" \t") for line in content.splitlines()), relative
    for name in ("taskPlan", "evidence", "report"):
        assert (ROOT / identity[name]).is_file(), name

    # These flags and hashes refer to the historical mobile/B02 revision.
    # They agree with each other, never with a later AC backend-only snapshot.
    latest = read_record(evidence["latestValidationEvidence"])
    same_snapshot(evidence["sourceFingerprint"], latest["sourceFingerprint"], "historical B02")
    historical_hash = latest["sourceFingerprint"]["sha256"]
    historical_hashes = {item["sha256"] for item in identity.get("sourceFingerprintHistory", [])}
    assert (identity["testedWorkingTreeSourceFingerprint"] == historical_hash
            or historical_hash in historical_hashes), "historical B02 snapshot must remain recorded"
    for flag in ("sqlTestsExecuted", "flutterTestsExecuted", "deviceTestsExecuted", "compileExecuted", "moduleAcceptancePassed"):
        assert type(evidence[flag]) is bool, flag
    for flag in ("sqlTestsExecuted", "flutterTestsExecuted", "deviceTestsExecuted", "moduleAcceptancePassed"):
        assert latest[flag] == evidence[flag], flag
    assert latest["goCompileExecuted"] == evidence["compileExecuted"]
    if evidence["sqlTestsExecuted"]:
        assert any(check["id"] == "go-sql-race-vet" and check["result"] == "PASS" for check in latest["checks"])
    no_full_closure(evidence)
    no_full_closure(latest)

    selected_name, selected_record = "historical B02", None
    scoped = {}
    for name in ("currentAC01", "currentAC02", "currentAC03", "currentAC04", "currentAC05"):
        if name in ledger:
            record = ledger[name]
            validated = scoped_record(name, record, ledger["resultDefinitions"])
            if validated is not None:
                scoped[name] = validated
                selected_name, selected_record = name, record
    selected_fingerprint = (selected_record["sourceFingerprint"]
                            if selected_record is not None else evidence["sourceFingerprint"])
    same_snapshot(ledger["sourceFingerprint"], selected_fingerprint, "selected current snapshot")
    for name in ("roots", "includedSuffixes", "includedAdditionalNames"):
        assert ledger["sourceFingerprint"][name] == selected_fingerprint[name], name
    actual = source_snapshot(selected_fingerprint)
    if actual != {key: selected_fingerprint[key] for key in ("sha256", "presentFileCount")}:
        committed = selected_record.get("gitBlobSourceFingerprint") if selected_record else None
        assert committed is not None, "workspace bytes differ without a retained Git text snapshot"
        same_snapshot(source_snapshot(selected_fingerprint, normalize_checkout=True), committed,
                      "Git text checkout bytes (protocol fixture remains exact)")
    else:
        same_snapshot(actual, selected_fingerprint, "workspace bytes")
    assert identity["testedWorkingTreeSourceFingerprint"] in {
        historical_hash, selected_fingerprint["sha256"]
    }, "B02 tested snapshot must refer to current backend or retained historical B02 evidence"
    if "latestValidationEvidence" in identity:
        # B02's current pointer follows its current tested scope. Its retained
        # foundation evidence still points to the historical mobile/runtime
        # record, which was independently checked above.
        expected_latest = evidence["latestValidationEvidence"]
        if selected_record is not None and identity["testedWorkingTreeSourceFingerprint"] != historical_hash:
            expected_latest = selected_record["evidence"]
        assert identity["latestValidationEvidence"] == expected_latest, "B02 current evidence pointer"
    # Module regression records may advertise scoped PASS while B02 remains
    # BLOCKED. Match those claims to their AC evidence without promoting B02.
    for module in modules:
        for name, verified in scoped.items():
            regression = module.get(name + "Regression")
            if regression is not None:
                assert regression["fullModuleAcceptancePassed"] is False, (module["id"], name)
                assert regression["currentResult"] == verified["currentResult"], (module["id"], name)
                if "evidence" in regression:
                    assert regression["evidence"] == ledger[name]["evidence"], (module["id"], name)

    if "currentAC04" in scoped:
        coverage = scoped["currentAC04"]["coverage"]
        assert len(coverage) == len({scene["id"] for scene in coverage}), "AC04 duplicate scene IDs"
        passed_runners = {check["id"] for check in scoped["currentAC04"]["checks"]
                          if check["result"] == "PASS" and check.get("exitCode") == 0}
        for scene in coverage:
            assert set(scene["moduleIds"]) <= module_ids, scene["id"]
            assert set(scene["evidenceRunners"]) <= passed_runners, scene["id"]
            path = ROOT / scene["testPath"]
            assert path.is_file(), scene["testPath"]
            content = path.read_text(encoding="utf-8")
            for function in scene["testFunctions"]:
                assert re.search(r"func " + re.escape(function) + r"\(", content), (scene["id"], function)

    if "currentAC05" in scoped:
        platform = scoped["currentAC05"]
        assert platform["currentResult"] == "BLOCKED", "AC05 outstanding platform matrix"
        assert platform["scopedBackendAcceptancePassed"] is False
        if platform["scopedAndroidAcceptancePassed"]:
            for check_id in platform["androidAcceptanceCheckIds"]:
                assert any(check["id"] == check_id and check["result"] == "PASS"
                           and check.get("exitCode") == 0 for check in platform["checks"]), check_id
        assert platform["fullDeviceMatrixPassed"] is False
        for scene in platform["coverage"]:
            assert set(scene["moduleIds"]) <= module_ids, scene["id"]
            assert (ROOT / scene["testPath"]).is_file(), scene["testPath"]

    allowed = {"identity-management-plan.md", "identity-management-validation-report.md",
               "../../services/api/authlab/identity-management-verification.json",
               "module-acceptance-handoff.md", "module-acceptance-ledger.json"}
    for name in scoped:
        record = ledger[name]
        for field in ("plan", "report", "evidence"):
            relative = record.get(field)
            if relative:
                allowed.add(Path(relative).name if relative.startswith("docs/design/") else "../../" + relative)
    for doc in ("HANDOFF.md", "progress.md", "module-acceptance-handoff.md", "identity-management-validation-report.md"):
        path = ROOT / "docs/design" / doc
        targets = re.findall(r"\]\(([^)]+)\)", path.read_text(encoding="utf-8"))
        # Historical UI image references are not B02 artifacts and may live
        # outside this checkout. Check all links in this new report, and only
        # this slice's five handoff links in the inherited documents.
        if doc != "identity-management-validation-report.md":
            expected = {"identity-management-plan.md", "identity-management-validation-report.md",
                        "../../services/api/authlab/identity-management-verification.json",
                        "module-acceptance-handoff.md", "module-acceptance-ledger.json"}
            assert expected <= set(targets), doc
            targets = [target for target in targets if target.split("#", 1)[0] in allowed]
        for target in targets:
            if "://" in target or target.startswith("#"):
                continue
            target = target.split("#", 1)[0]
            assert (path.parent / target).exists(), (doc, target)
    for name in scoped:
        report = ledger[name].get("report")
        if report:
            path = ROOT / report
            for target in re.findall(r"\]\(([^)]+)\)", path.read_text(encoding="utf-8")):
                if "://" not in target and not target.startswith("#"):
                    assert (path.parent / target.split("#", 1)[0]).exists(), (report, target)
    print(f"PASS: stable module IDs, historical B02 evidence/status, AC handoff links and {selected_name} source fingerprint ({actual['presentFileCount']} files)")
    print("B02 remains BLOCKED; scoped backend/Android PASS does not approve full anonymity closure or production.")
    print("Scope: bookkeeping only; this checker does not execute compilation, SQL, Flutter or device acceptance.")


if __name__ == "__main__":
    main()
