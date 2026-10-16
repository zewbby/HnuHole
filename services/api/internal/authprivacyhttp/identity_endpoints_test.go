package authprivacyhttp

import (
    "context"
    "errors"
    "net/http"
    "strings"
    "sync"
    "testing"
    "time"

    "github.com/google/uuid"
    "github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
)

type httpIdentityBackend struct {
    mu sync.Mutex
    calls int
    request authprivacy.IdentityChangeRequest
    directory authprivacy.IdentityDirectory
    result authprivacy.IdentityChangeResult
    err error
}
func (f *httpIdentityBackend) ListOwnIdentities(context.Context, [32]byte) (authprivacy.IdentityDirectory, error) {
    f.mu.Lock(); defer f.mu.Unlock(); f.calls++; return f.directory, f.err
}
func (f *httpIdentityBackend) ChangeOwnIdentity(_ context.Context, r authprivacy.IdentityChangeRequest) (authprivacy.IdentityChangeResult, error) {
    f.mu.Lock(); defer f.mu.Unlock(); f.calls++; f.request = r; return f.result, f.err
}
func (f *httpIdentityBackend) GetIdentityChangeResult(context.Context, [32]byte, [16]byte) (authprivacy.IdentityChangeResult, error) {
    f.mu.Lock(); defer f.mu.Unlock(); f.calls++; return f.result, f.err
}
func (f *httpIdentityBackend) count() int { f.mu.Lock(); defer f.mu.Unlock(); return f.calls }
func (f *httpIdentityBackend) setError(err error) { f.mu.Lock(); defer f.mu.Unlock(); f.err = err }
func (f *httpIdentityBackend) setResult(result authprivacy.IdentityChangeResult) { f.mu.Lock(); defer f.mu.Unlock(); f.result = result }

