#!/usr/bin/env python3
"""Generate reviewable native Passkey associations from explicit deployment IDs.

No network, host project edits or deployment. Only creates a new chosen directory.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import plistlib
import re


def validated_rp(value):
    if (not isinstance(value, str) or len(value) > 253
            or not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+", value)
            or any(len(part) > 63 for part in value.split('.'))
            or re.fullmatch(r"[0-9.]+", value)):
        raise ValueError('RP ID must be a canonical lowercase DNS domain')
    return value


def artifacts(rp_id, android_package=None, android_cert_sha256=None,
              ios_team_id=None, ios_bundle_id=None):
    rp_id = validated_rp(rp_id)
    if bool(android_package) != bool(android_cert_sha256):
        raise ValueError('Android package and signing SHA256 must be provided together')
    if bool(ios_team_id) != bool(ios_bundle_id):
        raise ValueError('iOS Team ID and bundle ID must be provided together')
    if not android_package and not ios_team_id:
        raise ValueError('At least one platform must be explicitly configured')
    result = {}
    android_origins = []
    if android_package:
        if (len(android_package) > 255 or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+", android_package)):
            raise ValueError('Invalid Android application ID')
        if re.fullmatch(r"(?:[0-9A-Fa-f]{2}:){31}[0-9A-Fa-f]{2}", android_cert_sha256):
            compact = android_cert_sha256.replace(':', '')
        elif re.fullmatch(r"[0-9A-Fa-f]{64}", android_cert_sha256):
            compact = android_cert_sha256
        else:
            raise ValueError('Signing SHA256 must contain exactly 32 fingerprint bytes')
        fingerprint = bytes.fromhex(compact)
        if not any(fingerprint):
            raise ValueError('Signing SHA256 cannot be the zero placeholder')
        origin_hash = base64.urlsafe_b64encode(fingerprint).decode('ascii').rstrip('=')
        android_origins.append('android:apk-key-hash:' + origin_hash)
        canonical = ':'.join(f'{part:02X}' for part in fingerprint)
        result['assetlinks.json'] = [{
            'relation': ['delegate_permission/common.get_login_creds'],
            'target': {'namespace': 'android_app', 'package_name': android_package,
                       'sha256_cert_fingerprints': [canonical]},
        }]
        include = json.dumps([{'include': 'https://' + rp_id + '/.well-known/assetlinks.json'}], separators=(',', ':')).replace('"', '\\"')
        result['android-passkey-associations.xml'] = (
            '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
            '  <string name="asset_statements" translatable="false">' + include + '</string>\n</resources>\n')
        result['android-passkey-manifest-snippet.xml'] = (
            '<meta-data xmlns:android="http://schemas.android.com/apk/res/android" '
            'android:name="asset_statements" android:resource="@string/asset_statements" />\n')
    if ios_team_id:
        if not re.fullmatch(r"[A-Z0-9]{10}", ios_team_id):
            raise ValueError('Invalid iOS Team ID')
        if (len(ios_bundle_id) > 255 or not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", ios_bundle_id)):
            raise ValueError('Invalid iOS bundle ID')
        result['apple-app-site-association'] = {'webcredentials': {'apps': [ios_team_id + '.' + ios_bundle_id]}}
        result['Runner.Passkey.entitlements'] = {'com.apple.developer.associated-domains': ['webcredentials:' + rp_id]}
    result['web-authn.config.fragment.json'] = {
        'webAuthn': {'rpId': rp_id, 'origins': ['https://' + rp_id], 'androidOrigins': android_origins},
    }
    return result


def write_new_directory(output, values):
    output = Path(output)
    # mkdir is atomic and refuses existing files, directories and symlinks.
    output.mkdir(mode=0o700)
    created = []
    try:
        for name, value in values.items():
            data = (plistlib.dumps(value, fmt=plistlib.FMT_XML) if name.endswith('.entitlements')
                    else value.encode('utf8') if name.endswith('.xml')
                    else (json.dumps(value, ensure_ascii=True, indent=2) + '\n').encode('utf8'))
            fd = os.open(output / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            created.append(output / name)
            with os.fdopen(fd, 'wb') as handle:
                handle.write(data)
    except BaseException:
        for path in created:
            path.unlink()
        output.rmdir()
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rp-id', required=True)
    parser.add_argument('--android-package')
    parser.add_argument('--android-cert-sha256')
    parser.add_argument('--ios-team-id')
    parser.add_argument('--ios-bundle-id')
    parser.add_argument('--out', type=Path, required=True, help='New output directory, must not exist')
    args = parser.parse_args()
    try:
        values = artifacts(args.rp_id, args.android_package, args.android_cert_sha256,
                           args.ios_team_id, args.ios_bundle_id)
        write_new_directory(args.out, values)
    except (ValueError, OSError) as error:
        parser.error(str(error))
    print('Association artifacts generated; review, sign and deploy explicitly before device acceptance.')


if __name__ == '__main__':
    main()
