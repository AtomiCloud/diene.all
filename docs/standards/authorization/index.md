# Authorization

Authorization for owned resources uses validated identity claims plus a nullable
`userId` ownership filter. There is no FGA, OpenFGA, relationship checker, policy
engine, or authorization service. The contract is:

```text
authorization = validated claims + nullable-userId ownership filtering
```

The reference implementation is the production zinc API. Every server-side
implementation follows the same three-layer flow even when the host language uses
different names.

## Outcomes

- **Owner:** passes their own `userId`; the subject claim matches and the data layer
  filters to that owner.
- **Admin or system caller:** omits `userId`; the subject comparison cannot pass, so
  an approved role must pass; the data layer receives null and does not add an owner
  filter.
- **Attacker:** passes another user's id, or omits the id without an approved role;
  both guard paths fail with a problem-typed 403 response.

The guard and repository filter are one indivisible contract. Null means
"unfiltered" only after the controller has proved that the caller has an approved
role.

## The Three Layers

```text
CONTROLLER  nullable userId + resource id
            -> guard against token subject or approved roles
            -> call service only after the guard passes

SERVICE     accept nullable userId and forward it unchanged
            -> no authorization logic and no subject lookup

DATA        apply the owner predicate only when userId is non-null
            -> null is the role-authorized unfiltered path
```

### Controller: Guard First

Every owned-resource endpoint accepts a nullable `userId` next to its resource
identifier. Search endpoints carry the same nullable value on their query model.
The guard is the first operation in the result chain.

```csharp
[Authorize, HttpGet("{id:guid}")]
public async Task<ActionResult<BookingRes>> Get(Guid id, string? userId)
{
  var result = await this
    .GuardOrAnyAsync(userId, AuthRoles.Field, AuthRoles.Admin, AuthRoles.Tin)
    .ThenAwait(_ => service.Get(userId, id))
    .Then(value => value?.ToRes(), Errors.MapAll);

  return this.ReturnNullableResult(
    result,
    new EntityNotFound("Booking not found", typeof(Booking), id.ToString())
  );
}
```

Search uses the same shape:

```csharp
public record SearchBookingQuery(
  string? Date,
  string? Direction,
  string? Status,
  string? Time,
  string? UserId,
  string? PassportNumber,
  int? Limit,
  int? Skip
);

[Authorize, HttpGet]
public async Task<ActionResult<IEnumerable<BookingPrincipalRes>>> Search(
  [FromQuery] SearchBookingQuery query
)
{
  var result = await this
    .GuardOrAnyAsync(query.UserId, AuthRoles.Field, AuthRoles.Admin, AuthRoles.Tin)
    .ThenAwait(_ => validator.ValidateAsyncResult(query, "Invalid search query"))
    .ThenAwait(value => service.Search(value.ToDomain()));

  return this.ReturnResult(result);
}
```

Use the all-roles variant for stricter writes. Admin-only endpoints with no owner
variant use a named authorization policy instead of a nullable ownership guard.

### Guard Family

The reference server exposes these operations; library implementations may use
clearer `GuardSub*` names while preserving the semantics.

```csharp
protected Result<Unit> Guard(string? target);
protected Task<Result<Unit>> GuardAsync(string? target);
protected Result<Unit> GuardOrAll(string? target, string field, params string[] values);
protected Task<Result<Unit>> GuardOrAllAsync(string? target, string field, params string[] values);
protected Result<Unit> GuardOrAny(string? target, string field, params string[] values);
protected Task<Result<Unit>> GuardOrAnyAsync(string? target, string field, params string[] values);
```

- `Guard(target)` passes only when `target` is non-null and equals the validated
  token subject.
- `GuardOrAny(target, field, values)` passes when the subject matches or any listed
  scope value is present.
- `GuardOrAll(target, field, values)` passes when the subject matches or all listed
  scope values are present.
- Null never passes the subject half. Omitting `userId` is therefore an
  administrator-only operation.
- Failures return an RFC 9457-compatible `Unauthorized` result with granted and
  required scope data. They do not throw.

The subject comes only from the validated token. In the .NET reference,
`NameClaimType = ClaimTypes.NameIdentifier` maps the JWT `sub` claim to
`User.Identity.Name`.

### Roles and Policies

Applications own their role vocabulary as plain constants over token claims:

