---
id: api-engine
title: API Engine
---

# API engine

`AtomiCloud.Diene.ApiEngine` is the typed backend-client layer. Every call to
another service comes back as `Result<T, Problem>` instead of an exception, and
every backend is declared once in a client tree addressed by the service tree.

It is a **client** only. The server half — the MVC controller base, the
exception-to-problem filter, the webhook scaffolding — lives in
`AtomiCloud.Diene.ServerEngine`.

## The client tree

A backend is declared once, with its address, its typed client, and nothing
else:

```csharp
services.AddAtomiClientTree(config, tree => tree
    .Register(notesAddress, http => new NotesClient(http))
    .Register(archiveAddress, http => new ArchiveClient(http)));
```

Each registration produces a named `HttpClient` carrying this engine's handler
pipeline plus a keyed typed client over it, so a call site may either resolve
through `IClientTree` or inject
`[FromKeyedServices("platform.service.module")]` directly.

The base address and timeout come from the engine-owned `HttpClient`
configuration block, keyed by the same address. There are no literals, and an
address with no configuration entry fails at composition rather than at the
first call to it.

### One hostname per backend

Each entry carries exactly **one** hostname. There is no physical URL list, no
round-robin, no circuit breaker, and no failover ladder. The gray-zone DNS A-set
is the platform's only failover mechanism, and a client-side copy of a routing
decision would be a second, staler source of truth for something the client
cannot see.

## Classification

`IApiCaller.Call` wraps one call to a generated client. HTTP has no result type
— only statuses, streams, and arbitrary bodies — and this is where that gap is
closed. Four outcomes, three of them failures:

| The upstream…                              | Becomes                          |
| ------------------------------------------ | -------------------------------- |
| answered successfully                      | `Ok(T)`                          |
| answered with an RFC 9457 problem envelope | that problem, verbatim           |
| answered with JSON that is not a problem   | `UpstreamRejected` (502)         |
| produced nothing interpretable             | `UpstreamTransportFailure` (504) |

The last two are deliberately **different problem types**. One means "the
service answered and said no", the other means "there is no answer to read".
Only the second is recoverable, and conflating them is what makes a caller retry
a rejection forever or give up on a blip.

A problem envelope is recognised by shape — a string `type`, a string `title`,
and a numeric `status` — and is found whether it is the body itself or nested
under a wrapper member, up to a bounded depth. Recognition is by parsing, not by
media type: a service that sends a problem under `application/json` is still
sending a problem, and one that claims `application/problem+json` while sending
an HTML error page is not.

No exception escapes a wrapped call. That includes a defect in the generated
client itself, which is reported by name in the problem detail rather than
swallowed.

### How the body reaches the classifier

A generated client turns an error response into its own exception type and does
not promise to carry the body on it. So the body is read from the **pipeline**
instead: a capture handler records the failed exchange into a per-call ambient
slot, and the classifier reads it there. That is what keeps the engine
generator-agnostic — any client built over the tree's `HttpClient` is
classifiable, with no reflection over exception shapes and no dependency on a
particular generator's abstractions.

## Per-backend authentication

An upstream with an `authResource` gets its own auth handler, bound to that
resource at registration. There is no shared token and no code path along which
one backend's credential could be sent to another. Tokens are acquired through
auth-engine's cache, so a burst of calls performs one acquisition and a token is
renewed within skew of expiry rather than after a request has already failed
with it.

A token that cannot be acquired throws its typed problem rather than sending the
request unauthenticated. The wrapper unwraps it back into the original problem,
so an identity-provider outage reads as an authentication failure and not as an
unreachable upstream.

## Retry-once-on-network-error

On an **opaque** network-level failure — no HTTP status received at all — the
transport retries exactly once over a fresh connection, then surfaces the
failure. The attempt count is carried in the problem payload, so "exactly one
retry" is checkable rather than asserted.

A received status is never retried, not even a 5xx: a status means the request
arrived and was processed, so retrying risks repeating a non-idempotent effect
for no gain. A timeout is not retried either — the caller asked for an answer
within a budget, and spending that budget twice serves it worse than telling it
the truth once.

## Rescue routing

When both attempts fail opaquely, the transport-failure problem reports whether
the dormant rescue-routing trip point is armed for that upstream. This engine
only reports it. The router that would act on it — catalog lookup, suffix
allowlist, budgeted candidate scan — lives in the frontend utilities, and
putting it here would make every server runtime carry a rescue path it must not
use.
