package authprivacyruntime

import (
 "bytes"
 "context"
 "crypto/ed25519"
 "crypto/tls"
 "errors"
 "fmt"
 "log/slog"
 "net"
 "net/http"
 "strings"
 "sync"
 "time"

 "github.com/jackc/pgx/v5/pgxpool"
 "github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
 "github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
 "github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacyhttp"
)

// CheckDatabase rejects a wrong database, missing formal schema, privileged
// connection, owner membership, and legacy-auth/DDL access before listening.
func CheckDatabase(ctx context.Context,pool *pgxpool.Pool,service authprivacyhttp.Service) error {
 party,schema,version:="c","c_auth",int64(11);if service==authprivacyhttp.VerifierService{party,schema,version="v","v_auth",3}
 var db,user string;var privileged,ownerMember,ddl,legacy bool;var migrated int64
 err:=pool.QueryRow(ctx,`SELECT current_database(),current_user,
   (SELECT rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls FROM pg_roles WHERE rolname=current_user),
   (EXISTS(SELECT 1 FROM pg_namespace n WHERE n.nspname=$1 AND pg_has_role(current_user,n.nspowner,'MEMBER')) OR EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE (n.nspname=$1 OR (n.nspname='public' AND c.relname IN ('channels','community_identities','identity_account_state','identity_change_receipts'))) AND pg_has_role(current_user,c.relowner,'MEMBER'))),
   has_database_privilege(current_user,current_database(),'CREATE,TEMP') OR has_schema_privilege(current_user,'public','CREATE') OR has_schema_privilege(current_user,$1,'CREATE'),
   COALESCE(has_table_privilege(current_user,to_regclass('public.sessions'),'SELECT'),false),
   COALESCE((SELECT MAX(version_id) FROM public.goose_db_version WHERE is_applied),0)`,schema).Scan(&db,&user,&privileged,&ownerMember,&ddl,&legacy,&migrated)
 if err!=nil||db!="hnuhole_"+party||user!="hnuhole_"+party+"_runtime"||privileged||ownerMember||ddl||legacy||migrated<version {return errors.New("database/schema/version/runtime privileges rejected")}
 var schemaOK bool
 query:=`SELECT to_regclass('c_auth.accounts') IS NOT NULL AND to_regclass('c_auth.authorization_gate') IS NOT NULL AND to_regclass('public.channels') IS NOT NULL AND EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='c_auth' AND table_name='receipt_outbox' AND column_name='claim_generation')`
 if party=="v"{query=`SELECT to_regclass('v_auth.otp_confirmations') IS NOT NULL AND to_regclass('v_auth.mail_outbox') IS NOT NULL AND to_regclass('v_auth.used_slots') IS NOT NULL`}
 if err=pool.QueryRow(ctx,query).Scan(&schemaOK);err!=nil||!schemaOK{return errors.New("required formal auth schema absent")}
 // Sequence permissions matter for Gate audit identity and V budget events.
 var denied bool
 if err=pool.QueryRow(ctx,`SELECT EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname=$1 AND c.relkind='S' AND NOT has_sequence_privilege(current_user,c.oid,'USAGE'))`,schema).Scan(&denied);err!=nil||denied{return errors.New("runtime auth sequence permissions absent")}
 var insufficient bool
 required:=[]string{"accounts","sessions","receipt_outbox","request_results"};if party=="v"{required=[]string{"otp_flows","otp_confirmations","mail_outbox","request_results"}}
 if err=pool.QueryRow(ctx,`SELECT EXISTS(SELECT 1 FROM unnest($2::text[]) AS required_table(table_name) WHERE NOT has_table_privilege(current_user,format('%I.%I',$1,required_table.table_name),'SELECT') OR NOT has_table_privilege(current_user,format('%I.%I',$1,required_table.table_name),'INSERT') OR NOT has_table_privilege(current_user,format('%I.%I',$1,required_table.table_name),'UPDATE'))`,schema,required).Scan(&insufficient);err!=nil||insufficient{return errors.New("runtime required auth DML privileges absent")}
 if party=="c"{
  if err=pool.QueryRow(ctx,`SELECT to_regclass('public.community_identities') IS NOT NULL AND to_regclass('public.identity_account_state') IS NOT NULL AND to_regclass('public.identity_change_receipts') IS NOT NULL`).Scan(&schemaOK);err!=nil||!schemaOK{return errors.New("identity management schema absent")}
  if err=pool.QueryRow(ctx,`SELECT EXISTS(SELECT 1 FROM unnest(ARRAY['community_identities','identity_account_state','identity_change_receipts']) AS t(name) WHERE NOT has_table_privilege(current_user,format('public.%I',t.name),'SELECT') OR NOT has_table_privilege(current_user,format('public.%I',t.name),'INSERT') OR (t.name<>'identity_change_receipts' AND NOT has_table_privilege(current_user,format('public.%I',t.name),'UPDATE')))` ).Scan(&insufficient);err!=nil||insufficient{return errors.New("identity management DML privileges absent")}
  var recoveryMember bool
  if err=pool.QueryRow(ctx,`SELECT pg_has_role(current_user,'hnuhole_c_recovery','MEMBER')`).Scan(&recoveryMember);err!=nil||recoveryMember{return errors.New("API must not possess recovery role membership")}
 }
 return nil
}

