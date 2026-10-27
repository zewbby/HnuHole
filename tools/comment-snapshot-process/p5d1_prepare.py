#!/usr/bin/env python3
"""Create the bounded P5-D1 observation-only source overlay in an owned D mount."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path


def replace_once(value, old, new):
    assert value.count(old) == 1, old[:80]
    return value.replace(old, new, 1)


GO_HELPER = r'''package commentsnapshot

import (
 "context"
 "fmt"
 "strings"
 "github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/readtiming"
)

// Only the disposable diagnostic binary calls this function. Embedded originals
// are unchanged; markers in the generated Lua contain no business decisions.
func diagnosticWriteSource(common, write string) string {
 once := func(old, replacement string) {
  if strings.Count(common,old)!=1 { panic("P5D1 source marker mismatch") }
  common=strings.Replace(common,old,replacement,1)
 }
 once("local r=cjson.decode(ARGV[1])", "local r=cjson.decode(ARGV[1])\ndiagEnabled=r.op=='prepare' or r.op=='publish';if diagEnabled then diagStart=diagTick() end")
 once("  local raw=redis.call('GET',KEYS[2])", "  local diagGetStart=diagTick()\n  local raw=redis.call('GET',KEYS[2])\n  diag.get_us=diagTick()-diagGetStart\n  local diagValidateStart=diagTick()")
 once("  local l={raw=raw,entries={},until_ms=until_ms,count=count}", "  diag.entries=count\n  local l={raw=raw,entries={},until_ms=until_ms,count=count}")
 once("  return l,stats", "  diag.validate_us=diagTick()-diagValidateStart\n  return l,stats")
 once("  local header=prefix..pack", "  local diagConstructStart=diagTick()\n  local header=prefix..pack")
 once("  redis.call('SET',KEYS[2],raw,'PXAT',tostring(until_ms))", "  diag.construct_us=diagTick()-diagConstructStart\n  local diagSetStart=diagTick()\n  redis.call('SET',KEYS[2],raw,'PXAT',tostring(until_ms))\n  diag.set_us=diagTick()-diagSetStart")
 return `local diag,diagEnabled,diagStart={},false,0
local function diagTick()
 if not diagEnabled then return 0 end
 local t=redis.call('TIME');return tonumber(t[1])*1000000+tonumber(t[2])
end
local function diagOperation()
`+common+write+`
end
local response=diagOperation()
if not diagEnabled then return response end
local total=diagTick()-diagStart
return {'P5D1',response,{diag.get_us or 0,diag.validate_us or 0,diag.construct_us or 0,diag.set_us or 0,total,diag.entries or 0}}
`
}

func unwrapDiagnostic(ctx context.Context, op string, values []any) ([]any,error) {
 if len(values)!=3 || str(values[0])!="P5D1" { return nil,fmt.Errorf("P5D1 missing envelope") }
 original,ok:=values[1].([]any);if !ok {return nil,fmt.Errorf("P5D1 original result")}
 metrics,ok:=values[2].([]any);if !ok || len(metrics)!=6 {return nil,fmt.Errorf("P5D1 metrics")}
 numbers:=make([]int64,6)
 for i,v:=range metrics { n,ok:=v.(int64);if !ok || n<0 || n>10000000 {return nil,fmt.Errorf("P5D1 invalid metric")};numbers[i]=n }
 if numbers[0]+numbers[1]+numbers[2]+numbers[3]>numbers[4] {return nil,fmt.Errorf("P5D1 nested metrics exceed script")}
 for i,name:=range []string{"get","validate","construct","set","script"} {
  readtiming.DiagnosticRecord(ctx,"lua_"+op+"_"+name,numbers[i]*1000,1)
 }
 readtiming.DiagnosticRecord(ctx,"lua_"+op+"_entries",0,numbers[5])
 return original,nil
}
'''

GO_TEST = r'''package commentsnapshot
import (
 "context"
 "reflect"
 "testing"
 "github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/readtiming"
)
func TestP5D1EnvelopePreservesOriginalAndRejectsInvalid(t *testing.T) {
 ctx,trace:=readtiming.Start(context.Background())
 original:=[]any{"PREPARED","id","expiry","flags"}
 envelope:=[]any{"P5D1",original,[]any{int64(1),int64(7),int64(1),int64(1),int64(12),int64(1024)}}
 got,e:=unwrapDiagnostic(ctx,"prepare",envelope)
 if e!=nil || !reflect.DeepEqual(got,original) {t.Fatalf("result %v %v",got,e)}
 stages:=trace.Snapshot().Stages
 if len(stages)!=6 || stages["lua_prepare_validate"].Nanoseconds!=7000 || stages["lua_prepare_entries"].Calls!=1024 {t.Fatal(stages)}
 for _,bad:=range [][]any{original,{"P5D1",original,[]any{int64(-1),int64(7),int64(1),int64(1),int64(12),int64(1)}},{"P5D1",original,[]any{int64(4),int64(7),int64(1),int64(1),int64(12),int64(1)}}} {
  if _,err:=unwrapDiagnostic(ctx,"prepare",bad);err==nil {t.Fatal("accepted invalid timing envelope")}
 }
}
'''


def main():
    ap=argparse.ArgumentParser();ap.add_argument('--original',type=Path,required=True);ap.add_argument('--destination',type=Path,required=True)
    args=ap.parse_args();assert not args.destination.exists()
    for name in ['services/api','infra','tools/comment-snapshot-process']:
        shutil.copytree(args.original/name,args.destination/name,ignore=shutil.ignore_patterns('__pycache__','.git','node_modules'))
    original={p.relative_to(args.destination).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in args.destination.rglob('*') if p.is_file()}
    changed=[]
    def edit(name,fn):
        f=args.destination/name;old=f.read_text();f.write_text(fn(old));changed.append(name)
    edit('services/api/internal/commentsnapshot/redis.go',lambda s:replace_once(replace_once(s,
        'commonSource + writeSource)', 'diagnosticWriteSource(commonSource, writeSource))'),
        '\tvalues, e := script.Run(bounded, s.client, keys, args...).Slice()',
        '\tfinishDiagnosticCall := readtiming.Span(ctx, "redis_"+str(req["op"])+"_script_call")\n\tvalues, e := script.Run(bounded, s.client, keys, args...).Slice()\n\tfinishDiagnosticCall()'))
    f=args.destination/'services/api/internal/commentsnapshot/redis.go';s=f.read_text();s=replace_once(s,'\treturn values, nil\n}', '\tif write && (req["op"] == "prepare" || req["op"] == "publish") { return unwrapDiagnostic(ctx, str(req["op"]), values) }\n\treturn values, nil\n}');f.write_text(s)
    helper=args.destination/'services/api/internal/commentsnapshot/p5d1_diagnostic.go';helper.write_text(GO_HELPER)
    test=helper.with_name('p5d1_diagnostic_test.go');test.write_text(GO_TEST)
    record=r'''
// DiagnosticRecord is private to the disposable P5-D1 source overlay.
func DiagnosticRecord(ctx context.Context,name string,nanos,calls int64) {
 t,ok:=ctx.Value(traceKey{}).(*Trace);if !ok {return}
 if phase,ok:=ctx.Value(phaseKey{}).(string);ok {name=phase+"."+name}
 t.mu.Lock();defer t.mu.Unlock()
 if nanos<0 || calls<0 {t.clockValid=false;return}
 if _,exists:=t.stages[name];!exists && len(t.stages)>=64 {t.truncated=true;return}
 s:=t.stages[name];s.Nanoseconds+=nanos;s.Calls+=calls;t.stages[name]=s
}
'''
    edit('services/api/internal/readtiming/readtiming.go',lambda s:s+record)
    pgfile='services/api/internal/authprivacy/community_comment_snapshots.go'
    def pg(s):
        start=s.index('\t\t\t\tif _, e = tx.Exec(ctx, `DELETE FROM c_comments.snapshots')
        end=s.index('\n\t\t\t}',start)
        block=s[start:end]
        assert block.count('tx.Exec')==2
        body=block.replace('return nil, e','return e')
        return s[:start]+'\t\t\t\te = func() error {\n\t\t\t\t\tdefer readtiming.Span(ctx, "pg_snapshot_write")()\n'+body+'\n\t\t\t\t\treturn nil\n\t\t\t\t}()\n\t\t\t\tif e != nil { return nil, e }'+s[end:]
    edit(pgfile,pg)
    changed += [str(helper.relative_to(args.destination)),str(test.relative_to(args.destination))]
    differences={}
    for name,oldhash in original.items():
        current=hashlib.sha256((args.destination/name).read_bytes()).hexdigest()
        if current!=oldhash: differences[name]={'before':oldhash,'after':current}
    assert set(differences)==set(changed[:3])
    # All authoritative Lua and authorization wrappers remain byte-for-byte equal.
    for name in ['services/api/internal/commentsnapshot/ledger_v2.lua','services/api/internal/commentsnapshot/read.lua','services/api/internal/commentsnapshot/write.lua','services/api/internal/authprivacy/authorization_gate.go','services/api/internal/authprivacy/community_identities.go','services/api/internal/authprivacy/community_posts.go']:
        assert (args.original/name).read_bytes()==(args.destination/name).read_bytes()
    (args.destination.parent/'observation-overlay.json').write_text(json.dumps({'originalFiles':original,'changed':differences,'added':changed[3:],'authoritativeLuaUnchanged':True,'authorizationUnchanged':True,'originalSource':str(args.original)},indent=2)+'\n')
    driver=(args.destination.parent/'harness/gaps_targeted.py').read_text()
    for old,new in [
        ("'scope':'SINGLE_PREDECLARED_PERFORMANCE_GAP'", "'scope':'P5_D1_OBSERVATION_ONLY_NOT_P95_ACCEPTANCE'"),
        ("[('replyExpanded',tokens[2],300,50)]", "[('replyExpanded',tokens[2],60,50)]"),
        ("stat['p95RegressionPercent']=(stat['redis']['p95Ms']/stat['postgres']['p95Ms']-1)*100", "stat['p95RegressionPercent']=None"),
        ("stat['p95Criterion']='PASS' if stat['p95RegressionPercent']<=5 else 'FAIL'", "stat['p95Criterion']='NOT_EVALUATED_DIAGNOSTIC'"),
        ("stat['result']='PASS' if stat['p95Criterion']=='PASS' and stat['environmentResult']=='PASS' else 'FAIL'", "stat['result']='COMPLETE' if stat['environmentResult']=='PASS' else 'UNRESOLVED'"),
        ("print(args.mode+' '+result['scope']+' '+kind+' '+stat['result']+' '+str(round(stat['p95RegressionPercent'],3))+'%',flush=True)", "print('P5D1 '+stat['result']+' '+json.dumps(stat['diagnosis']),flush=True)"),
        ("if stat['result']!='PASS':", "if stat['result']!='COMPLETE':"),
        ("result['result']='PASS' if all(x['result']=='PASS' for x in result['stats'].values())", "result['result']='COMPLETE' if all(x['result']=='COMPLETE' for x in result['stats'].values())"),
        ("if not args.diagnostic and result['result']!='PASS':raise SystemExit(1)", "if result['result']!='COMPLETE':raise SystemExit(1)"),
        ("if (i+1)%100==0:", "if (i+1)%10==0:"),
    ]:
        driver=replace_once(driver,old,new)
    diagnosis='''            assert len(records['postgres'])==len(records['redis'])==60
            fractions=[]
            for row in records['redis']:
                stages=row['serverTiming']['stages'];totals={name:0 for name in ['get','validate','construct','set','script']}
                for op in ['prepare','publish']:
                    for name in totals:
                        metric=stages['comments.lua_'+op+'_'+name]
                        assert metric['calls']==1 and metric['nanoseconds']>=0
                        totals[name]+=metric['nanoseconds']
                    assert stages['comments.lua_'+op+'_entries']['calls']>=1024
                    script=stages['comments.lua_'+op+'_script']['nanoseconds']
                    call=stages['comments.redis_'+op+'_script_call']['nanoseconds']
                    assert 0<script<=call, 'script clock does not close within RAW RPC'
                assert sum(totals[n] for n in ['get','validate','construct','set'])<=totals['script']
                fraction=totals['validate']/totals['script'];fractions.append(fraction)
                row['diagnosticLua']={'nanoseconds':totals,'validationFraction':fraction}
            hits=sum(v>=.70 for v in fractions)
            stat['diagnosis']={'id':'P5-D1','fixedPairs':60,'fractionThreshold':.70,'requiredRequestFraction':.80,'hits':hits,'requests':len(fractions),'observedRequestFraction':hits/len(fractions),'hypothesis':'SUPPORTED' if hits>=48 else 'REFUTED','isProductAcceptance':False}
'''
    driver=replace_once(driver,"            result['stats'][kind]=stat;dump(lab.run/'normalized-performance.json',result)",diagnosis+"            result['stats'][kind]=stat;dump(lab.run/'normalized-performance.json',result)")
    (args.destination.parent/'harness/p5d1_driver.py').write_text(driver)


if __name__=='__main__': main()
