---
title: API client (diene_api_engine)
summary: Register backends on the LPSM client tree and call them with Result-typed outcomes.
---

# API client — `diene_api_engine`

`diene_api_engine` is the client-side backend layer for the diene Dart family.
Every call returns `Result<T, Problem>` — no thrown fetch errors escape.

## Register a backend

A backend is one LPSM coordinate + one hostname (the home landscape's, from
config values — never a literal) + an optional per-resource auth binding.

```dart
final config = ApiEngineConfig.fromMap(configSlice); // merged/validated by the config lib
final engine = ApiEngine.fromConfig(
  config,
  auth: myAuthRetriever,        // IAuth seam — auth-engine plugs in here
  store: FileRescueStore(dir),  // real disk on Flutter; omit for in-memory
);

final backend = engine.backend(
  LpsmCoordinate(
    landscape: 'lapras',
    platform: 'platform',
    service: 'service',
    module: 'core',
  ),
)!;
```

## Call it

Bring your generated OA3 SDK's request shape (method + path + JSON decoder);
the engine attaches the token, sends with the retry-once profile, and folds the
response into a `Result`.

```dart
final Result<UserProfile> me = await backend.call(
  method: HttpMethod.get,
  path: '/user/me',
  decode: UserProfile.fromJson,
);

me.match(
  ok: (profile) => render(profile),
  err: (problem) => showProblem(problem), // RFC 9457 envelope
);
```

## Reconciliation

`toResult` classifies every outcome:

| Outcome                                  | Result                            |
| ---------------------------------------- | --------------------------------- |
| opaque network failure (past retry-once) | `Err` transport-failure Problem   |
| 2xx JSON                                 | `Ok(decode(json))`                |
| 2xx non-JSON / decode failure            | `Err` transport-failure Problem   |
| non-2xx problem body (incl. nested)      | `Err(Problem.fromJson)`           |
| non-2xx JSON that is not a problem       | `Err` unexpected-response Problem |
| non-2xx non-JSON / status-only           | `Err` transport-failure Problem   |

## Resilience

- **Retry-once** on an opaque network error (fresh connection). A received HTTP
  status — even 5xx — is never retried. This is NOT load balancing.
- **Dormant rescue router** (per-context enable flag; ON for Flutter): on a
  hard connect-failure it consults an on-disk Doc C catalog (seeded via Doc A's
  baked catalog hosts), scans that landscape's ordered candidate addresses with
  a jittered budget, pins the first healthy one until the primary heals, and
  keeps last-known-good forever. It enforces a baked endpoint-suffix allowlist
  on every doc-sourced URL, accepts only monotonically newer docs, never
  sources the auth issuer from a doc, and rescues addresses only — same
  landscape, never cross-landscape.

## Testing

`package:diene_api_engine/test_helper.dart` ships `FakeHttpTransport`,
`FakeAuth`, `FakeRescueStore`, plain-throw `expectOk`/`expectErr`/
`expectProblemType`, and response builders — dependency-light (no test
framework), so multi-backend and rescue paths test without real HTTP.
