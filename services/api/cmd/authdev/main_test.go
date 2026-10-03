package main

import (
 "crypto/rand"
 "crypto/x509"
 "encoding/base64"
 "encoding/json"
 "encoding/pem"
 "os"
 "path/filepath"
 "strings"
 "testing"
 "time"

 "github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacyhttp"
 "github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacyruntime"
)

func TestExplicitDevelopmentWebAuthnPolicyRequiresProvisionedTrust(t *testing.T) {
 dir:=filepath.Join(t.TempDir(),"material")
 android:="android:apk-key-hash:"+base64.RawURLEncoding.EncodeToString([]byte(strings.Repeat("a",32)))
 if err:=initialize([]string{"-dir",dir,"-webauthn-rp-id","example.test","-webauthn-https-origins","https://example.test","-webauthn-android-origins",android});err!=nil{t.Fatal(err)}
 c,err:=authprivacyruntime.LoadConfig(filepath.Join(dir,"c.json"),authprivacyhttp.CommunityService);if err!=nil{t.Fatal(err)}
 if c.WebAuthn==nil||c.WebAuthn.RPID!="example.test"||len(c.WebAuthn.AndroidOrigins)!=1||c.WebAuthn.AndroidOrigins[0]!=android{t.Fatal("explicit native policy was not persisted")}
 v,err:=authprivacyruntime.LoadConfig(filepath.Join(dir,"v.json"),authprivacyhttp.VerifierService);if err!=nil||v.WebAuthn!=nil{t.Fatal("V inherited C WebAuthn policy")}
 invalidDir:=filepath.Join(t.TempDir(),"invalid")
 if err=initialize([]string{"-dir",invalidDir,"-webauthn-rp-id","example.test","-webauthn-https-origins","https://example.test","-webauthn-android-origins",android+"="});err==nil{t.Fatal("bad signing association accepted")}
 if _,err=os.Stat(invalidDir);!os.IsNotExist(err){t.Fatal("invalid native configuration created private runtime material")}
}

// This test exercises startup input with real generated keys and certificates,
// never starts a listener/database, and does not store test material in Git.
func TestDevelopmentConfigurationRejectsBadMaterial(t *testing.T) {
 dir:=filepath.Join(t.TempDir(),"material")
 if err:=initialize([]string{"-dir",dir});err!=nil{t.Fatal(err)}
 otherDir:=filepath.Join(t.TempDir(),"other-material");if err:=initialize([]string{"-dir",otherDir});err!=nil{t.Fatal(err)}
 expiredPath:=expiredInternalCertificate(t,dir)
 path:=filepath.Join(dir,"c.json")
 original,err:=os.ReadFile(path);if err!=nil{t.Fatal(err)}
 if _,err=authprivacyruntime.LoadConfig(path,authprivacyhttp.CommunityService);err!=nil{t.Fatalf("generated C config invalid: %v",err)}
 if _,err=authprivacyruntime.LoadConfig(filepath.Join(dir,"v.json"),authprivacyhttp.VerifierService);err!=nil{t.Fatalf("generated V config invalid: %v",err)}
 cases:=[]struct{name string;change func(*authprivacyruntime.Config)}{
  {"missing-key",func(c *authprivacyruntime.Config){c.RequestKeyFile=""}},
  {"wrong-key-purpose",func(c *authprivacyruntime.Config){c.RequestKeyFile=c.NetworkKeyFile}},
  {"API-recovery-signing-reuse",func(c *authprivacyruntime.Config){c.Gate.RecoveryPublicKeyFile=c.TrustedCommunityKeyFile}},
  {"wrong-signing-trust",func(c *authprivacyruntime.Config){c.SigningKeyFile="v-signing.key"}},
  {"wrong-internal-root",func(c *authprivacyruntime.Config){c.InternalCertificateFile=filepath.Join(otherDir,"c-internal.pem");c.InternalKeyFile=filepath.Join(otherDir,"c-internal.key")}},
  {"expired-internal-certificate",func(c *authprivacyruntime.Config){c.InternalCertificateFile=expiredPath}},
  {"wrong-workload",func(c *authprivacyruntime.Config){c.InternalCertificateFile="v-internal.pem";c.InternalKeyFile="v-internal.key"}},
  {"wrong-certificate-key",func(c *authprivacyruntime.Config){c.PublicKeyFile="v-public.key"}},
  {"wrong-origin",func(c *authprivacyruntime.Config){c.PublicOrigin="https://attacker.invalid:8443"}},
  {"origin-query",func(c *authprivacyruntime.Config){c.PublicOrigin+="?secret=1"}},
  {"wrong-database",func(c *authprivacyruntime.Config){c.DatabaseURL="postgres://hnuhole_c_runtime@127.0.0.1:55432/hnuhole_v?sslmode=disable"}},
  {"owner-connection",func(c *authprivacyruntime.Config){c.DatabaseURL="postgres://hnuhole_c_owner@127.0.0.1:55432/hnuhole_c?sslmode=disable"}},
  {"inline-password",func(c *authprivacyruntime.Config){c.DatabaseURL="postgres://hnuhole_c_runtime:do-not-store@127.0.0.1:55432/hnuhole_c?sslmode=disable"}},
  {"wrong-timeout",func(c *authprivacyruntime.Config){c.SQLTimeoutSeconds=5}},
  {"unbounded-worker",func(c *authprivacyruntime.Config){c.WorkerBatch=10000}},
  {"unmarked-network",func(c *authprivacyruntime.Config){c.InternalListen="0.0.0.0:9443"}},
 }
 for _,tc:=range cases{t.Run(tc.name,func(t *testing.T){var c authprivacyruntime.Config;if err=json.Unmarshal(original,&c);err!=nil{t.Fatal(err)};tc.change(&c);if err=saveJSON(path,c);err!=nil{t.Fatal(err)};if _,err=authprivacyruntime.LoadConfig(path,authprivacyhttp.CommunityService);err==nil{t.Fatal("bad config accepted")}})}
 if err=save(path,original);err!=nil{t.Fatal(err)}
 // A permission regression must fail before service startup.
 if err=os.Chmod(filepath.Join(dir,"c-request.key"),0644);err!=nil{t.Fatal(err)}
 if _,err=authprivacyruntime.LoadConfig(path,authprivacyhttp.CommunityService);err==nil{t.Fatal("world-readable private key accepted")}
}

