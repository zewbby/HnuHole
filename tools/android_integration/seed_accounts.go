// Development-only bootstrap data. Compile this tool under services/api so it
// can reuse the production password profile; it is never part of an Android APK.
package main

import (
	"context"
	"encoding/json"
	"net/url"
	"os"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacy"
)

type account struct {
	Username string `json:"username"`
	Password string `json:"password"`
	Number   string `json:"number"`
}

func main() {
	if os.Getenv("HNUHOLE_INTEGRATION_SEED") != "android-integration-20261019" {
		panic("explicit owned integration seed required")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	var accounts []account
	if err := json.NewDecoder(os.Stdin).Decode(&accounts); err != nil || len(accounts) != 4 {
		panic("four private synthetic account inputs required")
	}
	dsn := os.Getenv("HNUHOLE_INTEGRATION_DSN")
	u, err := url.Parse(dsn)
	if err != nil || u.Host != "" || u.Path != "/hnuhole_c" || u.Query().Get("host") != "/home/hnuhole/android-integration-20261019-runtime/lab/source-c/socket" {
		panic("only this task's new local source C socket is allowed")
	}
	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		panic("owned connection failed")
	}
	defer pool.Close()
	var database, user string
	if err = pool.QueryRow(ctx, "SELECT current_database(),current_user").Scan(&database, &user); err != nil || database != "hnuhole_c" || user != "prerelease_admin" {
		panic("owned lab bootstrap database required")
	}
	preparer, err := authprivacy.NewPasswordPreparer(1, []string{"blocked development password"})
	if err != nil {
		panic("password profile unavailable")
	}
	tx, err := pool.Begin(ctx)
	if err != nil {
		panic("seed transaction unavailable")
	}
	defer tx.Rollback(ctx)
	for _, a := range accounts {
		material, err := preparer.PreparePassword(ctx, a.Password, a.Username)
		if err != nil {
			panic("synthetic password rejected")
		}
		_, err = tx.Exec(ctx, `INSERT INTO c_auth.accounts(account_id,platform_number,username,password_hash,password_salt,password_params_version)
		 VALUES($1,$2,$3,$4,$5,$6)`, uuid.NewString(), a.Number, a.Username, material.Hash[:], material.Salt[:], material.ParametersVersion)
		if err != nil {
			panic("synthetic seed rejected; no existing account is overwritten")
		}
	}
	if err = tx.Commit(ctx); err != nil {
		panic("seed commit failed")
	}
	println("Four isolated synthetic accounts seeded; authenticate using normal HTTPS login")
}
