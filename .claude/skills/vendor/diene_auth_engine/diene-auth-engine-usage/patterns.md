# diene_auth_engine patterns

## The fake-scripting model

The fakes in `test_helper.dart` are **scripted**, not recorded-and-replayed. Each
takes its behaviour up front and counts what it saw, so a test states its
preconditions in the constructor and asserts on the counters afterwards.

`FakeAuthProvider` scripts the IdP:

```dart
final FakeAuthProvider provider = FakeAuthProvider(
  onSignIn: () => AuthFixtures.sessionTokens(now: now),
  onRefresh: (SessionTokens current) => AuthFixtures.sessionTokens(
    now: now,
    refreshToken: 'rotated',        // a DIFFERENT token, same family
    refreshFamily: current.refreshFamily,
  ),
  resourceTokens: <String, ResourceToken>{
    key.mapKey: AuthFixtures.resourceToken(now: now, jwtToken: registered),
  },
  idTokenValue: registered,
);
```

Unscripted members throw `StateError` deliberately — "a token silently appeared"
is never a safe default in a test. To exercise the sign-in failure path, pass
`throwOnSignIn`; the controller converts the throw into a problem-typed `Failure`,
which is the behaviour under test.

Every fake records its traffic: `signInCount`, `refreshCount`, `reMintCount`,
`signOutCount`, `freshClaimTokenCount`, `lastExtraParams` on the provider;
`fetchAllCount`, `invalidated`, `invalidateAllCount` on `FakeAuth`; `getCount` /
`postCount` on `FakeUserDirectory`; `redeemCount` / `lastNonce` on
`FakeAppHandoffApi`; `pinged` on `FakeRegionPinger`; `processed` / `cleared` on
the carrier sources.

### `FakeAuth` batches model the claim-repair path

`FakeAuth` takes a **list** of batches. Successive `fetchAllTokens` calls return
successive entries, and the last one repeats. That is exactly the shape of the C0
§8 step-4 force-refresh: batch 0 is the unregistered token that sends the machine
to `/User/Me`, batch 1 is the refreshed token carrying the claim.

```dart
final FakeAuth auth = FakeAuth(<Map<ResourceKey, Result<ResourceToken>>>[
  <ResourceKey, Result<ResourceToken>>{
    key: Success<ResourceToken>(
      AuthFixtures.resourceToken(now: now, jwtToken: AuthFixtures.unregisteredJwt(key)),
    ),
  },
  <ResourceKey, Result<ResourceToken>>{
    key: Success<ResourceToken>(
      AuthFixtures.resourceToken(now: now, jwtToken: AuthFixtures.registeredJwt(key)),
    ),
  },
]);
```

Give it **one** batch to prove the already-registered fast path, and one batch
holding a `Failure` to prove per-backend failure isolation — a failed entry sends
that backend to `error` while a disjoint backend continues.

## Claim fixtures

`AuthFixtures.jwt` builds an unsigned `header.payload.sig` token: the client only
reads claims, and nothing here verifies signatures. Use the two named variants
rather than hand-assembling claim maps, so the exact C0 §8 key rule stays in one
place:

```dart
AuthFixtures.registeredJwt(key);                          // <platform>_<service> = "true"
AuthFixtures.unregisteredJwt(key);                        // the claim is absent
AuthFixtures.registeredJwt(key, extra: <String, Object?>{ // + the home claim
  Claims.homeLandscape: 'raichu',
});
```

Absence has several shapes and they all count as absent: a missing key, `null`,
boolean `true`, and any non-`"true"` string. Cover them with `extra` maps rather
than trusting one negative case — the string-vs-boolean distinction is the rule
most likely to regress.

## Asserting outcomes

`AuthExpect` returns the unwrapped value, so assertions chain:

```dart
final SessionTokens tokens = AuthExpect.ok(await session.signIn());
AuthExpect.status(AuthExpect.err(await session.refresh()), 401);
AuthExpect.errType(await session.refresh(), 'urn:diene:problem:refresh-reuse');
AuthExpect.phase(AuthExpect.ok(phases['lithium-api']!), OnboardingPhase.ready);
```

