# Withheld — castform Mercury webhook delivery

**Status: withheld. There is no end-to-end SIT proof of webhook delivery in the
`castform` preview, and this collection does not claim one.**

## What is withheld

A journey that publishes an event at a provider, lets Mercury deliver it to this
service's `/internal/webhooks/{provider}` route through the preview's callback
zone, and asserts the owned-event `200`, the not-mine `421`, and idempotency under
redelivery.

## Why

The D11 callback-contract re-ruling is still open. Until it is re-ruled, preview
delivery is visibly withheld: a `castform` preview may hold only a disabled
`deliveryClass: preview` subscription, and Mercury does not include it in the
candidate set. There is therefore no delivery path to assert against — any journey
written today would be asserting against a subscription that is switched off.

Writing it anyway would produce one of the two outcomes this collection exists to
prevent: a red run that blames the service for a platform decision, or a green run
that proves nothing because it fired at a local stand-in rather than at Mercury.

## What IS proven, and where

Webhook receipt is covered — just not at this tier, and not through Mercury:

- the `WebApplicationFactory` baseline in `IntTest` covers the owned `200`, the
  not-mine `421`, the real-error status, and idempotent replay against
  `App/Webhooks/NoteWebhookHandler.cs`;
- the handler convention itself, its signature verification, and its refusal
  statuses are proven inside `AtomiCloud.Diene.ServerEngine`, which this repository
  consumes rather than reimplements.

That coverage is owned by another worker on this node. It is real proof of the
handler; it is not proof of delivery.

## What would un-withhold it

D11 re-ruled such that a `castform` preview holds an ENABLED subscription that
Mercury includes in its candidate set. At that point the journey below becomes
writable as a real `.bru` request.

## The journey, as it would be written

```text
meta {
  name: Mercury delivers an owned event
  type: http
  seq: 1
}

post {
  url: {{baseUrl}}/internal/webhooks/note
  body: json
  auth: none
}

// Signed with a live rotation key from server_engine:webhook_signing_keys, then
// asserted at 200 for an owned event, 421 for a provider this service does not own,
// and asserted a second time with the same delivery id for idempotency.
```

Note the route is written thin over the receiver consumed from
`AtomiCloud.Diene.ServerEngine`; this repository writes no webhook endpoint of its
own.