func TestIdentityHTTPSBoundaryAndPrivateResponse(t *testing.T) {
    pki := newHTTPTestPKI(t)
    community := &httpTestCommunity{}
    now := time.Now().UTC()
    id := uuid.New()
    backend := &httpIdentityBackend{
        directory: authprivacy.IdentityDirectory{Identities: []authprivacy.OwnIdentity{{ID:id,Nickname:"海风",Avatar:"default-v1",IsOriginal:true,CreatedAt:now}},CreatedCount:1,ServerTime:now,ExpiresAt:now.Add(24*time.Hour)},
        result: authprivacy.IdentityChangeResult{State:"COMMITTED",Operation:"CREATE",IdentityID:id,ExpiresAt:now.Add(24*time.Hour)},
    }
    endpoints,err := NewCommunityEndpoints(CommunityOptions{Backend:community,Identities:backend,Passwords:httpTestPasswords{backend:community},InternalPeer:PeerIdentity{Environment:"lab",Service:VerifierService,Roots:pki.roots},AllowedOrigins:[]string{"https://app.invalid"},Limits:httpTestLimits()})
    if err != nil { t.Fatal(err) }
    server,client := httpTestPublicServer(t,endpoints.Public,pki,CommunityService)
    token,key := httpTestEncoding(32,8),httpTestEncoding(16,5)
    for _,tc := range []struct{ method,path,body string; headers map[string][]string; status int }{
        {"GET",identitiesPath,"",nil,401},
        {"GET",identitiesPath,"",map[string][]string{"Authorization":{"Bearer "+token+"="}},400},
        {"GET",identitiesPath+"?x=y","",map[string][]string{"Authorization":{"Bearer "+token}},400},
        {"GET",identitiesPath,"",map[string][]string{"Authorization":{"Bearer "+token},"Idempotency-Key":{key}},400},
        {"POST",identitiesPath,`{"nickname":"海风"}`,map[string][]string{"Authorization":{"Bearer "+token}},400},
        {"POST",identitiesPath,`{"nickname":"海风","nickname":"南风"}`,map[string][]string{"Authorization":{"Bearer "+token},"Idempotency-Key":{key},"Content-Type":{"application/json"}},400},
        {"POST",identitiesPath,`{"nickname":"海风","avatar":"external"}`,map[string][]string{"Authorization":{"Bearer "+token},"Idempotency-Key":{key},"Content-Type":{"application/json"}},400},
        {"POST",identitiesPath,`{"nickname":"海风"}`,map[string][]string{"Authorization":{"Bearer "+token},"Idempotency-Key":{key,key},"Content-Type":{"application/json"}},400},
        {"DELETE",identitiesPath+"/"+id.String(),`{}`,map[string][]string{"Authorization":{"Bearer "+token},"Idempotency-Key":{key}},400},
        {"PATCH",identitiesPath+"/not-a-uuid",`{"nickname":"海风"}`,map[string][]string{"Authorization":{"Bearer "+token},"Idempotency-Key":{key},"Content-Type":{"application/json"}},400},
        {"PUT",identitiesPath+"/"+id.String(),"",map[string][]string{"Authorization":{"Bearer "+token}},405},
        {"GET",identityResultPath,"",map[string][]string{"Authorization":{"Bearer "+token}},400},
    } {
        response,body,_ := doHTTPTest(t,client,tc.method,server.URL+tc.path,tc.body,tc.headers)
        if response.StatusCode != tc.status || body["requestId"] != response.Header.Get("X-Request-ID") || response.Header.Get("Cache-Control") != "no-store" { t.Fatalf("%s %s returned %d",tc.method,tc.path,response.StatusCode) }
    }
    if backend.count()!=0 { t.Fatal("malformed identity request reached authority") }
    response,body,_ := doHTTPTest(t,client,"GET",server.URL+identitiesPath,"",map[string][]string{"Authorization":{"Bearer "+token}})
    items,ok := body["identities"].([]any)
    if response.StatusCode!=200 || len(body)!=4 || !ok || len(items)!=1 || response.Header.Get("Session-Expires-At")!=utc(backend.directory.ExpiresAt) { t.Fatal("owned directory contract") }
    if item:=items[0].(map[string]any); len(item)!=6 || item["nickname"]!="海风" || item["avatar"]!="default-v1" || item["renameAvailableAt"]!=nil { t.Fatal("public identity fields leaked or changed") }
    response,body,_ = doHTTPTest(t,client,"POST",server.URL+identitiesPath,`{"nickname":"海风"}`,map[string][]string{"Authorization":{"Bearer "+token},"Idempotency-Key":{key},"Content-Type":{"application/json"}})
    if response.StatusCode!=200 || len(body)!=4 || body["identityId"]!=id.String() || body["operation"]!="CREATE" || body["errorCode"]!=nil { t.Fatal("committed change contract") }
    for _,tc := range []struct{err error;status int;code string}{
        {authprivacy.ErrIdentityInvalidName,400,"IDENTITY_INVALID_NAME"},
        {authprivacy.ErrIdentityDuplicateName,409,"IDENTITY_DUPLICATE_NAME"},
        {authprivacy.ErrIdentityLimit,409,"IDENTITY_LIMIT"},
        {authprivacy.ErrIdentityCreateCooldown,409,"IDENTITY_CREATE_COOLDOWN"},
        {authprivacy.ErrIdentityRenameCooldown,409,"IDENTITY_RENAME_COOLDOWN"},
        {authprivacy.ErrIdentityLast,409,"IDENTITY_LAST_REQUIRED"},
        {authprivacy.ErrIdentityNotFound,404,"IDENTITY_NOT_FOUND"},
        {authprivacy.ErrIdentityChangeConflict,409,"IDENTITY_CHANGE_CONFLICT"},
        {authprivacy.ErrSessionInvalid,401,"SESSION_INVALID"},
        {authprivacy.ErrSessionReplaced,401,"session_replaced"},
        {authprivacy.ErrAuthorizationUnavailable,503,"SERVICE_UNAVAILABLE"},
        {errors.New("private SQL detail"),503,"SERVICE_UNAVAILABLE"},
    } {
        backend.setError(tc.err)
        response,body,raw := doHTTPTest(t,client,"GET",server.URL+identitiesPath,"",map[string][]string{"Authorization":{"Bearer "+token}})
        if response.StatusCode!=tc.status || body["error"].(map[string]any)["code"]!=tc.code || response.Header.Get("Session-Expires-At")!="" || strings.Contains(raw,"private SQL detail") { t.Fatalf("identity error boundary: %s",raw) }
    }
    for _,tc := range []struct{path,method string}{ {identitiesPath,"GET"},{identitiesPath,"POST"},{identitiesPath+"/"+id.String(),"PATCH"},{identitiesPath+"/"+id.String(),"DELETE"},{identityResultPath,"GET"} } {
        response,_,_ := doHTTPTest(t,client,"OPTIONS",server.URL+tc.path,"",map[string][]string{"Origin":{"https://app.invalid"},"Access-Control-Request-Method":{tc.method},"Access-Control-Request-Headers":{"authorization, idempotency-key"}})
        if response.StatusCode!=204 { t.Fatalf("identity preflight %s",tc.method) }
    }
    backend.setError(nil)
    backend.setResult(authprivacy.IdentityChangeResult{State:"REJECTED",Operation:"CREATE",ErrorCode:"IDENTITY_LIMIT",ExpiresAt:now.Add(24*time.Hour)})
    response,body,_ = doHTTPTest(t,client,"GET",server.URL+identityResultPath,"",map[string][]string{"Authorization":{"Bearer "+token},"Idempotency-Key":{key}})
    if response.StatusCode!=200 || body["state"]!="REJECTED" || body["operation"]!="CREATE" || body["identityId"]!=nil || body["errorCode"]!="IDENTITY_LIMIT" { t.Fatal("terminal rejection receipt contract") }
    response,body,_ = doHTTPTest(t,client,"POST",server.URL+identitiesPath,`{"nickname":"海风"}`,map[string][]string{"Authorization":{"Bearer "+token},"Idempotency-Key":{key},"Content-Type":{"application/json"}})
    if response.StatusCode!=409 || body["error"].(map[string]any)["code"]!="IDENTITY_LIMIT" || response.Header.Get("Session-Expires-At")!="" { t.Fatal("terminal rejected mutation contract") }
    backend.setResult(authprivacy.IdentityChangeResult{State:"NOT_FOUND",ExpiresAt:now.Add(24*time.Hour)})
    response,body,_ = doHTTPTest(t,client,"GET",server.URL+identityResultPath,"",map[string][]string{"Authorization":{"Bearer "+token},"Idempotency-Key":{key}})
    if response.StatusCode!=200 || body["state"]!="NOT_FOUND" || body["operation"]!=nil || body["identityId"]!=nil { t.Fatal("absence must be an explicit query snapshot") }
    // An absence is never a successful mutation response.
    response,_,_ = doHTTPTest(t,client,"POST",server.URL+identitiesPath,`{"nickname":"海风"}`,map[string][]string{"Authorization":{"Bearer "+token},"Idempotency-Key":{key},"Content-Type":{"application/json"}})
    if response.StatusCode!=503 || response.Header.Get("Session-Expires-At")!="" { t.Fatal("invalid mutation outcome published") }
    for _,operation := range []string{"RENAME","DELETE"} {
        backend.setResult(authprivacy.IdentityChangeResult{State:"COMMITTED",Operation:operation,IdentityID:id,ExpiresAt:now.Add(24*time.Hour)})
        method,input := http.MethodDelete,""
        if operation=="RENAME" { method,input=http.MethodPatch,`{"nickname":"南风"}` }
        response,body,_ = doHTTPTest(t,client,method,server.URL+identitiesPath+"/"+id.String(),input,map[string][]string{"Authorization":{"Bearer "+token},"Idempotency-Key":{key},"Content-Type":{"application/json"}})
        if response.StatusCode!=200 || body["operation"]!=operation || body["identityId"]!=id.String() { t.Fatal("resource mutation contract") }
    }
}

