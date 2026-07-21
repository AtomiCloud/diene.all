### §2 Problem schema

- Envelope = RFC 9457 (`type`, `title`, `status`, `detail`, `instance`) + **`data`
  extension** carrying the typed payload.
- `type` URI template includes `{version}` — versioned contract identity: a version
  bump deliberately mints a NEW problem type:
  `{scheme}://{host}/docs/{landscape}/{platform}/{service}/{module}/{version}/{id}`.
- Template fed from an `ErrorPortal` config block; **built in exactly ONE place**
  (single-source builder requirement — zinc duplicates it in
  `ProblemDetailsService.cs` + `AuthResultTransformer.cs`, the failure mode this
  rule exists to prevent).
- JSON-schema export shape: each problem publishes id/title/version + schema of
  `data`. The Problem CRD (erbium/ERROR-PORTAL) replaces runtime error-info: the
  export target is erbium's Go informer API, not a runtime error-info endpoint
  (zinc's `V1ErrorController` is the shape precedent only); generator per language
  (zod / NJsonSchema / …) but ONE output shape.
- Problem catalog is versioned (`V1/*` style); portable generic set
  (EntityNotFound/Conflict, ValidationError, Unauthorized, Unauthenticated,
  InvalidJson…) enumerated as the baseline catalog.
