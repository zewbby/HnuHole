#!/usr/bin/env python3
"""Generate a review-only RP/package/signature bundle. No apply/deploy/device API."""
import argparse
import difflib
import hashlib
import importlib.util
import json
import re
from pathlib import Path

OWNER = 'HNUHOLE_COMMUNITY_ANDROID_STAGE3_V1'
PACKAGE = 'org.hnuhole.hnuhole_mobile.communityf5.passkey'
MISSING_PACKAGE = PACKAGE + '.unassociated'
PROPOSED_RP = 'hnuhole-community-passkey.pages.dev'
SPEC = importlib.util.spec_from_file_location('association_generator', Path(__file__).parents[1] / 'configure-passkey-associations.py')
associations = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(associations)


def values(repo, proof, rp):
    rp = associations.validated_rp(rp)
    if rp == 'zewbby.github.io' or rp.endswith('.zewbby.github.io'):
        raise ValueError('do not reuse or modify the authentication-session RP')
    if proof.get('owner') != OWNER or proof.get('deviceUsed') is not False or proof.get('associationApplied') is not False:
        raise ValueError('owned unconfigured baseline proof required')
    apks = proof['apks']
    if apks['control']['applicationId'] != PACKAGE or apks['unassociated']['applicationId'] != MISSING_PACKAGE or apks['badSignature']['applicationId'] != PACKAGE:
        raise ValueError('exact independent packages required')
    cert = apks['control']['certificateSha256']
    if cert != apks['unassociated']['certificateSha256'] or cert == apks['badSignature']['certificateSha256']:
        raise ValueError('same-cert package contrast and different-cert signature contrast required')
    if proof.get('badSignaturePayloadEqualsControl') is not True:
        raise ValueError('signature-only contrast must preserve every non-signature payload')
    generated = associations.artifacts(rp, PACKAGE, cert)
    policy = generated['web-authn.config.fragment.json']['webAuthn']
    files = {
        'site/.well-known/assetlinks.json': json.dumps(generated['assetlinks.json'], indent=2) + '\n',
        'candidate-debug/passkey_associations.xml': generated['android-passkey-associations.xml'],
        'candidate-debug/manifest-snippet.xml': generated['android-passkey-manifest-snippet.xml'],
        'runtime/web-authn.config.fragment.json': json.dumps(generated['web-authn.config.fragment.json'], indent=2) + '\n',
        'runtime/authdev-init-extra-argv.json': json.dumps([
            '-webauthn-rp-id', rp, '-webauthn-https-origins', 'https://' + rp,
            '-webauthn-android-origins', policy['androidOrigins'][0],
        ], indent=2) + '\n',
        'candidate-debug/dart-defines.fragment.json': json.dumps({'AUTH_DEV_PASSKEY_RP_ID': rp}, indent=2) + '\n',
    }
    # These are text proposals only; existing files/runtime are never edited.
    resource = 'apps/mobile/android/app/src/debug/res/values/passkey_associations.xml'
    old = (repo / resource).read_text(encoding='utf-8').splitlines(keepends=True)
    files['review-only.patch'] = ''.join(difflib.unified_diff(old, files['candidate-debug/passkey_associations.xml'].splitlines(keepends=True), fromfile='a/' + resource, tofile='b/' + resource))
    exclusions = [{'package': PACKAGE, 'certificateSha256': apks['badSignature']['certificateSha256'], 'expectedAssociation': False},
                  {'package': MISSING_PACKAGE, 'certificateSha256': cert, 'expectedAssociation': False}]
    manifest = {
        'owner': OWNER, 'status': 'DRAFT_REQUIRES_DOMAIN_AND_SECURITY_CONFIGURATION_APPROVAL',
        'rpId': rp, 'domainCandidateOnly': True, 'domainAvailabilityChecked': False,
        'domainControlVerified': False, 'publicAssociationPublished': False,
        'securityConfigurationApplied': False, 'deviceWindowGranted': False,
        'androidPackage': PACKAGE, 'certificateSha256': cert,
        'httpsOrigin': policy['origins'][0], 'androidOrigin': policy['androidOrigins'][0],
        'exactApprovedAssociationEntries': 1, 'excludedNegativeControls': exclusions,
        'sourceCommit': proof['sourceCommit'], 'fixedAuthenticationCommit': 'd859cb05c772cdf8d8b75e439a2bfedf0414dd46',
        'deviceReadyApks': False, 'baselineApksNeedRebuildWithApprovedRPAndOwnTLSLab': True,
        'files': {name: hashlib.sha256(data.encode()).hexdigest() for name, data in sorted(files.items())},
        'confirmationNeeded': ['independent domain availability and ownership/hosting account',
                               'one exact package/signing digest association and both DAL relations',
                               'new disposable task3 C policy and candidate debug XML/Dart RP setting',
                               'separate public deployment approval, device window and creation of synthetic system Passkeys'],
        'unchanged': ['task1/task2 packages, materials and databases', 'authentication-session domain and associations',
                      'production configuration/signing/deployment', 'C/V protocol, UV/resident/ES256 policy, final Gate', 'dependency locks'],
    }
    files['proposal.json'] = json.dumps(manifest, indent=2) + '\n'
    return files


def write_new(output, files):
    output = Path(output)
    output.mkdir(mode=0o700)  # No overwrite, linked destination or resume.
    for name, content in files.items():
        path = output / name
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open('x', encoding='utf-8', newline='\n') as stream:
            stream.write(content)
        # All bundle contents are public configuration/fingerprints. Do not
        # claim POSIX mode bits establish an ACL on a Windows/drvfs output.


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', required=True, type=Path)
    parser.add_argument('--repo', required=True, type=Path)
    parser.add_argument('--proof', required=True, type=Path)
    parser.add_argument('--rp-id', default=PROPOSED_RP)
    parser.add_argument('--output-name', default='review-bundle')
    args = parser.parse_args()
    work = args.work.resolve(strict=True)
    if work.is_symlink() or (work / '.owner').read_text().strip() != OWNER:
        raise ValueError('owned task3 review directory required')
    proof_path = args.proof.resolve(strict=True)
    if not proof_path.is_relative_to(work):
        raise ValueError('proof must belong to this task3 directory')
    proof = json.loads(proof_path.read_text())
    if not re.fullmatch(r'review-bundle(?:-[a-z0-9]+)?', args.output_name):
        raise ValueError('one bounded review-bundle directory name required')
    write_new(work / args.output_name, values(args.repo.resolve(strict=True), proof, args.rp_id))
    print('Prepared ' + args.output_name + ' only. Domain/RP/security configuration NOT_APPROVED; not deployed or applied; phone NOT_RUN.')


if __name__ == '__main__':
    main()
