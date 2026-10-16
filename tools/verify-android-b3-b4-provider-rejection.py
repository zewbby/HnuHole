#!/usr/bin/env python3
"""Verify direct provider evidence without treating an OEM cancellation as rejection.

This read-only verifier covers the provider boundary only. Product, version,
signature and SQL evidence must be evaluated separately for each fixed case.
"""
import hashlib
import re

RP_ERROR = 'curh: [50152] RP ID cannot be validated.'
VALIDATE = '[ValidateRpIdOperation] Operation started.'
ERROR_END = '[RegistrationChimeraActivity] Activity finished with error.'
SUCCESS_END = '[RegistrationChimeraActivity] Activity finished successfully.'
LINE = re.compile(r'^\s*(\d{10}\.\d+)\s+(\d+)\s+\d+\s+[A-Z]\s+[^:]+:\s?(.*)$')
# Obfuscated validator frames must match an explicitly observed installed build.
# Keep the original fixed-snapshot profile as the default for historic evidence.
PROVIDER_PROFILES = {'26.39.33': ('cvtf', ('cvte.a', 'cvtg.g'))}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def verify(raw, google_pid, launch_epoch, capture_epoch, native, *, server_followup=False,
           installed_provider_version=None):
    require(isinstance(raw, str) and 0 < len(raw.encode()) <= 2_000_000, 'Bounded provider log required')
    require(type(google_pid) is int and google_pid > 0, 'Actual Google UI PID required')
    require(0 < capture_epoch - launch_epoch <= 600, 'Bounded current case window required')
    require(type(native.get('pid')) is int and native['pid'] > 0, 'Actual App PID required')
    if installed_provider_version is None:
        rp_error, validator_frames = RP_ERROR, ('aolv.a', 'curi.g')
    else:
        require(installed_provider_version in PROVIDER_PROFILES, 'Unreviewed provider build')
        exception, validator_frames = PROVIDER_PROFILES[installed_provider_version]
        rp_error = exception + ': [50152] RP ID cannot be validated.'
    for key in ('nativeTimeout', 'nativeCancelled'):
        require(native.get(key, 0) == 0, 'Local UNKNOWN is never provider rejection')
    require(native.get('nativeBegun') == (2 if server_followup else 1)
            and native.get('nativeErrored') == 1
            and native.get('nativeSucceeded', 0) == (1 if server_followup else 0),
            'Exact negative request and optional successful server followup required')
    blocks = []
    for number, original in enumerate(raw.splitlines(), 1):
        match = LINE.match(original)
        if not match:
            continue
        epoch, pid, message = float(match[1]), int(match[2]), match[3]
        if not launch_epoch <= epoch <= capture_epoch:
            continue
        require(pid == google_pid, 'Mixed provider process log refused')
        item = dict(line=number, epoch=epoch, message=message,
                    sha256=hashlib.sha256(original.encode()).hexdigest())
        if VALIDATE in message:
            blocks.append([])
        if blocks:
            blocks[-1].append(item)
    require(len(blocks) == (2 if server_followup else 1), 'Missing or overlapping provider request')
    first = blocks[0]
    error = [x for x in first if ERROR_END in x['message']]
    success = [x for x in first if SUCCESS_END in x['message']]
    diagnoses = [x for x in first if rp_error in x['message']]
    require(len(error) == 1 and not success and diagnoses, 'Actual RP diagnosis and terminal error required')
    require(all(any('at ' + frame + '(' in x['message'] for x in first)
                for frame in validator_frames), 'Installed RP validator stack required')
    if installed_provider_version is not None:
        require(all(any('at ' + frame + '(' in x['message']
                        and '@' + installed_provider_version + ' ' in x['message'] for x in first)
                    for frame in validator_frames), 'Validator stack does not match installed provider build')
    require(all(abs(x['epoch'] - error[0]['epoch']) <= 2 for x in diagnoses),
            'RP diagnosis must belong to the terminal provider failure')
    network_errors = sorted(set(re.findall(r'net::(ERR_[A-Z_]+)', '\n'.join(x['message'] for x in first))))
    # A deliberately wrong RP may fail HTTPS hostname verification. A same-RP
    # signature/package comparison must not be accepted from a transport error.
    require(not network_errors or (server_followup and network_errors == ['ERR_CERT_COMMON_NAME_INVALID']),
            'Unrelated network failure cannot prove signature or package rejection')
    if server_followup:
        second = blocks[1]
        require(sum(SUCCESS_END in x['message'] for x in second) == 1
                and not any(ERROR_END in x['message'] or rp_error in x['message'] for x in second),
                'The separate correct-RP native creation must succeed')
    references = [dict(line=x['line'], epoch=x['epoch'], sha256=x['sha256'])
                  for x in first if rp_error in x['message'] or ERROR_END in x['message']
                  or VALIDATE in x['message'] or any('at ' + frame + '(' in x['message'] for frame in validator_frames)]
    return dict(result='PASS', scope='DIRECT_PROVIDER_REJECTION_ONLY', googleUiPid=google_pid,
                appPid=native['pid'], rejectionCode=50152, rejectionMessage='RP ID cannot be validated.',
                actualProviderRequestCount=len(blocks), networkErrors=network_errors,
                correctRpFollowupSucceeded=server_followup, evidenceLines=references,
                installedProviderVersion=installed_provider_version,
                sdkCancellationUsedAsDiagnosis=False, rawProofStored=False)
