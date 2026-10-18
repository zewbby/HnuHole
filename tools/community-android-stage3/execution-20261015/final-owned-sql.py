import datetime,importlib.util,json,uuid
from pathlib import Path
out=Path(__file__).resolve().parent
s=importlib.util.spec_from_file_location('ownlab',out/'lab.py');lab=importlib.util.module_from_spec(s);s.loader.exec_module(lab)
w,cfg=lab.owned();f=json.loads((w/'fixture/accounts.private.json').read_text());accounts={}
for tag in ('negative','positive'):
    key=str(uuid.UUID(f[tag]['accountId']));assert key==f[tag]['accountId']
    sql="SELECT json_build_object('credentialVersion',credential_version,'resetGeneration',reset_generation,'passkeys',(SELECT count(*) FROM c_auth.passkeys WHERE account_id=a.account_id),'unrevokedSessions',(SELECT count(*) FROM c_auth.sessions WHERE account_id=a.account_id AND revoked_at IS NULL),'resetIntentsConsumed',(SELECT count(*) FROM c_auth.reset_intents WHERE account_id=a.account_id AND state='CONSUMED'),'passwordResetEvents',(SELECT count(*) FROM c_auth.security_events WHERE account_id=a.account_id AND action='PASSWORD_RESET')) FROM c_auth.accounts a WHERE account_id='"+key+"'::uuid"
    accounts[tag]=json.loads(lab.query(sql))
print(json.dumps({'observedAccountsBeforeStrictExpectation':accounts}),flush=True)
assert accounts['positive']=={'credentialVersion':3,'resetGeneration':1,'passkeys':0,'unrevokedSessions':1,'resetIntentsConsumed':1,'passwordResetEvents':1}
assert accounts['negative']=={'credentialVersion':1,'resetGeneration':0,'passkeys':0,'unrevokedSessions':1,'resetIntentsConsumed':0,'passwordResetEvents':0}
events=json.loads(lab.query("SELECT coalesce(json_agg(q ORDER BY q.credential_version),'[]'::json) FROM (SELECT action,credential_version FROM c_auth.security_events WHERE action IN ('CREATE_PASSKEY','PASSWORD_RESET')) q"))
assert events==[{'action':'CREATE_PASSKEY','credential_version':2},{'action':'PASSWORD_RESET','credential_version':3}]
r={'result':'PASS_OWNED_SQL_POST_RESET_FACTS','recordedUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'accounts':accounts,'credentialEvents':events,'credentialVersionProgression':'1 registration -> 2 bind -> 3 password reset','initialAuditExpectationCorrectedFrom2To3AfterReadingUnchangedBindingAndResetCode':True,'allAccounts':2,'posts':lab.stats()['posts'],'noActualAccountIdentifiersExported':True,'originalSessionAlreadyReplacedBeforeReset':True,'oldSessionRejectionDoesNotIndependentlyProveResetRevokedAnActiveSession':True,'onlyTask3DatabaseObserved':True}
with (out/'final-owned-sql.json').open('x') as p:json.dump(r,p,indent=2)
print(json.dumps(r))
