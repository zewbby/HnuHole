package main

import (
	"context"
	"encoding/hex"
	"errors"
	"net/http"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/posts"
)

type postProbeState struct {
	CommandKey string `json:"commandKey"`
	TaskID     string `json:"taskId"`
	PostID     string `json:"postId"`
	ChannelID  string `json:"channelId"`
	Title      string `json:"title"`
	Body       string `json:"body"`
}

// 所有发布与核对均通过实际 HTTPS。受限 SQL 仅核验内部唯一性，不代替业务写入。
func (p *probe) posts(ctx context.Context, s *state) error {
	headers := map[string]string{"Authorization": "Bearer " + s.Token}
	directory, _, err := p.request(ctx, "GET", p.c, "/api/v1/channels", nil, headers, 200)
	if err != nil {
		return err
	}
	channels, ok := directory["channels"].([]any)
	if !ok || len(channels) == 0 {
		return errors.New("post probe channel directory absent")
	}
	channel, ok := channels[0].(map[string]any)
	if !ok {
		return errors.New("post probe channel shape invalid")
	}
	channelID, err := field(channel, "id")
	if err != nil {
		return err
	}
	// 通道 UUID 合法但资源不存在：读取应返回固定 404，不能误投影为 CREATE 的 409 或 503。
	missing, missingHeaders, err := p.request(ctx, "GET", p.c, "/api/v1/channels/ffffffff-ffff-4fff-8fff-ffffffffffff/posts", nil, headers, 404)
	if err != nil {
		return err
	}
	publicError, ok := missing["error"].(map[string]any)
	if !ok || len(missing) != 2 || len(publicError) != 2 || publicError["code"] != "POST_CHANNEL_UNAVAILABLE" ||
		publicError["message"] != "请求未能完成，请按原操作核对或重试。" || missing["requestId"] != missingHeaders.Get("X-Request-ID") ||
		missingHeaders.Get("Session-Expires-At") != "" || missingHeaders.Get("Server-Time") != "" {
		return errors.New("missing channel exposed private fields or wrong public error projection")
	}
	contextBody, _, err := p.request(ctx, "GET", p.c, "/api/v1/me/post-composer-context", nil, headers, 200)
	if err != nil || contextBody["selectionState"] != "DEFAULT_AVAILABLE" || contextBody["defaultIdentityId"] != s.IdentityID {
		return errors.New("post composer lost original active default identity")
	}

	command, err := randomCapability(16)
	if err != nil {
		return err
	}
	commandPath := "/api/v1/post-commands/" + command
	unknown, h, err := p.request(ctx, "GET", p.c, commandPath, nil, headers, 200)
	if err != nil || len(unknown) != 1 || unknown["state"] != "UNKNOWN_NOT_OBSERVED" || checkPostTimes(h) != nil {
		return errors.New("unobserved post command result or timestamps invalid")
	}
	intent := posts.Intent{Operation: posts.Create, ChannelID: channelID, IdentityID: s.IdentityID, Title: "海风👩‍👩‍👧‍👦", Body: "第一行\r\n第二行 e\u0301 🇨🇳"}
	input := posts.CreatePostInput{ChannelID: channelID, IdentityID: s.IdentityID, Title: intent.Title, Body: intent.Body}
	accepted, h, err := p.request(ctx, "PUT", p.c, commandPath, input, headers, 202)
	if err != nil {
		return err
	}
	if err != nil || accepted["state"] != "ACCEPTED" || accepted["operation"] != "CREATE" || accepted["attemptVersion"] != float64(1) || len(accepted) != 5 || checkPostTimes(h) != nil {
		return errors.New("post command did not persist strict accepted result")
	}
	taskID, err := field(accepted, "taskId")
	if err != nil {
		return err
	}
	postID, err := field(accepted, "postId")
	if err != nil {
		return err
	}
	s.Posts = &postProbeState{CommandKey: command, TaskID: taskID, PostID: postID, ChannelID: channelID, Title: intent.Title, Body: intent.Body}
	replay, _, err := p.request(ctx, "PUT", p.c, commandPath, input, headers, 202)
	if err != nil {
		return err
	}
	if err != nil || replay["taskId"] != taskID || replay["postId"] != postID {
		return errors.New("runtime replay changed accepted post binding")
	}
	input.Title = "换文字"
	if _, h, err = p.request(ctx, "PUT", p.c, commandPath, input, headers, 409); err != nil || h.Get("Session-Expires-At") != "" {
		return errors.New("conflicting post command was not rejected without renewal")
	}
	if err = p.waitPostPublished(ctx, *s); err != nil {
		return err
	}
	if err = p.postsRestart(ctx, *s); err != nil {
		return err
	}

	// 已公开时取消返回既成 PUBLISHED，不能把公开成功改写成取消或失败。
	cancelKey, err := randomCapability(16)
	if err != nil {
		return err
	}
	mutationHeaders := map[string]string{"Authorization": "Bearer " + s.Token, "Idempotency-Key": cancelKey}
	cancelled, _, err := p.request(ctx, "POST", p.c, "/api/v1/me/post-tasks/"+taskID+"/cancel", posts.AttemptVersionInput{ExpectedAttemptVersion: 1}, mutationHeaders, 200)
	if err != nil || cancelled["state"] != "COMMITTED" || cancelled["taskState"] != "PUBLISHED" {
		return errors.New("published post was rewritten by late cancellation")
	}

	// UNKNOWN 封印后，同一原意图的迟到 PUT 永远不能创建新任务。
	sealKey, err := randomCapability(16)
	if err != nil {
		return err
	}
	digest, err := posts.RequestDigest(intent)
	if err != nil {
		return err
	}
	sealPath := "/api/v1/post-commands/" + sealKey
	sealed, _, err := p.request(ctx, "POST", p.c, sealPath+"/seal", posts.SealInput{Operation: posts.Create, RequestDigest: hex.EncodeToString(digest[:])}, headers, 200)
	if err != nil || sealed["state"] != "NOT_ACCEPTED" || sealed["reason"] != "COMMAND_SEALED" {
		return errors.New("unknown post command was not sealed")
	}
	input.Title = intent.Title
	if _, _, err = p.request(ctx, "PUT", p.c, sealPath, input, headers, 409); err != nil {
		return err
	}
	sealed, _, err = p.request(ctx, "GET", p.c, sealPath, nil, headers, 200)
	if err != nil || sealed["state"] != "NOT_ACCEPTED" {
		return errors.New("sealed command lost its immutable tombstone")
	}

	// 业务无效文字形成拒绝回执；调用不能从错误响应推断会话续期。
	rejectKey, err := randomCapability(16)
	if err != nil {
		return err
	}
	input.Title = ""
	if _, h, err = p.request(ctx, "PUT", p.c, "/api/v1/post-commands/"+rejectKey, input, headers, 400); err != nil || h.Get("Session-Expires-At") != "" {
		return errors.New("invalid post content did not reject without renewal")
	}
	rejected, _, err := p.request(ctx, "GET", p.c, "/api/v1/post-commands/"+rejectKey, nil, headers, 200)
	if err != nil || rejected["state"] != "REJECTED" || rejected["errorCode"] != "POST_CONTENT_INVALID" {
		return errors.New("post content rejection left no durable original result")
	}
	return p.postDeleteRoundTrip(ctx, *s)
}

