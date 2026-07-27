### §7 App-handoff contract

- C0 defines the WIRE SHAPES only — not an implementation. App-handoff ships as
  an ENABLE-ABLE auth-engine module (dotnet: part of
  `AtomiCloud.Diene.AuthEngine`, consumed via ServerEngine/dotnet-api wiring).
  The configured base path is `{mount}`, default **`/app-handoff`**. The mint
  route is `POST {mount}` and the redeem route is `POST {mount}/redeem`; callers
  MUST NOT append a second `app-handoff` segment.
- **JSON/HTTP v1 wire** (`Content-Type: application/json`, responses
  `Cache-Control: no-store`):
  - **Mint** — authenticated web session, normal bearer authentication; request
    body `{}`. The server reads the validated OIDC `sub` and email from the
    authenticated session — neither is client-supplied — and returns `200`:
    `{ "nonce": <string>, "expiresAt": <RFC3339 UTC instant> }`.
  - The nonce is 32 cryptographically-random bytes encoded RFC 4648 base64url
    WITHOUT padding (43 ASCII characters), opaque and Logto-meaningless. Its
    record is `{sub, email, expiresAt, state}` with a fixed **15-minute TTL** and
    lifecycle `active → claimed → consumed|revoked`; `claimed` is exclusive and
    never returns to `active`, including after a process crash.
  - **Redeem** — unauthenticated `POST {mount}/redeem` request:

    ```json
    {
      "nonce": "<43-char base64url>",
      "device": {
        "platform": "android|ios",
        "appVersion": "<optional string>",
        "osVersion": "<optional string>",
        "model": "<optional string>"
      }
    }
    ```

    `device` is telemetry only and MUST NOT affect identity or authorization.
    Unknown top-level/device keys are rejected as invalid v1 input. On success
    return `200`:
    `{ "token": <Logto one-time token>, "email": <current primary email>,
    "expiresIn": 120 }`.
  - Redeem first atomically changes exactly one unexpired nonce
    `active → claimed`; every concurrent/replayed/expired/malformed attempt gets
    the SAME generic-expiry response. After the claim, perform exactly one
    `GET /api/users/{percent-encoded sub}`. Success requires: response `200`,
    `isSuspended == false`, non-null `primaryEmail`, and `primaryEmail` equal to
    the stored mint-time email under ASCII case-insensitive comparison. `404`,
    suspension, mismatch, null email, Management-API failure, or Logto mint
    failure transitions the nonce to `revoked` and returns the generic response.
  - Only after those checks, mint exactly
    `{ email: current.primaryEmail, expiresIn: 120,
    context: { interactionEvent: "SignIn" } }` through Logto. On success mark
    the nonce `consumed` before replying. A crash after claim is fail-closed:
    retry receives generic expiry and never mints a second token.
  - **One no-oracle error** for every redeem failure above: RFC 9457 problem id
    `AppHandoffExpired`, status `410`, title `App handoff expired`, detail
    `This app handoff is expired or invalid.`, and empty `data`. Its `type` URI
    is built by §2. Internal logs MAY retain the real reason; the response MUST
    NOT distinguish missing, expired, replayed, deleted, suspended, rebound, or
    upstream-failure states.
- **Carrier v1 (Q-I48)** — the canonical carrier text is exactly
  `atomi-app-handoff:v1:<nonce>` using the nonce encoding above:
  - Android Play Install Referrer carries it as one
    `application/x-www-form-urlencoded` field
    `app_handoff=<percent-encoded canonical carrier>`. Other campaign fields
    may coexist; zero or duplicate `app_handoff` fields are treated as absent.
  - iOS clipboard content is the canonical carrier text (ASCII leading/trailing
    whitespace may be trimmed). The app reads the clipboard on launch with NO
    consent tap; the system paste banner is accepted. App Clip is not v1.
  - After a syntactically valid carrier is captured, the client marks the
    Install Referrer value processed, or clears the clipboard only if it still
    equals the captured value, BEFORE redeem. It never logs/persists the nonce.
    Absent/invalid carrier or any `AppHandoffExpired` response falls back to
    normal interactive login; there is no second carrier-specific retry loop.
- The seconds-wide `sub`↔email rebinding race after Logto mint and before hosted
  consumption is accepted and documented (Q-I47-D4). There is no post-consume
  subject verification.
- Handoff x onboarding interplay: handoff completes ONLY the login (Logto identity
  established); afterwards the STANDARD per-backend onboarding gate takes over
  (§8 — absent claim → race-safe `GET /User/Me`/create → OnboardSync). No special
  handoff-side onboarding path exists.
