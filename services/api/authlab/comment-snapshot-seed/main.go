// Fixture-only occupancy seeder. It does not claim SQL/publication acceptance.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacyhttp"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacyruntime"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/comments"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/commentsnapshot"
)

func run(root, config, input string) error {
	if os.Getenv("COMMENT_SNAPSHOT_OWNED_PROCESS_FIXTURE") != "1" {
		return errors.New("owned fixture required")
	}
	root, _ = filepath.Abs(root)
	if filepath.Dir(config) != filepath.Join(root, "material") || filepath.Dir(input) != root {
		return errors.New("private fixture paths required")
	}
	var marker struct {
		RedisPID int `json:"snapshotRedisPid"`
	}
	b, err := os.ReadFile(filepath.Join(root, "fixture-owner.json"))
	if err != nil || json.Unmarshal(b, &marker) != nil || marker.RedisPID < 1 {
		return errors.New("owned Redis marker required")
	}
	cfg, err := authprivacyruntime.LoadConfig(config, authprivacyhttp.CommunityService)
	if err != nil {
		return err
	}
	if cfg.Comments == nil || cfg.Comments.Snapshots == nil || !cfg.Comments.Snapshots.ReadRedis {
		return errors.New("snapshot fixture required")
	}
	password, err := cfg.Read(cfg.Comments.Snapshots.Redis.PasswordFile, true, 1024)
	if err != nil {
		return err
	}
	client := redis.NewClient(&redis.Options{Addr: cfg.Comments.Snapshots.Redis.Address, Username: cfg.Comments.Snapshots.Redis.Username, Password: strings.TrimSpace(string(password)), MaxRetries: -1})
	defer client.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	info, err := client.Info(ctx, "server").Result()
	if err != nil || !strings.Contains(info, "process_id:"+strconv.Itoa(marker.RedisPID)+"\r\n") {
		return errors.New("Redis ownership mismatch")
	}
	var data struct {
		Owner, Post string
		Templates   []struct {
			Root string
			IDs  []uuid.UUID
		}
	}
	b, err = os.ReadFile(input)
	if err != nil || len(b) > 2<<20 || json.Unmarshal(b, &data) != nil || len(data.Templates) < 1 {
		return errors.New("invalid owned seed")
	}
	account, err := uuid.Parse(data.Owner)
	if err != nil {
		return err
	}
	post, err := uuid.Parse(data.Post)
	if err != nil {
		return err
	}
	key, err := cfg.Key32(cfg.Comments.CommandKeyFile)
	if err != nil {
		return err
	}
	fingerprint, err := cfg.Key32(cfg.Comments.FingerprintKeyFile)
	if err != nil {
		return err
	}
	codec, err := comments.NewCommandCodec(key[:], fingerprint[:])
	if err != nil {
		return err
	}
	store, err := commentsnapshot.New(*cfg.Comments.Snapshots, strings.TrimSpace(string(password)), codec.IntentFingerprint)
	if err != nil {
		return err
	}
	defer store.Close()
	if err = store.Check(ctx); err != nil {
		return err
	}
	owner := commentsnapshot.OwnerToken(codec.IntentFingerprint, account, cfg.Comments.Snapshots.Redis.Namespace)
	before, err := store.Usage(ctx, owner)
	if err != nil {
		return err
	}
	created := 0
	for i := before.AccountCount; i < cfg.Comments.Snapshots.MaxPerAccount; i++ {
		template := data.Templates[created%len(data.Templates)]
		scope := commentsnapshot.Scope{Owner: owner, Post: post, Kind: comments.MainComments, Sort: comments.Relevant}
		if template.Root != "" {
			scope.Root, err = uuid.Parse(template.Root)
			if err != nil {
				return err
			}
			scope.Kind = comments.Replies
		}
		at := time.Now().UTC().Truncate(time.Millisecond)
		snapshot := commentsnapshot.Snapshot{Ref: commentsnapshot.Ref{Backend: commentsnapshot.Redis, ID: uuid.New(), Epoch: store.Epoch(), Expires: at.Add(30 * time.Minute), Kind: scope.Kind, Sort: scope.Sort}, Scope: scope, Created: at, IDs: template.IDs}
		nonce := uuid.New()
		p, e := store.Prepare(ctx, snapshot, commentsnapshot.Request(codec.IntentFingerprint, owner, scope, nonce[:]), commentsnapshot.LegacyUsage{})
		if e != nil {
			return e
		}
		if e = store.Publish(ctx, p); e != nil {
			return e
		}
		created++
	}
	after, err := store.Usage(ctx, owner)
	if err != nil {
		return err
	}
	return json.NewEncoder(os.Stdout).Encode(map[string]any{"result": "PASS", "created": created, "startCount": before.AccountCount, "endCount": after.AccountCount, "reservedBytes": after.ReservedBytes, "templates": len(data.Templates), "scope": "synthetic committed-data occupancy, not SQL/publication acceptance"})
}

func main() {
	root := flag.String("fixture-root", "", "owned run directory")
	config := flag.String("config", "", "private config")
	input := flag.String("input", "", "owned committed-data templates")
	flag.Parse()
	if err := run(*root, *config, *input); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
