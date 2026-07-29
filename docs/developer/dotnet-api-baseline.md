---
id: dotnet-api-baseline
title: .NET API Baseline
---

# .NET API baseline

`dotnet-api` is the runnable ASP.NET Core service sample: a real HTTP host, a real
container image, real charts, and a Bruno SIT tier. It is additive on
[the .NET baseline](./dotnet-baseline.md), which still describes the toolchain,
the projects, and the coverage machinery.

Read this file for what the service adds: its two run modes, its task surface, and
the knobs a downstream service turns when it promotes this sample into its own.

## Run modes

The compiled artifact is two things, selected by the first non-flag argument. There
is no cron mode.

| Mode      | Argument          | What it does                                                     |
| --------- | ----------------- | ---------------------------------------------------------------- |
| `server`  | none, or `server` | Serves HTTP through the composition root. The default.           |
| `db-init` | `db-init`         | Runs the one-shot initialisation path, then exits with a status. |

`App/StartUp/RunMode.cs` resolves the mode. An unrecognised argument is an error
with exit code 2, never a silent fall back to the server: a typo in a Job's args
must not start a web host.

### What db-init does

`db-init` runs four steps, each independently switchable through the `db_init:`
configuration block, and exits `0` on success or `1` on the first failure:

1. **Reachability** — waits for Postgres, the cache, the KV store, and S3-compatible
   storage, bounded by `reachability_window` and `reachability_timeout`.
2. **Bucket create** — creates the storage bucket. Off by default; a landscape that
   provisions its bucket elsewhere leaves it off.
3. **Migrate** — applies real EF Core migrations.
4. **Seed** — writes preset data if it is not already there. Seeding is
   seed-if-not-exists, so a second run changes nothing.

It runs as its own hook-scoped Job before the rollout, never as part of the serving
Deployment. That separation is the point: the Deployment performs an ordinary
rolling update while a migration is in flight, and the Job never triggers a full
app recreation.

The serving process does not repeat any of this. `GET /` is dependency-blind — both
the liveness and the readiness probe target it — so a database blip cannot roll a
healthy deployment.

## Local commands

| Command                                | Purpose                                                        |
| -------------------------------------- | -------------------------------------------------------------- |
| `pls setup`                            | Synchronize vendored skills and restore repo-local .NET tools. |
| `pls clean`                            | Remove build and test artifacts.                               |
| `pls build`                            | Build every project in Release.                                |
| `pls dev`                              | Run the App under `dotnet watch`.                              |
| `pls run -- <args>`                    | Run the App in development mode.                               |
| `pls preview -- <args>`                | Build, then run the compiled Release artifact.                 |
| `pls up` / `pls down`                  | Start or stop the local dependencies.                          |
| `pls test`                             | Run the unit and integration tiers.                            |
| `pls test:unit` / `pls test:int`       | Run one tier.                                                  |
| `pls test:coverage`                    | Enforce both merged coverage ledgers.                          |
| `pls test:watch`                       | Watch the fast unit tier.                                      |
| `pls deadcode`                         | Emit the broad, non-blocking LLM review.                       |
| `pls lint`                             | Run every generated pre-commit gate.                           |
| `pls docker:build` / `pls docker:run`  | Build the local image, or run it and smoke `GET /`.            |
| `pls docker:clean`                     | Remove the local image.                                        |
| `pls secret:fetch` / `pls secret:scan` | Fetch the Infisical environment, or scan tracked content.      |

### Tasks this sample adds

These are build-time and validation commands, not deployment run modes. A
deployment only ever runs `server` or `db-init`.

| Command                    | Purpose                                                                |
| -------------------------- | ---------------------------------------------------------------------- |
| `pls db:init`              | Run the one-shot db-init path against the local dependencies.          |
| `pls config:validate`      | Bind and validate every block against the final merged layer.          |
| `pls config:schema`        | Regenerate the configuration schema from the registered option blocks. |
| `pls config:schema:verify` | Fail when the generated schema has drifted from the option types.      |
| `pls problems:export`      | Export the Problem catalog resources into the primordial chart.        |
| `pls problems:verify`      | Fail when the exported catalog has drifted from the registered one.    |

Both `:verify` tasks are drift gates: they regenerate and compare rather than
trusting the committed artifact, so a catalog or schema edited without re-exporting
is caught here instead of at deploy.

`pls config:validate` is the local reach into the same ValidateOnStart path the
server runs. A schema-invalid overlay fails it for the same reason, and with the
same message, that it would fail startup.

### Chart tasks

Two charts ship, so the helm surface has an each-chart axis and a both-charts axis.

| Command                                                  | Purpose                                                              |
| -------------------------------------------------------- | -------------------------------------------------------------------- |
| `pls helm:lint` / `pls helm:template` / `pls helm:debug` | The app chart alone.                                                 |
| `pls helm:primordial:lint` / `:template` / `:debug`      | The primordial chart alone.                                          |
| `pls helm:lint:all` / `pls helm:template:all`            | Both charts against every landscape values file.                     |
| `pls helm:deps` / `pls helm:primordial:deps`             | Build each chart's dependencies.                                     |
| `pls helm:vendor` / `pls helm:clean`                     | Add or remove the build-phase vendored copies.                       |
| `pls helm:versions`                                      | Assert one semver spans the image tag and both chart version fields. |

