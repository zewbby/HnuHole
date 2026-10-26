// commentsnapshotctl explicitly initializes or checks one new snapshot namespace.
// It uses the same private runtime configuration and MAC keys as the community API.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacyhttp"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacyruntime"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/comments"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/commentsnapshot"
)

func run(path string, initialize, check bool, operatorUser, operatorPasswordFile string) error {
	return runOperation(path, initialize, check, false, operatorUser, operatorPasswordFile)
}

func runOperation(path string, initialize, check, drain bool, operatorUser, operatorPasswordFile string) error {
	operations := 0
	for _, selected := range []bool{initialize, check, drain} {
		if selected {
			operations++
		}
	}
	if path == "" || operations != 1 || ((initialize || drain) && (operatorUser == "" || operatorPasswordFile == "")) || (check && (operatorUser != "" || operatorPasswordFile != "")) {
		return errors.New("choose exactly one explicit initialization, check or drain")
	}
	cfg, err := authprivacyruntime.LoadConfig(path, authprivacyhttp.CommunityService)
	if err != nil {
		return err
	}
	if cfg.Comments == nil || cfg.Comments.Snapshots == nil || !cfg.Comments.Snapshots.ReadRedis {
		return errors.New("Redis comment snapshots are not configured")
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
	settings := *cfg.Comments.Snapshots
	if initialize || drain {
		if operatorUser == settings.Redis.Username {
			return errors.New("initialization and drain require a separate operator identity")
		}
		settings.Redis.Username = operatorUser
		settings.Redis.PasswordFile = operatorPasswordFile
	}
	password, err := cfg.Read(settings.Redis.PasswordFile, true, 1024)
	if err != nil {
		return errors.New("snapshot credentials unavailable")
	}
	store, err := commentsnapshot.New(settings, strings.TrimSuffix(strings.TrimSuffix(string(password), "\n"), "\r"), codec.IntentFingerprint)
	if err != nil {
		return err
	}
	defer store.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if initialize {
		return store.InitializeNew(ctx)
	}
	if drain {
		return store.Drain(ctx)
	}
	return store.Check(ctx)
}

func main() {
	path := flag.String("config", "", "private community runtime JSON")
	initialize := flag.Bool("initialize-new-namespace", false, "initialize a provably empty snapshot namespace; never reset existing state")
	check := flag.Bool("check", false, "check existing snapshot configuration and state")
	drain := flag.Bool("drain", false, "block new preparations while preserving existing reads and publications")
	operatorUser := flag.String("operator-username", "", "separate operator ACL identity, initialization or drain")
	operatorPasswordFile := flag.String("operator-password-file", "", "private operator password path, initialization or drain")
	flag.Parse()
	if err := runOperation(*path, *initialize, *check, *drain, *operatorUser, *operatorPasswordFile); err != nil {
		fmt.Fprintln(os.Stderr, "comment snapshot operation failed:", err)
		os.Exit(1)
	}
	fmt.Println("comment snapshot operation completed")
}