Assert on the problem **`type`**, not on its `title` or `detail`. The type URI is
the contract; the prose is not. `AuthAssertionError` is a plain `Error`, so these
work under `flutter_test`, `package:test`, or a bare `dart run`.

## Testing the deferred-login order

The ordering is the contract: the carrier is marked processed (or the clipboard
cleared) **before** redeem, so a crash mid-redeem can never redeem twice. Assert
both halves:

```dart
final FakeInstallReferrerSource referrer = FakeInstallReferrerSource(
  'utm_source=play&app_handoff=atomi-app-handoff%3Av1%3A$nonce',
);
final DeferredLoginOutcome outcome = await DeferredLoginClient(
  api: api, device: device, referrer: referrer,
).prepare();

referrer.processed;          // true — marked before redeem
(outcome as DeferredLoginReady).extraParams['one_time_token'];
```

`FakeClipboardCarrierSource.clearIfEquals` only clears when the contents still
match, which is what makes the iOS half safe against a clipboard that changed
between read and clear. Test the mismatch case too.

A redeem failure must yield `DeferredLoginFallback`, never an exception —
`FakeAppHandoffApi` defaults to the generic-expiry problem precisely so the
fallback path is the cheap thing to write.

## Testing the home-claim rules

Three rules are worth a dedicated test each, because each one is a security
property rather than a convenience:

1. **The store never decides.** Seed `MemoryHomeClaimStore('wrong-landscape')`
   with a provider whose JWT claims `'right-landscape'`, and assert the resolution
   is `'right-landscape'` with `HomeResolutionKind.fromClaim`. A stale or tampered
   mirror must lose.
2. **Doc B runs only on an absent claim.** With a claim present,
   `FakeLandscapeSelectorSource.fetchCount` must stay `0`.
3. **Unconfirmed fails closed.** On the sign-up path, a `FakeAuthProvider` with no
   `freshClaimTokenValue` must make `SignInCoordinator.signIn` return
   `urn:diene:problem:home-claim-unconfirmed` — not silently mirror the Doc B
   selection.

For Doc B parsing, the negative cases are the point: an `address`/`issuer`/`url`
key at **any** depth (including inside `metadata`) and any URL-shaped string value
must reject the **whole** doc, not just that entry.

## The meta-tier convention

`lib/test_helper.dart` is a **dependency-light** sub-library: it imports the
package's own sources only — never `package:test`, `matcher`, `mockito`, or
`mocktail`. That keeps it out of a consumer's production dependency graph, so it
ships inside the main package instead of a separate
`diene_auth_engine_test_helper` package. `scripts/validate/dart-package.sh`
enforces the boundary.

The meta tier (`test/meta/`, `pls test:meta`, the `meta` codecov flag) measures
the helper itself on its own ledger, disjoint from the unit ledger over
`lib/src/**`. It owes:

- **assert-the-asserter** — every `AuthExpect` member shown to PASS on a
  known-good case and FAIL on a known-bad one. An assertion that cannot fail is
  worse than no assertion.
- **fixture/builder invariants** — `AuthFixtures` round-trips through
  `Claims.decode`, `sessionTokens` respects the family lifetimes, `resourceKey`
  produces the expected `mapKey` and `audience`.
- **fake behaviour** — batch cursor advance-and-hold, counter accuracy, and the
  deliberate `StateError` on an unscripted member.

The tier is conditional: it activates only where a helper and a meta test exist
together. A package with neither uploads no `meta` flag.

## Cross-family parity, in one paragraph

This package is the dart twin of `lib/bun/auth-engine`, **minus** the server
mint/redeem module and the web-client handoff half (dotnet-api hosts the
endpoints; dart only redeems), and **plus** the Doc B landscape-selector client
that bun keeps in `frontend-utils`' edge-doc client. Doc A, Doc C, and the dormant
rescue router are `lib/dart/api-engine`'s; all five bun-frontend-utils UX-pattern
mechanism-hook twins (`/persistence`, `/loader`, `/urlstate`, `/toast`, `/a11y`)
belong to `flutter-base`, because each needs a `BuildContext`, `MediaQuery`, or
`go_router` to exist at all. The full checklist, including the Flutter-dependency
delta and its two `dev_dependencies` consequences, is in
`doc/diene_auth_engine.md`.