func (p *probe) postDeleteRoundTrip(ctx context.Context, s state) error {
	key, err := randomCapability(16)
	if err != nil {
		return err
	}
	headers := map[string]string{"Authorization": "Bearer " + s.Token}
	accepted, _, err := p.request(ctx, "PUT", p.c, "/api/v1/post-commands/"+key,
		posts.CreatePostInput{ChannelID: s.Posts.ChannelID, IdentityID: s.IdentityID, Title: "删除验证", Body: "仅本次隔离环境的合成帖子"}, headers, 202)
	if err != nil {
		return err
	}
	taskID, err := field(accepted, "taskId")
	if err != nil {
		return err
	}
	postID, err := field(accepted, "postId")
	if err != nil {
		return err
	}
	probeState := s
	probeState.Posts = &postProbeState{TaskID: taskID, PostID: postID}
	if err = p.waitPostPublished(ctx, probeState); err != nil {
		return err
	}
	deleteKey, err := randomCapability(16)
	if err != nil {
		return err
	}
	headers["Idempotency-Key"] = deleteKey
	deleted, _, err := p.request(ctx, "POST", p.c, "/api/v1/posts/"+postID+"/delete", nil, headers, 200)
	if err != nil || deleted["state"] != "COMMITTED" || deleted["operation"] != "DELETE_POST" || deleted["postId"] != postID {
		return errors.Join(errors.New("own author delete did not commit"), err)
	}
	delete(headers, "Idempotency-Key")
	if _, h, err := p.request(ctx, "GET", p.c, "/api/v1/posts/"+postID, nil, headers, 404); err != nil || h.Get("Session-Expires-At") != "" {
		return errors.Join(errors.New("deleted post remained public or renewed failure"), err)
	}
	return nil
}

