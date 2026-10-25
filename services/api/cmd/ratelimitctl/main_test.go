package main

import (
	"context"
	"encoding/json"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/ratelimit"
)

func TestPrivateOperatorInputIsStrictAndRedacted(t *testing.T) {
	dir := t.TempDir()
	config := filepath.Join(dir, "operator.json")
	if err := run(config, false, false); err == nil {
		t.Fatal("implicit operation accepted")
	}
	if err := run(config, true, true); err == nil {
		t.Fatal("ambiguous operation accepted")
	}
	for _, body := range []string{`{"credential":"private-secret"}`, `{"service":"community"} {}`, `{"service":"private-secret"}`} {
		if err := os.WriteFile(config, []byte(body), 0600); err != nil {
			t.Fatal(err)
		}
		err := run(config, true, false)
		if err == nil || strings.Contains(err.Error(), "private-secret") {
			t.Fatal("operator error exposed private input or accepted invalid JSON")
		}
	}
	if err := os.Chmod(config, 0644); err != nil {
		t.Fatal(err)
	}
	if _, err := privateFile(config, 32768); err == nil {
		t.Fatal("public configuration material accepted")
	}
	link := filepath.Join(dir, "link.json")
	if err := os.Symlink(config, link); err == nil {
		if _, err = privateFile(link, 32768); err == nil {
			t.Fatal("symlink configuration accepted")
		}
	}
}
func TestOwnedPostgresExplicitInitializeAndRecoveryCLI(t *testing.T) {
	binary := os.Getenv("HNULIMIT_REDIS_SERVER")
	goose := os.Getenv("HNULIMIT_GOOSE")
	if binary == "" || goose == "" {
		t.Skip("owned Redis/Goose fixture absent")
	}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := listener.Addr().(*net.TCPAddr).Port
	listener.Close()
	dir := t.TempDir()
	redisConfig := filepath.Join(dir, "redis.conf")
	if err = os.WriteFile(redisConfig, []byte("bind 127.0.0.1\nport "+strconv.Itoa(port)+"\nsave \"\"\nappendonly no\nmaxmemory 64mb\nmaxmemory-policy noeviction\nrequirepass synthetic-cli-only\n"), 0600); err != nil {
		t.Fatal(err)
	}
	command := exec.Command(binary, redisConfig)
	command.Stdout = io.Discard
	command.Stderr = io.Discard
	if err = command.Start(); err != nil {
		t.Fatal("owned CLI Redis failed to start")
	}
	defer func() { command.Process.Kill(); command.Wait() }()
	address := "127.0.0.1:" + strconv.Itoa(port)
	operator := redis.NewClient(&redis.Options{Addr: address, Password: "synthetic-cli-only", MaxRetries: -1})
	defer operator.Close()
	ctx := context.Background()
	for i := 0; i < 100; i++ {
		if operator.Ping(ctx).Err() == nil {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	for _, service := range []string{"community", "verifier"} {
		t.Run(service, func(t *testing.T) {
			role := "c"
			schema := "c_rate_limit"
			migrations := "migrations"
			if service == "verifier" {
				role = "v"
				schema = "v_rate_limit"
				migrations = "verifier-migrations"
			}
			dsn := os.Getenv("AUTHLAB_RATE_CTL_" + strings.ToUpper(role) + "_DSN")
			if dsn == "" {
				t.Fatal("explicit owned operator database required")
			}
			parsed, e := pgxpool.ParseConfig(dsn)
			if e != nil || os.Getenv("AUTHLAB_ALLOW_SCHEMA_RESET") != "1" || parsed.ConnConfig.RuntimeParams["application_name"] != os.Getenv("AUTHLAB_RUNTIME_TAG") || !strings.HasPrefix(os.Getenv("AUTHLAB_RUNTIME_TAG"), "hnuhole_authlab_") {
				t.Fatal("refusing unowned operator fixture")
			}
			pool, e := pgxpool.NewWithConfig(ctx, parsed)
			if e != nil {
				t.Fatal("owned metadata connection failed")
			}
			defer pool.Close()
			var database, actor string
			var server *string
			var super bool
			if e = pool.QueryRow(ctx, `SELECT current_database(),current_user,inet_server_addr()::text,(SELECT rolsuper FROM pg_roles WHERE rolname=current_user)`).Scan(&database, &actor, &server, &super); e != nil || database != "hnuhole_limit_init_"+role || actor != "hnuhole_"+role || server != nil || super {
				t.Fatal("refusing foreign operator database")
			}
			migration := exec.Command(goose, "-dir", filepath.Join("..", "..", migrations), "up")
			migration.Env = append(os.Environ(), "GOOSE_DRIVER=postgres", "GOOSE_DBSTRING="+dsn)
			if _, e = migration.CombinedOutput(); e != nil {
				t.Fatal("owned CLI formal Goose preparation failed")
			}
			cfg := configuration{SubjectKeyFile: "subject-key", Service: service, DatabaseURL: dsn, DatabasePasswordFile: "database-password", RedisPasswordFile: "redis-password", Policy: ratelimit.TrialConfig(address, service+"_cli_owned")}
			for i := range cfg.Policy.Rules {
				action := cfg.Policy.Rules[i].Action
				isV := action == "otp.request" || action == "otp.verify"
				if service == "community" && isV || service == "verifier" && !isV && action != "entry.query" && action != "entry.mutation" {
					cfg.Policy.Rules[i].Mode = ratelimit.Off
				}
			}
			for file, value := range map[string]string{"subject-key": strings.Repeat("k", 32), "database-password": "synthetic-private-socket-only", "redis-password": "synthetic-cli-only"} {
				if e = os.WriteFile(filepath.Join(dir, file), []byte(value), 0600); e != nil {
					t.Fatal(e)
				}
			}
			path := filepath.Join(dir, service+".json")
			raw, _ := json.Marshal(cfg)
			if e = os.WriteFile(path, raw, 0600); e != nil {
				t.Fatal(e)
			}
			if e = run(path, true, false); e != nil {
				t.Fatal("explicit owner initialization failed", e)
			}
			var generation int64
			var state string
			if e = pool.QueryRow(ctx, `SELECT generation,state FROM `+schema+`.namespace WHERE singleton_id=1`).Scan(&generation, &state); e != nil || generation != 1 || state != "READY" {
				t.Fatal("explicit initialization missing")
			}
			if e = run(path, true, false); e == nil {
				t.Fatal("existing namespace silently reinitialized")
			}
			if e = run(path, false, true); e != nil {
				t.Fatal("explicit recovery failed", e)
			}
			var remaining float64
			expectedWindow := 3631.0
			if service == "verifier" {
				expectedWindow = 91
			}
			if e = pool.QueryRow(ctx, `SELECT generation,state,extract(epoch from barrier_until-clock_timestamp()) FROM `+schema+`.namespace WHERE singleton_id=1`).Scan(&generation, &state, &remaining); e != nil || generation != 2 || state != "RECOVERING" || remaining < expectedWindow-5 || remaining > expectedWindow+5 {
				t.Fatal("operator recovery ignored effective quota window", generation, state, remaining, e)
			}
			if strings.Contains(string(raw), "synthetic-cli-only") {
				t.Fatal("operator configuration embedded secret instead of separate file")
			}
		})
	}
}
