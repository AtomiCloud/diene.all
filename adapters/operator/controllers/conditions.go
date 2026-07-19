// Package controllers holds the thin controller-runtime glue: it maps API input
// and output, invokes the pure reconcile service, executes the returned plan
// through the kube/ledger ports, and flips Kubernetes status, events, and
// metrics. It carries no domain decisions and imports no decision internals
// (lib/operator/{note,plan,brake}); the architecture gate enforces that.
package controllers

import (
	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	"github.com/AtomiCloud/diene.go-base/lib/operator/reconcile"
)

// applyCondition maps a pure, k8s-free reconcile.Condition onto a metav1.Condition
// slice, stamping the transition time from the injected clock so int-tier tests
// are deterministic.
func applyCondition(conditions *[]metav1.Condition, c reconcile.Condition, generation int64, now metav1.Time) {
	meta.SetStatusCondition(conditions, metav1.Condition{
		Type:               c.Type,
		Status:             metav1.ConditionStatus(c.Status),
		Reason:             c.Reason,
		Message:            c.Message,
		ObservedGeneration: generation,
		LastTransitionTime: now,
	})
}
