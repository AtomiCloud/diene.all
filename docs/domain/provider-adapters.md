# Provider adapter contract

<!-- ### mercury -->
<!-- #### source: mercury -->

Mercury v1 ships seven provider adapters. Each adapter authenticates exact raw
request bytes before persistence, derives provider metadata, and produces a
stable dedup identity. Only a validly configured adapter rejecting request
authentication evidence returns `401`; no rejected request creates an event or
queue entry.

## Adapter matrix

| Provider ID       | Verification input                                                | Required credential/configuration                                           | Native dedup identity            | Operational notes                                                                          |
| ----------------- | ----------------------------------------------------------------- | --------------------------------------------------------------------------- | -------------------------------- | ------------------------------------------------------------------------------------------ |
| `stripe`          | `Stripe-Signature`; HMAC-SHA256 over `t + "." + raw body`         | One or two endpoint secrets; timestamp tolerance defaults to 300s           | JSON `id`                        | Accept any valid `v1` signature from either live secret; event type=`type`, time=`created` |
| `airwallex`       | `x-signature`; HMAC-SHA256 over `x-timestamp + raw body`          | One or two webhook secrets; timestamp tolerance defaults to 300s            | JSON `id`                        | Event type=`name`, time=`created_at` or signed timestamp                                   |
| `apple-app-store` | `signedPayload` compact JWS; ES256 leaf and validated `x5c` chain | Apple trusted roots, expected bundle ID, environment, optional app Apple ID | JWS `notificationUUID`           | Reject wrong algorithm, chain, validity, app, or environment before persistence            |
| `google-play`     | Pub/Sub `Authorization: Bearer <OIDC JWT>`; RS256                 | Google/JWKS verification key, exact push service-account email, audience    | Pub/Sub `messageId`/`message_id` | Audience defaults to the stored registered URL; issuer and verified email are mandatory    |
| `telegram`        | `X-Telegram-Bot-Api-Secret-Token` constant-time comparison        | One or two bot secret tokens                                                | JSON integer `update_id`         | `update_id` is also provider sequence                                                      |
| `discord`         | Ed25519 over `X-Signature-Timestamp + raw body`                   | One or two 32-byte public keys; optional timestamp tolerance                | JSON `id`                        | Signature is 64-byte hex; ZIP-215 compatibility is disabled                                |
| `logto`           | `logto-signature-sha-256`; HMAC-SHA256 over raw body              | One or two webhook secrets                                                  | Fallback hash                    | Event type=`event`, time=`createdAt`                                                       |

“One or two” describes the normal steady/rotation state, not a hard array
limit. Configuration must contain at least one valid current credential and
must not expose secret values in CRs, logs, events, or Upstash config.

## Verification failure law

Every generated route is preflighted with
`validateProviderConfiguration(provider, configuration)`. The function accepts
exactly the seven IDs in the adapter matrix and validates the credential shape
for that specific adapter. Provider-looking strings outside that set are not
accepted.

The provider bridge preserves a failure `kind` and `retryable` flag in addition
to the domain error code:

- `request-authentication-rejected` is `invalid-signature`, non-retryable, and
  maps to `401`;
- missing, invalid, unavailable, or malformed configuration and references are
  `missing-credential`, retryable, and map to a non-detail-leaking `503`;
- remote key resolution, other verifier dependencies, and unexpected verifier
  exceptions are internal retryable failures and map to `503`; and
- `unsupported-provider` is retryable and maps to `503`.

Failure messages never include credential bytes, access tokens, remote response
bodies, resolver errors, or secret references. An internal fault always wins
over a final authentication rejection when multiple credential generations
were attempted, because Mercury cannot prove the unavailable generation would
have rejected the request.

## Dedup identity

When a provider supplies an event ID, Mercury encodes it as:

```text
native:<RFC4648-base64url-without-padding(UTF8 provider event id)>
```

