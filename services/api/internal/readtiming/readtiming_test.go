package readtiming

import (
	"context"
	"fmt"
	"sync"
	"testing"
)

func TestOptionalTracePreservesContextAndAggregatesConcurrentCalls(t *testing.T) {
	parent, cancel := context.WithCancel(context.Background())
	defer cancel()
	if Phase(parent, "subject") != parent {
		t.Fatal("disabled observation changed the context")
	}
	Span(parent, "ignored")()
	ctx, trace := Start(parent)
	ctx = Phase(ctx, "comments")
	var wg sync.WaitGroup
	for i := 0; i < 40; i++ {
		wg.Add(1)
		go func() { defer wg.Done(); defer Span(ctx, "projection")() }()
	}
	wg.Wait()
	first := trace.Snapshot()
	if first.Stages["comments.projection"].Calls != 40 || first.Truncated || !first.ClockValid || first.Clock == "" {
		t.Fatalf("unexpected observation: %+v", first)
	}
	delete(first.Stages, "comments.projection")
	if trace.Snapshot().Stages["comments.projection"].Calls != 40 {
		t.Fatal("observer mutated recorder")
	}
	cancel()
	if ctx.Err() != context.Canceled {
		t.Fatal("observation detached cancellation")
	}
}

func TestTraceBoundsDistinctStages(t *testing.T) {
	ctx, trace := Start(context.Background())
	for i := 0; i < 100; i++ {
		Span(ctx, fmt.Sprintf("stage%d", i))()
	}
	value := trace.Snapshot()
	if len(value.Stages) != 64 || !value.Truncated {
		t.Fatalf("unbounded stages: %d, truncated=%v", len(value.Stages), value.Truncated)
	}
}
