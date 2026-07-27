// Package v1alpha1 holds the Problem catalog API surface.
//
// The Problem group is a SEPARATE API tree from the fleet registry package and
// from the sample domain package: it owns its own group constant, SchemeBuilder
// and AddToScheme, and nothing derives one group's identity from another. The
// group is atomi.cloud, taken from the canonical error-portal sketch and the
// shipped consumer fixture, both of which render this kind at apiVersion
// atomi.cloud/v1alpha1. The string problems.atomi.cloud is ONLY the
// plural.group CRD NAME; it is not a group. The fleet group constant is never
// inherited, aliased or composed here — this package imports no other API
// package, and a test pins the two constants apart.
//
// This tree is SCHEMA-ONLY in Phase 2. No reconciler, no webhook server and no
// merge loop live in this binary for Problem: the merge component (erbium's
// error-portal job, folded later as the reserved seventh --enable-problem
// sub-component seam) owns semantic validation, cross-row merging and every
// status write. The traffic controller separately publishes the derived edge
// catalog doc, and frontends read that doc rather than this CR at runtime.
//
// +kubebuilder:object:generate=true
// +groupName=atomi.cloud
package v1alpha1

import (
	"k8s.io/apimachinery/pkg/runtime/schema"
	"sigs.k8s.io/controller-runtime/pkg/scheme"
)

// Group is the Problem API group. It is declared here once and never composed
// from another package's constant. The CRD NAME built from it is
// problems.atomi.cloud.
const Group = "atomi.cloud"

// Version is the Problem API version.
const Version = "v1alpha1"

// GroupVersion is the group/version identity for the Problem API.
var GroupVersion = schema.GroupVersion{Group: Group, Version: Version}

// SchemeBuilder registers the Problem types into a runtime scheme.
var SchemeBuilder = &scheme.Builder{GroupVersion: GroupVersion}

// AddToScheme adds the Problem API types to a scheme.
var AddToScheme = SchemeBuilder.AddToScheme
