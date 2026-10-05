package authprivacyruntime

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5/pgxpool"
)

// PostgreSQL error DETAIL can contain an entire credential row, and an ERROR
// message itself can contain a failed type-conversion input. Bound SQL alone
// does not make database diagnostics safe. These settings disable ordinary SQL
// logging; they do not certify PANIC messages, extensions or external log sinks.
var privateDatabaseDiagnosticSettings = map[string]string{
	"log_statement":                     "none",
	"log_min_messages":                  "panic",
	"log_min_error_statement":           "panic",
	"log_error_verbosity":               "terse",
	"log_parameter_max_length":          "0",
	"log_parameter_max_length_on_error": "0",
	"log_min_duration_statement":        "-1",
	"log_min_duration_sample":           "-1",
	"log_transaction_sample_rate":       "0",
	"log_duration":                      "off",
}

func privateDatabaseDiagnostics(settings map[string]string) bool {
	for name, want := range privateDatabaseDiagnosticSettings {
		if settings[name] != want {
			return false
		}
	}
	return true
}

// CheckDatabaseDiagnostics checks the effective settings of the same role and
// connection pool used by the service. A missing or unsafe setting rejects
// startup without returning a driver error, SQL text or connection material.
func CheckDatabaseDiagnostics(ctx context.Context, pool *pgxpool.Pool) error {
	if pool == nil {
		return errors.New("private database diagnostics required")
	}
	names := make([]string, 0, len(privateDatabaseDiagnosticSettings))
	for name := range privateDatabaseDiagnosticSettings {
		names = append(names, name)
	}
	rows, err := pool.Query(ctx, `SELECT name,setting FROM pg_settings WHERE name=ANY($1::text[])`, names)
	if err != nil {
		return errors.New("private database diagnostics unavailable")
	}
	defer rows.Close()
	settings := make(map[string]string, len(names))
	for rows.Next() {
		var name, setting string
		if rows.Scan(&name, &setting) != nil {
			return errors.New("private database diagnostics unavailable")
		}
		settings[name] = setting
	}
	if rows.Err() != nil {
		return errors.New("private database diagnostics unavailable")
	}
	if !privateDatabaseDiagnostics(settings) {
		return errors.New("private database diagnostics rejected")
	}
	return nil
}
