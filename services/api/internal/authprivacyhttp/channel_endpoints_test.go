package authprivacyhttp

import (
    "context"
    "errors"
    "fmt"
    "strings"
    "sync"
    "testing"
    "time"

    "github.com/google/uuid"
    "github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
    "github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/channels"
)

type httpTestDirectory struct {
    mu sync.Mutex
    calls int
    result authprivacy.ChannelDirectory
    err error
}
func (d *httpTestDirectory) ListAuthorizedChannels(context.Context,[32]byte)(authprivacy.ChannelDirectory,error) {
    d.mu.Lock()
    defer d.mu.Unlock()
    d.calls++
    return d.result,d.err
}
func (d *httpTestDirectory) callCount() int {
    d.mu.Lock()
    defer d.mu.Unlock()
    return d.calls
}
func (d *httpTestDirectory) setError(err error) {
    d.mu.Lock()
    defer d.mu.Unlock()
    d.err = err
}
func httpTestCatalog() []channels.Channel {
    codes:=[]string{"vent","warning","recommendation","buddy","emotion","mutual_help","technology"}
    names:=[]string{"吐槽","避雷","安利","搭子","情感","互助","科技"}
    items:=make([]channels.Channel,7)
    for i:=range items {
        items[i]=channels.Channel{ID:uuid.MustParse(fmt.Sprintf("5f6f4f88-8f64-4bb2-9d34-%012d",i+1)),Code:codes[i],Name:names[i],InitiallyVisible:i<5,DisplayOrder:10*(i+1)}
    }
    return items
}
func TestDirectoryHTTPSContractAndCanonicalCapabilities(t *testing.T) {
    pki:=newHTTPTestPKI(t)
    community:=&httpTestCommunity{}
    directory:=&httpTestDirectory{result:authprivacy.ChannelDirectory{Channels:httpTestCatalog(),ExpiresAt:time.Now().UTC().Add(30*24*time.Hour)}}
    endpoints,err:=NewCommunityEndpoints(CommunityOptions{Backend:community,Channels:directory,
        Passwords:httpTestPasswords{backend:community},InternalPeer:PeerIdentity{Environment:"lab",Service:VerifierService,Roots:pki.roots},
        AllowedOrigins:[]string{"https://127.0.0.1:8443"},Limits:httpTestLimits()})
    if err!=nil {t.Fatal(err)}
    server,client:=httpTestPublicServer(t,endpoints.Public,pki,CommunityService)
    token:=httpTestEncoding(32,8)
    for _,tc:=range []struct{path,method,authorization string;status int}{
        {"/api/v1/channels","GET","",401},
        {"/api/v1/channels","GET","SessionRevoke "+token,401},
        {"/api/v1/channels","GET","Bearer "+token+"=",400},
        {"/api/v1/channels?ignored=true","GET","Bearer "+token,400},
        {"/api/v1/channels","POST","Bearer "+token,405},
    } {
        headers:=map[string][]string{}
        if tc.authorization!="" {headers["Authorization"]=[]string{tc.authorization}}
        response,body,_:=doHTTPTest(t,client,tc.method,server.URL+tc.path,"",headers)
        if response.StatusCode!=tc.status || body["requestId"]!=response.Header.Get("X-Request-ID") || response.Header.Get("Cache-Control")!="no-store" {
            t.Fatalf("%s boundary response: %d",tc.path,response.StatusCode)
        }
    }
    if directory.callCount()!=0 {t.Fatal("malformed capability reached directory transaction")}
    response,body,_:=doHTTPTest(t,client,"GET",server.URL+"/api/v1/channels","",map[string][]string{"Authorization":{"Bearer "+token},"X-Request-ID":{"client-controlled"}})
    if response.StatusCode!=200 || response.Header.Get("Session-Expires-At")!=utc(directory.result.ExpiresAt) || response.Header.Get("X-Request-ID")=="client-controlled" {
        t.Fatal("committed directory omitted authoritative metadata")
    }
    items,ok:=body["channels"].([]any)
    if !ok || len(items)!=7 || len(body)!=1 {t.Fatal("directory public shape changed")}
    first,ok:=items[0].(map[string]any)
    if !ok || len(first)!=5 || first["code"]!="vent" || first["initiallyVisible"]!=true {t.Fatal("directory exposed domain or auth fields")}
    for _,tc:=range []struct{err error;status int;code string}{
        {authprivacy.ErrAuthorizationUnavailable,503,"SERVICE_UNAVAILABLE"},
        {authprivacy.ErrChannelDirectoryUnavailable,503,"CHANNEL_DIRECTORY_UNAVAILABLE"},
        {authprivacy.ErrSessionInvalid,401,"SESSION_INVALID"},
        {authprivacy.ErrSessionReplaced,401,"session_replaced"},
        {errors.New("SQL internal secret"),503,"SERVICE_UNAVAILABLE"},
    } {
        directory.setError(tc.err)
        response,body,raw:=doHTTPTest(t,client,"GET",server.URL+"/api/v1/channels","",map[string][]string{"Authorization":{"Bearer "+token}})
        code:=body["error"].(map[string]any)["code"]
        if response.StatusCode!=tc.status || code!=tc.code || strings.Contains(raw,"SQL internal secret") || response.Header.Get("Session-Expires-At")!="" {
            t.Fatalf("failed directory response leaked metadata or wrong code: %s",raw)
        }
    }
    response,_,_ = doHTTPTest(t,client,"OPTIONS",server.URL+"/api/v1/channels","",map[string][]string{"Origin":{"https://127.0.0.1:8443"},"Access-Control-Request-Method":{"GET"},"Access-Control-Request-Headers":{"authorization"}})
    if response.StatusCode!=204 || !strings.Contains(response.Header.Get("Access-Control-Expose-Headers"),"Session-Expires-At") {t.Fatal("directory preflight did not expose renewal metadata")}
}

func TestRealHTTPSDirectoryUsesCommunitySessionsAndGatePostgres(t *testing.T) {
    s:=e2eNewServices(t)
    token,_:=e2eCredentialSignup(t,s)
    headers:=map[string]string{"Authorization":"Bearer "+token}
    body:=e2eJSON(t,s.client,"GET",s.cPublic.URL+"/api/v1/channels",nil,headers,200)
    if items,ok:=body["channels"].([]any); !ok || len(items)!=7 {t.Fatal("real authenticated catalog incomplete")}
    if err:=s.gate.Freeze(context.Background(),"real catalog freeze");err!=nil {t.Fatal(err)}
    body=e2eJSON(t,s.client,"GET",s.cPublic.URL+"/api/v1/channels",nil,headers,503)
    if body["error"].(map[string]any)["code"]!="SERVICE_UNAVAILABLE" {t.Fatal("frozen directory returned a different backend error")}
    if err:=s.recoverC();err!=nil {t.Fatal(err)}
    e2eJSON(t,s.client,"GET",s.cPublic.URL+"/api/v1/channels",nil,headers,401)
}