```csharp
public static class AuthRoles
{
  public const string Field = "roles";
  public const string Admin = "admin";
  public const string Tin = "tin";
}
```

Named policies are configuration-driven combinations of a claim field, an
`Any`/`All` operator, and target values. The JWT scheme validates issuer, audience,
signature, and lifetime before any guard reads claims. Every platform uses its own
configured lithium issuer; the authorization pattern does not assume a shared user
pool.

### Service: Pass Through

The service carries the nullable id verbatim. It neither fills a default nor reads
the current subject.

```csharp
public Task<Result<Booking?>> Get(string? userId, Guid id)
{
  return repo.Get(userId, id);
}
```

### Data: Conditional Owner Filter

The repository adds the owner predicate only for non-null input.

```csharp
return db.Bookings
  .Where(booking => booking.Id == id && (userId == null || booking.UserId == userId))
  .SingleOrDefaultAsync();
```

Search follows the same rule:

```csharp
if (!string.IsNullOrWhiteSpace(search.UserId))
{
  query = query.Where(booking => booking.UserId == search.UserId);
}
```

A mismatched owner returns not-found rather than forbidden. That avoids revealing
that another user's resource exists.

## Required Rules

1. Every owned-resource get, search, update, and delete path accepts a nullable
   `userId`.
2. The controller guards before any service or repository call.
3. Use owner-only, owner-or-any-role, or owner-or-all-roles semantics explicitly.
4. Admin and system callers omit `userId`; null flows unchanged after the role guard.
5. Services pass nullable `userId` through without authorization decisions.
6. Repositories apply the owner predicate if and only if `userId` is non-null.
7. Get-by-id and search/list use the same rule.
8. Admin-only endpoints use named policies rather than inventing a fake owner.
9. Create-under-user routes use a non-nullable user id and guard it against the
   subject or approved roles.
10. Guard failures are problem-typed 403 results; missing owned rows are 404 results.

## Pitfalls

- **Never default null from `sub`.** Doing so destroys the admin path because an
  administrator would see only resources whose owner id equals their own subject.
- **Never call the service before guarding.** The repository's null behavior is safe
  only because the controller has already established the caller's role.
- **Never trust caller-provided identity as the subject.** `userId` is untrusted data
  compared with the validated token subject, not an identity source.
- **Never move authorization into the service.** The controller owns identity and
  transport policy; the service remains reusable domain orchestration.
- **Never turn owner mismatch into 403.** Return not-found to avoid an existence
  oracle.
- **Never introduce an FGA or relationship-checker port.** Coarse claims plus the
  nullable owner predicate are the family authorization mechanism.

## Onboarding and Registration Claims

Authorization claims depend on a claims-first onboarding contract:

1. A client inspects the access token for its per-backend registration claim.
2. Only when the claim is absent may the client perform `GET /User/Me` as
   create-time race handling.
3. A missing row triggers the authenticated create-or-ok endpoint; a concurrent 409
   is treated as success until every backend is idempotent.
4. The backend validates the body tokens against IdP discovery/JWKS, requires the
   body-token subjects to match each other and the authorization-header subject,
   creates the local row, and writes the registration claim in one transaction.
5. Claim write-back failure rolls the row creation back.
6. The client forces token refresh and verifies the claim before entering the ready
   phase.
7. A claim that is present but stale follows the normal 401/404 error path; server
   reads never become a second onboarding detector.

Each backend has an independent claim, local row, token, and phase state. A client may
be ready for backend A while backend B is still bootstrapping. There is no singleton
"onboarded" flag.

Owned-resource endpoints apply a real registered-user default policy in addition to
their ownership guard. The production endpoint uses idempotent create-or-ok semantics,
not zinc's historical create-only 409 behavior.

## Home Landscape Claim

The `home_landscape` token claim is separate from per-backend registration:

- When present, the client routes directly to that home landscape.
- When absent during sign-up, the client uses the landscape selector, completes
  login and ordinary backend onboarding, then OnboardSync writes the claim.
- Logto's JWT customizer emits the claim from user custom data. The Logto operator
  owns that configuration; application code only reads the issued claim.
- The claim selects routing. It is not a replacement onboarding gate.

## Language Implementations

The shared standard is language-agnostic. Language bases add implementation-specific
guides in their own branch deltas; the .NET server stack remains the reference Guard
implementation.
