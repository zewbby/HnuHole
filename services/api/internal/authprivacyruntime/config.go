// Package authprivacyruntime assembles the explicitly development-only C/V
// processes. It never migrates a database or possesses a Gate recovery signer.
package authprivacyruntime

import (
 "bytes"
 "crypto/ed25519"
 "crypto/tls"
 "crypto/x509"
 "encoding/json"
 "errors"
 "fmt"
 "io"
 "net"
 "net/url"
 "os"
 "path/filepath"
 "strings"
 "time"

 "github.com/jackc/pgx/v5/pgxpool"
 "github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
 "github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacyhttp"
)

type GateConfig struct {
 Domain string `json:"domain"`
 EvidenceFile string `json:"evidenceFile"`
 EvidencePublicKeyFile string `json:"evidencePublicKeyFile"`
 RecoveryPublicKeyFile string `json:"recoveryPublicKeyFile"`
 BreakGlassPublicKeyFile string `json:"breakGlassPublicKeyFile"`
 AnchorFile string `json:"anchorFile"`
 AnchorKeyFile string `json:"anchorKeyFile"`
}

type Config struct {
 Environment string `json:"environment"`
 DatabaseURL string `json:"databaseUrl"`
 DatabasePasswordFile string `json:"databasePasswordFile"`
 PublicListen string `json:"publicListen"`
 InternalListen string `json:"internalListen"`
 PublicOrigin string `json:"publicOrigin"`
 PeerOrigin string `json:"peerOrigin"`
 AllowedOrigins []string `json:"allowedOrigins"`
 AllowDevelopmentNetwork bool `json:"allowDevelopmentNetwork"`
 CAFile string `json:"caFile"`
 PublicCertificateFile string `json:"publicCertificateFile"`
 PublicKeyFile string `json:"publicKeyFile"`
 InternalCertificateFile string `json:"internalCertificateFile"`
 InternalKeyFile string `json:"internalKeyFile"`
 NetworkKeyFile string `json:"networkKeyFile"`
 SigningKeyFile string `json:"signingKeyFile"`
 TrustedCommunityKeyFile string `json:"trustedCommunityKeyFile"`
 TrustedVerifierKeyFile string `json:"trustedVerifierKeyFile"`
 RequestKeyFile string `json:"requestKeyFile,omitempty"`
 PasswordBlocklistFile string `json:"passwordBlocklistFile,omitempty"`
 Gate *GateConfig `json:"gate,omitempty"`
 WebAuthn *authprivacy.WebAuthnConfig `json:"webAuthn,omitempty"`
 AddressLockKeyFile string `json:"addressLockKeyFile,omitempty"`
 OTPKeyFile string `json:"otpKeyFile,omitempty"`
 MailEncryptionKeyFile string `json:"mailEncryptionKeyFile,omitempty"`
 RequestHMACKeyFile string `json:"requestHmacKeyFile,omitempty"`
 LimitKeyFile string `json:"limitKeyFile,omitempty"`
 SMTPAddress string `json:"smtpAddress,omitempty"`
 SMTPFrom string `json:"smtpFrom,omitempty"`
 RequestTimeoutSeconds int `json:"requestTimeoutSeconds"`
 SQLTimeoutSeconds int `json:"sqlTimeoutSeconds"`
 ShutdownTimeoutSeconds int `json:"shutdownTimeoutSeconds"`
 WorkerBatch int `json:"workerBatch"`
 WorkerTimeoutSeconds int `json:"workerTimeoutSeconds"`
 WorkerIntervalSeconds int `json:"workerIntervalSeconds"`
 PasswordWorkers int `json:"passwordWorkers"`
 NetworkMutationCapacity int `json:"networkMutationCapacity"`
 NetworkQueryCapacity int `json:"networkQueryCapacity"`
 NetworkMaxEntries int `json:"networkMaxEntries"`
 base string
}

// LoadConfig rejects unknown fields and trailing JSON; values never include
// private key bytes or a database password, only separately permissioned paths.
func LoadConfig(path string, service authprivacyhttp.Service) (Config,error) {
 var c Config
 info,err:=os.Lstat(path);if err!=nil||!info.Mode().IsRegular(){return c,errors.New("runtime configuration must be a regular file")};f,err:=os.Open(path);if err!=nil{return c,errors.New("cannot read runtime configuration")};defer f.Close();raw,err:=io.ReadAll(io.LimitReader(f,32769));if err!=nil{return c,errors.New("cannot read runtime configuration")}
 if len(raw)>32768 {return c,errors.New("runtime configuration too large")}
 d:=json.NewDecoder(bytes.NewReader(raw)); d.DisallowUnknownFields()
 if err=d.Decode(&c); err!=nil {return c,errors.New("invalid runtime configuration JSON")}
 if d.Decode(new(any))!=io.EOF {return c,errors.New("trailing runtime configuration JSON")}
 c.base,err=filepath.Abs(filepath.Dir(path)); if err!=nil {return c,err}
 return c,c.Validate(service)
}

