# Withheld — app-handoff mint and redeem

**Status: withheld. The mint and redeem endpoints do not exist in the consumed
`AtomiCloud.Diene.AuthEngine` version, so no journey can prove them.**

This is a blocked deliverable, not a policy decision. It needs a ruling from the
node controller.

## What is withheld

`POST {mount}` (mint a single-use nonce bound to the caller's validated `sub` and
email) and `POST {mount}/redeem` (validate the nonce, re-resolve identity through
the Management API, mint a 120-second Logto one-time token), plus the expiry and
replay cases.

## The evidence

`AtomiCloud.Diene.AuthEngine` is pinned at `1.0.0` in `Directory.Packages.props`.
Composing that package's endpoints and enumerating the resulting
`EndpointDataSource` yields every route the consumed libraries contribute:

```text
GET    /app-handoff/session
GET    /openapi/{documentName}.json
GET    /scalar/{documentName?}
POST   /internal/onboard-sync/complete
GET    /internal/onboard-sync/phase
POST   /internal/webhooks/{provider}
GET    /system/health
GET    /system/version
```

`MapAtomiAuthEngine` contributes exactly one route — `{mount}/session` — and no
mint or redeem route. The package's public surface carries no `IDeferredTokenStore`,
`IDeferredTokenMinter`, nonce type, or one-time-token client either.

The session route that DOES exist is exercised by
[`06-app-handoff/handoff-session.bru`](../06-app-handoff/handoff-session.bru).

## Why it is not written anyway

Every alternative is worse than a named gap:

- asserting `404` on `{mount}/redeem` would encode the absence as the contract, and
  would go green for the wrong reason the day the endpoints ship;
- pointing the journey at a stand-in would substitute a fake at a tier that
  forbids fakes;
- omitting it silently would leave a DoD line item looking covered.

## What would un-withhold it

A published `AtomiCloud.Diene.AuthEngine` version whose module maps the mint and
redeem routes. When that version is pinned, re-run the endpoint enumeration above,
confirm the routes and their verbs, and write the pair into `06-app-handoff/`.

## The journey, as it would be written

```text
meta {
  name: App handoff mint
  type: http
  seq: 2
}

post {
  url: {{baseUrl}}{{handoffMount}}
  body: json
  auth: inherit
}

// Captures the opaque nonce, then redeems it once at {{handoffMount}}/redeem for a
// one-time token with expiresIn 120, then redeems the SAME nonce a second time and
// asserts the replay is refused with a generic expiry problem.
```
