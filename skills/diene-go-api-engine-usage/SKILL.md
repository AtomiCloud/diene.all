---
name: diene-go-api-engine-usage
description: Use the diene Go api-engine — the multi-backend client tree, 3-case response classification, the engine-owned config block, the retry-once profile, C0 wire codecs, and its TestHelper.
---

# Diene Go api-engine usage

`github.com/AtomiCloud/diene.go-api-engine` is the Go family's outbound API
client engine. It is **client only** — it hosts nothing. Middleware, controllers,
health and readiness endpoints, and error-info publishing belong to the base
template's hosting layer or the error portal, never here. That is what lets a
pure worker with no HTTP surface depend on it.

Every fallible call returns `(T, error)` where the error carries an RFC 9457
`problem.Problem`; recover it with
`var pe *problem.Error; errors.As(err, &pe)`.

Start with the compiling examples in `lib/apiengine/example_test.go`,
`lib/wire/example_test.go`, and `testhelper/example_test.go`.

## The three cases

`apiengine.Execute[T]` maps every response onto exactly three outcomes:

| case               | what you get                                         |
| ------------------ | ---------------------------------------------------- |
| `2xx`              | the body decoded into `T`, `err == nil`              |
| `4xx`              | the **backend's own** envelope as a `*problem.Error` |
| `5xx` or transport | an api-engine problem-typed error                    |

Do: read the backend's `data` extension off the returned envelope — it is the
typed payload the backend published.

Don't: re-mint or rewrite a 4xx envelope. This library deliberately passes it
through untouched, because rewriting it strips the contract the caller came for.

C0 groups 5xx with transport because they are indistinguishable to a caller: in
both cases the backend never gave an answer it stands behind. A 4xx without an
envelope is NOT silently turned into one — you get
`apiengine.ProblemResponseNotProblem`, naming the non-conformant backend.

Use `apiengine.Classify` directly only if you are driving the transport
yourself; `Execute` already applies it. Use `Client.Call` when you need the raw
status or headers, and `apiengine.Send` when you do not need the body.

## The multi-backend client tree

One consumer onboards to MANY backends. Register them all in the config block and
build ONE `apiengine.ClientTree`; resolve a client with `tree.Backend(name)`.

Do: treat a region as just another registered backend. Each registered backend is
one hostname.

Don't: build client-side routing or a host list per backend. Routing between
regions is deleted — the DNS gray zone owns it (ARCHITECTURE §4).

Tokens resolve **per backend** through the auth-engine seam. Pass
`TreeOptions.Tokens` an `authengine.Retriever`; a `*authengine.TokenCache`
satisfies it, and `authengine.NewClientCredentialsSource` behind that cache
covers the operator m2m flow. Do not rebuild those seams. A backend whose
`resource` differs from its logical name sets `BackendConfig.Resource`; a backend
needing no credentials just omits `Indicator` and is called unauthenticated.

`Config.Tree` derives the auth-engine `ResourceTree` from the same block, so the
token cache and the client tree can never drift into two disagreeing lists.

## Resilience

The profile is **retry once on a network error, and nothing else**. Not load
balancing, not a backoff ladder. One transport failure is retried exactly once —
enough to ride out a connection reset — and then surfaces as a problem-typed
error. A 5xx is never retried.

Set it with `RetryConfig{Network: true, Delay: wire.Duration(...)}`. Inject
`Sleep` in tests so the pause costs no wall-clock time.

## Configuration

`apiengine.ConfigBlockSchema()` publishes this engine's owned block under
`apiengine.ConfigBlockKey` (`api`), per C0 §3's every-engine-owns-its-block rule.

Do: compose that schema into your root schema alongside the other engines'
blocks, and let the CONFIG lib merge and validate the whole document.

Don't: expect this library to merge or validate your config. It validates only
its own block, once, via `Config.Validate`.

## Wire formats (C0 §1)

Use `lib/wire` for any value crossing the wire — Go's own defaults disagree with
the contract:

- `wire.Duration` — ISO 8601 (`PT10S`), not Go's integer nanoseconds.
- `wire.Instant` — RFC 3339 **UTC** instant; rendering always normalizes to UTC.
- `wire.Zone` — IANA identifier (`Asia/Singapore`). An offset (`+08:00`) or an
  abbreviation (`SGT`) is rejected: neither resolves back to the political rules
  a future timestamp must be read under.

Calendar durations `P1Y`/`P1M` are rejected — a year and a month have no fixed
length, so they cannot become an exact duration.

## TestHelper

Import `github.com/AtomiCloud/diene.go-api-engine/testhelper`.

- `NewFakeTree` — a whole multi-backend tree over fakes in one call, with a
  no-op retry sleep already wired.
- `NewFakeBackend` — an in-process backend answering by path. `Routes` map a path
  to a `Route`; `TransportFailures: 1` exercises the retry, `2` exhausts it.
  A path with no route answers with an RFC 9457 404, because a real
  C0-conformant backend does not answer a miss with a bare status.
- `Canned` / `ProblemResponse` — mint the RFC 9457 envelope a 4xx test needs,
  including its `data` extension.
- `NewFakeRetriever` — a per-resource token source; `Asked()` proves each backend
  got its OWN token, and `FailResource` reaches the credentials-unavailable path.
- `AssertProblem` / `AssertOutcome` / `AssertCount` — and their `Check*` halves
  for use without a `*testing.T`. Only the fields you set on `ProblemOptions`
  are compared, so assert the `data` extension you care about and nothing else.

Prove the retry with `AssertCount(t, backend, 2)`: the original attempt plus the
one permitted retry.

## Pointers

- Package docs: <https://pkg.go.dev/github.com/AtomiCloud/diene.go-api-engine>
- Problem envelope and catalog:
  <https://pkg.go.dev/github.com/AtomiCloud/diene.go-errors-problems>
- Token seams: <https://pkg.go.dev/github.com/AtomiCloud/diene.go-auth-engine>
