// Package moderation defines privacy-safe report and notification DTOs.
package moderation

import (
 "crypto/sha256"
 "encoding/base64"
 "encoding/hex"
 "encoding/json"
 "errors"
 "strings"
 "time"
 "unicode/utf8"

 "github.com/google/uuid"
)

var ErrInvalid = errors.New("invalid moderation input")
const MaxImageBytes = 2*1024*1024
const MaxBatchBytes = 8*1024*1024
type Image struct { MIME string `json:"mime"`; Base64 string `json:"base64"` }
type Material struct { Description string `json:"description"`; Images []Image `json:"images"`; CreatedAt time.Time `json:"createdAt,omitempty"` }
type ReportInput struct { PostID string `json:"postId"`; IdentityID *string `json:"identityId"`; Reason string `json:"reason"`; Description string `json:"description"`; Images []Image `json:"images"` }
type Decision struct { CommandID string `json:"commandId"`; ExpectedVersion int64 `json:"expectedVersion"`; Action string `json:"action"`; Days int `json:"days"`; Reason string `json:"reason"`; Accept bool `json:"accept"`; Role string `json:"role"` }
func ValidID(s string) bool { id,e:=uuid.Parse(s); return e==nil && id!=uuid.Nil && id.String()==s }
func ValidReason(s string) bool { switch s {case "ADVERTISING","HARASSMENT","PRIVACY","FRAUD","ILLEGAL","OTHER":return true};return false }
func Text(s string,n int) bool { return utf8.ValidString(s) && utf8.RuneCountInString(s)<=n && !strings.ContainsRune(s,0) }
func Images(items []Image,max int)([][]byte,error) {
 if len(items)>max{return nil,ErrInvalid};total:=0;out:=make([][]byte,0,len(items))
 for _,i:=range items { switch i.MIME {case "image/png","image/jpeg","image/gif","image/webp":default:return nil,ErrInvalid};if len(i.Base64)>base64.StdEncoding.EncodedLen(MaxImageBytes){return nil,ErrInvalid}; b,e:=base64.StdEncoding.Strict().DecodeString(i.Base64);if e!=nil || len(b)==0 || len(b)>MaxImageBytes || base64.StdEncoding.EncodeToString(b)!=i.Base64{return nil,ErrInvalid};total+=len(b);if total>MaxBatchBytes{return nil,ErrInvalid};out=append(out,b) };return out,nil
}
func (r ReportInput) Validate()error { if !ValidID(r.PostID)||r.IdentityID!=nil&&!ValidID(*r.IdentityID)||!ValidReason(r.Reason)||!Text(r.Description,200){return ErrInvalid};_,e:=Images(r.Images,6);return e }
func (m Material) Validate(max int)error {if !Text(m.Description,500)||strings.TrimSpace(m.Description)==""&&len(m.Images)==0{return ErrInvalid};_,e:=Images(m.Images,max);return e}
func (d Decision) Validate()error {if !ValidID(d.CommandID)||d.ExpectedVersion<1||!Text(d.Reason,500)||strings.TrimSpace(d.Reason)==""{return ErrInvalid};switch d.Action {case "DISMISS","TAKEDOWN","RESET_NICKNAME","RESET_AVATAR":if d.Days!=0{return ErrInvalid};case "MUTE","BAN":if d.Days!=1&&d.Days!=3&&d.Days!=7&&d.Days!=30&&!(d.Action=="BAN"&&d.Days==0){return ErrInvalid};default:return ErrInvalid};return nil}
func Fingerprint(v any)string { b,_:=json.Marshal(v);h:=sha256.Sum256(b);return hex.EncodeToString(h[:]) }
type Report struct { ID string `json:"id"`; CaseID string `json:"caseId"`; State string `json:"state"`; PostID string `json:"postId"`; Reason string `json:"reason"`; Description string `json:"description"`; CreatedAt time.Time `json:"createdAt"`; Outcome string `json:"outcome"`; Explanation string `json:"explanation"` }
type ReportResult struct { State string `json:"state"`; Report *Report `json:"report,omitempty"` }
type Route struct { Name string `json:"name"`; ResourceID string `json:"resourceId"` }
type Notification struct { ID string `json:"id"`; EventID string `json:"eventId"`; Source string `json:"source"`; Scope string `json:"scope"`; IdentityID *string `json:"identityId,omitempty"`; Kind string `json:"kind"`; State string `json:"state"`; Title string `json:"title"`; Body string `json:"body"`; CreatedAt time.Time `json:"createdAt"`; ReadAt *time.Time `json:"readAt"`; Route Route `json:"route"` }
type NotificationPage struct { Items []Notification `json:"items"`; NextBefore *string `json:"nextBefore"` }
type Evidence struct { Title string `json:"title"`; Body string `json:"body"`; Images []Image `json:"images"` }
type Case struct { ID string `json:"id"`; Number string `json:"number"`; PostID string `json:"postId"`; Reason string `json:"reason"`; State string `json:"state"`; Version int64 `json:"version"`; CreatedAt time.Time `json:"createdAt"`; PlatformNumber string `json:"platformNumber"`; Outcome string `json:"outcome"`; Explanation string `json:"explanation"`; Evidence *Evidence `json:"evidence,omitempty"`; Reports []Material `json:"reports,omitempty"`; Sanctions []Sanction `json:"sanctions,omitempty"` }
type Sanction struct { ID string `json:"id"`; CaseID string `json:"caseId"`; Action string `json:"action"`; Reason string `json:"reason"`; StartsAt time.Time `json:"startsAt"`; EndsAt *time.Time `json:"endsAt"`; RevokedAt *time.Time `json:"revokedAt"`; PostID string `json:"postId"`; AppealCount int `json:"appealCount"`; ActiveAppealID *string `json:"activeAppealId"` }
type Appeal struct { ID string `json:"id"`; SanctionID string `json:"sanctionId"`; CaseID string `json:"caseId"`; State string `json:"state"`; Ordinal int `json:"ordinal"`; Version int64 `json:"version"`; Reason string `json:"reason"`; PlatformNumber string `json:"platformNumber,omitempty"`; OriginalActorNumber string `json:"originalActorNumber,omitempty"`; Action string `json:"action,omitempty"`; Materials []Material `json:"materials"` }
type AppealResult struct { State string `json:"state"`; Appeal *Appeal `json:"appeal,omitempty"` }
