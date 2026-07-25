// Package v1alpha1 holds the Boron private-ingress API surface.
//
// +kubebuilder:object:generate=true
// +groupName=boron.atomi.cloud
package v1alpha1

import (
	"k8s.io/apimachinery/pkg/runtime/schema"
	"sigs.k8s.io/controller-runtime/pkg/scheme"
)

// GroupVersion is the group/version identity for Boron.
var GroupVersion = schema.GroupVersion{Group: "boron.atomi.cloud", Version: "v1alpha1"}

// SchemeBuilder registers the Boron types into a runtime scheme.
var SchemeBuilder = &scheme.Builder{GroupVersion: GroupVersion}

// AddToScheme adds the Boron API types to a scheme.
var AddToScheme = SchemeBuilder.AddToScheme
