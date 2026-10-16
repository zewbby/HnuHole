#!/usr/bin/env python3
"""Verify bounded B6 evidence and completion claims; never execute acceptance."""
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CASE_IDS = tuple([f'NI-L{i:02}' for i in range(1, 5)]
                 + [f'NI-U{i:02}' for i in range(1, 4)]
                 + [f'NI-A{i:02}' for i in range(1, 5)]
                 + [f'NI-C{i:02}' for i in range(1, 5)]
                 + [f'NI-D{i:02}' for i in range(1, 6)]
                 + [f'NI-K{i:02}' for i in range(1, 3)]
                 + ['NI-X01', 'NI-X02'])
SECOND_DEVICE_CASES = {'NI-X01', 'NI-X02'}
STAGE_IDS = {
    'batch-register', 'batch-phone-draft', 'batch-companion-draft',
    'batch-phone-retake', 'batch-account-isolation', 'batch-passkey-drop',
    'batch-passkey-reconcile', 'batch-passkey-remove-existing',
    'batch-gate-session-recover', 'batch-passkey-ack-interrupted-success',
    'batch-passkey-timeout', 'batch-passkey-origin-reject',
    'batch-passkey-rejected-reconcile', 'batch-passkey-route-cancel',
}
REQUIRED_CHECKS = {
    'R01-full-sql-race-vet', 'R03-actual-cv-process',
    'R05-actual-dart-https-sql', 'flutter-analysis-and-available-tests',
    'standard-android-debug-release', 'android-native-vault',
    'android-passkey-codec', 'installed-release-boundary',
    'openapi-complete', 'host-tool-guards', 'source-and-secret-review',
    'owned-test-cleanup-and-preservation',
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def matches_text_digest(data, sha, lf_sha=None):
    assert re.fullmatch(r'[0-9a-f]{64}', sha)
    if lf_sha is not None:
        assert re.fullmatch(r'[0-9a-f]{64}', lf_sha)
    return digest(data) == sha or (lf_sha is not None
                                  and digest(data.replace(b'\r\n', b'\n')) == lf_sha)


def repository_path(root, relative):
    assert isinstance(relative, str) and '\\' not in relative
    path = (root / relative).resolve(strict=True)
    assert path.is_relative_to(root.resolve()) and path.is_file(), relative
    return path


def read_reference(root, reference):
    path = repository_path(root, reference['path'])
    data = path.read_bytes()
    assert matches_text_digest(data, reference['sha256'], reference.get('lfSha256')), reference['path']
    return json.loads(data)


def at_pointer(document, pointer):
    assert pointer.startswith('/')
    current = document
    for key in pointer[1:].split('/'):
        key = key.replace('~1', '/').replace('~0', '~')
        current = current[int(key)] if isinstance(current, list) else current[key]
    return current


def validate_completion(record):
    """Derive both endpoints from the fixed matrix, not from a claimed count."""
    cases = record['cases']
    assert len(cases) == len(CASE_IDS) == len({case['id'] for case in cases})
    assert {case['id'] for case in cases} == set(CASE_IDS)
    assert all(case['result'] in {'PASS', 'FAIL', 'BLOCKED', 'NOT_RUN'} for case in cases)
    checks = record['checks']
    assert len(checks) == len({check['id'] for check in checks})
    accepted = {check['id'] for check in checks
                if check['result'] == 'PASS' and type(check.get('exitCode')) is int
                and check['exitCode'] == 0}
    b6 = REQUIRED_CHECKS <= accepted and record['unresolvedSecurityCriticalDefects'] == []
    assert record['b6Result'] == ('PASS' if b6 else 'NOT_RUN')
    single = b6 and all(case['result'] == 'PASS' for case in cases
                       if case['id'] not in SECOND_DEVICE_CASES)
    complete = b6 and all(case['result'] == 'PASS' for case in cases)
    for name, expected in [('b6WithoutSecondAndroidPassed', single),
                           ('nonIOSDevelopmentAcceptancePassed', complete)]:
        assert type(record[name]) is bool and record[name] is expected, name
    counts = {state: sum(case['result'] == state for case in cases)
              for state in ['PASS', 'FAIL', 'BLOCKED', 'NOT_RUN']}
    assert record['fixedCaseCounts'] == counts
    assert record['matrixResult'] == ('PASS' if complete else 'BLOCKED')
    for name in ['fullAnonymityClosurePassed', 'productionApproved',
                 'fullDeviceMatrixPassed', 'iosAcceptancePassed',
                 'futureBusinessAcceptancePassed']:
        assert record[name] is False, name
    assert record['iosResult'] == 'SKIP' and record['productionResult'] == 'NOT_RUN'
    return counts


def validate_case(case, dependencies, module_ids):
    assert set(case['moduleIds']) <= module_ids and case['moduleIds']
    assert case['historicalVersionRewritten'] is False
    if case['result'] != 'PASS':
        assert case['id'] in SECOND_DEVICE_CASES
        assert case['result'] == 'BLOCKED' and case['blocker'] == 'SECOND_PHYSICAL_ANDROID'
        return
    source = at_pointer(dependencies[case['dependencyId']], case['pointer'])
    assert source['result'] == 'PASS'
    if case['boundary'] == 'B1_B2_ACTUAL_APP_DEVICE_SQL':
        assert source['exitCode'] == 0 and source['report']['caseId'] == case['id']
        assert all(source['report'][name] is True for name in ['actualApp', 'actualCV', 'nativeVault'])
        assert source['sqlAndProxyCounts']['result'] == source['deviceWitness']['result'] == 'PASS'
        assert source['capturedAtLaunch'] is True
        assert source['apkSha256'] == case['apkSha256']
        assert source['sourceFilesSha256'] and source['report']['pid'] > 0
    elif case['boundary'] == 'B3_B4_ACTUAL_APP_DEVICE_SQL':
        assert source['caseId'] == case['id'] and source['stageKeys']
        assert source['stageKeys'] == case['stageKeys']
        versions = dependencies[case['dependencyId']]['acceptedStageVersions']
        assert case['stageVersions'] == {key: versions[key] for key in source['stageKeys']}
        assert all(value['pid'] > 0 and re.fullmatch(r'[0-9a-f]{64}', value['apkSha256'])
                   for value in case['stageVersions'].values())
        stages = at_pointer(dependencies[case['stageEvidenceDependencyId']], case['stageEvidencePointer'])
        for key in source['stageKeys']:
            stage = stages[key]
            app = stage['actualApp']
            assert app['actualApp'] is True and app['nativeVault'] is True
            if case['id'] == 'NI-K01' and key in {'ni-k01-fresh', 'ni-k01-no-key'}:
                # These phases prove local guest/refusal without contacting
                # C/V. A claimed actual C/V call would contradict that scope.
                assert app['actualCV'] is False
                fact = ('freshProductGuestWithoutAutomaticAuthentication' if key == 'ni-k01-fresh'
                        else 'actualProductReadOverwriteAndAuthorityRejected')
                assert app[fact] is True
                sql = stage['independentSqlAndProxy']
                assert sql['delta'] and all(value == 0 for value in sql['delta'].values())
                assert sql['before']['sql'] == sql['after']['sql'] and sql['sqlReadOnly'] is True
            else:
                assert app['actualCV'] is True
            assert stage['actualApp']['pid'] == stage['independentDevice']['pid'] == versions[key]['pid']
            assert stage['independentDevice']['result'] == stage['independentSqlAndProxy']['result'] == 'PASS'
            assert stage['versionAtLaunch']['capturedAtLaunch'] is True
            assert stage['versionAtLaunch']['apkSha256'] == versions[key]['apkSha256']
    elif case['boundary'] == 'DIRECT_PROVIDER_AND_ACTUAL_PRODUCT_SQL':
        assert source['caseId'] == case['id'] and source['apkSha256'] == case['apkSha256']
        assert source['rawAppFixtureResult'] == 'FAIL' and source['rawAppFixtureResultRewritten'] is False
        provider = source['independentProvider']
        assert provider['result'] == 'PASS' and provider['rejectionCode'] == 50152
        assert provider['scope'] == 'DIRECT_PROVIDER_REJECTION_ONLY'
        assert provider['sdkCancellationUsedAsDiagnosis'] is False and provider['evidenceLines']
        assert source['independentSql']['result'] == 'PASS'
        assert source['facts']['actualGoogleRpValidationRejected'] is True
        assert source['facts']['samePositiveControlPassed'] is True
        if case['id'] in {'NI-D02', 'NI-D03'}:
            assert provider['networkErrors'] == []
            assert source['facts']['noCProofSubmitted'] is True and source['facts']['noPasskeyAdded'] is True
        assert dependencies[case['dependencyId']]['originalUnknownResolved'] is False
    elif case['boundary'] == 'SECOND_PHYSICAL_ANDROID':
        assert case['id'] in SECOND_DEVICE_CASES
        devices = source['physicalAndroidDevices']
        assert len(devices) >= 2 and len({item['id'] for item in devices}) == len(devices)
        assert all(item['isPhysicalAndroid'] is True and item['isEmulator'] is False for item in devices)
        assert all(source[name] is True for name in ['actualApp', 'actualCV', 'independentSqlVerified'])
        assert source['actualOemTransfer'] is True if case['id'] == 'NI-X01' else source['actualCrossDevicePasskeyRecovery'] is True
    else:
        raise AssertionError('Unrecognized actual acceptance boundary')


def validate_record(root, ledger, current):
    record = json.loads(repository_path(root, current['evidence']).read_text(encoding='utf-8'))
    assert record['scope'] == 'NON_IOS_B6_FINAL_REGRESSION_AND_HANDOFF'
    assert current['currentResult'] == record['currentResult'] == 'PASS'
    assert current['sourceFingerprint'] == record['sourceFingerprint']
    counts = validate_completion(record)
    for flag in ['b6WithoutSecondAndroidPassed', 'nonIOSDevelopmentAcceptancePassed']:
        assert current[flag] is record[flag]
    assert ledger['currentNonIOS']['closurePlan']['caseStates'] == {case['id']: case['result'] for case in record['cases']}
    assert ledger['currentNonIOS']['closurePlan']['nonIOSDevelopmentAcceptancePassed'] is record['nonIOSDevelopmentAcceptancePassed']
    dependencies = {item['id']: read_reference(root, item) for item in record['dependencies']}
    assert len(dependencies) == len(record['dependencies'])
    module_ids = {item['id'] for item in ledger['modules']}
    for case in record['cases']:
        validate_case(case, dependencies, module_ids)
    stages = record['historicalBatchStages']
    assert len(stages) == 14 and {stage['id'] for stage in stages} == STAGE_IDS
    for stage in stages:
        source = at_pointer(dependencies[stage['dependencyId']], stage['pointer'])
        assert source['id'] == stage['id'] and source['result'] == 'PASS' and source['exitCode'] == 0
        assert source['apkSha256'] == stage['apkSha256'] and stage['historicalVersionRewritten'] is False
        assert set(stage['moduleIds']) <= module_ids
    inputs = record['testedCandidateInputs']
    assert inputs and len(inputs) == len({item['path'] for item in inputs})
    changed = {item['path']: item for item in record['toolingChangesAfterProductRegression']}
    for item in inputs:
        data = repository_path(root, item['path']).read_bytes()
        if item['path'] in changed:
            change = changed[item['path']]
            assert item['path'].startswith('tools/')
            assert change['testedSha256'] == item['testedSha256']
            assert matches_text_digest(data, change['finalSha256'],
                                       change.get('finalLfSha256') if Path(item['path']).suffix == '.py' else None)
            assert change['functionalProductSourceChanged'] is False
        else:
            exact = item['path'] == 'packages/auth-protocol-vectors/v1.json' or Path(item['path']).suffix in {'.png', '.jpg', '.jpeg', '.jar', '.ico'}
            assert digest(data) == item['testedSha256'] or (
                not exact and digest(data.replace(b'\r\n', b'\n')) == item['testedSha256']), item['path']
    assert set(changed) <= {item['path'] for item in inputs}
    final_lf = record.get('finalToolingFilesLfSha256', {})
    if final_lf:
        assert set(final_lf) == set(record['finalToolingFilesSha256'])
    for relative, sha in record['finalToolingFilesSha256'].items():
        assert relative.startswith('tools/')
        data = repository_path(root, relative).read_bytes()
        assert matches_text_digest(data, sha, final_lf.get(relative) if Path(relative).suffix == '.py' else None), relative
    for artifact in record['handoffArtifacts']:
        data = repository_path(root, artifact['path']).read_bytes()
        assert digest(data) == artifact['sha256'] or digest(data.replace(b'\r\n', b'\n')) == artifact['lfSha256']
    for artifact in record['candidateApks']:
        assert re.fullmatch(r'[0-9a-f]{64}', artifact['sha256'])
        assert artifact['productionDistributionApproved'] is False
    release = next(check for check in record['checks'] if check['id'] == 'installed-release-boundary')
    assert release['details']['originalOwnedDebugApkRestored'] is True
    assert all(release['details']['checks'].values()) and len(release['details']['checks']) >= 13
    native = next(check for check in record['checks'] if check['id'] == 'android-native-vault')
    assert native['details']['atomicReplacementProcessPairs'] == 3
    assert native['details']['actualNativeKeystore'] is True
    review = next(check for check in record['checks'] if check['id'] == 'source-and-secret-review')
    assert review['details']['privateKeysOrRawProofsInCandidate'] is False
    assert review['details']['releaseDebugActivityAbsent'] is True
    assert record['publication'] == {'committed': False, 'pushed': False, 'deployed': False}
    return record, counts


def main():
    ledger = json.loads((ROOT / 'docs/design/module-acceptance-ledger.json').read_text(encoding='utf-8'))
    _, counts = validate_record(ROOT, ledger, ledger['currentB6'])
    print(f'PASS: B6 evidence/handoff; fixed matrix {counts}; missing second-device evidence does not authorize complete non-iOS acceptance.')
    print('Scope: evidence bookkeeping only, no functional/device tests executed by this checker.')


if __name__ == '__main__':
    main()
