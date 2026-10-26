#!/usr/bin/env python3
"""Independently reverse observation wrappers and compare normalized Go source."""
import hashlib
import json
from pathlib import Path
import re
import subprocess

base=Path('/home/hnuhole/comment-snapshot-redis-20261024-8ed8f28')
original=base/'stage5-replies-only-r1/source';root=base/'d-output-native/p5d1-r1';source=root/'source'
def fmt(s):return subprocess.run(['/usr/lib/go-1.22/bin/gofmt'],input=s,text=True,capture_output=True,check=True).stdout
def load(name):return (source/name).read_text(),(original/name).read_text()
checks={}
name='services/api/internal/commentsnapshot/redis.go';current,old=load(name)
current=current.replace('diagnosticWriteSource(commonSource, writeSource)','commonSource + writeSource')
current,n=re.subn(r'\tfinishDiagnosticCall := [^\n]+\n','',current);assert n==1
current,n=re.subn(r'\tfinishDiagnosticCall\(\)\n','',current);assert n==1
current,n=re.subn(r'\tif write && \(req\["op"\] == "prepare" \|\| req\["op"\] == "publish"\) \{\n\t\treturn unwrapDiagnostic\(ctx, str\(req\["op"\]\), values\)\n\t\}\n','',current);assert n==1
assert fmt(current)==fmt(old);checks[name]='PASS_REVERSED_OBSERVATIONS_NORMALIZED_EXACT'
name='services/api/internal/readtiming/readtiming.go';current,old=load(name)
current=current[:current.index('// DiagnosticRecord is private')]
assert fmt(current)==fmt(old);checks[name]='PASS_REVERSED_OBSERVATIONS_NORMALIZED_EXACT'
name='services/api/internal/authprivacy/community_comment_snapshots.go';current,old=load(name)
a=old.index('\t\t\t\tif _, e = tx.Exec(ctx, `DELETE FROM c_comments.snapshots');b=old.index('\n\t\t\t}',a)
x=current.index('\t\t\t\te = func() error {');y=current.index('\n\t\t\t}',x)
current=current[:x]+old[a:b]+current[y:]
assert fmt(current)==fmt(old);checks[name]='PASS_REVERSED_OBSERVATIONS_NORMALIZED_EXACT'
api=original/'services/api';unchanged=0
for f in api.rglob('*'):
    if not f.is_file() or '__pycache__' in f.parts:continue
    name=str(f.relative_to(original))
    if name in checks:continue
    assert f.read_bytes()==(source/name).read_bytes(),name
    unchanged+=1
r={'result':'PASS','changedGoSemanticRestoration':checks,'otherAPIFilesByteEqual':unchanged,'authoritativeLua':'BYTE_EQUAL','publicAuthorization':'BYTE_EQUAL','observationOnly':True}
for name in ['focused-real-redis-tests','focused-timing-tests','build-vet']:
    f=root/(name+'.private.log');data=f.read_text()
    assert 'FAIL' not in data and 'SKIP' not in data
    r[name]={'sha256':hashlib.sha256(f.read_bytes()).hexdigest(),'topLevelPassCount':len(re.findall(r'^--- PASS:',data,re.M))}
(root/'static-verification.json').write_text(json.dumps(r,indent=2)+'\n')
Path('/mnt/d/HnuHole-task-storage/comment-snapshot-redis-20261024/p5d1-r1-static-verification.json').write_text(json.dumps(r,indent=2)+'\n')
print(json.dumps(r))
