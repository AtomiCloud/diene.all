# Mercury SIT contract

<!-- ### mercury -->
<!-- #### source: mercury -->

This suite exercises an assembled Mercury stack from a client/test-fixture
boundary. It does not import domain, storage, provider, or delivery internals.

## Required injection

Set both endpoints:

```bash
export MERCURY_SIT_BASE_URL='https://hooks.webhook.mercury.<sit-zone>'
export MERCURY_SIT_CONTROL_URL='http://<fixture-control-endpoint>'
# Optional when the injected fixture boundary requires authentication:
export MERCURY_SIT_CONTROL_BEARER='<opaque-token>'
# Optional per-request bound; defaults to 10000 and may not exceed 300000:
export MERCURY_SIT_TIMEOUT_MS='10000'
bun run test:sit
```

`src/index.ts` must publicly export `createMercuryTestStack`. The isolated
[stack adapter](stack-adapter.ts) calls that factory with the environment and
the complete seven-provider fixture list. The returned object structurally
implements [the test-stack contract](contract.ts).

The base URL is Mercury's ordinary public product surface. The control URL is
an injected SIT-only fixture boundary that can register deterministic receivers,
hold/release delivery, inject dependency failure, inspect timestamps and
identities, and capture consumer requests. It must not add a production admin
door or bypass the product pipeline.

The product URL must be an HTTPS origin. The control URL must be an HTTP or
HTTPS origin; credentials, paths, queries, and fragments are rejected on both.
The client opens one fixture session with the product URL and exact ordered
seven-provider list, invokes one distinct bounded control endpoint for each
scenario, validates the complete returned evidence, and deletes the session on
`close`. Cleanup is idempotent, and a cleanup failure remains a test failure.

## Failure-closed rules

The suite fails when:

- either URL is absent;
- the public factory or any required capability is absent;
- any of the seven genuine/forged provider fixture pairs is absent;
- a claimed Neon, Upstash, Tigris, secret-store, Route 53, or observability
  dependency is fake, unreachable, anonymous, or aliased incorrectly;
- a scenario returns incomplete evidence; or
- the stack cannot demonstrate the required timing/cardinality itself.

There are no skips, “not configured” successes, or memory-adapter fallbacks.
The documentation/absence tests run without the stack, but they do not turn a
missing black-box stack into a green SIT run.

## Scenario map

| Factory capability              | Black-box proof                                                                                          |
| ------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `inspectDependencies`           | Real dependency identities and one distinct Upstash per landscape                                        |
| `runProviderVerificationMatrix` | Genuine and forged formats for all seven adapters                                                        |
| `runAtomicAcceptance`           | Verification, one atomic dedup/event/queue commit, response timing, local duplicate and remote duplicate |
| `runFanout`                     | One registration means one delivery; three per-row registrations mean three; local vs canonical address  |
| `runSignatureLifecycle`         | Fresh initial/retry/replay signatures and stripped/forged/stale rejection on public/private paths        |
| `runConsoleJourney`             | Login, multi-landscape fan-in, source-landscape replay, and D11 visibility                               |
| `runAppleBackfill`              | Singleton recovery through the ordinary pipeline and missed-cycle alert                                  |
| `inspectGoogleSubscription`     | 31-day retention, explicit DLQ, OIDC contract, and drift repair                                          |
| `runArchiveLifecycle`           | Verified archive before deletion and deletion block on failure                                           |
| `inspectRoute53Landing`         | Provider request plus exact geoproximity record metadata                                                 |

## Local checks

Run stack-independent checks while the environment is being assembled:

```bash
bun test tests/sit/documentation.sit.test.ts
bunx biome lint tests/sit
```

The full `bun run test:sit` command remains red until a real stack is injected.

## Approved external authorities

The local control performs provider verification, atomic acceptance, fan-out,
delivery signature lifecycle, and the console journey against the two Compose
Mercury processes. Facts owned by an external platform are not accepted from
scenario URL variables. They require both:

```bash
export MERCURY_SIT_PROOF_BEARER='<opaque-authority-credential>'
export MERCURY_SIT_PROOF_TRUST_JSON='{
  "route53-landing": {
    "authorityId": "platform-dns",
    "keyId": "dns-2026-07",
    "url": "https://proof.example.test/v1/observe",
    "resourceIdentity": "route53:ZONE_ID:hooks.webhook.mercury.example",
    "publicKeyPem": "-----BEGIN PUBLIC KEY-----\n...\n-----END PUBLIC KEY-----\n"
  }
}'
```

Each trust entry fixes an uncredentialed HTTPS URL, authority, Ed25519 key, and
exact resource identity. The authority receives a fresh session ID, 256-bit
nonce, request time, product origin, landscape list, and resource identity. Its
signed response must bind those values plus the canonical request digest and a
specific completed product operation. Issuance may be at most 60 seconds old,
expiry may be at most five minutes after issuance, and the observed operation
must complete during that request. Schema-valid evidence with a stale,
mismatched, unsigned, or incorrectly signed envelope fails.

The required trust keys are `dependencies-secret-store`,
`dependencies-route53`, `dependencies-tigris`, `apple-backfill`,
`google-subscription`, `archive-lifecycle`, and `route53-landing`. Missing
trust or credentials is a
proof-pending failure, never a skip.

For concurrent local work, `scripts/local/up.sh` creates a unique run ID,
Compose project, material directory, and host ports. Use the printed run ID:

```bash
MERCURY_SIT_RUN_ID='<printed-id>' ./scripts/local/test-sit.sh journey
MERCURY_SIT_RUN_ID='<printed-id>' ./scripts/local/down.sh
```
