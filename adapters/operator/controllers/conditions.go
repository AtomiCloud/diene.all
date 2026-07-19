// Package controllers holds the thin controller-runtime glue: it guards,
// validates, routes, and delegates to the pure lib services, then flips the
// standard condition vocabulary from their outputs. Business rules live in
// lib/operator/*; k8s resource I/O lives behind the adapters/operator/kube ports.
// This layer carries no domain decisions (the architecture gate enforces it).
package controllers

import (
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	"github.com/AtomiCloud/diene.go-base/lib/operator/plan"
)

// applyCondition maps a pure, k8s-free plan.Condition onto a metav1.Condition
// slice, stamping the transition time from the injected clock so int-tier tests
// are deterministic.
func applyCondition(conditions *[]metav1.Condition, c plan.Condition, generation int64, now metav1.Time) {
	meta.SetStatusCondition(conditions, metav1.Condition{
		Type:               c.Type,
		Status:             metav1.ConditionStatus(c.Status),
		Reason:             c.Reason,
		Message:            c.Message,
		ObservedGeneration: generation,
		LastTransitionTime: now,
	})
}