func TestRealHTTPSIdentityManagementPostgres(t *testing.T) {
    s := e2eNewServices(t)
    token,_ := e2eCredentialSignup(t,s)
    headers := map[string]string{"Authorization":"Bearer "+token}
    list := e2eJSON(t,s.client,"GET",s.cPublic.URL+identitiesPath,nil,headers,200)
    if list["createdCount"]!=float64(0) || len(list["identities"].([]any))!=0 { t.Fatal("registration created an identity") }
    // Zero identities retain the channel browsing capability.
    e2eJSON(t,s.client,"GET",s.cPublic.URL+"/api/v1/channels",nil,headers,200)
    firstKey := httpTestEncoding(16,11)
    headers["Idempotency-Key"] = firstKey
    first := e2eJSON(t,s.client,"POST",s.cPublic.URL+identitiesPath,map[string]string{"nickname":"海风"},headers,200)
    replay := e2eJSON(t,s.client,"GET",s.cPublic.URL+identityResultPath,nil,headers,200)
    if replay["state"]!="COMMITTED" || replay["identityId"]!=first["identityId"] { t.Fatal("commit receipt not durable") }
    again := e2eJSON(t,s.client,"POST",s.cPublic.URL+identitiesPath,map[string]string{"nickname":"海风"},headers,200)
    if again["identityId"]!=first["identityId"] { t.Fatal("retry duplicated effect") }
    e2eJSON(t,s.client,"POST",s.cPublic.URL+identitiesPath,map[string]string{"nickname":"南风"},headers,409)
    headers["Idempotency-Key"] = httpTestEncoding(16,12)
    renamed := e2eJSON(t,s.client,"PATCH",s.cPublic.URL+identitiesPath+"/"+first["identityId"].(string),map[string]string{"nickname":"南风"},headers,200)
    if renamed["operation"]!="RENAME" { t.Fatal("rename did not commit") }
    headers["Idempotency-Key"] = httpTestEncoding(16,13)
    e2eJSON(t,s.client,"PATCH",s.cPublic.URL+identitiesPath+"/"+first["identityId"].(string),map[string]string{"nickname":"北风"},headers,409)
    headers["Idempotency-Key"] = httpTestEncoding(16,14)
    e2eJSON(t,s.client,"DELETE",s.cPublic.URL+identitiesPath+"/"+first["identityId"].(string),nil,headers,409)
    rejected := e2eJSON(t,s.client,"GET",s.cPublic.URL+identityResultPath,nil,headers,200)
    if rejected["state"]!="REJECTED" || rejected["errorCode"]!="IDENTITY_LAST_REQUIRED" { t.Fatal("business rejection was not terminalized") }
    headers["Idempotency-Key"] = httpTestEncoding(16,15)
    second := e2eJSON(t,s.client,"POST",s.cPublic.URL+identitiesPath,map[string]string{"nickname":"北风"},headers,200)
    headers["Idempotency-Key"] = httpTestEncoding(16,16)
    e2eJSON(t,s.client,"POST",s.cPublic.URL+identitiesPath,map[string]string{"nickname":"西风"},headers,200)
    headers["Idempotency-Key"] = httpTestEncoding(16,17)
    e2eJSON(t,s.client,"DELETE",s.cPublic.URL+identitiesPath+"/"+second["identityId"].(string),nil,headers,200)
    headers["Idempotency-Key"] = httpTestEncoding(16,18)
    e2eJSON(t,s.client,"POST",s.cPublic.URL+identitiesPath,map[string]string{"nickname":"东风"},headers,409)
    delete(headers,"Idempotency-Key")
    list = e2eJSON(t,s.client,"GET",s.cPublic.URL+identitiesPath,nil,headers,200)
    if list["createdCount"]!=float64(3) || list["nextCreateAt"]==nil || len(list["identities"].([]any))!=2 { t.Fatal("delete reset creation quota") }
    if err:=s.gate.Freeze(context.Background(),"identity freeze");err!=nil { t.Fatal(err) }
    e2eJSON(t,s.client,"GET",s.cPublic.URL+identitiesPath,nil,headers,503)
    if err:=s.recoverC();err!=nil { t.Fatal(err) }
    e2eJSON(t,s.client,"GET",s.cPublic.URL+identitiesPath,nil,headers,401)
}
