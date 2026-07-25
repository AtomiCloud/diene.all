// Package testhelper ships the fake configuration sources, schema and overlay
// fixtures, pre-validated stub builders, and fail-fast assertions that
// consumers of github.com/AtomiCloud/diene.go-config would otherwise repeat in
// every test.
//
// The fakes are in-memory [github.com/AtomiCloud/diene.go-config/lib/config]
// sources, so a consumer drives the real loader over base, overlay, and env
// layers without touching the filesystem or the process environment. The
// fixtures include a valid composed schema over a neutral demo block (config
// never owns an engine's block), an invalid overlay whose merged result fails
// validation, and an uncompilable schema fragment for fault paths.
//
// The assertion helpers depend only on the minimal [TestingT] interface (which
// *testing.T satisfies), never on the concrete testing type, so they stay
// framework-free and are themselves black-box testable with a recording double.
package testhelper
