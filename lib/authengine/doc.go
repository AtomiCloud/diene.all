// Package authengine implements the AtomiCloud Go server-side auth contract:
// JWT/JWKS validation against a baked OIDC issuer, claims-to-principal mapping,
// per-resource access tokens over the resourceTree model, machine-to-machine
// client-credential flows, and the family nullable-userId ownership
// authorization pattern.
//
// The package is transport-free by design. It ships decision machinery
// (validation, token resolution, ownership guards, named claim policies) rather
// than an HTTP framework: the Go family has no server-engine analogue, so no
// middleware, controller base class, or webhook surface lives here. Consumers
// that grow an HTTP surface wire these decisions into their own handlers.
//
// Every fallible surface returns the idiomatic (T, error) pair with
// problem-typed failures minted through
// github.com/AtomiCloud/diene.go-errors-problems, so an auth failure is an RFC
// 9457 envelope the whole family already understands. Recover it with:
//
//	var pe *problem.Error
//	if errors.As(err, &pe) {
//		use(pe.Problem)
//	}
//
// Nondeterminism arrives through injected seams only — the clock through
// github.com/AtomiCloud/diene.go-interfaces System, verification keys through
// [VerificationKeys], the IdP through [Provider], and the token cache through
// [TokenStore] — which is what makes the whole surface black-box testable and
// is what the shipped testhelper package fakes.
package authengine