func TestWrongOperatorSignerPreservesExistingEvidence(t *testing.T) {
 dir:=filepath.Join(t.TempDir(),"material")
 if err:=initialize([]string{"-dir",dir});err!=nil{t.Fatal(err)}
 path:=filepath.Join(dir,"operator","operator.json")
 original,err:=os.ReadFile(path);if err!=nil{t.Fatal(err)}
 evidencePath:=filepath.Join(dir,"c-evidence.json")
 marker:=[]byte("existing-evidence-must-not-be-overwritten")
 if err=save(evidencePath,marker);err!=nil{t.Fatal(err)}
 for _,command:=range []string{"issue","recover"}{t.Run(command,func(t *testing.T){var op operatorConfig;if err=json.Unmarshal(original,&op);err!=nil{t.Fatal(err)};if command=="issue"{op.EvidenceKeyFile="recovery.key"}else{op.RecoveryKeyFile="evidence.key"};if err=saveJSON(path,op);err!=nil{t.Fatal(err)};if err=operate(command,[]string{"-operator",path});err==nil{t.Fatal("wrong purpose operator signer accepted")};after,err:=os.ReadFile(evidencePath);if err!=nil{t.Fatal(err)};if string(after)!=string(marker){t.Fatal("invalid operator key replaced evidence")}})}
}

func expiredInternalCertificate(t *testing.T,dir string) string {
 t.Helper()
 caBytes,err:=os.ReadFile(filepath.Join(dir,"dev-ca.pem"));if err!=nil{t.Fatal(err)};caBlock,_:=pem.Decode(caBytes);ca,err:=x509.ParseCertificate(caBlock.Bytes);if err!=nil{t.Fatal(err)}
 keyBytes,err:=os.ReadFile(filepath.Join(dir,"operator","dev-ca.key"));if err!=nil{t.Fatal(err)};keyBlock,_:=pem.Decode(keyBytes);key,err:=x509.ParsePKCS8PrivateKey(keyBlock.Bytes);if err!=nil{t.Fatal(err)}
 leafBytes,err:=os.ReadFile(filepath.Join(dir,"c-internal.pem"));if err!=nil{t.Fatal(err)};leafBlock,_:=pem.Decode(leafBytes);leaf,err:=x509.ParseCertificate(leafBlock.Bytes);if err!=nil{t.Fatal(err)}
 leaf.NotBefore=time.Now().Add(-2*time.Hour);leaf.NotAfter=time.Now().Add(-time.Hour)
 der,err:=x509.CreateCertificate(rand.Reader,leaf,ca,leaf.PublicKey,key);if err!=nil{t.Fatal(err)}
 path:=filepath.Join(dir,"expired-c-internal.pem");if err=save(path,pem.EncodeToMemory(&pem.Block{Type:"CERTIFICATE",Bytes:der}));err!=nil{t.Fatal(err)};return path
}