func (c Config) Path(path string) string { if filepath.IsAbs(path) {return path}; return filepath.Join(c.base,path) }

func (c Config) Validate(service authprivacyhttp.Service) error {
 if c.Environment!="dev" || (service!=authprivacyhttp.CommunityService && service!=authprivacyhttp.VerifierService) {return errors.New("only explicitly dev C/V configuration is supported")}
 if err:=c.validateWebAuthn(service);err!=nil{return err}
 if c.PublicListen==c.InternalListen {return errors.New("public and internal listeners must be separate")}
 for _,address:=range []string{c.PublicListen,c.InternalListen} {
  host,port,err:=net.SplitHostPort(address); ip:=net.ParseIP(host)
  if err!=nil || ip==nil || port=="" || (address==c.InternalListen && !ip.IsLoopback()) || (!ip.IsLoopback() && !c.AllowDevelopmentNetwork) {return errors.New("listeners need literal IP and explicit development network policy")}
 }
 origin,err:=validOrigin(c.PublicOrigin); if err!=nil {return err}
 if _,err=validOrigin(c.PeerOrigin); err!=nil {return err}
 if c.PublicOrigin==c.PeerOrigin {return errors.New("C/V origins must be independent")}
 _,publicPort,_:=net.SplitHostPort(c.PublicListen)
 if origin.Port()!=publicPort {return errors.New("public origin port differs from listener")}
 if len(c.AllowedOrigins)>32 {return errors.New("too many allowed origins")}
 for _,raw:=range c.AllowedOrigins {if _,err=validOrigin(raw);err!=nil{return err}}
 party:="c";if service==authprivacyhttp.VerifierService{party="v"}
 db,err:=pgxpool.ParseConfig(c.DatabaseURL)
 if err!=nil || db.ConnConfig.Password!="" || db.ConnConfig.User!="hnuhole_"+party+"_runtime" || db.ConnConfig.Database!="hnuhole_"+party || c.DatabasePasswordFile=="" {return errors.New("database URL must name database/runtime role and keep password in a private file")}
 if c.RequestTimeoutSeconds<1 || c.RequestTimeoutSeconds>60 || c.SQLTimeoutSeconds!=10 || c.SQLTimeoutSeconds>c.RequestTimeoutSeconds || c.ShutdownTimeoutSeconds<1 || c.ShutdownTimeoutSeconds>60 || c.PasswordWorkers<1 || c.PasswordWorkers>16 || c.WorkerBatch<1 || c.WorkerBatch>100 || c.WorkerTimeoutSeconds<1 || c.WorkerTimeoutSeconds>30 || c.WorkerIntervalSeconds<1 || c.WorkerIntervalSeconds>60 {return errors.New("invalid bounded timeout/worker configuration")}
 roots,err:=c.Roots(); if err!=nil{return err}
 public,err:=c.Certificate(false); if err!=nil{return err}
 leaf,err:=x509.ParseCertificate(public.Certificate[0]); if err!=nil{return errors.New("invalid public certificate")}
 if _,err=leaf.Verify(x509.VerifyOptions{Roots:roots,DNSName:origin.Hostname(),KeyUsages:[]x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}});err!=nil{return errors.New("public certificate does not match configured origin/trust")}
 internal,err:=c.Certificate(true);if err!=nil{return err}
 internalLeaf,err:=x509.ParseCertificate(internal.Certificate[0]);if err!=nil{return errors.New("invalid internal certificate")};intermediates:=x509.NewCertPool();for _,der:=range internal.Certificate[1:]{certificate,parseErr:=x509.ParseCertificate(der);if parseErr!=nil{return errors.New("invalid internal certificate chain")};intermediates.AddCert(certificate)}
 for _,usage:=range []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth,x509.ExtKeyUsageClientAuth}{if _,err=internalLeaf.Verify(x509.VerifyOptions{Roots:roots,Intermediates:intermediates,KeyUsages:[]x509.ExtKeyUsage{usage}});err!=nil{return errors.New("internal certificate outside configured trust")}}
 peer:=authprivacyhttp.VerifierService;if service==peer{peer=authprivacyhttp.CommunityService}
 if _,err=authprivacyhttp.InternalTLSConfig(internal,authprivacyhttp.PeerIdentity{Environment:c.Environment,Service:peer,Roots:roots});err!=nil{return errors.New("invalid internal workload identity/certificate")}
 validationPeer,err:=authprivacyhttp.NewPeerClient(authprivacyhttp.PeerClientOptions{Origin:c.PeerOrigin,Environment:c.Environment,LocalService:service,PeerService:peer,ClientCertificate:internal,Roots:roots,Timeout:time.Duration(c.WorkerTimeoutSeconds)*time.Second});if err!=nil{return errors.New("invalid peer origin/certificate policy")};validationPeer.CloseIdleConnections()
 seen:=map[string]bool{}
 paths:=[]string{c.NetworkKeyFile,c.SigningKeyFile}
 if service==authprivacyhttp.CommunityService {
  paths=append(paths,c.RequestKeyFile)
  if c.Gate==nil || c.Gate.Domain=="" || c.Gate.EvidenceFile=="" || c.Gate.AnchorFile=="" || c.PasswordBlocklistFile=="" {return errors.New("C requires evidence/anchor/recovery public trust and password blocklist")}
  paths=append(paths,c.Gate.AnchorKeyFile)
  for _,p:=range []string{c.Gate.EvidencePublicKeyFile,c.Gate.RecoveryPublicKeyFile,c.Gate.BreakGlassPublicKeyFile} {if _,err=c.PublicKey(p);err!=nil{return err}}
  if _,err=c.Read(c.PasswordBlocklistFile,false,1048576);err!=nil{return err}
 } else {
  if c.Gate!=nil {return errors.New("V must not borrow the C Gate")}
  paths=append(paths,c.AddressLockKeyFile,c.OTPKeyFile,c.MailEncryptionKeyFile,c.RequestHMACKeyFile,c.LimitKeyFile)
  if _,err=authprivacy.NewSMTPProvider(authprivacy.SMTPConfig{Address:c.SMTPAddress,From:c.SMTPFrom,Timeout:5*time.Second,AllowInsecureLoopback:true});err!=nil{return err}
 }
 for _,p:=range paths {
  size:=32;if p==c.SigningKeyFile || c.Gate!=nil && p==c.Gate.AnchorKeyFile {size=64}
  b,e:=c.Read(p,true,size);if e!=nil||len(b)!=size{return errors.New("missing or invalid purpose key")}
  if bytes.Equal(b,make([]byte,size))||seen[string(b)]{return errors.New("zero or reused purpose key")};seen[string(b)]=true
  if size==64 && !bytes.Equal(ed25519.NewKeyFromSeed(b[:32]),b) {return errors.New("invalid Ed25519 private key")}
 }
 cp,err:=c.PublicKey(c.TrustedCommunityKeyFile);if err!=nil{return err};vp,err:=c.PublicKey(c.TrustedVerifierKeyFile);if err!=nil{return err}
 signing,err:=c.PrivateKey(c.SigningKeyFile);if err!=nil{return err}
 expected:=cp;if service==authprivacyhttp.VerifierService{expected=vp}
 if bytes.Equal(cp,vp)||!bytes.Equal(signing.Public().(ed25519.PublicKey),expected){return errors.New("C/V signing trust must be independent and match local signer")}
 trustKeys:=[]ed25519.PublicKey{cp,vp}
 if c.Gate!=nil{
  for _,path:=range []string{c.Gate.EvidencePublicKeyFile,c.Gate.RecoveryPublicKeyFile,c.Gate.BreakGlassPublicKeyFile}{key,err:=c.PublicKey(path);if err!=nil{return err};trustKeys=append(trustKeys,key)}
  anchor,err:=c.PrivateKey(c.Gate.AnchorKeyFile);if err!=nil{return err};trustKeys=append(trustKeys,anchor.Public().(ed25519.PublicKey))
 }
 seenTrust:=map[string]bool{};for _,key:=range trustKeys{if seenTrust[string(key)]{return errors.New("protocol/evidence/recovery/anchor trust purposes must be independent")};seenTrust[string(key)]=true}
 network,err:=c.Key32(c.NetworkKeyFile);if err!=nil{return err}
 if c.NetworkMutationCapacity<1 || c.NetworkMutationCapacity>10000 || c.NetworkQueryCapacity<1 || c.NetworkQueryCapacity>10000 || c.NetworkMaxEntries<1 || c.NetworkMaxEntries>65536 || network==([32]byte{}) {return errors.New("invalid network budget")}
 _,err=c.Read(c.DatabasePasswordFile,true,1024);return err
}

