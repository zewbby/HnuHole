package authprivacyruntime

import (
	"context"
	"errors"
	"log"
	"log/slog"

	"github.com/zhubaozhenshuai666-lang/HnuHole/services/api/internal/authprivacyhttp"
)

type FailureStage string

const (
	ConfigurationFailure FailureStage = "configuration"
	RuntimeFailure       FailureStage = "runtime"
)

func diagnosticService(service authprivacyhttp.Service) string {
	switch service {
	case authprivacyhttp.CommunityService, authprivacyhttp.VerifierService:
		return string(service)
	default:
		return "unknown"
	}
}

// LogFailure deliberately excludes error text, SQL details, URLs and paths.
// Driver/transport errors can include secrets or attacker-controlled bytes.
// The small fixed vocabulary still identifies the process and failure stage.
func LogFailure(logger *slog.Logger, service authprivacyhttp.Service, stage FailureStage, err error) {
	if err == nil {
		return
	}
	if stage != ConfigurationFailure && stage != RuntimeFailure {
		stage = "unknown"
	}
	reason := "failed"
	if errors.Is(err, context.DeadlineExceeded) {
		reason = "deadline_exceeded"
	} else if errors.Is(err, context.Canceled) {
		reason = "cancelled"
	}
	logger.Error("authentication process failure", "service", diagnosticService(service), "stage", string(stage), "reason", reason)
}

type httpDiagnosticWriter struct {
	logger  *slog.Logger
	service authprivacyhttp.Service
}

func (w httpDiagnosticWriter) Write(message []byte) (int, error) {
	// net/http's default logger includes peer addresses and panic values. Never
	// parse or forward that message; report only that a transport event occurred.
	w.logger.Warn("HTTP transport event", "service", diagnosticService(w.service))
	return len(message), nil
}

func HTTPErrorLogger(logger *slog.Logger, service authprivacyhttp.Service) *log.Logger {
	return log.New(httpDiagnosticWriter{logger: logger, service: service}, "", 0)
}
