// Package v1alpha1 holds the fleet registry API surface.
//
// The fleet group is a SEPARATE API tree from the sample domain in
// api/v1alpha1 and from the Problem API in api/problems/v1alpha1: it owns its
// own group constant, SchemeBuilder and AddToScheme, and nothing derives one
// group's identity from another. The group string is a discovered consumer
// contract — carbon's primordial chart and every service primordial chart
// render these kinds at apiVersion fleet.atomi.cloud/v1alpha1 — so it is
// pinned by a test, never re-derived.
//
// +kubebuilder:object:generate=true
// +groupName=fleet.atomi.cloud
package v1alpha1

import (
	"k8s.io/apimachinery/pkg/runtime/schema"
	"sigs.k8s.io/controller-runtime/pkg/scheme"
)

// Group is the fleet API group. It is declared here once and never composed
// from another package's constant.
const Group = "fleet.atomi.cloud"

// Version is the fleet API version.
const Version = "v1alpha1"

// GroupVersion is the group/version identity for the fleet API.
var GroupVersion = schema.GroupVersion{Group: Group, Version: Version}

// SchemeBuilder registers the fleet types into a runtime scheme.
var SchemeBuilder = &scheme.Builder{GroupVersion: GroupVersion}

// AddToScheme adds the fleet API types to a scheme.
var AddToScheme = SchemeBuilder.AddToScheme
