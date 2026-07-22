### §8 Onboarding contract (multi-backend)

- **Full resource identity (S7)** is
  `ResourceKey = (platform, landscape, service, resourceName)`. Every component
  is an explicit lowercase DNS label; none is inferred. Its canonical client-map
  key is `platform/landscape/service/resourceName`. `resourceName` occupies the
  M slot of the public LPSM coordinate, so the Logto resource identifier / JWT
  `aud` is exactly
  `https://<resourceName>.<service>.<platform>.<landscape>.cluster.atomi.cloud`
  (no trailing slash). The identifier is an identity string; dereferenceability
  is not required.
- A registered backend declares its stable `backendId`, the full resource keys
  it needs, and which one protects its `/User` onboarding surface. Client state
  is `(backendId → phase)` plus `(ResourceKey → token result)` through the IAuth
  seam. UI gates wait only for the backend(s) a route/module needs; one backend
  may be ready while another is onboarding or errored.
- **All-token batch (S7)**: at onboarding/bootstrap start, the client snapshots
  the backend registry, deduplicates the union by full `ResourceKey`, and starts
  acquisition for EVERY key before awaiting an individual result. A still-valid
  cached token satisfies acquisition; otherwise the provider may issue one
  network request per resource. Bounded concurrency is legal, lazy first-call
  acquisition is not.
  - The logical result is a total map with exactly one entry per requested key:
    `{ token, expiresAt }` or a problem-typed failure. The batch completes only
    when every entry is terminal; no requested key is omitted.
  - Failure is isolated per backend: a backend enters `error` if any of its
    required resource entries failed, while disjoint backends may continue. It
    is not a fleet-wide all-or-nothing batch.
- **Exact registration claim (S20)**: readiness is inspected in EACH resource
  access token, never inferred from an ID token or API probe. Claim key =
  `<platform>_<service>`, with both labels lowercased and every `-` replaced by
  `_`; value MUST be the JSON string **`"true"`**. Missing, null, boolean `true`,
  or any other value counts as absent. The token's full per-landscape `aud`
  supplies the resource/landscape scope; `home_landscape` (§13) is distinct.
- **Per-backend claims-first state table (S20)** — no singleton onboarded flag:
  1. Start `bootstrapping`; resolve the backend's complete token batch.
  2. If every required resource token has the exact registration claim, the
     backend is registered: enter `needsOnboarding` only when a separately
     declared app-specific onboarding claim is absent, otherwise `ready`.
  3. If the registration claim is absent from ANY required resource token, use
     the designated onboarding-resource token for exactly one
     `GET /User/Me`. `200` means the row already exists and skips create; `404`
     causes `POST /User` with the normal bearer header and body
     `{ "idToken": <raw ID token>, "accessToken": <raw onboarding-resource
     access token> }`. Any `2xx` or `409` from POST is create-or-ok; every other
     GET/POST status or transport failure enters `error`.
  4. After GET `200` or accepted POST, force-refresh ALL resource tokens for
     that backend and re-check the exact claim. Present on every token → apply
     step 2; still absent → `error` (`OnboardingClaimMissing`). This is the only
     claim-repair/race path.
  5. If a claim was present and a normal owned-resource call later returns
     `401`/`404`, enter `error`; MUST NOT run `/User/Me` or create again. A stale
     claim is an ordinary authorization/data error, never a second detector.
- OnboardSync's backend create-or-ok transaction writes the local row and the
  `<platform>_<service> = "true"` claim together; claim-write failure rolls the
  row back. Existing create-only backends may return `409`, which clients treat
  as success before the mandatory refresh/re-check above.
- **Logto CR shape (S6/Q-I36)** — every Logto-protected target has exactly
  one `LogtoApp` CR per **(app × vlandscape)**, the single home of all
  app-level truth (scalars declared once, unrepresentably conflict-free; the
  old per-row `LogtoApp` fragment CRs are ABOLISHED). Redirect URIs are
  **DERIVED**, never declared per row. The app coordinate includes
  `(platform, service, module, vlandscape)`; platform/service/module come from
  the owning chart's mandatory service-tree coordinate rendered by the
  standard CR helper, never from parsing a hostname. Its live serve-set is the
  `VirtualLandscapeService` rows with that exact coordinate and `serve:true`.
  For each host landscape `L` in that set:
  - `origin(L) = https://<module>.<service>.<platform>.<L>.cluster.atomi.cloud`
    (lowercase, no explicit/default port, no trailing slash);
  - a declared `redirectPath` / `postLogoutPath` MUST be an absolute RFC 3986
    path beginning with one `/`, with no scheme, authority, query, fragment,
    empty/dot segments, or percent-encoded `/`; trailing slash is significant;
  - derived redirect/post-logout URI = `origin(L) + declaredPath`; derived CORS
    origin = `origin(L)`.
  Non-HTTPS/local/vendor exceptions are explicit only through
  `extraRedirectUris[]`, `extraPostLogoutRedirectUris[]`, or
  `extraCorsOrigins[]`; no environment-specific implicit branch exists.
- Redirect/post-logout extras MUST be absolute, fragment-free URIs. CORS extras
  MUST be origins only (scheme + host + optional non-default port; no userinfo,
  path other than `/`, query, or fragment). Normalize scheme/host to lowercase,
  remove default ports, preserve allowed path/query bytes, deduplicate after
  normalization, then sort by UTF-8 byte order. The desired managed set `D` is
  the normalized derived set union the normalized matching `extra*` list.
  Serving a row adds its entries; `serve:false`, row removal, path change, or
  extra-list removal retracts them.
- **Derived-set reconcile (Q-I36)**: with observed upstream set `O` and the
  last applied managed set `A` stored in
  `customData["cloud.atomi/last-applied"]`, write exactly `(O − A) ∪ D`, then
  persist `D` as the new `A`. Thus manual console additions survive and stale
  formerly-managed entries are removed. Logto PATCH replaces metadata objects,
  so the operator MUST GET, merge the complete metadata object in memory, and
  PATCH the complete object. Deterministic sorted sets make repeated reconcile
  a no-op.
- Anything used as an API/token audience has exactly one `LogtoResource` CR per
  full `ResourceKey`; no CR is shared across keys. `LogtoApp.spec.resourceRefs`
  is an explicit list of those CR names; a missing ref is a hard
  `ResourceRefMissing` error, never inferred.
- **Audience split (S7)**: resource identifiers are per full key and therefore
  PER-LANDSCAPE; the issuer is shared. A token for raichu is not
  interchangeable with amphoros even on the same vlandscape.
