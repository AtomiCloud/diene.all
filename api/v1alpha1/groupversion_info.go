// Package v1alpha1 holds the toy sample API surface for the operator template.
//
// It is a fenced sample domain (R2): consumers replace the Note/Journal types
// wholesale with their real CRDs while keeping the reusable operator machinery
// (ledger, brake, plan, adapters, chart, gates, harness) untouched.
//
// +kubebuilder:object:generate=true
// +groupName=sample.diene.atomi.cloud
package v1alpha1

import (
	"k8s.io/apimachinery/pkg/runtime/schema"
	"sigs.k8s.io/controller-runtime/pkg/scheme"
)

// ─── DOMAIN WIRING (sample) ──────────────────────────────────────────────────
// Per-instance API identity. Defined once (R4) at the top of its chain so the
// group/version is the single mechanical tokenization point for a consumer.

// GroupVersion is the group/version identity for the sample API.
var GroupVersion = schema.GroupVersion{Group: "sample.diene.atomi.cloud", Version: "v1alpha1"}

// ─── END DOMAIN WIRING (sample) ──────────────────────────────────────────────

// SchemeBuilder registers the sample types into a runtime scheme.
var SchemeBuilder = &scheme.Builder{GroupVersion: GroupVersion}

// AddToScheme adds the sample API types to a scheme.
var AddToScheme = SchemeBuilder.AddToScheme
