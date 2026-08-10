---
name: diene-e2e-usage
description: Use when consuming the diene_e2e package — the L-dart family version-train and test-harness (stub server, journey drivers, shared C0 app-handoff fixture, bundled member test helpers).
---

# Using `diene_e2e`

`diene_e2e` is the ONE package a consumer of the L-dart family depends on. It is
the version-train (a coherent set of the seven family libraries under one
version) and the consumer test-harness (bundled member test helpers + this
package's own glue).

## Two import roots

- `package:diene_e2e/diene_e2e.dart` — runtime: the family version-train
  re-exports plus the pure-value C0 §7 app-handoff (deferred-login) contract
  models (carrier codec, mint/redeem wire shapes) this package owns.
- `package:diene_e2e/test_helper.dart` — tests: the dependency-light harness
  (`StubServer`, `AppHandoffStub`, `Journey`, `DeferredLoginJourney`,
  `expect*` plain-throw assertions) plus every family member's `test_helper.dart`
  that exists. NO test-framework dependency, so importing it costs a consumer's
  production graph nothing.

## Stub server + journeys

Point a client at a `StubServer`, register route handlers, and drive a `Journey`:

```dart
final server = await StubServer.start();
server.on('GET', '/health', (r) => StubResponse.json({'ok': true}));
// ... run the client against server.baseUrl, then server.close().
```

`Journey` runs ordered async steps and stops at the first failure;
`expectJourneyOk` / `expectJourneyFailedAt` assert the outcome.

## Shared deferred-login (app-handoff) fixture

Do NOT hand-roll an app-handoff server. Mount the canonical `AppHandoffStub`
onto your `StubServer` and drive it with `DeferredLoginJourney`:

```dart
final stub = AppHandoffStub(problemTypeUri: '<c0 §2 type uri>')
  ..addUser(const AppHandoffUser(sub: 'u1', primaryEmail: 'a@b.com'))
  ..mintingUser = const AppHandoffUser(sub: 'u1', primaryEmail: 'a@b.com');
stub.mount(server);

final driver = DeferredLoginJourney(baseUrl: server.baseUrl, platform: 'android');
final result = await driver.redeemCarrier(installReferrer); // or .redeemNonce(nonce)
// result.outcome == DeferredLoginOutcome.redeemed | interactiveFallback
```

The fixture enforces single-use nonces and returns ONE indistinguishable
`AppHandoffExpired` (410) body for every failure (missing, expired, replayed,
deleted, suspended, email-rebound) — no account-state oracle.

## Writing this package's TestHelper

The harness lives in `lib/src/{stub,journey,assertions}` and is surfaced through
`lib/test_helper.dart`. It is dependency-light by rule: fakes, builders, and
plain-throw assertions only — never a `test`/`matcher`/mocking dependency. Its
own correctness is proven by the meta tier (`pls test:meta`): every assertion
helper is shown to fail on a known-bad input and pass on a known-good one, and
the fixture/driver invariants are asserted directly.

## Version train

Members bump independently; e2e declares the compatible set and releases the
train. Depend on `diene_e2e` for the whole family; depend on a single member
directly only when you truly need just that one library.