// An omitted policy leaves Passkey endpoints fail closed. A native deployment
// must explicitly provision its fixed RP, HTTPS origins and APK signing origins;
// PublicOrigin/AllowedOrigins never select or extend WebAuthn authority.
func (c Config) validateWebAuthn(service authprivacyhttp.Service) error {
 if c.WebAuthn==nil{return nil}
 if service!=authprivacyhttp.CommunityService{return errors.New("V must not possess C WebAuthn policy")}
 if _,err:=authprivacy.NewWebAuthnValidator(*c.WebAuthn);err!=nil{return errors.New("invalid fixed WebAuthn RP/native origin policy")}
 return nil
}

func validOrigin(raw string) (*url.URL,error) {
 u,err:=url.Parse(raw)
 if err!=nil||u.Scheme!="https"||u.Hostname()==""||u.User!=nil||u.RawQuery!=""||u.Fragment!=""||u.Path!=""||u.Opaque!=""||u.ForceQuery||u.Port()==""{return nil,errors.New("origin must be fixed HTTPS authority with explicit port")}
 return u,nil
}
func (c Config) Read(path string,private bool,max int) ([]byte,error) {
 if path==""{return nil,errors.New("required material file missing")}
 p:=c.Path(path);info,err:=os.Lstat(p)
 if err!=nil||!info.Mode().IsRegular()||info.Size()>int64(max)||info.Size()==0 || private && info.Mode().Perm()&0077!=0{return nil,fmt.Errorf("invalid permissions/size/type for material %s",filepath.Base(p))}
 f,err:=os.Open(p);if err!=nil{return nil,errors.New("cannot read runtime material")};defer f.Close();b,err:=io.ReadAll(io.LimitReader(f,int64(max)+1));if err!=nil||len(b)>max{return nil,errors.New("cannot read bounded runtime material")};return b,nil
}
func (c Config) Key32(path string) (out [32]byte,err error) {b,err:=c.Read(path,true,32);if err!=nil||len(b)!=32||bytes.Equal(b,make([]byte,32)){return out,errors.New("invalid 32 byte purpose key")};copy(out[:],b);return out,nil}
func (c Config) PrivateKey(path string) (ed25519.PrivateKey,error) {b,err:=c.Read(path,true,64);if err!=nil||len(b)!=64||!bytes.Equal(ed25519.NewKeyFromSeed(b[:32]),b){return nil,errors.New("invalid private signer")};return ed25519.PrivateKey(b),nil}
func (c Config) PublicKey(path string) (ed25519.PublicKey,error) {b,err:=c.Read(path,false,32);if err!=nil||len(b)!=32||bytes.Equal(b,make([]byte,32)){return nil,errors.New("invalid public trust key")};return ed25519.PublicKey(b),nil}
func (c Config) Roots() (*x509.CertPool,error) {b,err:=c.Read(c.CAFile,false,32768);if err!=nil{return nil,err};p:=x509.NewCertPool();if !p.AppendCertsFromPEM(b){return nil,errors.New("invalid fixed development CA")};return p,nil}
func (c Config) Certificate(internal bool) (tls.Certificate,error) {
 cert,key:=c.PublicCertificateFile,c.PublicKeyFile;if internal{cert,key=c.InternalCertificateFile,c.InternalKeyFile}
 b,err:=c.Read(cert,false,32768);if err!=nil{return tls.Certificate{},err};k,err:=c.Read(key,true,32768);if err!=nil{return tls.Certificate{},err}
 pair,err:=tls.X509KeyPair(b,k);if err!=nil{return pair,errors.New("invalid TLS certificate/key pair")};return pair,nil
}
func (c Config) PoolConfig() (*pgxpool.Config,error) {
 p,err:=pgxpool.ParseConfig(c.DatabaseURL);if err!=nil{return nil,errors.New("invalid database connection")}
 password,err:=c.Read(c.DatabasePasswordFile,true,1024);if err!=nil{return nil,err}
 p.ConnConfig.Password=strings.TrimSpace(string(password));p.ConnConfig.ConnectTimeout=5*time.Second
 p.MaxConns=12;p.MinConns=0;p.ConnConfig.RuntimeParams["statement_timeout"]=fmt.Sprint(c.SQLTimeoutSeconds*1000)
 p.ConnConfig.RuntimeParams["lock_timeout"]=fmt.Sprint(c.SQLTimeoutSeconds*1000)
 return p,nil
}
