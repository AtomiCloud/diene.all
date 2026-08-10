// Package testhelper ships the fakes and assertions consumers of
// github.com/AtomiCloud/diene.go-auth-engine would otherwise rebuild in every
// test suite.
//
// The auth engine is seam-heavy by design — a verification-key source, an identity
// provider, a token store, a deferred-login store, per-backend onboarding surfaces —
// and every one of them has to be faked before a consumer can test a single guarded
// handler. Rebuilding that scaffolding per repository is how subtly different fakes
// (one that forgets token expiry, one whose store is not atomic) end up proving
// different contracts in different services.
//
// [FakeIDP] is the centrepiece: it signs REAL RS256 tokens with a generated key
// pair and publishes them through a real [VerificationKeys] implementation, so a
// consumer's validation path is exercised end to end without a network, a container,
// or a live tenant. Its scriptable failure hooks then let a consumer prove the
// unhappy paths — expired, wrong issuer, unknown key — that are otherwise
// unreachable in a test.
//
// The assertion helpers depend only on the minimal [TestingT] interface, never on
// the concrete testing type, so they stay framework-free and are themselves
// black-box testable with a recording double.
package testhelper
