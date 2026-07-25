### §10 Edge docs — three-doc model

- **Three T3-derived docs** — nobody hand-authors them; each carries its
  own monotonic version doubling as the HTTP cache tag:
  - **Doc A — fleet doc**: `{ catalogHosts: [...], version, ttl }` ONLY
    (~200 bytes). CONSTANTLY refreshed (foregrounded, stale-while-
    revalidate). Hosts deliberately span failure domains: R2 via CF custom
    domain · CloudFront via the R53 rescue domain · CloudFront's own
    `*.cloudfront.net` name. "Catalogs advertise catalogs" — grow the host
    set anytime via the doc, no app release.
  - **Doc B — landscape selector** (per platform × env): `{ platform,
    tier, landscapes: [{ name, region, metadata… }, …] }` — landscape
    names + metadata ONLY, NO addresses, NO issuer (client derives ping
    URLs by convention). Pure VIEW, derived (never hand-authored) from
    Landscape + PlatformDependency/row presence + ClusterRegistration.status
    + VirtualLandscape(Service).
  - **Doc C — platform catalog** (per platform × env): `{ platform, tier,
    version, catalog: { <landscape>: { <service>: { <module>: [ <full
    address>, … ] } } } }` — FULL addresses, no templating, an ORDERED
    candidate list per landscape × service × module (primary first, rescue
    alternates after). DORMANT: fetched only on the client rescue router's
    hard-connect-failure trip, then cached to disk (last-known-good
    forever).
- **Client rules (normative)** (per-doc cadence):
  - **Doc A**: fetched constantly by every client that has one — the
    carrier that advertises where Docs B/C themselves live.
  - **Doc B**: MUST fetch EXACTLY ONCE per user, at sign-up (region
    picking): fetch → ping each listed region (healthy regions only) →
    user/system picks → home claim written (§13). Never used for
    per-request routing — clients hold ONE hostname after that (their home
    landscape's).
  - **Doc C**: DORMANT — fetched ONLY when the client rescue router trips
    on a HARD connect-failure (never on the hot path). Router lives in the
    shared api-engine/frontend-utils machinery (bun + dart twins),
    everywhere that has a client (Flutter + browser); the nextjs SERVER
    runtime is EXEMPT (its rescue = redeploy). On trip: jittered, budgeted
    scan over Doc C's ordered candidates, then pin-until-heal.
  - **ENDPOINT-SUFFIX ALLOWLIST (replaces doc signing)**: every URL ANY of
    the three docs supplies MUST match the client's BAKED
    `*.cluster.atomi.cloud` suffix pattern (+ rescue root(s)), enforced at
    USE time; any entry that doesn't match MUST be rejected (doc-level, not
    per-entry — a doc containing one bad suffix is untrusted).
  - **AUTH ISSUER IS ALWAYS BAKED at build, never doc-sourced** — the OIDC
    issuer a client validates tokens against ships in the build artifact;
    no doc (A, B, or C) ever carries a trust anchor.
  - **60s cache semantics**: every publish sets `Cache-Control: max-age=60`
    on both hosting targets (see below) and stamps a version doubling as
    the HTTP cache tag (ETag) — cheap 304s; clients never accept a version
    older than one already seen, per doc (monotonic, no rollback).
  - **Health-gated entries**: a Doc B landscape entry appears ONLY once
    that row's deployment is actually healthy — never a provisioning or
    draining region.
- **Dormant-router contract**: trip condition = hard connect-failure only
  (never a soft error, never opportunistic); jittered budgeted scan over
  Doc C's ordered candidates; pin-until-heal (stick to the first working
  candidate until it fails again); server-context exemption — the nextjs
  SERVER runtime never runs this router. Rescues ADDRESSES only — a dead
  home region is a restore/re-home event, not a routing event.
- **Hosting**: exactly two CDNs, one dumb publisher — R2 (public bucket, CF
  custom domain) + S3 (behind CloudFront); both are S3-API targets so the
  traffic controller's publish step is the SAME PUT issued twice + purge
  (CF) / invalidate (CloudFront) issued twice, per doc (all three). Problem
  catalogs (§14) ride the identical channel and cache contract. NO doc
  signing — the baked allowlist replaces it.
