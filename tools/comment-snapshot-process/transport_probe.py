"""Fixed 20-request TCP_NODELAY contrast; never performance acceptance."""
import argparse
import hashlib
import json
from pathlib import Path

from growth import add_roots, seed_post
from normalized import occupancy
from performance import readers, reply_data
from request_timing import observations
from run import Lab, dump, elapsed_clock, host_clock, host_clock_summary, source_digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--redis', type=Path, required=True)
    args = parser.parse_args()
    args.shared_admission = 'official'; args.duration = 0; args.suite = 'diagnostic'
    lab = Lab(args)
    result = dict(scope='DIAGNOSTIC_ONLY_NOT_ACCEPTANCE', result='RUNNING', requests=[],
                  fixedBlocks=[False, True, True, False], maximumRequests=20,
                  decision='Each path: mean HTTP-server residual OFF>=30ms and ON<=8ms')
    try:
        lab.setup()
        negative = seed_post(lab, 2); add_roots(lab, negative, 10000)
        replies = reply_data(lab); result['occupancySeed'] = occupancy(lab)
        tokens = readers(lab, 2); lab.sql('ANALYZE;')
        assert int(lab.sql('SELECT count(*) FROM c_comments.tasks;')) == 11563
        for child in [lab.a, lab.b]: child.terminate(); child.wait(timeout=20)
        lab.cfg['comments']['observeReadTimings'] = True
        ips = dict(postgres='127.0.0.8', redis='127.0.0.9')
        children = []
        for backend in ips:
            lab.cfg['comments']['snapshots'].update(createBackend=backend, readPostgres=True, readRedis=True)
            children.append(lab.start_api('transport-'+backend, ips[backend], int(lab.cfg['internalListen'].split(':')[-1])))
        lab.request_pace_seconds = .27
        initial = host_clock(); started = elapsed_clock()
        for block, nodelay in [(-1, True)] + list(enumerate(result['fixedBlocks'])):
            for index, kind in enumerate(['replyPreview', 'replyExpanded']):
                path = replies + ('&expanded=true' if index else '')
                order = ['postgres', 'redis'] if block % 2 else ['redis', 'postgres']
                for backend in order:
                    assert elapsed_clock()-started <= 90, 'fixed diagnostic deadline'
                    body, ms, headers = lab.request(ips[backend], path, token=tokens[index], tcp_nodelay=nodelay)
                    assert len(body['comments']) == (50 if index else 5)
                    assert lab.last_request_tcp_nodelay == int(nodelay)
                    result['requests'].append(dict(block=block, warmup=block == -1, tcpNoDelay=nodelay,
                        kind=kind, backend=backend, latencyMs=ms,
                        requestId={k.lower(): v for k, v in headers.items()}['x-request-id'],
                        startRawNanoseconds=lab.last_request_start_raw_ns, clockOffsets=lab.last_request_clock_offsets))
        final = host_clock()
        for child in children: child.terminate(); child.wait(timeout=20)
        timing = observations(lab.logs.glob('api-transport-*.private.log'))
        for request in result['requests']:
            request['serverTiming'] = timing[request['requestId']]
            request['residualMilliseconds'] = request['latencyMs']-request['serverTiming']['elapsedMilliseconds']
        assert len(result['requests']) == 20
        result.update(result='PASS_DATA_COLLECTION', elapsedSeconds=elapsed_clock()-started,
                      hostClockSummary=host_clock_summary(initial, final), sourceDigest=source_digest(lab.source),
                      apiBinarySHA256=hashlib.sha256((lab.root/'bin/process-api').read_bytes()).hexdigest(),
                      workerIntervalSeconds=lab.cfg['workerIntervalSeconds'], cleanupIntervalSeconds=lab.cfg['comments']['snapshots']['cleanupIntervalSeconds'])
    except BaseException as error:
        result.update(result='FAIL_DIAGNOSTIC', error=str(error)); raise
    finally:
        result['fixture'] = str(lab.run); dump(lab.root/'transport-probe.json', result); lab.cleanup()
    print('TRANSPORT PROBE '+result['result'], flush=True)


if __name__ == '__main__':
    main()
