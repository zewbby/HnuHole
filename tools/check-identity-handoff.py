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
        path = ROOT / relative
        result.update(relative.encode())
        result.update(b"\0")
        data = path.read_bytes()
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
    if name == "currentNonIOS":
        # Backend regression and the unfinished device matrix are independent
        # acceptance dimensions in this incremental record.
        assert record["currentResult"] == "BLOCKED", name
    else:
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
        required = (("R01-full-sql-race-vet", "R03-actual-cv-process", "R05-actual-dart-https-sql")
                    if name == "currentNonIOS" else ("R01", "R02", "R03"))
        for check_id in required:
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
    for name in ("currentAC01", "currentAC02", "currentAC03", "currentAC04", "currentAC05", "currentAndroidLive", "currentAndroidFault", "currentNonIOS"):
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
    retained_tested_hashes = {historical_hash, selected_fingerprint["sha256"]}
    retained_tested_hashes.update(record["sourceFingerprint"]["sha256"] for record in scoped.values()
                                 if record.get("scopedBackendAcceptancePassed")
                                 or record.get("scopedAndroidLiveAcceptancePassed")
                                 or record.get("scopedAndroidFaultAcceptancePassed")
                                 or record.get("scopedAndroidMatrixAcceptancePassed"))
    # Keep B02's tested pointer on its real older version when a later batch
    # adds unexecuted device fixtures. A new handoff manifest is not a new run.
    for historical in scoped.get("currentNonIOS", {}).get("historicalBackendRuns", []):
        accepted = {check["id"] for check in historical["checks"]
                    if check["result"] == "PASS" and check.get("exitCode") == 0}
        if {"R01-full-sql-race-vet", "R03-actual-cv-process", "R05-actual-dart-https-sql"} <= accepted:
            retained_tested_hashes.add(historical["sourceFingerprintSha256"])
    assert identity["testedWorkingTreeSourceFingerprint"] in retained_tested_hashes, \
        "B02 tested snapshot must refer to current or retained accepted evidence"
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

    if "currentAndroidLive" in scoped:
        live = scoped["currentAndroidLive"]
        assert live["currentResult"] == "BLOCKED", "Remaining platform matrix is not complete"
        assert live["fullDeviceMatrixPassed"] is False
        assert live["systemPasskeyPassed"] is False
        if live["scopedAndroidLiveAcceptancePassed"]:
            checks = {check["id"]: check for check in live["checks"]}
            for check_id in live["androidLiveAcceptanceCheckIds"]:
                assert checks[check_id]["result"] == "PASS" and checks[check_id]["exitCode"] == 0, check_id
            write = live["devicePhases"]["write"]
            read = live["devicePhases"]["read"]
            assert write["phase"] == "write" and read["phase"] == "read"
            assert write["pid"] != read["pid"] and read["priorPid"] == write["pid"]
            for phase in (write, read):
                assert all(phase[field] is True for field in ("actualApp", "actualCV", "nativeVault"))
            assert read["logoutRevokedOldSession"] is True and read["passwordLogin"] is True
        for scene in live["coverage"]:
            assert set(scene["moduleIds"]) <= module_ids, scene["id"]
            assert (ROOT / scene["testPath"]).is_file(), scene["testPath"]

    if "currentAndroidFault" in scoped:
        fault = scoped["currentAndroidFault"]
        assert fault["currentResult"] == "BLOCKED"
        assert fault["fullDeviceMatrixPassed"] is False and fault["systemPasskeyPassed"] is False
        if fault["scopedAndroidFaultAcceptancePassed"]:
            checks = {check["id"]: check for check in fault["checks"]}
            phases = ("write", "unknown", "reconcile", "frozen", "recovered", "offline-logout", "drain")
            prior = None
            pids = set()
            for name in phases:
                check = checks["device-" + name]
                assert check["result"] == "PASS" and check["exitCode"] == 0
                phase = fault["devicePhases"][name]
                assert phase["phase"] == name and phase["pid"] not in pids
                assert all(phase[field] is True for field in ("actualApp", "actualCV", "nativeVault"))
                if prior is not None:
                    assert phase["priorPid"] == prior
                pids.add(phase["pid"])
                prior = phase["pid"]
            for name, fields in {
                "unknown": ("unknownIntentDurable",),
                "reconcile": ("originalIntentReconciled", "noDuplicateIdentity"),
                "frozen": ("gateRefusedProtectedMutation", "nativeSessionPreserved"),
                "recovered": ("authorityRecheckedAfterGateRecovery", "oldGenerationSessionRejected", "frozenMutationAbsent"),
                "offline-logout": ("localBearerCleared", "independentLogoutCapabilityDurable"),
                "drain": ("logoutRevokedOldSession", "passwordLogin", "pendingLogoutDrained"),
            }.items():
                assert all(fault["devicePhases"][name][field] is True for field in fields)
            assert fault["proxyMetrics"]["droppedCommittedCreates"] == 1
            assert fault["proxyMetrics"]["blockedRevocations"] >= 1
            assert fault["proxyMetrics"]["resultQueries"] >= 1
            sql = {name: fault["sqlReadback"][name]["sql"] for name in phases}
            assert sql["unknown"]["committedCreates"] == sql["write"]["committedCreates"] + 1
            assert sql["unknown"]["activeIdentities"] == sql["write"]["activeIdentities"] + 1
            for name in phases[2:]:
                for field in ("accounts", "activeIdentities", "committedCreates", "committedRenames"):
                    assert sql[name][field] == sql["unknown"][field], (name, field)
                assert sql[name]["frozenMutationProfiles"] == 0
            assert sql["frozen"]["gateState"] == "FROZEN"
            assert sql["recovered"]["gateState"] == sql["drain"]["gateState"] == "OPEN"
            assert sql["recovered"]["gateGeneration"] > sql["frozen"]["gateGeneration"]
            assert sql["drain"]["revokedSessions"] > sql["offline-logout"]["revokedSessions"]
            assert sql["drain"]["activeSessions"] == 1
        for scene in fault["coverage"]:
            assert set(scene["moduleIds"]) <= module_ids
            assert (ROOT / scene["testPath"]).is_file()

    if "currentNonIOS" in scoped:
        matrix = scoped["currentNonIOS"]
        assert matrix["currentResult"] == "BLOCKED"
        assert matrix["moduleAcceptancePassed"] is False
        if "batchPreparation" in matrix:
            batch = matrix["batchPreparation"]
            assert batch["deviceAcceptanceResult"] in {"NOT_RUN", "PARTIAL", "PASS"}
            assert batch["buildResult"] in {"NOT_RUN", "PASS"}
            assert batch["fullModuleAcceptancePassed"] is False
            assert batch["onlyPhysicalAndroidAvailable"] == "vivo S18"
            assert batch["oemPhysicalTransferResult"] == "BLOCKED"
            assert batch["configExportResult"] in {"BLOCKED", "PASS"}
            if batch["configExportResult"] == "BLOCKED":
                assert batch["blocker"]["kind"] == "AUTOMATIC_APPROVAL_REVIEW_QUOTA_FAILURE"
            else:
                assert batch["historicalApprovalFailure"]["kind"] == "AUTOMATIC_APPROVAL_REVIEW_QUOTA_FAILURE"
                assert batch["historicalApprovalFailure"]["resolved"] is True
                assert batch["currentProxySourceActivated"] is True
            # Historical accepted APK/fixture/runner hashes remain immutable;
            # current tooling can advance for the fixed subsequent batches.
            for relative, sha in batch.get("currentSourceFilesSha256", batch["sourceFilesSha256"]).items():
                assert hashlib.sha256((ROOT / relative).read_bytes()).hexdigest() == sha, relative
            for run in batch["completedRegressionProcesses"]:
                assert run["result"] == "PASS" and run["exitCode"] == 0
                assert run["newBatchDeviceFixtureCovered"] is False
                assert run["testedSourceManifestExportResult"] in {"BLOCKED", "PASS"}
                if run["testedSourceManifestExportResult"] == "PASS":
                    assert run["cacheSourceMatchesCurrentAtCollection"] is True
            if "batchVerification" in matrix:
                current = matrix["batchVerification"]
                pids = set()
                for entry in current["phases"]:
                    assert entry["result"] == "PASS" and entry["exitCode"] == 0
                    assert entry["apkSha256"] in current["acceptedApkSha256"]
                    assert len(entry["fixtureSourceSha256"]) == 64
                    assert len(entry["runnerSha256"]) == 64
                    process = (entry["deviceId"], entry["report"]["pid"])
                    assert process not in pids
                    pids.add(process)
                    assert entry["report"]["phase"] == entry["id"]
                    assert all(entry["report"][k] for k in ("actualApp", "actualCV", "nativeVault"))
                    if entry["id"].startswith("batch-passkey-") or entry["id"] == "batch-gate-session-recover":
                        counts = entry["proxyCounts"]
                        assert counts["phase"] == entry["id"] and counts["result"] == "PASS"
                        assert counts["scope"] == "PROXY_COUNTERS_ONLY"
                        assert counts["proofsStored"] is False and counts["actualAppAcceptancePassed"] is False
                        expected = 1 if entry["id"] in {"batch-passkey-drop", "batch-passkey-origin-reject"} else 0
                        assert counts["delta"]["bindingSubmits"] == expected
                    if entry["id"] == "batch-passkey-timeout":
                        assert 55000 <= entry["report"]["nativeCancellationElapsedMillis"] <= 75000
                        assert entry["report"]["noHostBackBeforeNativeCancellation"] is True
                assert current["fullModuleAcceptancePassed"] is False
        domain = read_record(matrix["domainEvidence"])
        assert domain["currentResult"] == "PASS" and domain["systemPasskeyPassed"] is False
        assert domain["publicAssociation"]["httpStatus"] == 200
        assert domain["publicAssociation"]["contentType"] == "application/json"
        assert all(domain["publicAssociation"][key] is True for key in
                   ("noRedirect", "normalTlsVerification", "payloadMatches"))
        assert domain["googleDigitalAssetLinks"]["linked"] is True
        site = ROOT / domain["sourceDirectory"]
        assert sorted(str(p.relative_to(site)).replace("\\", "/") for p in site.rglob("*") if p.is_file()) == sorted(domain["files"])
        for name, description in domain["files"].items():
            assert hashlib.sha256((site / name).read_bytes()).hexdigest() == description["sha256"], name
        pids = set()
        for phase in matrix.get("devicePhases", []):
            assert phase["result"] == "PASS" and phase["exitCode"] == 0
            report = phase["report"]
            assert report["phase"] == phase["id"] and report["pid"] not in pids
            pids.add(report["pid"])
            assert all(report[key] is True for key in ("actualApp", "actualCV", "nativeVault"))
        for scene in matrix["coverage"]:
            assert set(scene["moduleIds"]) <= module_ids
            assert (ROOT / scene["testPath"]).is_file()
        for phase in matrix.get("boundaryDevicePhases", []):
            assert phase["result"] == "PASS" and phase["exitCode"] == 0
            assert phase["apkSha256"] in matrix["versions"]["boundary"]["acceptedApkSha256"]
            report = phase["report"]
            assert report["phase"] == phase["id"]
            assert all(report[key] is True for key in ("actualApp", "actualCV", "nativeVault"))
        if "realImeVerification" in matrix:
            ime = matrix["realImeVerification"]
            assert ime["result"] == "PASS"
            assert ime["humanPhysicalKeyboardUsed"] is True
            assert ime["productTextInjected"] is False
            assert ime["identityCreated"] is False
            assert ime["keyboard"]["restoredOriginal"] is True
            assert ime["keyboard"]["keyboardInstalledByTest"] is False
            phases = {phase["id"]: phase for phase in ime["phases"]}
            assert set(phases) == {"phone-ime-inspect", "phone-ime-write", "phone-ime-read"}
            assert len({phase["report"]["pid"] for phase in phases.values()}) == 3
            for phase in phases.values():
                assert phase["result"] == "PASS" and phase["exitCode"] == 0
                assert all(phase["report"][key] is True for key in
                           ("actualApp", "actualCV", "nativeVault"))
                assert phase["report"]["syntheticEditingValuesInjected"] is False
            write = phases["phone-ime-write"]["report"]
            assert all(write[key] is True for key in
                       ("realDevicePointerFocusedEditor", "physicalPointerEventsEnabled",
                        "actualPhoneImeCompositionObserved",
                        "uncommittedComposingTextExcludedFromNativeDraft",
                        "committedSyntheticDraftDurablySaved"))
            assert write["actualEditingEventCount"] > 0 and write["actualComposingEventCount"] > 0
            assert phases["phone-ime-read"]["report"]["sameSessionAndCommittedImeDraftRestoredInNewProcess"] is True
            assert all(phases[name]["apkSha256"] == ime["apkSha256"] for name in
                       ("phone-ime-write", "phone-ime-read"))
            assert ime["touchPrerequisite"]["pid"] == write["pid"]
            assert all(attempt["result"] == "FAIL" for attempt in ime["historicalFailedAttempts"])
        if "talkBackVerification" in matrix:
            talkback = matrix["talkBackVerification"]
            assert talkback["result"] == "PASS"
            assert talkback["humanSpeechObserved"] is True
            assert talkback["semanticsActionsInjected"] is False
            assert talkback["originalAccessibilityRestored"] is True
            assert talkback["environmentResume"]["schemaReset"] is False
            phases = {phase["id"]: phase for phase in talkback["phases"]}
            assert set(phases) == {"phone-talkback-prepare", "phone-talkback-navigate", "phone-talkback-read"}
            assert len({phase["report"]["pid"] for phase in phases.values()}) == 3
            for phase in phases.values():
                assert phase["result"] == "PASS" and phase["exitCode"] == 0
                assert phase["apkSha256"] == talkback["apkSha256"]
                assert all(phase["report"][key] is True for key in ("actualApp", "actualCV", "nativeVault"))
                assert all(phase["report"][key] is False for key in
                           ("semanticsActionsInjected", "nicknameTextInjected", "identityCreated"))
                if phase["id"] != "phone-talkback-prepare":
                    assert phase["hostAccessibilityEvidence"]["actualLoadedTalkBack"] is True
                    assert phase["report"]["platformSemanticsEnabled"] is True
                    assert phase["report"]["platformAccessibleNavigation"] is True
            navigate = phases["phone-talkback-navigate"]["report"]
            assert all(navigate[key] is True for key in
                       ("actualSettingsFocusTraversal", "actualIdentityEditorFocusAndCancel", "actualSecurityRouteAndReturn"))
            assert navigate["actualPlatformAccessibilityFocusEvents"] >= 4
            assert navigate["actualPlatformAccessibilityTapEvents"] >= 4
            assert phases["phone-talkback-read"]["report"]["sameSessionAndDraftRestoredInNewProcess"] is True
            assert phases["phone-talkback-read"]["report"]["actualRestoredEditorAccessibilityFocus"] is True
            assert all(talkback["humanObservation"][key] is True for key in
                       ("settingsLabelsClear", "editorAndCancelClear", "securityAndReturnClear", "restoredNicknameAndDraftClear"))
        if "formalClosureVerification" in matrix:
            closure = matrix["formalClosureVerification"]
            assert closure["result"] == "PASS"
            assert closure["realSevenDayWait"] is False
            assert closure["sqlDeadlineEdited"] is False
            assert closure["hostOrPhoneClockChanged"] is False
            assert closure["schemaResetDuringAcceptance"] is False
            assert closure["originalAccountCiphertextUnchanged"] is True
            assert closure["unresolvedOperationLateCallbacksCovered"] is False
            assert closure["closureWithSystemPasskeyCovered"] is False
            phases = {phase["id"]: phase for phase in closure["phases"]}
            assert set(phases) == {
                "closure-draft-request", "closure-draft-released", "closure-draft-register",
                "closure-profile-request", "closure-profile-released", "closure-profile-register",
                "closure-new-read",
            }
            assert len({phase["report"]["pid"] for phase in phases.values()}) == 7
            for phase in phases.values():
                assert phase["result"] == "PASS" and phase["exitCode"] == 0
                assert all(phase["report"][key] is True for key in
                           ("actualApp", "actualCV", "nativeVault", "simulatedGateTime"))
                assert phase["report"]["systemPasskey"] is False
                assert phase["apkSha256"] in closure["acceptedApkSha256"]
            # Earlier accepted phases keep their exact APK/source version;
            # the current fixture hash must not rewrite their historical scope.
            assert phases["closure-draft-request"]["apkSha256"] == closure["firstPhaseVersion"]["apkSha256"]
            for name in ("closure-draft-released", "closure-profile-released"):
                assert phases[name]["report"]["oldBearerPasswordAndRecoveryCodeRejected"] is True
                assert phases[name]["report"]["repeatedOriginalStatusLookupDidNotRestoreSession"] is True
            for name in ("closure-draft-register", "closure-profile-register"):
                assert phases[name]["report"]["sameExactEmailRequiredFreshOtpAndActualRegistration"] is True
                assert phases[name]["report"]["newAccountNoOldIdentityCounterCooldownDraftOrLocalOperation"] is True
            assert phases["closure-new-read"]["report"]["sameNicknameCreatedWithFreshIdAndIndependentHistory"] is True
            for cycle in closure["hostCycles"]:
                assert cycle["capture"]["immutableDeadlineExactlySevenDays"] is True
                assert all(cycle["advance"][key] is True for key in
                           ("ordinaryWorkersFinalizedAndReleased", "identityProfilesErased",
                            "permanentIdentityReceiptsUnchanged", "passwordAndUsernameErased",
                            "verifierExactEmailQuotaEmptyAfterAck"))
                assert cycle["advance"]["sqlDeadlineEdited"] is False
            assert [cycle["capture"]["activeIdentityCountBeforeDeadline"] for cycle in closure["hostCycles"]] == [0, 3]
        for check in matrix.get("nativeDeviceChecks", []):
            assert check["result"] == "PASS" and check["exitCode"] == 0
            if check["id"] == "native-ciphertext-transfer-reinstall":
                details = check["details"]
                assert details["targetIsEmulator"] is True
                assert all(details[key] is False for key in
                           ("keysExported", "mainAppUninstalled", "fullAppMigrationPassed", "oemDeviceTransferPassed"))

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
