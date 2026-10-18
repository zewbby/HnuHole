"""Check the bounded B5 handoff. This does not run device acceptance."""
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
RECORD = 'services/api/authlab/android-b5-20261016-verification.json'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    record = json.loads((ROOT / RECORD).read_text(encoding='utf-8'))
    assert record['scope'] == 'B5_TWO_PHYSICAL_ANDROID_BOUNDED_ACCEPTANCE'
    historical = record['historicalB6']
    data = (ROOT / historical['path']).read_bytes()
    assert digest(data.replace(b'\r\n', b'\n')) == historical['lfSha256']
    previous = json.loads(data)
    assert previous['fixedCaseCounts'] == dict(PASS=22, FAIL=0, BLOCKED=2, NOT_RUN=0)
    assert previous['b6Result'] == 'PASS'
    cases = record['cases']
    assert len(cases) == 24 and len({c['id'] for c in cases}) == 24
    old = {c['id']: c for c in previous['cases']}
    assert set(old) == {c['id'] for c in cases}
    for case in cases:
        if case['id'] not in {'NI-X01', 'NI-X02'}:
            assert case == old[case['id']], 'Historical device/version evidence changed'
    x01, x02 = [next(c for c in cases if c['id'] == k) for k in ['NI-X01', 'NI-X02']]
    assert x01['result'] == 'PASS' and x02['result'] == 'FAIL'
    assert all(x01[k] is True for k in [
        'actualOemTransferCompleted', 'actualOemApplicationDataTransfer',
        'productNativeCipherNotCopied', 'fixtureCredentialsNotCopied',
        'targetDidNotAutomaticallyLogin', 'sourceActualSessionRestoredAndServerVerified'])
    assert x01['selectedApplications'] == x01['selectedApplicationDataEntries'] == 1
    assert x01['selectedPersonalDataEntries'] == 0
    assert all(d['physical'] is True for d in record['devices'].values())
    assert record['devices']['source']['model'] != record['devices']['target']['model']
    assert x02['sourceNativeCreationAttempts'] == 1 and x02['sourceBindingCommitted'] is True
    assert x02['targetNativeGetAttempts'] == 4
    assert len(x02['attempts']) == 4
    assert all(a['nativeBegun'] == a['nativeTimeout'] == 1 and a['nativeSucceeded'] == 0 for a in x02['attempts'])
    assert x02['actualCrossDeviceProofReturned'] is False and x02['resetIntentCreated'] is False
    assert x02['sqlAfter'] == dict(accounts=1, passkeys=1, activeSessions=1, activeResets=0)
    counts = {state: sum(c['result'] == state for c in cases) for state in ['PASS', 'FAIL', 'BLOCKED', 'NOT_RUN']}
    assert counts == record['fixedCaseCounts'] == dict(PASS=23, FAIL=1, BLOCKED=0, NOT_RUN=0)
    assert record['remainingFixedIds'] == ['NI-X02']
    for key in ['nonIOSDevelopmentAcceptancePassed', 'productionApproved', 'iosAcceptancePassed', 'fullAnonymityClosurePassed']:
        assert record[key] is False
    for entry in record['currentSourceInputs']:
        data = (ROOT / entry['path']).read_bytes().replace(b'\r\n', b'\n')
        assert digest(data) == entry['lfSha256'], entry['path']
    fixture = (ROOT / record['fixturePath']).read_bytes().replace(b'\r\n', b'\n')
    assert digest(fixture) == record['sourceBuild']['fixtureSha256']
    assert digest(fixture.replace(b'HnuHole test 26ac0016', b'HnuHole B5 26ac0016')) == record['oemBuild']['fixtureSha256']
    # These are the actual runtime source roots. The added operator and test
    # fixture are separate; no product change was tested or claimed here.
    subprocess.run(['git', 'diff', '--exit-code', record['productBaseline'], '--', *record['unchangedProductRoots']], cwd=ROOT, check=True, capture_output=True)
    ledger = json.loads((ROOT / 'docs/design/module-acceptance-ledger.json').read_text(encoding='utf-8'))
    assert ledger['currentB5']['evidence'] == RECORD
    assert ledger['currentB5']['fixedCaseCounts'] == counts
    assert ledger['currentB5']['nonIOSDevelopmentAcceptancePassed'] is False
    for module in ledger['modules']:
        if module['id'] in {'N01', 'A12', 'A07', 'N03'}:
            assert module['currentB5Regression']['evidence'] == RECORD
    for relative in record['handoffDocuments']:
        assert 'auth-privacy-b5-validation-report.md' in (ROOT / relative).read_text(encoding='utf-8')
    assert all(record['restoration'][role]['exactOriginalProviderSettingsRestored'] for role in ['source', 'target'])
    print('PASS: B5 evidence/handoff; fixed matrix 23 PASS / 1 FAIL; NI-X02 remains open.')
    print('Scope: bookkeeping and unchanged-source check only; no new device ceremony or full non-iOS approval.')


if __name__ == '__main__':
    main()