func NewGate(c Config,pool *pgxpool.Pool) (*authprivacy.PostgresAuthorizationGate,error) {
 if c.Gate==nil{return nil,errors.New("C Gate configuration required")}
 key,err:=c.PrivateKey(c.Gate.AnchorKeyFile);if err!=nil{return nil,err}
 anchor,err:=authprivacy.NewFileAuthorizationAnchorStore(c.Path(c.Gate.AnchorFile),key);if err!=nil{return nil,err}
 evidence,err:=c.PublicKey(c.Gate.EvidencePublicKeyFile);if err!=nil{return nil,err};recovery,err:=c.PublicKey(c.Gate.RecoveryPublicKeyFile);if err!=nil{return nil,err};breakGlass,err:=c.PublicKey(c.Gate.BreakGlassPublicKeyFile);if err!=nil{return nil,err}
 return authprivacy.NewPostgresAuthorizationGate(authprivacy.AuthorizationGateConfig{Pool:pool,Domain:c.Gate.Domain,Evidence:authprivacy.NewFileAuthorizationEvidenceProvider(c.Path(c.Gate.EvidenceFile)),EvidencePublicKey:evidence,RecoveryPublicKey:recovery,BreakGlassPublicKey:breakGlass,Anchor:anchor,Clock:time.Now})
}

func trust(c Config) (*protocol.Verifier,error) {
 cp,err:=c.PublicKey(c.TrustedCommunityKeyFile);if err!=nil{return nil,err};vp,err:=c.PublicKey(c.TrustedVerifierKeyFile);if err!=nil{return nil,err}
 var community,verifier protocol.PublicKey;copy(community[:],cp);copy(verifier[:],vp)
 return protocol.NewVerifier(c.Environment,[]protocol.TrustedKey{
  {Environment:c.Environment,Purpose:protocol.PurposeRegister,Epoch:1,PublicKey:verifier},
  {Environment:c.Environment,Purpose:protocol.PurposeRetireAuth,Epoch:1,PublicKey:verifier},
  {Environment:c.Environment,Purpose:protocol.PurposeRetired,Epoch:1,PublicKey:community},
  {Environment:c.Environment,Purpose:protocol.PurposeReleased,Epoch:1,PublicKey:community},
 })
}
func localSigner(c Config,service authprivacyhttp.Service) (authprivacy.Signer,error) {
 key,err:=c.PrivateKey(c.SigningKeyFile);if err!=nil{return nil,err}
 trustPath:=c.TrustedCommunityKeyFile;if service==authprivacyhttp.VerifierService{trustPath=c.TrustedVerifierKeyFile};expected,err:=c.PublicKey(trustPath);if err!=nil||!bytes.Equal(key.Public().(ed25519.PublicKey),expected){return nil,errors.New("local signing key purpose mismatch")}
 return func(ctx context.Context,epoch uint32,message []byte) ([]byte,error) {if ctx.Err()!=nil{return nil,ctx.Err()};if epoch!=1{return nil,errors.New("unconfigured signing epoch")};return ed25519.Sign(key,message),nil},nil
}

type runner interface{Run(context.Context) error}

