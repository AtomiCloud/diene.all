// Package boron contains Kubernetes-free Boron domain decisions: canonical
// hostname derivation, path normalization, install-profile admission, the
// shared-backend guardrail, and deterministic oldest-wins conflict ordering.
//
// This package is pure domain: it imports no k8s.io/* or sigs.k8s.io/* packages.
package boron

import (
	"fmt"
	"strings"
	"time"
)

// PublicServiceAnnotation marks a backend Service as also reachable via a public
// route (platinum). Exposing such a Service requires allowSharedBackend: true.
const PublicServiceAnnotation = "boron.atomi.cloud/public"

// Coordinates is the unchanged four-slot LPSM coordinate. Instance is a separate
// required projection field, never a fifth coordinate slot.
type Coordinates struct {
	Landscape string
	Platform  string
	Service   string
	Module    string
}

// ConflictCandidate identifies an Exposure competing for a hostname+path.
type ConflictCandidate struct {
	Namespace string
	Name      string
	CreatedAt time.Time
}

// Hostname derives Boron's one supported DNS form:
// <module>.<service>.<platform>.<instance>.<landscape>.<zone>.
func Hostname(c Coordinates, instance, zone string) string {
	parts := []string{c.Module, c.Service, c.Platform, instance, c.Landscape, zone}
	for i := range parts {
		parts[i] = strings.Trim(strings.ToLower(parts[i]), ".")
	}
	return strings.Join(parts, ".")
}

// NormalizePath provides the API default even to objects created before schema defaulting.
func NormalizePath(path string) string {
	if path == "" {
		return "/*"
	}
	return path
}

// ValidPath reports whether path is a CF-supported segment-boundary match: it
// must start with "/", carry at most one wildcard per segment (a segment is
// either "*" or wildcard-free), and no port, query string, or fragment. Anything
// finer (regex, partial-segment wildcards) is UnsupportedMatch.
func ValidPath(path string) bool {
	if !strings.HasPrefix(path, "/") {
		return false
	}
	if strings.ContainsAny(path, "?#:") {
		return false
	}
	for segment := range strings.SplitSeq(strings.TrimPrefix(path, "/"), "/") {
		if strings.Contains(segment, "*") && segment != "*" {
			return false
		}
	}
	return true
}

// Profile names Boron recognizes for Garden-managed installations, plus the
// registered-cluster admin exception.
const (
	ProfileLapras     = "lapras"
	ProfileDitto      = "ditto"
	ProfileRegistered = "registered"
)

// ProfileAdmission is the install-profile admission decision.
type ProfileAdmission struct {
	Allowed bool
	Reason  string
	Message string
}

// AdmitProfile decides whether this installation may program exposures at all.
// Garden installs Boron only on a connected lapras profile and, when explicitly
// requested for inspection, ditto. Hosted landscapes (eevee, plusle, minun) and
// hermetic landscapes (rotom, absol) never run Boron. An independently approved
// registered cluster is admitted regardless of connectivity.
func AdmitProfile(profile string, connected, dittoEnabled bool) ProfileAdmission {
	switch profile {
	case ProfileRegistered:
		return ProfileAdmission{Allowed: true, Reason: ReasonAccepted, Message: "registered-cluster admin installation"}
	case ProfileLapras:
		if !connected {
			return ProfileAdmission{Reason: ReasonProfileUnsupported, Message: "lapras profile is not connected; Boron programs exposures only on a connected laptop"}
		}
		return ProfileAdmission{Allowed: true, Reason: ReasonAccepted, Message: "connected lapras profile"}
	case ProfileDitto:
		if !connected || !dittoEnabled {
			return ProfileAdmission{Reason: ReasonProfileUnsupported, Message: "ditto runs Boron only when explicitly enabled for inspection on a connected run"}
		}
		return ProfileAdmission{Allowed: true, Reason: ReasonAccepted, Message: "explicitly inspectable ditto profile"}
	default:
		return ProfileAdmission{
			Reason:  ReasonProfileUnsupported,
			Message: fmt.Sprintf("profile %q never runs Boron (hosted human traffic is ENTEI-owned; hermetic profiles are tunnel-free)", profile),
		}
	}
}

// BackendURL produces the in-cluster origin URL for the tunnel ingress rule.
func BackendURL(namespace, name string, port int32) string {
	return fmt.Sprintf("http://%s.%s.svc.cluster.local:%d", name, namespace, port)
}

// SharedBackendAllowed enforces the explicit public/private sharing opt-in.
func SharedBackendAllowed(public, allowShared bool) bool {
	return !public || allowShared
}

// Older reports whether left wins Boron's deterministic oldest-wins ordering.
func Older(left, right ConflictCandidate) bool {
	if left.CreatedAt.Before(right.CreatedAt) {
		return true
	}
	if right.CreatedAt.Before(left.CreatedAt) {
		return false
	}
	leftKey := left.Namespace + "/" + left.Name
	rightKey := right.Namespace + "/" + right.Name
	return leftKey < rightKey
}
