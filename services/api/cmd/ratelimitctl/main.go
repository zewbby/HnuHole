// ratelimitctl is an explicit operator tool, never invoked by either API. It
// cannot migrate a schema, reset Redis or bypass a recovery barrier.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/ratelimit"
)

type configuration struct {
	SubjectKeyFile       string           `json:"subjectKeyFile"`
	Service              string           `json:"service"`
	DatabaseURL          string           `json:"databaseUrl"`
	DatabasePasswordFile string           `json:"databasePasswordFile"`
	RedisPasswordFile    string           `json:"redisPasswordFile"`
	Policy               ratelimit.Config `json:"policy"`
}

func privateFile(path string, max int) ([]byte, error) {
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode().Perm()&0077 != 0 || info.Size() < 1 || info.Size() > int64(max) {
		return nil, errors.New("private configuration material unavailable")
	}
	data, err := os.ReadFile(path)
	if err != nil || len(data) > max {
		return nil, errors.New("private configuration material unavailable")
	}
	return data, nil
}
func run(path string, initialize, recover bool) error {
	if path == "" || initialize == recover {
		return errors.New("choose exactly one explicit initialization or recovery operation")
	}
	raw, err := privateFile(path, 32768)
	if err != nil {
		return err
	}
	var config configuration
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if decoder.Decode(&config) != nil || decoder.Decode(new(any)) != io.EOF {
		return errors.New("invalid private operator configuration")
	}
	if config.Service != "community" && config.Service != "verifier" || config.Policy.ValidateFor(config.Service) != nil {
		return errors.New("invalid namespace configuration")
	}
	resolve := func(p string) string {
		if filepath.IsAbs(p) {
			return p
		}
		return filepath.Join(filepath.Dir(path), p)
	}
	dbPassword, err := privateFile(resolve(config.DatabasePasswordFile), 1024)
	if err != nil {
		return err
	}
	redisPassword, err := privateFile(resolve(config.RedisPasswordFile), 1024)
	if err != nil {
		return err
	}
	dbConfig, err := pgxpool.ParseConfig(config.DatabaseURL)
	if err != nil || dbConfig.ConnConfig.Password != "" {
		return errors.New("database credentials must use a separate private file")
	}
	dbConfig.ConnConfig.Password = strings.TrimSpace(string(dbPassword))
	dbConfig.MaxConns = 2
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	pool, err := pgxpool.NewWithConfig(ctx, dbConfig)
	if err != nil {
		return errors.New("namespace metadata unavailable")
	}
	defer pool.Close()
	store, err := ratelimit.NewPostgresNamespaceStore(pool, config.Service)
	if err != nil {
		return err
	}
	password := strings.TrimSuffix(strings.TrimSuffix(string(redisPassword), "\n"), "\r")
	client := redis.NewClient(&redis.Options{Addr: config.Policy.Address, Username: config.Policy.Username, Password: password, MaxRetries: -1, PoolSize: 1, ContextTimeoutEnabled: true, DialTimeout: time.Second, ReadTimeout: time.Second, WriteTimeout: time.Second})
	defer client.Close()
	info, err := client.Info(ctx, "server").Result()
	if err != nil {
		return errors.New("namespace component unavailable")
	}
	runID := ""
	for _, line := range strings.Split(info, "\n") {
		if strings.HasPrefix(line, "run_id:") {
			runID = strings.TrimSpace(strings.TrimPrefix(line, "run_id:"))
		}
	}
	keyBytes, err := privateFile(resolve(config.SubjectKeyFile), 32)
	if err != nil || len(keyBytes) != 32 {
		return errors.New("private subject key unavailable")
	}
	var subjectKey [32]byte
	copy(subjectKey[:], keyBytes)
	engine, err := ratelimit.New(config.Policy, password, store, subjectKey)
	if err != nil {
		return err
	}
	defer engine.Close()
	if initialize {
		ns, err := store.Initialize(ctx, runID, engine.PolicyHash(), engine.RecoveryWindow())
		if err != nil {
			return err
		}
		return engine.InitializeRedis(ctx, ns)
	}
	ns, err := store.Load(ctx)
	if err != nil {
		return err
	}
	longest := engine.RecoveryWindow()
	_, err = store.Reconfigure(ctx, ns.Generation, runID, engine.PolicyHash(), longest)
	return err
}
func main() {
	path := flag.String("config", "", "private operator config")
	initialize := flag.Bool("initialize-new-namespace", false, "initialize only an empty, migrated namespace")
	recover := flag.Bool("begin-recovery", false, "start the full recovery barrier without clearing Redis")
	flag.Parse()
	if err := run(*path, *initialize, *recover); err != nil {
		fmt.Fprintln(os.Stderr, "shared namespace operation failed; check private configuration and owner permissions")
		os.Exit(1)
	}
	fmt.Println("shared namespace operation recorded; APIs continue to enforce the persisted recovery barrier")
}
