// Package logto is the Logto adapter behind the auth-engine provider seam.
//
// Logto is the only identity-provider implementation in v1 and no second provider
// is planned, but it still lives behind
// github.com/AtomiCloud/diene.go-auth-engine/lib/authengine's Provider interface:
// that is what keeps Logto's HTTP shape out of the engine's decisions and lets
// consumer tests drive minting, rotation, and claim write-back without a live
// tenant.
//
// Every platform that needs authentication runs its OWN Logto instance with its own
// issuer and its own user pool — they are auth-isolated by design. This package
// therefore takes its endpoints as configuration and never assumes a shared tenant.
//
// The deployed Logto is a maintained fork driven by a declarative operator; this
// package only speaks its API and owns none of its configuration plane.
package logto
