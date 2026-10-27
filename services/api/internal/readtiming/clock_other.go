//go:build !linux

package readtiming

import "time"

const clockName = "GO_MONOTONIC"

var clockOrigin = time.Now()

func clockNow() (int64, bool) { return time.Since(clockOrigin).Nanoseconds(), true }
