# Mercury wire protocol

<!-- ### mercury -->
<!-- #### source: mercury -->

Mercury has two wire boundaries: provider-native public intake and the Atomi
v1 envelope delivered to registered consumers. Raw provider authentication is
terminated at intake and is never forwarded.

## Public intake

The canonical URL is:

```text
https://hooks.webhook.mercury.<vlandscape>.cluster.atomi.cloud/t/<tenant-slug>/<registered-route>
```

A registered custom domain may omit the slug. The exact registered domain is
only a lookup hint; the stored tenant URL and successful provider verification
establish authority. Request `Host`, `Forwarded`, `X-Forwarded-*`, source IP,
and payload business fields never establish tenant identity.

Mercury consumes the provider's exact body bytes and adapter-owned headers.
The sequence is fixed:

```text
resolve registered route -> verify -> atomically dedup + persist + enqueue -> respond 200 -> deliver
```

### Intake responses

| Result                                | Status | Required behavior                                                           |
| ------------------------------------- | -----: | --------------------------------------------------------------------------- |
| New event accepted                    |  `200` | Dedup guard, event, and every endpoint obligation committed before response |
| Same-landscape duplicate              |  `200` | Drop without another event, obligation, or TTL refresh                      |
| Body larger than 1 MiB                |  `413` | Cancel the request stream before full materialization or route lookup       |
| Invalid provider credential/signature |  `401` | Persist nothing                                                             |
| Genuinely unregistered path or domain |  `404` | Persist nothing; never use as an ownership signal                           |
| Tenant quota exhausted                |  `429` | Include `Retry-After`; ask the provider to retry                            |
| Verifier/configuration unavailable    |  `503` | Persist nothing; do not misreport an internal fault as forged traffic       |
| Failure before atomic acceptance      |  `5xx` | Leave no partial acceptance and ask the provider to retry                   |

A transient internal failure must never be translated into a provider-facing
`4xx`. A retry may land in another landscape and be accepted there; that is
why consumer idempotency is mandatory.

The adapter consumes the request as a bounded byte stream. `Content-Length`
is an early rejection hint, never the only enforcement: chunked and dishonest
length requests are cancelled as soon as they cross 1 MiB. The same bound is
also configured on the Bun server.

## Internal delivery endpoint

Every registered backend module exposes:

```http
POST /internal/webhooks/{provider}
Content-Type: application/vnd.atomi.webhook.v1+json
X-Atomi-Webhook-Signature: t=<unix-seconds>, v1=<64-lowercase-hex>
```

The body is UTF-8 JSON. Mercury emits the fields in the order shown below and
MACs those exact bytes, which makes retries testable byte-for-byte. Field order
is not semantic to consumers; consumers must ignore unknown fields while
`version` is `1`.

```json
{
  "version": 1,
  "eventId": "<opaque landing-landscape event id>",
  "dedupId": "native:<base64url> | sha256:<64 lowercase hex>",
  "tenantId": "<stable opaque tenant id>",
  "routeId": "<stable opaque route id>",
  "provider": "<lowercase provider id>",
  "landingLandscape": "<landscape>",
  "receivedAt": "<RFC3339 UTC instant>",
  "providerEventId": "<string or null>",
  "providerTimestamp": "<RFC3339 UTC instant or null>",
  "providerSequence": "<opaque string or null>",
  "providerHeaders": { "<lowercase name>": ["<ordered value>"] },
  "payload": {
    "contentType": "<provider type or application/octet-stream>",
    "bodyBase64": "<RFC 4648 base64 with padding>"
  },
  "delivery": {
    "endpointId": "<snapshotted registration id>",
    "attempt": 1,
    "replay": false
  }
}
```

`eventId`, `dedupId`, tenant, route, provider, receive metadata, and provider
payload remain stable across attempts. `attempt` starts at 1 and increases for
the `(eventId, endpointId)` obligation, including replay. Console replay sets
`replay` to `true` and keeps the snapshotted endpoint identity.

Only adapter-approved business headers are included, with lowercase names and
ordered values. Provider authentication and signature headers are forbidden in
the delivery envelope.

The signed body, rather than mutable convenience headers, is the authoritative
identity. In particular the MAC binds tenant, route, endpoint, event, dedup,
attempt/replay, provider ordering/receive metadata, payload media type, and the
exact provider payload bytes. Delivery sends only the v1 media type and
signature as protocol headers; consumers must read identity from the verified
body.

## Internal signature verification

The signature is independent of lithium/M2M and is required on public and
cluster-local delivery paths.

The digest is:

```text
HMAC-SHA256(ASCII(unixSeconds) || 0x2e || exactRequestBodyBytes, key)
```

`key` is the endpoint's live UTF-8 signing secret, resolved from a server-owned
credential record and delivered through Infisical and ExternalSecret. The
header must contain exactly one `t` and one `v1` parameter; HTTP optional
whitespace is allowed. Duplicate, missing, unknown, or malformed parameters
fail closed.

A consumer must verify in this order:

1. Retain the exact request bytes; do not parse JSON first.
2. Parse `t` as unsigned whole Unix seconds and `v1` as exactly 64 lowercase
   hexadecimal characters.
3. Reject when `abs(nowSeconds - t) > 300`.
4. Compute the digest for every currently live rotation key and compare in
   constant time.
5. Return `401` on any authentication failure, never `421`.
6. Parse and validate the v1 body only after authentication succeeds.

Mercury creates a fresh timestamp and signature for every initial attempt,
retry, and replay. `delivery.attempt` and `delivery.replay` also make the
canonical body distinct when those values change. The provider's original
signature is never reused or forwarded.

## Consumer reply contract

- Exact final `200` completes the endpoint obligation. Response bodies are
  ignored.
- `421 Misdirected Request` means the compiled address is stale or wrong.
  Mercury alerts, recompiles, and retries the same endpoint once at the
  refreshed address before ordinary retry handling.
- Every other status, including other `2xx`, all `3xx`, `4xx`, and `5xx`, plus
  DNS, TLS, connect, and timeout failures is an endpoint failure. Mercury does
  not follow redirects.
- `404` means a genuinely missing handler route. It is never “not my
  landscape,” ownership, or failover signaling.

## Delivery semantics

Delivery is **at-least-once and unordered**. There is no cross-landscape
sequencer; same-landscape rough FIFO is incidental. Every consumer must be
idempotent and use a domain idempotency key, normally
`(tenantId, routeId, dedupId)`, never arrival order or attempt number. Provider
timestamp/sequence and Mercury receive metadata exist for domain-specific
reconstruction only.
