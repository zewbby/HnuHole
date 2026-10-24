package ratelimit

import (
	"context"
	"log/slog"
	"time"
)

// LogMetrics has a fixed configuration-bounded series count and no subject,
// request, credential, content, email, or network labels. It uses the runtime's
// private structured logger; no public metrics endpoint is created.
func (c *Controller) LogMetrics(ctx context.Context, logger *slog.Logger, period time.Duration) {
	if logger == nil || period < time.Second || period > time.Hour {
		return
	}
	ticker := time.NewTicker(period)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			c.WriteMetrics(logger)
		}
	}
}
func (c *Controller) WriteMetrics(logger *slog.Logger) {
	if logger == nil {
		return
	}
	snapshot := c.Metrics.Snapshot()
	for _, rule := range c.config.Rules {
		metric := snapshot[rule.Action]
		logger.Info("shared_rate_limit_metrics", "action", rule.Action, "mode", string(rule.Mode), "requests", metric.Requests, "allowed", metric.Allowed, "denied", metric.Denied, "would_deny", metric.WouldDeny, "redis_errors", metric.Errors, "fallbacks", metric.Fallbacks, "duration_ns_total", metric.Nanoseconds)
	}
}