func Run(ctx context.Context,c Config,service authprivacyhttp.Service) error {
 if err:=c.Validate(service);err!=nil{return err}
 poolConfig,err:=c.PoolConfig();if err!=nil{return err}
 pool,err:=pgxpool.NewWithConfig(ctx,poolConfig);if err!=nil{return errors.New("create runtime database pool failed")};defer pool.Close()
 startup,cancel:=context.WithTimeout(ctx,10*time.Second)
 err=pool.Ping(startup);if err==nil{err=CheckDatabase(startup,pool,service)};cancel();if err!=nil{return errors.New("runtime database startup validation failed")}
 verifier,err:=trust(c);if err!=nil{return err};signer,err:=localSigner(c,service);if err!=nil{return err}
 roots,err:=c.Roots();if err!=nil{return err};certificate,err:=c.Certificate(true);if err!=nil{return err}
 peerService:=authprivacyhttp.VerifierService;if service==peerService{peerService=authprivacyhttp.CommunityService}
 identity:=authprivacyhttp.PeerIdentity{Environment:c.Environment,Service:peerService,Roots:roots}
 peer,err:=authprivacyhttp.NewPeerClient(authprivacyhttp.PeerClientOptions{Origin:c.PeerOrigin,Environment:c.Environment,LocalService:service,PeerService:peerService,ClientCertificate:certificate,Roots:roots,Timeout:time.Duration(c.WorkerTimeoutSeconds)*time.Second});if err!=nil{return err};defer peer.CloseIdleConnections()
 network,err:=c.Key32(c.NetworkKeyFile);if err!=nil{return err}
 limits:=authprivacyhttp.NetworkLimits{Key:network,MutationCapacity:c.NetworkMutationCapacity,QueryCapacity:c.NetworkQueryCapacity,MaxEntries:c.NetworkMaxEntries,Window:time.Minute}
 var endpoints *authprivacyhttp.Endpoints;var gate *authprivacy.PostgresAuthorizationGate;var worker runner
 workerConfig:=authprivacy.DefaultWorkerConfig()
 workerConfig.BatchSize=c.WorkerBatch
 workerConfig.TaskTimeout=time.Duration(c.WorkerTimeoutSeconds)*time.Second
 workerConfig.Interval=time.Duration(c.WorkerIntervalSeconds)*time.Second
 if workerConfig.MaxBackoff<workerConfig.Interval{workerConfig.MaxBackoff=2*workerConfig.Interval}
 workerConfig.ReceiptLease=workerConfig.TaskTimeout+5*time.Second
 observer:=func(event authprivacy.WorkerObservation){slog.Info("bounded worker pass","task",event.Name,"processed",event.Processed,"failed",event.Failed,"batch_limit",event.BatchLimit,"duration_ms",event.Duration.Milliseconds())}
 if service==authprivacyhttp.CommunityService {
  gate,err=NewGate(c,pool);if err!=nil{return err}
  request,err:=c.Key32(c.RequestKeyFile);if err!=nil{return err}
  community,err:=authprivacy.NewCommunityWithReceiptSigner(pool,verifier,1,request,signer,gate);if err!=nil{return err}
  if c.WebAuthn!=nil{community,err=community.WithWebAuthn(*c.WebAuthn);if err!=nil{return err}}
  raw,err:=c.Read(c.PasswordBlocklistFile,false,1048576);if err!=nil{return err}
  passwords,err:=authprivacy.NewPasswordPreparer(c.PasswordWorkers,strings.Fields(string(raw)));if err!=nil{return err}
  endpoints,err=authprivacyhttp.NewCommunityEndpoints(authprivacyhttp.CommunityOptions{Backend:community,Passwords:passwords,InternalPeer:identity,AllowedOrigins:c.AllowedOrigins,Limits:limits});if err!=nil{return err}
  worker,err=authprivacy.NewCommunityWorker(community,workerConfig,signer,peer.ReceiveReceipt,observer);if err!=nil{return err}
 } else {
  lock,err:=c.Key32(c.AddressLockKeyFile);if err!=nil{return err};store,err:=authprivacy.NewVerifierStore(pool,verifier,lock);if err!=nil{return err}
  otp,err:=c.Key32(c.OTPKeyFile);if err!=nil{return err};mailKey,err:=c.Key32(c.MailEncryptionKeyFile);if err!=nil{return err};hmacKey,err:=c.Key32(c.RequestHMACKeyFile);if err!=nil{return err};limit,err:=c.Key32(c.LimitKeyFile);if err!=nil{return err}
  smtp,err:=authprivacy.NewSMTPProvider(authprivacy.SMTPConfig{Address:c.SMTPAddress,From:c.SMTPFrom,Timeout:time.Duration(c.WorkerTimeoutSeconds)*time.Second,AllowInsecureLoopback:true});if err!=nil{return err}
  eligibility,err:=authprivacy.NewEligibility(store,authprivacy.EligibilityConfig{OTPKey:otp,OTPKeyVersion:1,MailEncryptionKey:mailKey,MailEncryptionKeyVersion:1,RequestHMACKey:hmacKey,HMACKeyVersion:1,LimitKey:limit,RegistrationEpoch:1,SendBudget:10,VerifyBudget:30},signer,smtp,peer);if err!=nil{return err}
  endpoints,err=authprivacyhttp.NewVerifierEndpoints(authprivacyhttp.VerifierOptions{Eligibility:eligibility,Receipts:store,InternalPeer:identity,AllowedOrigins:c.AllowedOrigins,Limits:limits});if err!=nil{return err}
  worker,err=authprivacy.NewVerifierWorker(eligibility,workerConfig,observer);if err!=nil{return err}
 }
 publicCert,err:=c.Certificate(false);if err!=nil{return err};publicTLS,err:=authprivacyhttp.PublicTLSConfig(publicCert);if err!=nil{return err};internalTLS,err:=authprivacyhttp.InternalTLSConfig(certificate,identity);if err!=nil{return err}
 live:=func(w http.ResponseWriter,r *http.Request){w.Header().Set("Cache-Control","no-store");if r.Method!="GET"{w.WriteHeader(405);return};w.WriteHeader(200);_,_=w.Write([]byte("ok\n"))}
 ready:=func(w http.ResponseWriter,r *http.Request){w.Header().Set("Cache-Control","no-store");if r.Method!="GET"{w.WriteHeader(405);return};check,cancel:=context.WithTimeout(r.Context(),2*time.Second);defer cancel();err:=pool.Ping(check);if err==nil&&gate!=nil{_,err=gate.Snapshot(check)};if err!=nil{w.WriteHeader(503);return};w.WriteHeader(200);_,_=w.Write([]byte("ready\n"))}
 public:=http.HandlerFunc(func(w http.ResponseWriter,r *http.Request){switch r.URL.Path{case "/health/live":live(w,r);case "/health/ready":ready(w,r);default:endpoints.Public.ServeHTTP(w,r)}})
 timeout:=time.Duration(c.RequestTimeoutSeconds)*time.Second
 bounded:=func(next http.Handler) http.Handler{return http.HandlerFunc(func(w http.ResponseWriter,r *http.Request){request,cancel:=context.WithTimeout(r.Context(),timeout);defer cancel();next.ServeHTTP(w,r.WithContext(request))})}
 servers:=[]*http.Server{{Addr:c.PublicListen,Handler:bounded(public),TLSConfig:publicTLS},{Addr:c.InternalListen,Handler:bounded(endpoints.Internal),TLSConfig:internalTLS}}
 listeners:=make([]net.Listener,0,2)
 for _,server:=range servers{
  server.ReadHeaderTimeout=5*time.Second;server.ReadTimeout=timeout;server.WriteTimeout=timeout+time.Second;server.IdleTimeout=30*time.Second;server.MaxHeaderBytes=32768
  listener,err:=net.Listen("tcp",server.Addr);if err!=nil{for _,l:=range listeners{_ = l.Close()};return errors.New("runtime listener bind failed")};listeners=append(listeners,tls.NewListener(listener,server.TLSConfig))
 }
 runCtx,stop:=context.WithCancel(ctx);defer stop();fail:=make(chan error,3);var wg sync.WaitGroup
 for _,server:=range servers{server.BaseContext=func(net.Listener) context.Context{return runCtx}}
 for i,server:=range servers{wg.Add(1);go func(s *http.Server,l net.Listener){defer wg.Done();fail<-s.Serve(l)}(server,listeners[i])}
 wg.Add(1);go func(){defer wg.Done();fail<-worker.Run(runCtx)}()
 slog.Info("development runtime listening","service",service,"public",c.PublicListen,"internal",c.InternalListen,"worker_batch",workerConfig.BatchSize,"worker_concurrency",workerConfig.Concurrency,"worker_task_seconds",workerConfig.TaskTimeout.Seconds(),"receipt_lease_seconds",workerConfig.ReceiptLease.Seconds())
 var result error
 select{case <-ctx.Done():case result=<-fail:if errors.Is(result,http.ErrServerClosed)||errors.Is(result,context.Canceled){result=nil}}
 // Stop accepting first, cancel workers and requests, then wait for bounded
 // shutdown before closing the pool. No startup path calls Gate.Recover.
 for _,server:=range servers{server.SetKeepAlivesEnabled(false)}
 for _,listener:=range listeners{_ = listener.Close()}
 stop();shutdown,cancelShutdown:=context.WithTimeout(context.Background(),time.Duration(c.ShutdownTimeoutSeconds)*time.Second);defer cancelShutdown()
 for _,server:=range servers{if err=server.Shutdown(shutdown);err!=nil{_ = server.Close();if result==nil{result=err}}}
 wg.Wait()
 if ctx.Err()!=nil && (errors.Is(result,net.ErrClosed)||errors.Is(result,http.ErrServerClosed)||errors.Is(result,context.Canceled)){result=nil}
 if result!=nil{return fmt.Errorf("runtime stopped: %w",result)};return nil
}
