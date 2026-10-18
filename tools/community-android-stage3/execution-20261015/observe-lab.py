import datetime,http.client,importlib.util,json,re,ssl,sys
from pathlib import Path
out=Path(__file__).resolve().parent
s=importlib.util.spec_from_file_location('lab',out/'lab.py');lab=importlib.util.module_from_spec(s);s.loader.exec_module(lab)
w,cfg=lab.owned();ctx=ssl.create_default_context(cafile=str(w/'material/dev-ca.pem'))
action,label=sys.argv[1:];assert action in ('stats','arm-binding-response-loss','release-result-queries') and re.fullmatch('[a-z0-9-]{3,55}',label)
c=http.client.HTTPSConnection('127.0.0.1',cfg['ports']['proxy'],context=ctx,timeout=8)
try:
    c.request('POST','/__stage3/control',json.dumps({'action':action}),{'Authorization':'LabControl '+cfg['controlToken'],'Content-Type':'application/json'});r=c.getresponse();assert r.status==200;result=json.loads(r.read(32768))
finally:c.close()
result['observedUTC']=datetime.datetime.now(datetime.timezone.utc).isoformat();result['tlsVerified']=True
result['challenges']=json.loads(lab.query("SELECT coalesce(json_agg(q),'[]'::json) FROM (SELECT kind,state,count(*) AS count,bool_and(expires_at=created_at+interval '5 minutes') AS exact_five_minutes,bool_and(expires_at<=clock_timestamp()) AS all_naturally_expired FROM c_auth.auth_challenges GROUP BY kind,state) q"))
result['noClockOrAuthOverlay']=True
with (out/(label+'.lab.json')).open('x') as f:json.dump(result,f,indent=2)
print(json.dumps(result))
