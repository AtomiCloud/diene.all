// Package apiengine is the Go family's outbound API client engine.
//
// It is CLIENT ONLY. It hosts nothing: no middleware, no controllers, no
// health or readiness endpoints, and no error-info publishing. Those belong to
// the base template's hosting layer or to the error portal, and keeping them out
// is what lets a pure worker — an operator with no HTTP surface at all — depend
// on this library.
//
// # The three cases
//
// Every response falls into exactly one of three cases, and [Execute] maps them
// onto Go's ordinary (T, error) pair:
//
//   - 2xx — the body decodes into T and the error is nil.
//   - 4xx — the backend's own RFC 9457 envelope surfaces as a
//     *[problem.Error], with its type, title, status and `data` extension
//     intact. It is NOT re-minted: that envelope is the contract the backend
//     published, and rewriting it would strip the typed payload the caller
//     came for.
//   - 5xx or a transport failure — an api-engine problem-typed error. C0
//     groups these because they are indistinguishable to a caller: in both
//     cases the backend never gave an answer it stands behind.
//
// # Many backends, one consumer
//
// A consumer onboards to MANY backends, so [ClientTree] is the registry: one
// entry per backend, each with its own origin and its own token. Tokens resolve
// per backend through the auth-engine's [authengine.Retriever] seam — a
// *authengine.TokenCache satisfies it — so this library never learns whether a
// user session or a client-credentials flow produced the token it attaches.
//
// # Resilience
//
// The profile is retry-once-on-network-error and nothing more. This is not load
// balancing, and there is no client-side routing between regions: the DNS gray
// zone owns routing (ARCHITECTURE §4), so each registered backend is one
// hostname and a region is simply another registered backend.
//
// # Configuration
//
// [ConfigBlockSchema] publishes this engine's owned config block (C0 §3). This
// library never merges or validates a consumer's wider document — the config lib
// is the sole merger and validator; a consumer composes this block into its root
// schema alongside the other engines' blocks.
//
// Durations in that block are ISO 8601 (C0 §1) via the sibling package
// [github.com/AtomiCloud/diene.go-api-engine/lib/wire], which also carries the
// RFC 3339 instant and IANA zone types for values that cross the wire.
package apiengine
