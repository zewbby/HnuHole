import com.sun.jdi.*;
import com.sun.jdi.connect.*;
import com.sun.jdi.event.*;
import com.sun.jdi.request.*;
import java.util.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
public class NativeCallbackError {
 static boolean credentialException(ObjectReference value) {
  ReferenceType type=value.referenceType();
  while(type instanceof ClassType c) {
   if(List.of("androidx.credentials.exceptions.CreateCredentialException",
              "androidx.credentials.exceptions.GetCredentialException").contains(c.name()))return true;
   type=c.superclass();
  }
  return false;
 }
 static void printError(ObjectReference e) throws Exception {
  Set<Long> seen=new HashSet<>();
  for(int depth=0;depth<8 && e!=null && seen.add(e.uniqueID());depth++) {
   String name=e.referenceType().name();
   String msg="";
   for(String f:List.of("detailMessage","errorMessage")) {
    Field field=e.referenceType().fieldByName(f);
    if(field!=null && e.getValue(field) instanceof StringReference s && !s.value().isEmpty()) {msg=s.value();break;}
   }
   String lower=msg.toLowerCase(Locale.ROOT);
   Map<String,List<String>> known=new LinkedHashMap<>();
   known.put("SYNC_ACCOUNT",List.of("sync account","syncaccount","同步账号","同步帐号"));
   known.put("NETWORK",List.of("network","connection failed","unable to connect","网络"));
   known.put("ASSOCIATION",List.of("assetlinks","not associated","not linked","digital asset link","incoming request cannot be validated","unable to verify the package","cannot validate the package","rp id cannot be validated","应用签名验证失败","域名验证失败"));
   known.put("ENCRYPTED_DATA_LOCKED",List.of("encrypted data","failed to decrypt","unable to decrypt","加密数据"));
   known.put("GOOGLE_ACCOUNT",List.of("google account","no account","account not found","sign in","登录"));
   known.put("API_DEVELOPER_ERROR",List.of("developer_error","apiexception: 10","unknown calling package"));
   known.put("GENERIC_CANCEL",List.of("cancel","canceled","cancelled","取消"));
   known.put("USER_CANCEL_TEXT",List.of("by the user","user canceled","user cancelled","用户取消"));
   List<String> categories=new ArrayList<>();for(var k:known.entrySet()) if(k.getValue().stream().anyMatch(lower::contains)) categories.add(k.getKey());
   String hash=HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(msg.getBytes(StandardCharsets.UTF_8)));
   System.out.println("ERROR class="+name+" depth="+depth+" messageLength="+msg.length()+" messageSha256="+hash+" categories="+String.join(",",categories));
   Field cf=e.referenceType().fieldByName("cause");Value cause=cf==null?null:e.getValue(cf);e=cause instanceof ObjectReference o?o:null;
  }
 }
 public static void main(String[] args) throws Exception {
  if(args.length!=1 || !args[0].matches("[0-9]{4,5}"))throw new IllegalArgumentException();
  AttachingConnector c=Bootstrap.virtualMachineManager().attachingConnectors().stream().filter(x->x.name().equals("com.sun.jdi.SocketAttach")).findFirst().orElseThrow();
  Map<String,Connector.Argument> a=c.defaultArguments();a.get("hostname").setValue("127.0.0.1");a.get("port").setValue(args[0]);a.get("timeout").setValue("5000");VirtualMachine vm=c.attach(a);
  try {
   {
    MethodEntryRequest request=vm.eventRequestManager().createMethodEntryRequest();
    request.addClassFilter("org.hnuhole.authpasskey.AuthPasskeyPlugin$*");
    request.setSuspendPolicy(EventRequest.SUSPEND_EVENT_THREAD);request.enable();
    System.out.println("READY: own Passkey onError listener; no result modification");System.out.flush();
    long end=System.currentTimeMillis()+100000;boolean captured=false;
    while(System.currentTimeMillis()<end && !captured) {
     EventSet events=vm.eventQueue().remove(1000);if(events==null)continue;
     try {
      for(Event event:events) {
       if(event instanceof MethodEntryEvent me && me.method().name().equals("onError")) {
        StackFrame frame=me.thread().frame(0);
        List<Value> values=frame.getArgumentValues();
        System.out.println("CALLBACK method="+me.method().signature()+" argumentTypes="+me.method().argumentTypeNames());
        for(Value value:values) {
         if(value instanceof ObjectReference error && credentialException(error)) {
          System.out.println("CAPTURE_SOURCE=CALLBACK_ARGUMENT");printError(error);captured=true;
         }
        }
        if(!captured) {
         try {
          for(LocalVariable variable:frame.visibleVariables()) {
           if(!List.of("e","error","exception").contains(variable.name()))continue;
           Value value=frame.getValue(variable);
           if(value instanceof ObjectReference error && credentialException(error)) {
            System.out.println("CAPTURE_SOURCE=CALLBACK_LOCAL_VARIABLE");printError(error);captured=true;
           }
          }
         } catch(AbsentInformationException ignored) { }
        }
        if(captured) {System.out.println("CAPTURED: native SDK error; original callback resumed unchanged");System.out.flush();break;}
        else {System.out.println("NO_ERROR_OBJECT_AT_THIS_ENTRY: awaiting typed callback");System.out.flush();}
       }
      }
     } finally {events.resume();}
    }
    request.disable();if(!captured)System.out.println("NOT_CAPTURED: no SDK error callback witnessed");
    return;
   }
  } finally {vm.dispose();}
 }
}
