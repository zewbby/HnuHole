"""Keep only compact, scoped Flutter machine-test evidence; no full logs."""
import json, sys
from pathlib import Path
tests = {}; errors = []; success = False; failure_prints=[]
for line in sys.stdin:
    try: event = json.loads(line)
    except (ValueError, TypeError): continue
    if not isinstance(event,dict): continue
    kind = event.get("type")
    if kind == "testStart":
        tests[event["test"]["id"]] = {"name": event["test"]["name"]}
        if not event["test"]["name"].startswith("loading "): print("Running: "+event["test"]["name"],flush=True)
    elif kind == "print" and ("EXCEPTION CAUGHT" in str(event.get("message","")) or "Expected:" in str(event.get("message",""))):
        failure_prints.append({"testId":event.get("testID"),"message":str(event.get("message",""))[:1800]})
    elif kind == "error":
        errors.append({"testId":event.get("testID"),"message":str(event.get("error",""))[:400]})
        print("Error: "+str(event.get("error",""))[:180],flush=True)
    elif kind == "testDone" and not event.get("hidden",False):
        test = tests.get(event["testID"],{})
        if not any(s in test.get("name","") for s in ("(setUpAll)","(tearDownAll)","loading ")):
            test["result"] = "SKIP" if event.get("skipped") else "PASS" if event["result"]=="success" else "FAIL"
            print(test.get("name","test")+": "+test["result"],flush=True)
    elif kind == "done":
        success = event.get("success",False)
record={"scope":"WINDOWS_FLUTTER_TESTER_NOT_ANDROID_OR_IOS",
        "result":"PASS" if success else "FAIL",
        "cases":[v for v in tests.values() if "result" in v],
        "errors":errors, "failureDetails":failure_prints}
destination=Path(sys.argv[1])
if destination.exists():
    prior=json.loads(destination.read_text(encoding="utf-8"))
    history=prior.pop("history",[])
    record["history"]=history+[prior]
destination.parent.mkdir(parents=True,exist_ok=True)
destination.write_text(json.dumps(record,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
print(json.dumps({"result":record["result"],"cases":len(record["cases"]),"errors":len(errors)}),flush=True)
sys.exit(0 if success else 1)
