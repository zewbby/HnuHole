package authprivacyruntime

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5/pgconn"
	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacyhttp"
)

func TestProcessDiagnosticsExcludeUntrustedErrors(t *testing.T) {
	const secret = "sentinel-email@example.invalid/password/otp/bearer/recovery/private-key"
	for _, err := range []error{
		errors.New(secret),
		&pgconn.PgError{Message: secret, Detail: secret, Where: secret},
		fmt.Errorf("%s: %w", secret, context.DeadlineExceeded),
		fmt.Errorf("%s: %w", secret, context.Canceled),
	} {
		var output bytes.Buffer
		logger := slog.New(slog.NewJSONHandler(&output, nil))
		LogFailure(logger, authprivacyhttp.Service(secret), FailureStage(secret), err)
		if strings.Contains(output.String(), secret) {
			t.Fatal("diagnostic exposed error or caller-provided labels")
		}
		var event map[string]any
		if err := json.Unmarshal(output.Bytes(), &event); err != nil {
			t.Fatal(err)
		}
		if event["service"] != "unknown" || event["stage"] != "unknown" || len(event) != 6 {
			t.Fatalf("unexpected diagnostic fields: %v", event)
		}
	}
}

func TestHTTPPanicDiagnosticExcludesRequestAndPanicMaterial(t *testing.T) {
	const secret = "sentinel@example.invalid-secret-capability"
	var output bytes.Buffer
	logger := slog.New(slog.NewJSONHandler(&output, nil))
	server := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		panic(secret)
	}))
	server.Config.ErrorLog = HTTPErrorLogger(logger, authprivacyhttp.CommunityService)
	server.Start()
	defer server.Close()
	request, _ := http.NewRequest(http.MethodGet, server.URL+"/"+secret, nil)
	request.Header.Set("Authorization", "Bearer "+secret)
	response, err := server.Client().Do(request)
	if response != nil {
		response.Body.Close()
	}
	// Close waits for the panic handler and its diagnostic writer to finish.
	// Reading the plain test buffer before that wait races with net/http.
	server.Close()
	if err == nil {
		t.Fatal("panic did not close the HTTP connection")
	}
	if strings.Contains(output.String(), secret) || strings.Contains(output.String(), "127.0.0.1") || strings.Contains(output.String(), "goroutine") {
		t.Fatal("HTTP diagnostics exposed panic, request, peer or stack")
	}
	if !strings.Contains(output.String(), "HTTP transport event") {
		t.Fatal("transport failure was not recorded")
	}
}
