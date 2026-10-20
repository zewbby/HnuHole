#!/usr/bin/env python3
"""Private-file operator for fault_proxy; never an HTTP control API."""
import argparse
import json
import os
from pathlib import Path
import uuid
from fault_proxy import Journal,configuration,require,valid_rule

def control(config,command,rule_file=None,rule_id=None):
    c=configuration(config);j=Journal(c['controlRoot'])
    with j.locked():
        old=j.read()
        if command=='status':return {k:v for k,v in old.items() if k not in ('sessionDigest','bodyMarker')}
        if command=='arm':
            require(old.get('state') not in ('armed','hit','held_before_upstream','held_response_after_upstream'),'finish or abort previous rule first')
            p=Path(rule_file);require(p.is_file() and not p.is_symlink() and p.stat().st_uid==os.getuid() and not p.stat().st_mode&0o077,'private owned rule file required')
            r=json.loads(p.read_text());valid_rule(r,c['allowedAccounts'])
            r.update(id=uuid.uuid4().hex,state='armed',release=False,cancel=False);j.write(r);j.event('armed',r,mode=r['mode'],account=r['account'],method=r['method'],pathTemplate=r['path']);return {'id':r['id'],'state':'armed'}
        require(old.get('id')==rule_id,'exact rule id required')
        require(old.get('state') in ('armed','hit','held_before_upstream','held_response_after_upstream'),'rule is already terminal')
        if command=='release':old['release']=True
        elif command=='abort':
            old['cancel']=True
            if old['state']=='armed':old['state']='cancelled_before_hit'
        else:raise RuntimeError('unknown command')
        j.write(old);j.event('operator_'+command,old);return {'id':old['id'],'state':old['state'],'action':command}

def main():
    os.umask(0o077)
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--config',required=True);p.add_argument('command',choices=('status','arm','release','abort'));p.add_argument('--rule-file');p.add_argument('--id');a=p.parse_args()
    print(json.dumps(control(a.config,a.command,a.rule_file,a.id)))

if __name__=='__main__':main()