`pls helm:vendor` exists because helm cannot reference files outside the chart
directory. In local development the config YAMLs live outside the chart and the app
reads them directly; the build step copies them in so they can be bundled as
ConfigMaps. Those copies are gitignored and regenerated per build — never
committed. `pls helm:clean` removes them again.

### dev, run, and preview are three different things

They differ in what is running, which is what makes them worth having all three:

- **`pls dev`** runs the App under `dotnet watch`. Edit a file and the host
  restarts. This is the inner loop; it is not what any landscape runs.
- **`pls run -- <args>`** runs the App once in development mode, from source. Use it
  to drive a specific invocation — `pls run -- db-init` exercises the one-shot path
  against the local dependencies.
- **`pls preview -- <args>`** builds Release first and then runs the compiled
  artifact from `App/bin/Release/`. This is the closest local approximation of what
  the image ships, and it is where a Release-only failure — a
  warnings-as-errors break, a trimmed dependency, a configuration file that was
  never copied to the output — actually shows up.

`pls up` and `pls down` start and stop the local dependencies detached. Run `up`
before the integration tier or before `pls run -- db-init`; nothing else needs it.

## The SIT tier

System integration tests are Bruno journeys in `tests/sit/bruno/`, run headless
against the Garden-managed `castform` preview supplied by the `environments`
segment. There are no fakes and no Testcontainers at this tier.

The collection, its environment contract, and its two deliberately withheld
journeys are documented in
[`tests/sit/bruno/README.md`](../../tests/sit/bruno/README.md).

One command runs it:

```bash
pls test:sit
```

It delegates to `scripts/ci/sit.sh`, which is also exactly what CI runs. One
definition of the run on purpose: two would drift, and a local green would then be
free to describe a different run from a CI green.

`bru` comes from `bruno-cli` and has to be on `PATH` for the tier to run at all:

```bash
bru --version
```

The recursive flag is `-r`, and `bru` 1.16.0 has no `--recursive` alias — it
rejects it outright. That distinction is worth knowing rather than discovering:
the journeys all live in numbered folders, so a run that lost `-r` would pick up
nothing and still report a tier.

## Promotion knobs

A downstream service turns these; everything else is machinery it inherits.

### Identity

| Knob             | Where                                                                                |
| ---------------- | ------------------------------------------------------------------------------------ |
| Service tree     | `app:` in `App/Config/settings.yaml` — landscape, platform, service, module, version |
| Image name       | `IMAGE` in `tasks/Taskfile.docker.yaml`, and the CD workflow's image reference       |
| Chart name       | `name` in the chart's `Chart.yaml`                                                   |
| OpenAPI branding | `http:open_api:title` and `description`                                              |

Identity is configuration, never source. The rebrand gate rejects a hardcoded
service name, OpenAPI title, or auth endpoint, and the SIT collection asserts the
served title against the configured value rather than against a literal.

### Port and host

`infra/Dockerfile` bakes `APP_HOST=+` and `APP_PORT=8080` as build args and composes
`ASPNETCORE_URLS` from them, and the image exposes `8080`. Both are overridable at
build time and at run time; the chart's Service and probes follow the same value.

### Settings keys

`App/Config/settings.yaml` is the FULL base layer: every key the service ever reads
exists there, including the ones only an environment override ever fills. A key that
exists nowhere binds to a default and fails silently, so landscape overlays stay
sparse and name only what differs.

Every value is overridable through the environment as `ATOMI_<BLOCK>__<KEY>`, with
`__` between levels. **Lists use INDEXED keys** —
`ATOMI_HTTP__CORS__ALLOWED_ORIGINS__0`, `__1`, and so on. A JSON array or a
comma-separated string in one variable does not bind; it produces an empty list.

Secrets are declared blank in the base layer and injected through that same
environment path. Nothing special-cases them.

The blocks a downstream service usually touches: `app:`, `http:`, `auth:`,
`db_init:`, `otel:`, and the named connection presets under `postgres:`, `cache:`,
`kv:`, and `storage:`. Connection names are UPPERCASE, and a preset is a map of
named connections — a second pool is data, not code.

### Helm values

Two charts ship: the app chart under `infra/root_chart/` is pure runtime, and the
primordial chart carries the T3 custom-resource set. Each has its own
`values.yaml`, its landscape overlays, and its `values.schema.json`; the schema is
what a downstream service edits first, because it is the gate every values file is
checked against.

One semver spans the image tag and both charts' `version` and `appVersion` fields.
Bumping one without the others fails the version-match check.

### Coverage thresholds

`.config/dotnet-base.test.yaml` holds one entry per tier: the registered test
projects, the assembly include and exclude filters, and the minimum. Unit is 100%
over `[Lib*]*`; integration is 80% over `[App*]*`. Adding a project means one
solution line and one YAML list entry — the filters, merged thresholds, Codecov
globs, and dead-code discovery all follow the naming convention from there.

## What stays base-named

Keep `dotnet-base.slnx`, `.config/dotnet-base.test.yaml`, and the
`AtomiCloud.DotnetBase.*` root namespaces base-named. They are merge-stability
surfaces, not identity, and renaming them costs a conflict on every upstream merge
while buying nothing a reader can see.