When it does not, the adapter freezes the exact verified signature identity
(decoded signature bytes when available, otherwise the verified token or JWS
bytes) and Mercury computes:

```text
sha256(
  uint64be(length(rawBody)) || rawBody ||
  uint32be(length(signatureIdentity)) || signatureIdentity
)
```

The result is `sha256:<64 lowercase hex>`. The physical guard additionally
uses stable opaque `tenantId` and `routeId`, so display slug/path renames cannot
collide. The fallback is not the fresh internal delivery signature.

## Registered URL law

Any scheme that includes a URL in its signature or token audience must use the
exact URL stored on the route. It must never reconstruct that value from
request `Host`, proxy headers, or the socket address.

Google Pub/Sub's OIDC audience defaults to the stored registered push URL.
Future adapterless URL-inclusive schemes follow the same rule. A mismatch is
an authentication failure, not permission to try another tenant.

## Credential storage and fan-out

- Internal provider verification material follows the ordinary platform and
  landscape Infisical convention and is materialized into every serving
  Mercury namespace by ExternalSecret.
- External tenant secrets live under Mercury's tenant-secret path class and
  use the same Infisical/ExternalSecret delivery plane.
- Apple roots and Google public verification keys are trust material; bundle,
  environment, audience, and service-account constraints remain registered
  configuration.
- Derived Upstash config contains only secret pointers and generation IDs.
  Secret values never enter CRs, management responses, event envelopes, or
  Upstash.

## Rotation requirements

All symmetric secrets, public-key sets, tenant API credentials, and internal
delivery keys support dual-live generations:

1. Mint or register generation N+1 without revoking N.
2. Commit metadata and distribute N+1 through Infisical/ExternalSecret.
3. Confirm every serving landscape and consumer has loaded N+1.
4. During overlap, verification tries all live keys without exposing which one
   matched.
5. Begin the 48-hour overlap clock from the last rollout confirmation.
6. Revoke N only after the overlap and health checks succeed.

Rollback keeps the prior generation live. A partially distributed generation
must surface degraded rotation health and must never cause unilateral revocation.

Compiled routes order `verificationSecretRefs` newest-live first, followed by
non-expired overlap generations. The bridge tries each usable configuration,
retaining compatibility with the singular `verificationSecretRef` field.

## Production operation credentials

Apple history and Google Pub/Sub administration resolve relative secret
references beneath `security.providerSecretRoot`. Recommended mounted files are:

```text
<providerSecretRoot>/
├── apple-app-store-history.p8
└── google-pubsub-service-account.json
```

The Apple file contains only the raw PKCS#8 PEM. The Google file contains the
standard `service_account` JSON whose `client_email` equals the configured
expected service-account email and whose token URI is an approved Google OAuth
endpoint. The `dataFrom.extract` ExternalSecret projection creates these flat
keys directly beneath `providerSecretRoot`, so configuration references use
exactly `apple-app-store-history.p8` and
`google-pubsub-service-account.json` without subdirectories. Mount each as a
root-confined regular file with read-only permissions; replace it atomically
during rotation. Neither value belongs in YAML.

Apple history, Google OAuth, and Google Pub/Sub keep their request timeout and
caller cancellation active until response-body consumption completes. They
stream into a fixed-size bounded reader, reject dishonest or missing
`Content-Length` responses once actual bytes exceed the cap, and immediately
cancel stalled or oversized bodies without logging body content.

## Fixture requirements

Unit and SIT fixtures cover, for every adapter:

- one genuine provider-format request;
- body, header, credential, and target tampering;
- rotation overlap with old and new credentials independently accepted;
- missing/malformed headers and unsupported algorithms where applicable;
- stable native or fallback dedup identity; and
- proof that failure occurs before persistence.

Apple fixtures include a real test certificate chain and forged chain/target
cases. Google fixtures include signed OIDC claims for correct and incorrect
issuer, audience, email, and `email_verified` values.