func checkPostTimes(h http.Header) error {
	server, err := time.Parse(time.RFC3339Nano, h.Get("Server-Time"))
	if err != nil {
		return err
	}
	expiry, err := time.Parse(time.RFC3339Nano, h.Get("Session-Expires-At"))
	if err != nil || !expiry.After(server) {
		return errors.New("post committed time headers absent")
	}
	return nil
}

func (p *probe) waitPostPublished(ctx context.Context, s state) error {
	ticker := time.NewTicker(200 * time.Millisecond)
	defer ticker.Stop()
	deadline := time.NewTimer(20 * time.Second)
	defer deadline.Stop()
	for {
		body, _, err := p.request(ctx, "GET", p.c, "/api/v1/me/post-tasks/"+s.Posts.TaskID, nil, map[string]string{"Authorization": "Bearer " + s.Token}, 200)
		if err != nil {
			return err
		}
		task, ok := body["task"].(map[string]any)
		if !ok {
			return errors.New("post task detail shape invalid")
		}
		if task["state"] == "PUBLISHED" {
			return nil
		}
		if task["state"] != "ACCEPTED" {
			return errors.New("real publication worker failed the accepted post")
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-deadline.C:
			return errors.New("real publication worker did not publish accepted post")
		case <-ticker.C:
		}
	}
}

func (p *probe) postsRestart(ctx context.Context, s state) error {
	if s.Posts == nil {
		return errors.New("runtime post state absent")
	}
	headers := map[string]string{"Authorization": "Bearer " + s.Token}
	result, h, err := p.request(ctx, "GET", p.c, "/api/v1/post-commands/"+s.Posts.CommandKey, nil, headers, 200)
	if err != nil || result["state"] != "ACCEPTED" || result["taskId"] != s.Posts.TaskID || result["postId"] != s.Posts.PostID || checkPostTimes(h) != nil {
		return errors.New("post original acceptance lost after worker or process restart")
	}
	public, _, err := p.request(ctx, "GET", p.c, "/api/v1/posts/"+s.Posts.PostID, nil, headers, 200)
	if err != nil {
		return err
	}
	post, ok := public["post"].(map[string]any)
	if !ok || len(public) != 1 || len(post) != 6 || post["title"] != s.Posts.Title || post["body"] != s.Posts.Body || post["channelId"] != s.Posts.ChannelID {
		return errors.New("public post did not preserve exact Unicode text and strict DTO")
	}
	author, ok := post["author"].(map[string]any)
	if !ok || len(author) != 3 || author["state"] != "ACTIVE" || author["nickname"] != "南风" || author["avatar"] != "default-v1" {
		return errors.New("public author exposed private fields or lost current projection")
	}
	feed, _, err := p.request(ctx, "GET", p.c, "/api/v1/channels/"+s.Posts.ChannelID+"/posts?limit=1", nil, headers, 200)
	if err != nil {
		return err
	}
	items, ok := feed["items"].([]any)
	if !ok || len(items) != 1 {
		return errors.New("published post absent or duplicated in latest feed")
	}
	card, ok := items[0].(map[string]any)
	if !ok || len(card) != 5 || card["postId"] != s.Posts.PostID {
		return errors.New("feed exposed body or wrong post")
	}
	own, _, err := p.request(ctx, "GET", p.c, "/api/v1/me/posts?limit=1", nil, headers, 200)
	if err != nil {
		return err
	}
	items, ok = own["items"].([]any)
	if !ok || len(items) != 1 {
		return errors.New("own successful post list absent")
	}
	capability, _, err := p.request(ctx, "GET", p.c, "/api/v1/me/posts/"+s.Posts.PostID+"/capabilities", nil, headers, 200)
	if err != nil || capability["canDelete"] != true || capability["canEdit"] != false {
		return errors.New("own minimal delete capability absent")
	}
	pool, err := p.fixturePool(ctx)
	if err != nil {
		return err
	}
	defer pool.Close()
	var unique bool
	err = pool.QueryRow(ctx, `SELECT (SELECT count(*) FROM c_posts.posts WHERE post_id=$1::uuid AND visibility='PUBLISHED')=1
AND (SELECT count(*) FROM c_posts.post_identity_bindings WHERE post_id=$1::uuid AND identity_id=$2::uuid)=1
AND (SELECT count(*) FROM c_posts.publication_tasks WHERE post_id=$1::uuid)=1
AND (SELECT count(*) FROM c_posts.publication_attempts WHERE task_id=$3::uuid AND state='PUBLISHED')=1`, s.Posts.PostID, s.IdentityID, s.Posts.TaskID).Scan(&unique)
	if err != nil || !unique {
		return errors.New("runtime SQL post binding or publication uniqueness invalid")
	}
	return nil
}

