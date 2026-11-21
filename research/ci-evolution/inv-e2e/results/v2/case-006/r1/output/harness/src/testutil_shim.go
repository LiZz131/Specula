// Package testutil is a minimal build shim for the supplied raft subset.
// The real package is absent from the immutable input; only the scheduler
// helper referenced by node_test.go is provided. Focused Specula tests do not
// call it.
package testutil

import "time"

// WaitSchedule briefly yields so other goroutines can be scheduled.
func WaitSchedule() { time.Sleep(10 * time.Millisecond) }
