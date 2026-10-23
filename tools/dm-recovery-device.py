"""Explicit isolated Android recovery acceptance driver; synthetic fixtures only."""
import subprocess,json,pathlib,sys,time,os
adb=os.environ.get('DM_RECOVERY_ADB', 'adb')
pkg='org.hnuhole.hnuhole_mobile.dmrecovery'
root=pathlib.Path(os.environ['DM_RECOVERY_EVIDENCE']); root.mkdir(parents=True,exist_ok=True)
def run(device,*args,input=None,check=True):
 p=subprocess.run([adb,'-s',device,*args],input=input,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=90)
 if check and p.returncode: raise RuntimeError('adb operation failed: '+args[0])
 return p.stdout.decode(errors='replace')
def inject(device):
 c=json.loads(pathlib.Path(os.environ['DM_RECOVERY_FIXTURE']).read_text())
 run(device,'reverse','tcp:58444','tcp:'+c['HOST_PORT'])
 c['DM_ORIGIN']='https://127.0.0.1:58444'
 run(device,'shell','run-as',pkg,'mkdir','-p','files')
 run(device,'shell','run-as',pkg,'sh','-c',"'cat > files/dm-recovery-fixture.json'",input=json.dumps(c).encode())
def phase(device,name,expected=None):
 run(device,'shell','am','force-stop',pkg)
 run(device,'shell','run-as',pkg,'rm','-f','files/owned-device-driver-stage.json')
 run(device,'shell','am','start','-n',pkg+'/org.hnuhole.hnuhole_mobile.MainActivity','--ez','hnuhole-device-driver','true','--es','hnuhole-device-phase',name)
 target=expected or 'pass-'+name
 deadline=time.monotonic()+75
 while time.monotonic()<deadline:
  raw=run(device,'shell','run-as',pkg,'cat','files/owned-device-driver-stage.json',check=False)
  try: value=json.loads(raw)
  except ValueError: time.sleep(.5);continue
  if value['stage']==target:
   (root/(device+'-'+name+'.json')).write_text(json.dumps(value))
   print(device,name,value['stage'],'pid',value['pid']);return
  if value['stage'].startswith('fail-'): raise RuntimeError('device assertion failed: '+name)
  time.sleep(.5)
 raise RuntimeError('device phase timed out: '+name)
if __name__=='__main__':
 mode,device=sys.argv[1:3]
 if mode=='install':
  print(device,run(device,'install','-r',os.environ['DM_RECOVERY_APK']).strip())
  inject(device);print(device,'private fixture injected')
 elif mode=='phase': phase(device,sys.argv[3],sys.argv[4] if len(sys.argv)>4 else None)
 elif mode=='inject': inject(device)