func (p *probe) postGateRead(ctx context.Context, s state, want int) error {
	if s.Posts == nil {
		return nil
	}
	for _, path := range []string{"/api/v1/post-commands/" + s.Posts.CommandKey, "/api/v1/posts/" + s.Posts.PostID} {
		_, h, err := p.request(ctx, "GET", p.c, path, nil, map[string]string{"Authorization": "Bearer " + s.Token}, want)
		if err != nil || h.Get("Session-Expires-At") != "" || h.Get("Server-Time") != "" {
			return errors.Join(errors.New("post protected read bypassed Gate/session boundary"), err)
		}
	}
	return nil
}

// 原有到期注销夹具只缩短自己的合成 dueAt；新文字 hook 仍以同事务事件约束。
func (p *probe) postSyntheticClosureStop(ctx context.Context, tx pgx.Tx, account string) error {
	_, err := tx.Exec(ctx, `INSERT INTO c_posts.publication_stop_events(account_id,generation,stopped_at,cause)
SELECT account_id,stop_generation+1,clock_timestamp(),'REQUEST_CLOSURE' FROM c_posts.account_publication_control WHERE account_id=$1::uuid`, account)
	if err != nil {
		return errors.New("cannot record synthetic closure publication stop")
	}
	_, err = tx.Exec(ctx, `UPDATE c_posts.account_publication_control SET stop_generation=stop_generation+1 WHERE account_id=$1::uuid`, account)
	if err != nil {
		return errors.New("cannot advance synthetic closure publication stop")
	}
	return nil
}

func (p *probe) postClosureReturned(ctx context.Context, pool *pgxpool.Pool, oldAccount, newToken string) error {
	s, err := p.load()
	if err != nil {
		return err
	}
	if s.Posts == nil {
		return nil
	}
	headers := map[string]string{"Authorization": "Bearer " + newToken}
	public, _, err := p.request(ctx, "GET", p.c, "/api/v1/posts/"+s.Posts.PostID, nil, headers, 200)
	if err != nil {
		return err
	}
	post, ok := public["post"].(map[string]any)
	if !ok {
		return errors.New("old published post lost after account closure")
	}
	author, ok := post["author"].(map[string]any)
	code, validCode := author["shortCode"].(string)
	if !ok || len(author) != 3 || author["state"] != "ACCOUNT_CLOSED" || author["avatar"] != "inactive-v1" || !validCode || !posts.ValidShortCode(code) {
		return errors.New("closed public author did not use independent identity placeholder")
	}
	for _, path := range []string{"/api/v1/me/posts", "/api/v1/me/post-tasks"} {
		list, _, e := p.request(ctx, "GET", p.c, path, nil, headers, 200)
		items, good := list["items"].([]any)
		if e != nil || !good || len(items) != 0 {
			return errors.New("same-email new account inherited old post ownership")
		}
	}
	unknown, _, err := p.request(ctx, "GET", p.c, "/api/v1/post-commands/"+s.Posts.CommandKey, nil, headers, 200)
	if err != nil || unknown["state"] != "UNKNOWN_NOT_OBSERVED" {
		return errors.New("new account inherited old command facts")
	}
	if _, _, err = p.request(ctx, "GET", p.c, "/api/v1/me/posts/"+s.Posts.PostID+"/capabilities", nil, headers, 404); err != nil {
		return err
	}
	var compact bool
	err = pool.QueryRow(ctx, `SELECT NOT EXISTS(SELECT 1 FROM c_posts.command_receipts WHERE owner_account_id=$1::uuid)
AND EXISTS(SELECT 1 FROM c_posts.post_identity_bindings WHERE account_id=$1::uuid AND post_id=$2::uuid)
AND EXISTS(SELECT 1 FROM c_posts.publication_tasks WHERE owner_account_id=$1::uuid AND post_id=$2::uuid AND NOT owner_visible)`, oldAccount, s.Posts.PostID).Scan(&compact)
	if err != nil || !compact {
		return errors.New("formal closure lost binding or retained private command owner")
	}
	return nil
}
