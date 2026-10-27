//go:build linux

package readtiming

import "golang.org/x/sys/unix"

const clockName = "CLOCK_MONOTONIC_RAW"

// A failed diagnostic clock invalidates the observation, never authorization.
func clockNow() (int64, bool) {
	var value unix.Timespec
	if unix.ClockGettime(unix.CLOCK_MONOTONIC_RAW, &value) != nil {
		return 0, false
	}
	return value.Nano(), true
}
