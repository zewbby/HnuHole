// Package readtiming records optional durations without observing request data.
package readtiming

import (
	"context"
	"sync"
	"time"
)

type traceKey struct{}
type phaseKey struct{}

type Stage struct {
	Nanoseconds int64 `json:"nanoseconds"`
	Calls       int64 `json:"calls"`
}

type Observation struct {
	StartedUnixNanoseconds int64            `json:"startedUnixNanoseconds"`
	ElapsedNanoseconds     int64            `json:"elapsedNanoseconds"`
	Stages                 map[string]Stage `json:"stages"`
	Truncated              bool             `json:"truncated"`
	Clock                  string           `json:"clock"`
	ClockValid             bool             `json:"clockValid"`
}

type Trace struct {
	mu          sync.Mutex
	started     time.Time
	startedTick int64
	clockValid  bool
	stages      map[string]Stage
	truncated   bool
}

func Start(ctx context.Context) (context.Context, *Trace) {
	tick, valid := clockNow()
	t := &Trace{started: time.Now(), startedTick: tick, clockValid: valid, stages: make(map[string]Stage)}
	return context.WithValue(ctx, traceKey{}, t), t
}

func Phase(ctx context.Context, phase string) context.Context {
	if ctx.Value(traceKey{}) == nil {
		return ctx
	}
	return context.WithValue(ctx, phaseKey{}, phase)
}

func noop() {}

// Span names and phases are fixed internal labels, never request values.
func Span(ctx context.Context, name string) func() {
	t, ok := ctx.Value(traceKey{}).(*Trace)
	if !ok {
		return noop
	}
	if phase, ok := ctx.Value(phaseKey{}).(string); ok {
		name = phase + "." + name
	}
	started, startedValid := clockNow()
	return func() {
		finished, finishedValid := clockNow()
		elapsed := finished - started
		t.mu.Lock()
		defer t.mu.Unlock()
		if !startedValid || !finishedValid || elapsed < 0 {
			t.clockValid = false
			elapsed = 0
		}
		stage, exists := t.stages[name]
		if !exists && len(t.stages) >= 64 {
			t.truncated = true
			return
		}
		stage.Nanoseconds += elapsed
		stage.Calls++
		t.stages[name] = stage
	}
}

// Snapshot returns a copy; observers cannot mutate in-flight measurements.
func (t *Trace) Snapshot() Observation {
	t.mu.Lock()
	defer t.mu.Unlock()
	stages := make(map[string]Stage, len(t.stages))
	for name, stage := range t.stages {
		stages[name] = stage
	}
	finished, valid := clockNow()
	elapsed := finished - t.startedTick
	if !valid || elapsed < 0 {
		t.clockValid = false
		elapsed = 0
	}
	return Observation{StartedUnixNanoseconds: t.started.UnixNano(), ElapsedNanoseconds: elapsed, Stages: stages, Truncated: t.truncated, Clock: clockName, ClockValid: t.clockValid}
}
