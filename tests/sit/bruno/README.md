# Bruno SIT collection

Black-box API journeys for `diene-dotnet-api`, run headless against the
Garden-managed `castform` preview supplied by the `environments` segment. This is
the family's standard SIT location: `tests/sit/bruno/` for the collection,
`tests/sit/bruno/environments/` for its environments.

There are no fakes and no Testcontainers at this tier. Every request crosses the
preview's kgateway-exposed edge, against the same compiled artifact the image ships.

## Run it

```bash
pls test:sit
```

That is the only command. It delegates to `scripts/ci/sit.sh`, which is what CI
runs too, so a local green and a CI green describe the same run. The script writes
a JUnit report to `TestResults/sit/sit.junit.xml` and passes `--bail`, so the first
failing request stops the run instead of producing a cascade.

`bru` comes from `bruno-cli`. Confirm it is on `PATH` before running:

```bash
bru --version
```

## Environment contract

The `sit` environment reads everything from the process environment, so no preview
coordinate and no credential is ever committed. The `environments` segment supplies
these when it hands over the preview.

| Variable                             | Required | What it is                                                  |
| ------------------------------------ | -------- | ----------------------------------------------------------- |
| `SIT_BASE_URL`                       | yes      | The preview's HTTPS origin for this service.                |
| `SIT_AUDIENCE`                       | yes      | This service's `castform`-coordinate Logto audience.        |
| `SIT_LOGTO_ENDPOINT`                 | yes      | The landscape-local Logto origin.                           |
| `SIT_LOGTO_CLIENT_ID`                | yes      | M2M client id for this service's audience.                  |
| `SIT_LOGTO_CLIENT_SECRET`            | yes      | M2M client secret for this service's audience.              |
| `SIT_CORS_ORIGIN`                    | yes      | The origin the preview set via the indexed CORS list key.   |
| `SIT_SEED_NOTE_TITLE`                | yes      | Title of the row db-init's idempotent seed writes.          |
| `SIT_LOGTO_MANAGEMENT_RESOURCE`      | yes      | Logto Management API resource indicator.                    |
| `SIT_LOGTO_MANAGEMENT_CLIENT_ID`     | yes      | Management API client id, used for session revocation.      |
| `SIT_LOGTO_MANAGEMENT_CLIENT_SECRET` | yes      | Management API client secret.                               |
| `SIT_LOGTO_SUBJECT`                  | yes      | The subject whose sessions the revocation journey destroys. |
| `SIT_LOGTO_REFRESH_TOKEN`            | yes      | A refresh token issued out of band for that subject.        |
| `SIT_OPENAPI_TITLE`                  | no       | Exact `http:open_api:title` the preview was deployed with.  |

`SIT_BASE_URL` follows the dotted preview form
`module.service.platform.instance.landscape.zone`, with the instance outside the
LPSM coordinate:

```text
https://api.dotnet-api.sulfoxide.<instance>.castform.dev.atomi.cloud
```

The instance segment is the preview's allocation, so it is never hardcoded here.
If `SIT_BASE_URL` is empty the collection throws on its first request and names the
variable, rather than connection-refusing its way through every journey.

## What the journeys cover

| Folder           | Feature                                                                      |
| ---------------- | ---------------------------------------------------------------------------- |
| `00-auth`        | Machine-token acquisition from the landscape-local Logto.                    |
| `01-info`        | `GET /` info endpoint, the OpenAPI document, and the consumed system routes. |
| `02-config`      | `ATOMI_X__Y` overriding a file value, scalar and indexed-list forms.         |
| `03-notes`       | The sample module's CRUD journey through the preview.                        |
| `04-problems`    | The RFC 9457 envelope, its `data` extension, and the versioned type URI.     |
| `05-modes`       | `server` serving, and db-init's migration and idempotent seed.               |
| `06-app-handoff` | The enabled auth-engine module at its configured mount.                      |
| `07-tokens`      | Refresh with rotation, revocation, and refusal after revocation.             |

Folder order is the run order, and it matters: `00-auth` must precede everything
that carries a token, and `07-tokens` must come last because it revokes the
subject's sessions.

## What is deliberately NOT proven here

See [`withheld/`](./withheld/README.md). Two journeys are authored but not run:
`castform` Mercury webhook delivery, and the app-handoff mint/redeem pair. Neither
is silently missing and neither is faked.

## Conventions

- Assertions name the value they checked and log it, so a report shows the observed
  landscape, title, or status rather than only a pass mark.
- Overrides are asserted against BOTH the expected value and the file value they
  replaced. An assertion that only checks the expected value cannot tell a working
  override from a coincidence.
- URLs are built from environment variables, never from literals, wherever the
  route is configuration-driven — the handoff mount and the API root especially.
- The collection needs no `--sandbox=developer`: no script here requires a Node
  module.
