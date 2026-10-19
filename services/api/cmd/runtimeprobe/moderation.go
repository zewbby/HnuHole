package main

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
)

// Existing main 0015 facts only: no administrator, decision, sanction or new
// business behavior. These synthetic facts must survive the real backup.
type moderationProbeState struct {
	RequestID      string `json:"requestId"`
	CaseID         string `json:"caseId"`
	PostID         string `json:"postId"`
	NotificationID string `json:"notificationId"`
	ReadAt         string `json:"readAt"`
}

const syntheticReport = "隔离预发布合成举报"

func (p *probe) moderationFacts(ctx context.Context, s *state) error {
	if s.Images == nil || s.Moderation != nil {
		return errors.New("moderation fixture requires its existing image post and no prior report")
	}
	id, err := uuid.NewRandom()
	if err != nil {
		return err
	}
	headers := map[string]string{"Authorization": "Bearer " + s.Token}
	path := "/api/v1/reports/" + id.String()
	absent, _, err := p.request(ctx, "GET", p.c, path, nil, headers, 200)
	if err != nil || absent["state"] != "NOT_SUBMITTED" {
		return errors.New("synthetic report request fence missing")
	}
	retry, err := field(absent, "retryToken")
	if err != nil {
		return err
	}
	input := map[string]any{"postId": s.Images.PostID, "reason": "OTHER", "description": syntheticReport, "images": []any{}, "retryToken": retry}
	result, _, err := p.request(ctx, "PUT", p.c, path, input, headers, 200)
	if err != nil || result["state"] != "SUBMITTED" {
		return errors.New("synthetic report was not submitted")
	}
	report, ok := result["report"].(map[string]any)
	if !ok {
		return errors.New("synthetic report shape invalid")
	}
	caseID, err := field(report, "caseId")
	if err != nil {
		return err
	}
	s.Moderation = &moderationProbeState{RequestID: id.String(), CaseID: caseID, PostID: s.Images.PostID}
	page, _, err := p.request(ctx, "GET", p.c, "/api/v1/system-notifications", nil, headers, 200)
	if err != nil {
		return err
	}
	items, ok := page["items"].([]any)
	if !ok || len(items) != 1 {
		return errors.New("synthetic report notification missing")
	}
	notice, ok := items[0].(map[string]any)
	if !ok || notice["kind"] != "REPORT_PROGRESS" || notice["readAt"] != nil {
		return errors.New("synthetic report notification state invalid")
	}
	s.Moderation.NotificationID, err = field(notice, "id")
	if err != nil {
		return err
	}
	notice, _, err = p.request(ctx, "POST", p.c, "/api/v1/system-notifications/"+s.Moderation.NotificationID+"/read", map[string]any{}, headers, 200)
	if err != nil {
		return err
	}
	s.Moderation.ReadAt, err = field(notice, "readAt")
	if err != nil {
		return err
	}
	if _, err = time.Parse(time.RFC3339Nano, s.Moderation.ReadAt); err != nil {
		return errors.New("notification read time invalid")
	}
	return p.moderationSnapshot(ctx, *s)
}

func (p *probe) moderationSnapshot(ctx context.Context, s state) error {
	if s.Moderation == nil {
		return errors.New("moderation snapshot not initialized")
	}
	m := s.Moderation
	headers := map[string]string{"Authorization": "Bearer " + s.Token}
	result, _, err := p.request(ctx, "GET", p.c, "/api/v1/reports/"+m.RequestID, nil, headers, 200)
	if err != nil || result["state"] != "SUBMITTED" {
		return errors.New("original synthetic report unavailable")
	}
	report, ok := result["report"].(map[string]any)
	if !ok || report["id"] != m.RequestID || report["caseId"] != m.CaseID || report["postId"] != m.PostID ||
		report["state"] != "PENDING" || report["reason"] != "OTHER" || report["description"] != syntheticReport {
		return errors.New("original synthetic report facts changed")
	}
	notice, _, err := p.request(ctx, "GET", p.c, "/api/v1/system-notifications/"+m.NotificationID, nil, headers, 200)
	if err != nil || notice["id"] != m.NotificationID || notice["kind"] != "REPORT_PROGRESS" || notice["readAt"] != m.ReadAt {
		return errors.New("original notification or read status changed")
	}
	route, ok := notice["route"].(map[string]any)
	if !ok || route["name"] != "REPORT" || route["resourceId"] != m.RequestID {
		return errors.New("original notification route changed")
	}
	return nil
}

func (p *probe) moderationGateRead(ctx context.Context, s state, want int) error {
	if s.Moderation == nil {
		return nil
	}
	headers := map[string]string{"Authorization": "Bearer " + s.Token}
	for _, path := range []string{"/api/v1/reports/" + s.Moderation.RequestID, "/api/v1/system-notifications/" + s.Moderation.NotificationID} {
		if _, _, err := p.request(ctx, "GET", p.c, path, nil, headers, want); err != nil {
			return err
		}
	}
	return nil
}
