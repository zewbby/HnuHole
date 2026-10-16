// Test-only operator for the owned joint lab. Calls the existing trusted mute
// entry with the real Gate; no direct state rewrites, DDL or public admin route.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy/protocol"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacyhttp"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacyruntime"
)

func run() error {
	root := flag.String("root", "", "canonical owned lab root")
	config := flag.String("config", "", "this lab C config")
	task := flag.String("task", "", "synthetic task in this fresh database")
	flag.Parse()
	canonical, e := filepath.EvalSymlinks(*root)
	canonicalConfig, ce := filepath.EvalSymlinks(*config)
	marker, me := os.ReadFile(filepath.Join(*root, ".owner"))
	if e != nil || ce != nil || canonicalConfig != *config || me != nil || canonical != *root || os.Geteuid() == 0 ||
		!strings.HasPrefix(*root, "/home/hnuhole/post-media-joint-") ||
		!strings.HasPrefix(string(marker), "post-image-integration-20261015|") ||
		!strings.HasPrefix(*config, *root+"/run-") || filepath.Base(*config) != "c.json" ||
		filepath.Dir(filepath.Dir(filepath.Dir(*config))) != *root || filepath.Base(filepath.Dir(*config)) != "material" {
		return errors.New("unowned fixture refused")
	}
	id, e := uuid.Parse(*task)
	if e != nil || id.String() != *task {
		return errors.New("invalid synthetic task")
	}
	c, e := authprivacyruntime.LoadConfig(*config, authprivacyhttp.CommunityService)
	if e != nil {
		return errors.New("fixture config rejected")
	}
	pc, e := c.PoolConfig()
	if e != nil || pc.ConnConfig.Host != filepath.Join(filepath.Dir(filepath.Dir(*config)), "socket") ||
		!strings.HasPrefix(pc.ConnConfig.RuntimeParams["application_name"], "hnuhole_joint_run-") {
		return errors.New("unmarked database refused")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	pool, e := pgxpool.NewWithConfig(ctx, pc)
	if e != nil {
		return errors.New("fixture connection failed")
	}
	defer pool.Close()
	if authprivacyruntime.CheckDatabase(ctx, pool, authprivacyhttp.CommunityService) != nil {
		return errors.New("restricted runtime required")
	}
	gate, e := authprivacyruntime.NewGate(c, pool, authprivacyhttp.CommunityService)
	if e != nil {
		return e
	}
	cp, e := c.PublicKey(c.TrustedCommunityKeyFile)
	if e != nil {
		return e
	}
	vp, e := c.PublicKey(c.TrustedVerifierKeyFile)
	if e != nil {
		return e
	}
	var ck, vk protocol.PublicKey
	copy(ck[:], cp)
	copy(vk[:], vp)
	verifier, e := protocol.NewVerifier(c.Environment, []protocol.TrustedKey{
		{Environment: c.Environment, Purpose: protocol.PurposeRegister, Epoch: 1, PublicKey: vk},
		{Environment: c.Environment, Purpose: protocol.PurposeRetireAuth, Epoch: 1, PublicKey: vk},
		{Environment: c.Environment, Purpose: protocol.PurposeRetired, Epoch: 1, PublicKey: ck},
		{Environment: c.Environment, Purpose: protocol.PurposeReleased, Epoch: 1, PublicKey: ck},
	})
	if e != nil {
		return e
	}
	k, e := c.Key32(c.RequestKeyFile)
	if e != nil {
		return e
	}
	community, e := authprivacy.NewCommunity(pool, verifier, 1, k, gate)
	if e != nil {
		return e
	}
	command, e := c.Key32(c.Posts.CommandKeyFile)
	if e != nil {
		return e
	}
	fingerprint, e := c.Key32(c.Posts.FingerprintKeyFile)
	if e != nil {
		return e
	}
	cursor, e := c.Key32(c.Posts.CursorKeyFile)
	if e != nil {
		return e
	}
	community, e = community.WithPosts(ctx, authprivacy.PostConfig{Environment: c.PublicOrigin, KeyKey: command, FingerprintKey: fingerprint, CursorKey: cursor})
	if e != nil {
		return e
	}
	var account uuid.UUID
	var version int64
	e = pool.QueryRow(ctx, `SELECT t.owner_account_id,r.version FROM c_posts.publication_tasks t JOIN c_auth.account_restrictions r ON r.account_id=t.owner_account_id WHERE t.task_id=$1`, id).Scan(&account, &version)
	if e != nil {
		return errors.New("synthetic task missing")
	}
	until := time.Now().Add(3 * time.Second)
	return community.ApplyAccountMute(ctx, account, version, &until)
}

func main() {
	if run() != nil {
		fmt.Fprintln(os.Stderr, "owned publication-stop probe failed")
		os.Exit(1)
	}
	fmt.Println("owned short publication stop committed through Gate")
}
