#!/usr/bin/env python3
"""Read-only HTTPS DAL verification after explicit domain-control confirmation."""
import argparse
import hashlib
import json
import ssl
import urllib.request
from pathlib import Path


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        raise ValueError('DAL must return HTTP 200 directly; redirects rejected')


def validate_response(status, content_type, body, expected):
    if status != 200 or content_type.split(';', 1)[0].strip().lower() != 'application/json':
        raise ValueError('direct 200/application-json required')
    if len(body) > 65536:
        raise ValueError('DAL response too large')
    if json.loads(body) != expected:
        raise ValueError('public association differs from the one reviewed package/certificate; do not overwrite it')


def check(bundle, confirmed):
    if not confirmed:
        raise ValueError('domain control and approved deployment must be confirmed before remote checks')
    proposal = json.loads((bundle / 'proposal.json').read_text())
    artifact = bundle / 'site/.well-known/assetlinks.json'
    if hashlib.sha256(artifact.read_bytes()).hexdigest() != proposal['files']['site/.well-known/assetlinks.json']:
        raise ValueError('reviewed DAL changed')
    rp = proposal['rpId']
    # Use the generator's canonical validation; no arbitrary URL/port/path.
    import importlib.util
    spec = importlib.util.spec_from_file_location('stage3_proposal', Path(__file__).with_name('proposal.py'))
    source = importlib.util.module_from_spec(spec); spec.loader.exec_module(source)
    source.associations.validated_rp(rp)
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect(),
                                        urllib.request.HTTPSHandler(context=ssl.create_default_context()))
    request = urllib.request.Request('https://' + rp + '/.well-known/assetlinks.json', headers={'Accept': 'application/json'})
    with opener.open(request, timeout=25) as response:
        body = response.read(65537)
        validate_response(response.status, response.headers.get('Content-Type', ''), body, json.loads(artifact.read_text()))
    return {'result': 'PASS_HTTPS_DAL_DOCUMENT_ONLY', 'rpId': rp, 'certificateAndHostnameVerified': True,
            'redirectFollowed': False, 'providerAcceptanceProved': False, 'deviceUsed': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, required=True)
    parser.add_argument('--confirmed-approved-domain-control-and-deployment', action='store_true')
    args = parser.parse_args()
    print(json.dumps(check(args.bundle, args.confirmed_approved_domain_control_and_deployment)))
