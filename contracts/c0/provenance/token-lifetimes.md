### §12 Token lifetimes

- **Access tokens: 10 minutes.**
- **Refresh tokens: 14 days, ROTATING** — every refresh mints a new refresh
  token; reuse of an already-rotated token is treated as theft (reuse
  detection invalidates the family).
- **Apps re-mint on open**: on every app foreground/open, silently refresh
  so a session always starts on a fresh access token; this — not a short
  access TTL — is what bounds staleness in practice.
- This is the normative value fleet-wide; any other goal doc citing an
  access-token TTL (deferred-login, auth-engine, frontend goals) must
  match this section.
