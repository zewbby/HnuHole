"""Join optional server phase observations by server-generated request IDs."""
import json
import shlex


def observations(logs):
    values = {}
    for path in logs:
        for line in path.read_text().splitlines():
            if ' INFO comment_snapshot_request_timing ' not in line:
                continue
            fields = dict(part.split('=', 1) for part in shlex.split(line) if '=' in part)
            ident = fields['request_id']
            assert ident and ident not in values, 'missing/duplicate server timing request ID'
            assert fields['truncated'] == 'false', 'server phase observation truncated'
            assert fields['clock'] == 'CLOCK_MONOTONIC_RAW' and fields['clock_valid'] == 'true', 'invalid server phase clock'
            stages = json.loads(fields['stages_json'])
            values[ident] = dict(elapsedMilliseconds=int(fields['elapsed_ns'])/1e6,
                                 startedUnixNanoseconds=int(fields['started_unix_ns']),
                                 clock=fields['clock'],
                                 stages=stages)
    return values


def attach(records, values):
    for paths in records.values():
        for requests in paths.values():
            for request in requests:
                ident = request['requestId']
                assert ident in values, 'measured request has no server phase observation'
                request['serverTiming'] = values[ident]
