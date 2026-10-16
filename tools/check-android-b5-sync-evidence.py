"""Validate final B5 sync handoff without running a device ceremony."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
RECORD = 'services/api/authlab/android-b5-sync-20261016-verification.json'


def lf_sha(path):
    return hashlib.sha256(path.read_bytes().replace(b'\r\n', b'\n')).hexdigest()


def main():
    record = json.loads((ROOT/RECORD).read_text(encoding='utf-8'))
    assert record['scope'] == 'FINAL_NON_IOS_FOUNDATION_WITH_TWO_PHYSICAL_ANDROID_SYNC'
    dependencies = {}
    for entry in record['dependencies']:
        assert lf_sha(ROOT/entry['path']) == entry['lfSha256'], entry['path']
        dependencies[entry['id']] = json.loads((ROOT/entry['path']).read_text(encoding='utf-8'))
    b6, original = dependencies['b6'], dependencies['b5-original']
    assert original['fixedCaseCounts'] == dict(PASS=23, FAIL=1, BLOCKED=0, NOT_RUN=0)
    assert original['nonIOSDevelopmentAcceptancePassed'] is False
    spec = importlib.util.spec_from_file_location('b6_guard', ROOT/'tools/check-non-ios-closure.py')
    guard = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(guard)
    guard.validate_completion(b6)
    assert b6['b6Result'] == 'PASS'
    inputs = {item['path']: item for item in b6['testedCandidateInputs']}
    assert len(record['unchangedB6ProductInputs']) >= 150
    for item in record['unchangedB6ProductInputs']:
        assert item['path'] in inputs
        assert item['sha256'] in (inputs[item['path']]['sourceSha256'], inputs[item['path']]['testedSha256'])
        data = (ROOT/item['path']).read_bytes()
        assert item['normalization'] in ['RAW', 'LF']
        if item['normalization'] == 'LF':
            data = data.replace(b'\r\n', b'\n')
        assert hashlib.sha256(data).hexdigest() == item['sha256'], item['path']
    subprocess.run(['git', 'diff', '--exit-code', record['productBaseline'], '--', *record['unchangedProductRoots']], cwd=ROOT, check=True, capture_output=True)
    cases = record['cases']
    old = {case['id']:case for case in original['cases']}
    assert len(cases) == len(old) == 24 and {c['id'] for c in cases} == set(old)
    assert all(c == old[c['id']] for c in cases if c['id'] != 'NI-X02')
    case = next(c for c in cases if c['id'] == 'NI-X02')
    assert case['result'] == 'PASS'
    assert case['targetNativeGetAttemptsCumulative'] == 7
    assert case['sourceNativeCreationAttempts'] == 1
    assert case['successfulTargetPid'] > 0
    assert case['successfulNativeCounters'] == dict(nativeBegun=1, nativeSucceeded=1)
    assert all(case[k] is True for k in ['actualSyncedPasskeyOnTarget', 'actualProductCResetIntent',
        'fullNewRecoveryCodeConfirmation', 'intentDidNotAutoLogin', 'resetDidNotAutoLogin',
        'sameAccountRestored', 'explicitNewPasswordLogin', 'oldPasskeysAbsent'])
    assert case['oldSessionHttpStatus'] == case['oldPasswordHttpStatus'] == case['oldRecoveryCodeHttpStatus'] == 401
    assert case['sqlStages'] == [
        dict(accounts=1, passkeys=1, activeSessions=1, activeResets=1),
        dict(accounts=1, passkeys=0, activeSessions=0, activeResets=0),
        dict(accounts=1, passkeys=0, activeSessions=1, activeResets=0)]
    for role in ['source', 'target']:
        assert record['devices'][role]['physical'] is True
    assert record['devices']['source']['model'] != record['devices']['target']['model']
    assert record['attempts']['fifth']['nativeSucceeded'] == 1
    assert record['attempts']['fifth']['fixtureFailedBeforeResetCommit'] is True
    assert record['attempts']['sixth']['nativeGetOtherDomError'] == 1
    assert record['attempts']['sixth']['userReportedNoSelectionOrVerification'] is True
    assert record['attempts']['seventh']['result'] == 'PASS'
    fixture = (ROOT/record['fixturePath']).read_bytes().replace(b'\r\n', b'\n')
    original_fixture = (ROOT/'apps/mobile/integration_test/auth_android_b5_device_test.dart').read_bytes().replace(b'\r\n', b'\n')
    assert fixture == original_fixture.replace(b'AuthCrypto.randomEncoded(24)', b'AuthCrypto.randomEncoded(32)')
    assert record['build']['fixtureSha256'] in [
        hashlib.sha256(fixture).hexdigest(),
        hashlib.sha256((ROOT/record['fixturePath']).read_bytes()).hexdigest()]
    for item in record['currentSourceInputs']:
        assert lf_sha(ROOT/item['path']) == item['lfSha256']
    counts = {state:sum(c['result'] == state for c in cases) for state in ['PASS', 'FAIL', 'BLOCKED', 'NOT_RUN']}
    assert counts == record['fixedCaseCounts'] == dict(PASS=24, FAIL=0, BLOCKED=0, NOT_RUN=0)
    assert record['remainingFixedIds'] == [] and record['nonIOSDevelopmentAcceptancePassed'] is True
    assert record['fullAnonymityClosurePassed'] is False and record['productionApproved'] is False
    assert record['iosAcceptancePassed'] is False and record['futureBusinessAcceptancePassed'] is False
    assert record['restoration']['targetExactOriginal'] is True
    assert record['restoration']['sourceProviderWrittenByThisSyncRun'] is False
    ledger = json.loads((ROOT/'docs/design/module-acceptance-ledger.json').read_text(encoding='utf-8'))
    assert ledger['currentB5Sync']['evidence'] == RECORD
    assert ledger['currentB5Sync']['nonIOSDevelopmentAcceptancePassed'] is True
    assert ledger['currentB5Sync']['fixedCaseCounts'] == counts
    assert ledger['currentB5']['nonIOSDevelopmentAcceptancePassed'] is False
    assert ledger['currentB5Bitwarden']['result'] == 'BLOCKED'
    for module in ledger['modules']:
        if module['id'] in ['A07', 'N03', 'N01', 'A12']:
            assert module['currentB5SyncRegression']['evidence'] == RECORD
    for relative in record['handoffDocuments']:
        assert 'auth-privacy-b5-sync-validation-report.md' in (ROOT/relative).read_text(encoding='utf-8')
    print('PASS: fixed 24/24; original failed attempts preserved; B6 product inputs unchanged.')
    print('Scope: non-iOS anonymous foundation development acceptance only; no production, iOS or future business approval.')


if __name__ == '__main__':
    main()
