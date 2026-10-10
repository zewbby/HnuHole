#!/usr/bin/env python3
"""Create build-only Go overlays for an isolated seven-day closure test.

The production sources and immutable SQL deadlines are unchanged. Only the
owned test binaries' Gate clock and signed development evidence clock advance.
TLS, host/phone clocks, SQL constraints, and business code keep normal behavior.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path('/var/tmp/hnuhole-android-live-closure-20261007')
REPO = Path('/var/tmp/hnuhole-android-live-faults-20261005/repo')


def main():
    global ROOT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', choices=[str(ROOT), '/var/tmp/hnuhole-android-live-batch-20261007',
        '/var/tmp/hnuhole-android-live-b3-b4-20261009'], default=str(ROOT))
    parser.add_argument('--extend-b3b4-cycles', action='store_true')
    parser.add_argument('--extend-b3b4-retry-cycles', action='store_true')
    parser.add_argument('--extend-b3b4-targeted-assertion-cycles', action='store_true')
    parser.add_argument('--final-b3b4-uninstalled-batch', action='store_true')
    parser.add_argument('--discoverable-b3b4-preflight-batch', action='store_true')
    args = parser.parse_args()
    ROOT = Path(args.work)
    flags=(args.extend_b3b4_cycles,args.extend_b3b4_retry_cycles,args.extend_b3b4_targeted_assertion_cycles,args.final_b3b4_uninstalled_batch,args.discoverable_b3b4_preflight_batch)
    assert sum(flags)<=1,'Choose exactly one bounded extension scope'
    extending=any(flags)
    if extending:
        assert ROOT == Path('/var/tmp/hnuhole-android-live-b3-b4-20261009')
    assert ROOT.resolve() == ROOT and not ROOT.is_symlink()
    assert (ROOT / 'OWNER').read_text().strip() == 'HNUHOLE_ANDROID_LIVE_DEV_V1'
    assert (REPO.parent / 'OWNER').read_text().strip() == 'HNUHOLE_ANDROID_LIVE_DEV_V1'
    target = ROOT / 'clock-overlay'
    target.mkdir(mode=0o700, exist_ok=True)
    clock = ROOT / 'clock-offset-ns'
    if clock.exists():
        if extending:
            previous=json.loads((target/'scope.json').read_text())
            assert 0 <= int(clock.read_text()) <= previous['maximumOffsetDays']*24*3600*10**9
            assert (target/'scope.json').is_file()
        else:
            assert clock.read_text().strip() == '0', 'Never replace an advanced clock'
    else:
        clock.write_text('0\n')
    helper = '''
// TEST BUILD ONLY: fixed owned development clock; no production flag or route.
func closureDeviceClock() time.Time {
 marker, err := os.ReadFile("/var/tmp/hnuhole-android-live-closure-20261007/OWNER")
 if err != nil || strings.TrimSpace(string(marker)) != "HNUHOLE_ANDROID_LIVE_DEV_V1" { panic("invalid isolated closure clock owner") }
 raw, err := os.ReadFile("/var/tmp/hnuhole-android-live-closure-20261007/clock-offset-ns")
 if err != nil { panic("isolated closure clock unavailable") }
 offset, err := strconv.ParseInt(strings.TrimSpace(string(raw)), 10, 64)
 if err != nil || offset < 0 || offset > int64(16*24*time.Hour) { panic("invalid isolated closure clock") }
 return time.Now().Add(time.Duration(offset))
}
'''
    helper = helper.replace('/var/tmp/hnuhole-android-live-closure-20261007', str(ROOT))
    if args.extend_b3b4_targeted_assertion_cycles:
        assert ROOT == Path('/var/tmp/hnuhole-android-live-b3-b4-20261009')
    if args.final_b3b4_uninstalled_batch:
        plan=json.loads((ROOT/'b3b4-evidence/final-batch-20261010.json').read_text())
        assert plan['userConfirmedUninstall'] and plan['baseClosedAccounts']==8 and plan['allowedClosureCycles']==[8,9]
    if args.discoverable_b3b4_preflight_batch:
        plan=json.loads((ROOT/'b3b4-evidence/discoverable-batch-20261010.json').read_text())
        assert plan['baseClosedAccounts']==10 and plan['allowedClosureCycles']==[10,11] and plan['requireActualAssertionPreflight']
    maximum=96 if args.discoverable_b3b4_preflight_batch else (80 if args.final_b3b4_uninstalled_batch else (64 if args.extend_b3b4_targeted_assertion_cycles else (48 if args.extend_b3b4_retry_cycles else (24 if args.extend_b3b4_cycles else 16))))
    if maximum!=16:
        helper = helper.replace('16*24*time.Hour', str(maximum)+'*24*time.Hour')
    files = ['internal/authprivacyruntime/server.go', 'cmd/authdev/main.go']
    replacements, hashes = {}, {}
    for name in files:
        original = REPO / 'services/api' / name
        source = original.read_text()
        hashes[name] = hashlib.sha256(source.encode()).hexdigest()
        if name.endswith('server.go'):
            assert source.count('Clock: time.Now') == 1
            source = source.replace('Clock: time.Now', 'Clock: closureDeviceClock')
            source = source.replace('"net/http"', '"net/http"\n "os"\n "strconv"')
        else:
            old = 'at := time.Now().UTC().Truncate(time.Microsecond)'
            assert source.count(old) == 1
            source = source.replace(old, 'at := closureDeviceClock().UTC().Truncate(time.Microsecond)')
            if '"strconv"' not in source:
                source = source.replace('"strings"', '"strings"\n "strconv"')
        rewritten = target / (name.replace('/', '-') + '.go')
        rewritten.write_text(source + helper)
        replacements[str(original)] = str(rewritten)
    (target / 'overlay.json').write_text(json.dumps({'Replace': replacements}, indent=2) + '\n')
    (target / 'scope.json').write_text(json.dumps({
        'testBuildOnly': True, 'productionSourcesChanged': False,
        'sqlDeadlineEdited': False, 'hostOrPhoneClockChanged': False,
        'originalSourcesSha256': hashes,
        'replacements': ['Gate.Clock', 'development evidence TrustedAt/IssuedAt'],
        'maximumOffsetDays': maximum,
        'existingClockOffsetPreserved': True,
    }, indent=2) + '\n')
    print('PASS: isolated build-only closure clock overlay prepared')


if __name__ == '__main__':
    main()
