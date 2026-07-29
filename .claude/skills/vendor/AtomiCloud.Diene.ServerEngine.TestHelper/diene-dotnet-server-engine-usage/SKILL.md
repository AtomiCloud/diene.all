---
name: diene-dotnet-server-engine-usage
description: Use AtomiCloud.Diene.ServerEngine and its TestHelper in .NET services. Use when writing an MVC controller, rendering a typed problem as an HTTP response, exposing the system or OnboardSync routes, or receiving a signed internal webhook delivery.
---

# Diene .NET Server Engine usage

The MVC server wiring every Diene service shares: one controller base, one error
shape, the system routes, OnboardSync, and the signed
`/internal/webhooks/{provider}` receiver.

## Compose in this order

```csharp
builder.Services
    .AddAtomiProblems(identity, portal, catalog => catalog.AddBaseline())
    .AddAtomiServerEngine(config)
    .AddAtomiWebhookSecrets(internalWebhookSecret)
    .AddAtomiWebhookHandler(sp => new StripeHandler(sp.GetRequiredService<INotes>()));

app.MapControllers();
```

Problems FIRST. The exception filter resolves the catalog and the type-URI
builder the moment it renders anything, so the wrong order fails at the first
error rather than at startup.

`AddAtomiServerEngine` also adds this package's assembly as an MVC application
part. **Your own controllers are a separate part.** If you drive your service from
a test host, the entry assembly is the test project, so register your assembly
explicitly or every one of your routes 404s with nothing reporting why:

```csharp
builder.Services.AddControllers().AddApplicationPart(typeof(MyController).Assembly);
```

## Derive from AtomiController and return Results

```csharp
[Route("notes")]
public sealed class NotesController(INotes notes) : AtomiController
{
    [HttpGet("{id}")]
    public Task<ActionResult<Note>> Get(string id) => this.ResolveAsync(notes.FindAsync(id));

    [HttpDelete("{id}")]
    public Task<ActionResult> Delete(string id) => this.ResolveEmptyAsync(notes.EraseAsync(id));
}
```

`Resolve` answers 200 with the value, `ResolveEmpty` answers 204, and either
raises the typed problem so the shipped filter renders it. There is exactly ONE
place that writes an error response — do not add a second by returning
`BadRequest(...)` or `Problem(...)` from an action.

**Do not add `[ApiController]`.** It installs an automatic 400 for model-state
failures in ASP.NET's own shape, so your service would emit two error contracts.
Without it a malformed body arrives as a null model; validate it and return a
typed problem.

**Register your problems.** `AddBaseline()` covers the seven portable problems. A
problem no catalog holds renders as 500 with an `about:blank` type — correct, but
not what you meant.

## The webhook contract punishes two plausible mistakes

Implement `IWebhookHandler`; the signature is already verified and the envelope
already validated before you are called.

```csharp
public sealed class StripeHandler(INotes notes) : IWebhookHandler
{
    public string Provider => "stripe";

    public async Task<Result<WebhookOutcome, IDomainProblem>> HandleAsync(
        WebhookEnvelope envelope,
        CancellationToken cancellationToken = default)
    {
        var key = WebhookIdempotency.KeyOf(envelope);
        if (await notes.SeenAsync(key, cancellationToken)) return WebhookOutcome.Processed;
        ...
    }
}
```

- Return `WebhookOutcome.NotMine` for an event you do not own. It answers **421**.
  **NEVER 404.** Mercury reads 404 as a real endpoint failure and retries for the
  full 72-hour window, then dead-letters the event.
- Return a typed problem only for a REAL error. Mercury will retry it.
- `Processed` answers exactly **200**. Every other 2xx is a real failure to
  mercury, which is why the reply is not yours to choose.
- **Be idempotent.** Mercury acks the provider before your obligation finishes, so
  a redelivery and a cross-landscape provider retry can both arrive. Dedup on
  `WebhookIdempotency.KeyOf`, never on `delivery.attempt` or arrival order.
- Never hand-roll signature verification. It ships here, it is constant-time
  against every live rotation key, and its failure is 401 — never 421.

Supply every live rotation key to `AddAtomiWebhookSecrets`. During a rotation both
the outgoing and incoming keys must verify, or in-flight deliveries are rejected.

## Configuration is validated, not constructed

```csharp
var identity = ServiceIdentityConfig.Create("lapras", "sulfoxide", "notes", "api", version);
if (identity.IsFailure(out var error)) throw new InvalidOperationException(error.ToString());
```

The factories name the offending field. `WebhookConfig.Create` refuses a tolerance
ABOVE the C0 maximum rather than clamping it, so a receiver that asked for ten
minutes is told so instead of quietly getting five.

## Wire formats come from the package

`AddAtomiServerEngine` applies the C0 contract to MVC's JSON: camelCase, RFC 3339
UTC instants, ISO 8601 durations, IANA timezone ids, decimals and 64-bit integers
as strings, and enums as snake_case NAMES. Call
`ServerEngineServiceCollectionExtensions.ApplyWireContract` on options you own
elsewhere — a client that reads with default options will fail on the enum names.

## Testing with the TestHelper

```csharp
await using var host = await ServerEngineTestHost.StartAsync(options =>
{
    options.Handlers.Add(new RecordingWebhookHandler("stripe"));
    options.Now = new DateTimeOffset(2026, 1, 1, 0, 0, 0, TimeSpan.Zero);
});

var body = new WebhookEnvelopeBuilder().ToBytes();
(await host.DeliverAsync("stripe", body)).ShouldBeProcessed();
```

- `ServerEngineTestHost` runs the real routing, filter, and negotiation pipeline
  with no socket. It ships a `/probe` controller so you can prove the filter is
  wired into YOUR host without needing a controller whose failure you predicted.
- Use `ShouldBeProcessed`, `ShouldBeNotMine`, `ShouldBeSignatureRejected`,
  `ShouldBeUnsupportedMedia`, `ShouldBeMalformedEnvelope` rather than comparing
  status codes. They refuse the wrong-but-plausible status by construction, and
  the 404 case says why.
- `host.Clock.Advance(...)` reaches the stale-timestamp case; `host.Secrets.Rotate`
  and `host.Secrets.Forget` reach the rotation and lost-secret cases. Those three
  are the ones a real clock and a real secret cannot reach.
- `WebhookEnvelopeBuilder.With` / `WithNested` build the INVALID envelopes — a
  removed field, an uppercase header name, an unpadded payload — that a typed
  record cannot express.
- Assert bodies with the published Problems TestHelper: `await response.Should()
  .BeRfc9457()`. Every response this package writes satisfies it, including the
  webhook protocol refusals.
