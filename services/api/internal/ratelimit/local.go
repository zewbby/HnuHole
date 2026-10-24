package ratelimit

import (
	"sync"
	"time"
)

type localBudget struct {
	at, timeUsed time.Time
	tokens       float64
}
type LocalRead struct {
	mu      sync.Mutex
	entries map[string]localBudget
}

func (l *LocalRead) Admit(subject string) (Decision, error) {
	return l.AdmitWithBudget(subject, 100, 5)
}
func (l *LocalRead) AdmitWithBudget(subject string, capacity, rate float64) (Decision, error) {
	if capacity < 1 || capacity > 10000 || rate < 1 || rate > 1000 {
		return Decision{}, ErrCapacity
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	now := time.Now()
	if l.entries == nil {
		l.entries = map[string]localBudget{}
	}
	v, ok := l.entries[subject]
	if !ok {
		if len(l.entries) >= 4096 {
			for k, b := range l.entries {
				if now.Sub(b.timeUsed) >= time.Minute {
					delete(l.entries, k)
				}
			}
			if len(l.entries) >= 4096 {
				return Decision{}, ErrCapacity
			}
		}
		v = localBudget{at: now, tokens: capacity}
	}
	if now.After(v.at) {
		v.tokens += now.Sub(v.at).Seconds() * rate
		if v.tokens > capacity {
			v.tokens = capacity
		}
		v.at = now
	}
	v.timeUsed = now
	if v.tokens < 1 {
		l.entries[subject] = v
		return Decision{RetryAfter: 1}, nil
	}
	v.tokens--
	l.entries[subject] = v
	return Decision{Allowed: true}, nil
}
func (c *Controller) RecordFallback(action string) {
	if _, ok := c.rules[action]; ok {
		c.Metrics.add(action, "fallback", 0)
	}
}
