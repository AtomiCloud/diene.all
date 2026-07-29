---
name: diene-dotnet-api-engine-usage
description: Use AtomiCloud.Diene.ApiEngine and its TestHelper in .NET services. Use when calling another service, registering a backend in the client tree, turning an upstream response into Result<T, Problem>, attaching a per-backend token, or faking an upstream in tests.
---

# Diene .NET API Engine usage

The typed backend-client layer. Every call to another service returns
`Result<T, Problem>`; nothing on this surface throws to report an upstream
failure. This package is a **client** — the MVC controller base and the
exception-to-problem filter live in `AtomiCloud.Diene.ServerEngine`.

## Register each backend once, from configuration

```csharp
var config = ApiEngineConfig.Create(options).Get();   // check the failure, see below

builder.Services.AddAtomiClientTree(config, tree => tree
    .Register(notesAddress, http => new NotesClient(http))
    .Register(archiveAddress, http => new ArchiveClient(http)));
```

The address is a `ServiceAddress` — `platform`, `service`, `module`; the
landscape is implied by where the service is deployed, so a client cannot
address another landscape. Its `ToString()` is both the keyed-service key and
the configuration key, so a backend is named the same way everywhere.

Build configuration through `ApiEngineConfig.Create` and check the failure. It
names the offending field:

```csharp
var built = ApiEngineConfig.Create(options);
if (built.IsFailure(out var error)) throw new InvalidOperationException(error.ToString());
```

Never construct configuration around the factory. Validation is where a
non-absolute base address, a non-ISO-8601 timeout, or scopes on an
unauthenticated upstream get rejected — at composition, with the field named,
rather than at the first call.

**Do not add a second base address for a backend.** One hostname per upstream is
the design. Physical URL lists, round-robin, circuit breakers, and failover
ladders are deliberately absent: the gray-zone DNS A-set is the platform's
failover mechanism, and a client-side list is a staler copy of a decision the
client cannot see.

## Wrap every call

```csharp
var outcome = await caller.Call(notesAddress, ct => client.GetNoteAsync(id, ct));

return outcome.Match(
    note => Ok(note),
    problem => Problem(problem));
```

One line of ceremony per call, and in exchange no exception escapes — including a
defect in the generated client, which is named in the problem detail rather than
swallowed. Resolve the client from `IClientTree`, or inject it directly:

```csharp
public NoteService([FromKeyedServices("lithium.notes.note")] NotesClient notes) { … }
```

### The four outcomes

| The upstream…                              | You get                          |
| ------------------------------------------ | -------------------------------- |
| answered successfully                      | `Ok(T)`                          |
| answered with an RFC 9457 problem envelope | that problem, verbatim           |
| answered with JSON that is not a problem   | `UpstreamRejected` (502)         |
| produced nothing interpretable             | `UpstreamTransportFailure` (504) |

**Branch on the last two separately.** `UpstreamRejected` means the service
answered and said no — retrying gets the same answer.
`UpstreamTransportFailure` means there is no answer to read, and it is the only
recoverable one. Treating them alike is how a caller retries a rejection forever
or gives up on a network blip.

Register both in your catalog so their type URIs resolve to your error portal:

```csharp
builder.Services.AddAtomiProblems(identity, portal, catalog => catalog
    .AddBaseline()
    .AddApiEngineProblems());
```

The statuses and recoverability come from `ApiEngineProblems` constants, which
are the same values the classifier stamps on the wire — so the catalog row and
the envelope cannot drift.

## Attach a token per backend

Set `authResource` (and any scopes) on the upstream's configuration entry. Each
backend then gets its own handler bound to its own resource; there is no shared
token and no path along which one backend's credential reaches another. Register
auth-engine's `TokenCache` and the engine picks it up:

```csharp
services.AddSingleton<TokenCache>();   // over your ICredentialClient, IAuthClock, TokenLifetimeConfig
```

Do not attach an `Authorization` header yourself, and do not reuse one upstream's
resource for another because "it is the same identity provider". The resource is
what scopes the token.

## Testing with the TestHelper

`AtomiCloud.Diene.ApiEngine.TestHelper` fakes the **network**, not the client
tree. Plug a `FakeUpstream` in as the primary handler so the real pipeline —
auth, retry, capture, classification — is what runs:

```csharp
var upstream = new FakeUpstream("notes");
upstream.RespondOk(UpstreamResponses.Payload(new { id = "n-1" }));
upstream.RespondProblem(HttpStatusCode.NotFound, UpstreamResponses.Problem(type, title, 404, detail));

services.AddHttpClient("lithium.notes.note")
    .ConfigurePrimaryHttpMessageHandler(() => upstream);
```

`UpstreamResponses` builds a body for every branch of the matrix — problem,
nested problem, non-problem JSON, plain payload — through the platform
serializer, so a change to the wire contract reaches your fixtures instead of
leaving them describing an older one.

Assert on outcomes with the shipped assertions, which decode this engine's typed
payloads for you:

```csharp
outcome.ShouldBeOk();
outcome.ShouldBePassedThrough(upstreamTypeUri).ShouldHaveStatus(404);
outcome.ShouldBeUpstreamRejected().Body.Should().Contain("legacy");
outcome.ShouldBeTransportFailure().Attempts.Should().Be(2);
```

**Assert the attempt COUNT, not that "it retried".** `FakeUpstream.Attempts` is
the number of requests that reached the wire, and it is the only way to tell one
retry from three or none. `FakeUpstream` throws when its queue is exhausted for
exactly this reason — an unexpected extra call is the defect worth catching.

For tokens, `FakeTokens.Cache(resources)` mints one token per resource whose
value names that resource, so a cross-backend leak shows up in the header the
fake upstream recorded. It composes over auth-engine's own published
`FakeCredentialClient` rather than reimplementing that port.

`FakeClientTree` is for a subject that takes `IClientTree` and resolves from it.
It has **no pipeline**, so it cannot prove anything about auth attachment,
retries, or classification — use a real tree over a `FakeUpstream` for those.
