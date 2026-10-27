#!/usr/bin/env python3
"""Frozen binaries, sequential performance cohorts, then faults and real TTL.

The only concurrent fixtures are the sparse, real-time compatibility/read tests
after all foreground performance and capacity traffic has finished.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import subprocess

from run import Lab, dump, source_digest
from resource_watch import wait_quiet


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,required=True)
    parser.add_argument('--source',type=Path,required=True)
    parser.add_argument('--redis',type=Path,required=True)
    args=parser.parse_args();parent=args.root.resolve()
    args.shared_admission='official';args.duration=1805;args.suite='reading'
    bootstrap=Lab(args)
    result={'result':'RUNNING','checks':{},'noForegroundPressureOverlap':True,'fixedTTLSeconds':1800}
    directory=args.source/'tools/comment-snapshot-process'
    original=source_digest(args.source)
    def verify_source():
        if source_digest(args.source)!=original:raise RuntimeError('candidate source changed during campaign')
    def child_root(name):
        path=parent/name;path.mkdir(mode=0o700)
        for cache in ['go','go-build']:(path/cache).symlink_to(parent/cache,target_is_directory=True)
        return path
    def command(name,script,root,extra=(),timeout=4500):
        verify_source()
        with (parent/(name+'.private.log')).open('wb') as stream:
            completed=subprocess.run(['python3',str(directory/script),'--root',str(root),'--source',str(args.source),*map(str,extra)],
                                     env=bootstrap.env,stdout=stream,stderr=subprocess.STDOUT,timeout=timeout)
        result['checks'][name]={'result':'PASS' if completed.returncode==0 else 'FAIL','returncode':completed.returncode}
        dump(parent/'campaign-summary.json',result)
        print(name+' '+result['checks'][name]['result'],flush=True)
        return completed.returncode
    try:
        # Compile once before measuring. All subsequent fixtures verify both
        # source digest and the exact bytes they copy from this manifest.
        if os.environ.get('COMMENT_SNAPSHOT_BINARY_DIR'):
            raise RuntimeError('campaign creates its own frozen binary manifest')
        manifest={'sourceDigest':original,'binaries':{}}
        for name,target in [('api','./cmd/api'),('authdev','./cmd/authdev'),('commentsnapshotctl','./cmd/commentsnapshotctl'),
                            ('ratelimitctl','./cmd/ratelimitctl'),('snapshot-seed','./authlab/comment-snapshot-seed')]:
            bootstrap.install_binary(name,target)
            manifest['binaries'][name]=hashlib.sha256((parent/'bin'/('process-'+name)).read_bytes()).hexdigest()
        verify_source();dump(parent/'bin/binary-manifest.json',manifest)
        os.environ['COMMENT_SNAPSHOT_BINARY_DIR']=str(parent/'bin')
        bootstrap.env['COMMENT_SNAPSHOT_BINARY_DIR']=str(parent/'bin')
        result.update(sourceDigest=original,apiBinarySHA256=manifest['binaries']['api'])
        for mode in ['compatibility','steady']:
            wait_quiet()
            root=child_root('performance-'+mode)
            command('performance-'+mode,'normalized.py',root,['--redis',args.redis,'--mode',mode])
            run=Path(json.loads((root/'process-latest.json').read_text())['run'])
            measured=json.loads((run/'normalized-performance.json').read_text())
            assert measured['metadata']['apiBinarySHA256']==manifest['binaries']['api']
            assert measured['metadata']['sourceDigest']==original
            result['checks']['performance-'+mode]['stats']=measured['stats']
        # Performance is complete before this fixture starts any API worker.
        args.root=child_root('functional');lab=Lab(args)
        try:
            lab.setup();lab.scoped_tests()
            result['checks']['cross-process-and-restart']={'result':'PASS'}
            for name,extra in [('exercise',['--capacity-only']),('faults',['--redis',args.redis]),
                               ('admission',['--redis',args.redis]),('growth',[]),('rollback',[])]:
                command(name,name+'.py',args.root,extra,timeout=1800)
            # Sparse reads only, no foreground performance/capacity traffic.
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
                interval=executor.submit(command,'compatibility-real-time','compatibility.py',args.root,['--redis',args.redis],2200)
                long=executor.submit(lab.long_read)
                long_result=long.result()
                interval.result()
                result['checks']['redis-real-time']=long_result
            compatibility=json.loads((args.root/'compatibility-summary.json').read_text())
            assert compatibility['apiBinarySHA256']==manifest['binaries']['api']
            assert compatibility['sourceDigest']==original
            assert hashlib.sha256((args.root/'bin/process-api').read_bytes()).hexdigest()==manifest['binaries']['api']
            command('drain','drain.py',args.root)
            result['functionalFixture']=str(lab.run)
            lab.results['result']='PASS' if all(v['result']=='PASS' for k,v in result['checks'].items() if not k.startswith('performance-')) else 'FAIL'
        finally:
            dump(lab.run/'summary.json',lab.results);lab.cleanup()
        verify_source()
        result['result']='PASS' if all(v['result']=='PASS' for v in result['checks'].values()) else 'FAIL'
    except BaseException as error:
        result.update(result='FAIL',error=str(error));raise
    finally:
        dump(parent/'campaign-summary.json',result)
    if result['result']!='PASS':raise SystemExit(1)


if __name__=='__main__':main()
