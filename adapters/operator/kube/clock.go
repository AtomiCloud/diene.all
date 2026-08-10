// Package kube holds the thin k8s-facing adapter seams the controllers depend on
// so that (a) the pure lib never imports k8s types, (b) reconciles stay thin, and
// (c) int-tier tests can inject deterministic collaborators. It provides a Clock,
// an event Recorder port, and a narrow owned-resource (ConfigMap) port, each
// implemented over controller-runtime.
package kube

import "time"

// Clock is the time seam controllers use to stamp condition transitions, so
// envtest runs can inject a fixed clock for deterministic assertions.
type Clock interface {
	Now() time.Time
}

// RealClock is the production Clock backed by the wall clock.
type RealClock struct{}

// Now returns the current wall-clock time.
func (RealClock) Now() time.Time { return time.Now() }
